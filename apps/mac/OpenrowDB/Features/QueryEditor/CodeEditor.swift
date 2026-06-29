// CodeEditor.swift
import AppKit
import OpenrowDBCore
import SwiftUI

/// SwiftUI wrapper around `NSTextView` for the SQL editor.
///
/// Two layout traps are avoided here:
///
/// 1. We do **not** use `NSTextView.scrollableTextView()` because that factory
///    ships the view at frame `(0,0,0,0)` and SwiftUI's first layout pass
///    briefly keeps it that way. The text container width is computed as
///    `width - 2 * inset`, which goes negative; `NSLayoutManager` caches the
///    broken layout and never recomputes once the real frame arrives, leaving
///    a permanently blank text view.
/// 2. We do **not** seed the scroll view with a hard-coded frame like
///    `600x400`. Apple DTS confirms that `NSViewRepresentable` reads
///    `intrinsicContentSize` BEFORE the frame is set, then sizes the view as
///    `min(parent_proposed, intrinsic)`. Any container that honors intrinsic
///    sizes (the legacy `HSplitView`/`VSplitView`, or any custom layout that
///    queries `sizeThatFits`) makes a seeded 600px frame win over
///    `.frame(maxWidth: .infinity)` until an unrelated state mutation forces
///    a re-layout. Symptom: editor stuck at 600px until user clicks Run.
///    Fix: combine `NoIntrinsicScrollView` (returns `noIntrinsicMetric`) with
///    `sizeThatFits` accepting the parent's proposal.
/// Hands the parent view the editor's current text + selection on demand.
/// Reading the live `NSTextView` at run time sidesteps two traps of the
/// `onCursorChange` snapshot: it trails one SwiftUI render, and it goes stale
/// the instant the Run menu takes first responder from the text view — both of
/// which made partial runs ("Run Selection" / "Run Current Statement") fire on
/// the wrong text. AppKit keeps `selectedRange()` intact across focus loss, so
/// the live read is always the selection the user still sees.
@MainActor
final class EditorAccess {
    fileprivate var textProvider: (() -> String)?
    fileprivate var rangeProvider: (() -> NSRange)?

    /// The editor's current text + selected range, or nil before the text view
    /// exists (or when no editor is attached). Used by the run actions.
    func snapshot() -> (text: String, selectedRange: NSRange)? {
        guard let textProvider, let rangeProvider else { return nil }
        return (textProvider(), rangeProvider())
    }

    /// The live selection length only — no string copy. Used to gate the "Run
    /// Selection" menu item. Read straight off the text view so the enabled
    /// state is correct even when SwiftUI builds the menu from a view tree that
    /// hasn't yet applied the latest `cursor` @State change (the menu-open race
    /// that left "Run Selection" greyed right after a mouse drag-select).
    func selectionLength() -> Int { rangeProvider?().length ?? 0 }
}

struct CodeEditor: NSViewRepresentable {
    @Binding var text: String
    var dialect: SQLDialect
    var schema: SchemaSnapshot
    var onSubmit: (() -> Void)?
    /// 1-indexed character offset of the last query error, or nil. When set,
    /// the editor draws a red wavy underline on the token at that position.
    var errorPosition: Int?
    /// Bumped by parents (e.g. user clicks "Jump to error" in the results
    /// pane) to request that the cursor be moved to `errorPosition`. Without
    /// this, an `errorPosition` change alone wouldn't move the cursor on
    /// repeated clicks of the same error.
    var jumpRequest: Int = 0
    /// Reports the caret line/column (and any selection length) whenever the
    /// selection changes, so the status bar can show `Ln · Col` like a native
    /// code editor. Columns are 1-based UTF-16 offsets within the line.
    var onCursorChange: ((CursorPosition) -> Void)? = nil
    /// Lets the parent read the editor's *live* text + selection at run time
    /// (see `EditorAccess`). Partial runs use this instead of the `cursor`
    /// snapshot so "Run Selection" / "Run Current Statement" target what's
    /// actually selected right now — the snapshot lags a SwiftUI render and is
    /// stale the instant the Run menu steals first responder from the editor.
    var access: EditorAccess? = nil

    struct CursorPosition: Equatable {
        var line: Int = 1
        var column: Int = 1
        /// UTF-16 offset of the selection start (the caret when nothing is
        /// selected), used to extract the selection or the statement under the
        /// caret for partial runs.
        var location: Int = 0
        var selectionLength: Int = 0
    }

    func makeNSView(context: Context) -> NoIntrinsicScrollView {
        let scroll = NoIntrinsicScrollView(frame: .zero)
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        // Paint the scroll view (incl. the area behind the line-number ruler) in
        // the editor's own background so the gutter and text share one surface.
        // With a clear background the gutter showed the lighter window colour,
        // and the seam against the dark text area read as a vertical line that
        // appeared to run the full height of the pane.
        scroll.drawsBackground = true
        scroll.backgroundColor = .textBackgroundColor
        scroll.autoresizingMask = [.width, .height]
        scroll.translatesAutoresizingMaskIntoConstraints = true

        let textView = CompletionTextView(frame: .zero)
        textView.completionResolver = { [weak coordinator = context.coordinator] display, isFinal in
            coordinator?.resolveCompletion(display: display, isFinal: isFinal)
        }
        textView.onCommandReturn = { [weak coordinator = context.coordinator] in
            coordinator?.onSubmit?()
        }
        textView.onTab = { [weak coordinator = context.coordinator, weak textView] in
            guard let coordinator, let textView else { return false }
            return coordinator.completeTopSuggestion(textView)
        }

        // Resizing: vertical grows with content, horizontal tracks the scroll view.
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                  height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]

        if let container = textView.textContainer {
            container.widthTracksTextView = true
            container.heightTracksTextView = false
            container.size = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                    height: CGFloat.greatestFiniteMagnitude)
            container.lineFragmentPadding = 4
        }

        // Editing & input behaviour.
        textView.delegate = context.coordinator
        textView.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.textContainerInset = NSSize(width: 6, height: 6)
        textView.drawsBackground = true
        textView.backgroundColor = .textBackgroundColor
        textView.textColor = .labelColor
        textView.insertionPointColor = .labelColor
        textView.string = text

        let ruler = LineNumberRulerView(textView: textView, scrollView: scroll)
        scroll.hasVerticalRuler = true
        scroll.rulersVisible = true
        scroll.verticalRulerView = ruler

        scroll.documentView = textView
        context.coordinator.textView = textView
        context.coordinator.rulerView = ruler

        // Expose the live text view so the parent can pull the real selection at
        // the moment of a run, bypassing the lagging `onCursorChange` snapshot.
        access?.textProvider = { [weak textView] in textView?.string ?? "" }
        access?.rangeProvider = { [weak textView] in
            textView?.selectedRange() ?? NSRange(location: 0, length: 0)
        }

        let highlighter = SQLSyntaxHighlighter(dialect: dialect)
        textView.textStorage?.delegate = highlighter
        context.coordinator.highlighter = highlighter
        highlighter.highlightAll(textView)

        // Report the initial caret position once the view is live. Deferred to
        // the next run loop because invoking the closure synchronously here
        // would mutate SwiftUI @State during the representable's first layout.
        let coordinator = context.coordinator
        DispatchQueue.main.async { [weak textView] in
            if let textView { coordinator.reportCursor(textView) }
        }

        return scroll
    }

    func updateNSView(_ nsView: NoIntrinsicScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        // Refresh the text binding too — not just the closures. If SwiftUI reuses
        // one CodeEditor instance across query tabs (same view identity), the
        // coordinator keeps the *first* tab's `$runner.sql` binding. Typing in a
        // second tab would then write the first tab's SQL while the second tab's
        // text view gets reset to its own empty string on the next update — the
        // "can't type more than one character in tab 2" bug.
        context.coordinator.text = $text
        context.coordinator.dialect = dialect
        context.coordinator.schema = schema
        context.coordinator.onSubmit = onSubmit
        context.coordinator.onCursorChange = onCursorChange
        context.coordinator.highlighter?.dialect = dialect
        // Only sync from binding when the text genuinely diverged. Without this
        // guard, every keystroke triggers updateNSView → setString → wipes the
        // current selection and breaks the cursor.
        if textView.string != text {
            let selected = textView.selectedRange()
            textView.string = text
            let length = (text as NSString).length
            let clamped = NSRange(
                location: min(selected.location, length),
                length: min(selected.length, max(0, length - min(selected.location, length)))
            )
            textView.setSelectedRange(clamped)
            context.coordinator.highlighter?.highlightAll(textView)
        }

        applyErrorHighlight(textView, position: errorPosition)
        context.coordinator.rulerView?.refresh()

        if jumpRequest != context.coordinator.lastJumpRequest {
            context.coordinator.lastJumpRequest = jumpRequest
            if let position = errorPosition {
                jumpToPosition(textView, position: position)
            }
        }
    }

    private func applyErrorHighlight(_ textView: NSTextView, position: Int?) {
        guard let layoutManager = textView.layoutManager else { return }
        let fullRange = NSRange(location: 0, length: (textView.string as NSString).length)
        layoutManager.removeTemporaryAttribute(.underlineStyle, forCharacterRange: fullRange)
        layoutManager.removeTemporaryAttribute(.underlineColor, forCharacterRange: fullRange)

        guard let position, position > 0 else { return }
        let tokenRange = tokenRange(in: textView.string, around: position - 1)
        guard tokenRange.location != NSNotFound, tokenRange.length > 0 else { return }
        let style = NSUnderlineStyle.thick.rawValue | NSUnderlineStyle.patternDot.rawValue
        layoutManager.addTemporaryAttribute(.underlineStyle, value: style, forCharacterRange: tokenRange)
        layoutManager.addTemporaryAttribute(.underlineColor, value: NSColor.systemRed, forCharacterRange: tokenRange)
    }

    private func jumpToPosition(_ textView: NSTextView, position: Int) {
        let nsString = textView.string as NSString
        guard position > 0 else { return }
        let zero = min(position - 1, nsString.length)
        let range = tokenRange(in: textView.string, around: zero)
        let target = range.location != NSNotFound ? range : NSRange(location: zero, length: 0)
        textView.setSelectedRange(target)
        textView.scrollRangeToVisible(target)
        textView.window?.makeFirstResponder(textView)
    }

    /// Find the identifier or punctuation token straddling `zeroIndex`. Returns
    /// `{NSNotFound, 0}` for out-of-range. The caller treats a zero-length
    /// match as "no token here" and falls back to a caret-only selection.
    private func tokenRange(in text: String, around zeroIndex: Int) -> NSRange {
        let chars = Array(text)
        guard zeroIndex >= 0, zeroIndex < chars.count else {
            return NSRange(location: NSNotFound, length: 0)
        }
        func isIdent(_ c: Character) -> Bool { c.isLetter || c.isNumber || c == "_" }
        var start = zeroIndex
        var end = zeroIndex
        if isIdent(chars[zeroIndex]) {
            while start > 0, isIdent(chars[start - 1]) { start -= 1 }
            while end < chars.count, isIdent(chars[end]) { end += 1 }
        } else {
            end = zeroIndex + 1
        }
        let prefixUtf16 = String(chars[0..<start]).utf16.count
        let tokenUtf16 = String(chars[start..<end]).utf16.count
        return NSRange(location: prefixUtf16, length: tokenUtf16)
    }

    func sizeThatFits(_ proposal: ProposedViewSize,
                      nsView: NoIntrinsicScrollView,
                      context: Context) -> CGSize? {
        CGSize(
            width: proposal.width ?? 320,
            height: proposal.height ?? 200
        )
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, dialect: dialect, schema: schema, onSubmit: onSubmit, onCursorChange: onCursorChange)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        var dialect: SQLDialect
        var schema: SchemaSnapshot
        var onSubmit: (() -> Void)?
        var onCursorChange: ((CursorPosition) -> Void)?
        weak var textView: NSTextView?
        weak var rulerView: LineNumberRulerView?
        var highlighter: SQLSyntaxHighlighter?
        var lastJumpRequest: Int = 0

        private var isCompleting = false

        /// Map from popup display string (with glyph prefix) back to the raw
        /// suggestion. Needed because `textView(_:completions:...)` hands AppKit
        /// `[String]` only — we can't attach metadata. On accept we look up the
        /// kind here to decide whether to auto-quote (tables/columns) and to
        /// strip the glyph before insertion.
        private var displayToSuggestion: [String: CompletionSuggestion] = [:]

        init(text: Binding<String>, dialect: SQLDialect, schema: SchemaSnapshot, onSubmit: (() -> Void)?, onCursorChange: ((CursorPosition) -> Void)?) {
            self.text = text
            self.dialect = dialect
            self.schema = schema
            self.onSubmit = onSubmit
            self.onCursorChange = onCursorChange
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            let newValue = textView.string
            if text.wrappedValue != newValue {
                text.wrappedValue = newValue
            }
            rulerView?.refresh()
            scheduleCompletion(in: textView)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            reportCursor(textView)
        }

        /// Translate the text view's selected range into 1-based line/column and
        /// push it to `onCursorChange`. Line is the count of newlines before the
        /// caret + 1; column is the UTF-16 distance from the start of that line.
        func reportCursor(_ textView: NSTextView) {
            guard let onCursorChange else { return }
            let ns = textView.string as NSString
            let selection = textView.selectedRange()
            let caret = min(selection.location, ns.length)
            var line = 1
            var index = 0
            while index < caret {
                if ns.character(at: index) == 10 { line += 1 }
                index += 1
            }
            let lineRange = ns.lineRange(for: NSRange(location: caret, length: 0))
            let column = caret - lineRange.location + 1
            onCursorChange(CursorPosition(line: line, column: column, location: caret, selectionLength: selection.length))
        }

        /// Trigger the AppKit completion panel as the user types. The popup is
        /// only useful while the cursor is on an identifier-like word (letters,
        /// digits, underscore, or just after a `.` for column qualifiers); we
        /// skip it on whitespace, punctuation, and selection ranges to avoid
        /// flashing the panel for every keystroke. The `isCompleting` guard
        /// prevents re-entry — `complete(_:)` itself can mutate the text view
        /// (when AppKit shows the inline candidate suffix), which would
        /// otherwise re-fire `textDidChange` and recurse.
        private func scheduleCompletion(in textView: NSTextView) {
            guard !isCompleting else { return }
            let selection = textView.selectedRange()
            guard selection.length == 0 else { return }
            let cursor = selection.location
            let chars = Array(textView.string)
            guard cursor > 0, cursor <= chars.count else { return }
            let prev = chars[cursor - 1]
            let isIdentifier = prev.isLetter || prev.isNumber || prev == "_" || prev == "."
            guard isIdentifier else { return }

            // Require ≥2 identifier chars before opening the popup. Triggering
            // on the first letter of every word makes typing feel hijacked,
            // because AppKit's complete() steals focus until dismissed.
            if prev != "." {
                var idLen = 0
                var i = cursor - 1
                while i >= 0 {
                    let c = chars[i]
                    if c.isLetter || c.isNumber || c == "_" { idLen += 1; i -= 1 } else { break }
                }
                guard idLen >= 2 else { return }
            }

            isCompleting = true
            textView.complete(nil)
            isCompleting = false
        }

        /// Called by `CompletionTextView` from inside
        /// `insertCompletion(_:forPartialWordRange:movement:isFinal:)`.
        ///
        /// - Preview path (`isFinal == false`): return the bare text (glyph
        ///   stripped) so the inline preview the popup paints into the editor
        ///   doesn't contain the ⚡/ƒ/▦/▤/◇ marker. Auto-quote is intentionally
        ///   skipped here because the user hasn't committed; quoting on
        ///   preview would make the inline candidate visually jump.
        /// - Final path (`isFinal == true`): return the bare text *plus*
        ///   dialect quoting for tables/columns/schemas.
        func resolveCompletion(display: String, isFinal: Bool) -> String? {
            guard let suggestion = displayToSuggestion[display] else { return nil }
            return isFinal
                ? Self.resolvedInsertion(for: suggestion, dialect: dialect)
                : suggestion.text
        }

        func textView(
            _ textView: NSTextView,
            completions words: [String],
            forPartialWordRange charRange: NSRange,
            indexOfSelectedItem index: UnsafeMutablePointer<Int>?
        ) -> [String] {
            let request = CompletionRequest(
                text: textView.string,
                cursor: NSMaxRange(charRange),
                dialect: dialect
            )
            let results = SQLCompletionProvider.suggestions(for: request, schema: schema)

            displayToSuggestion.removeAll(keepingCapacity: true)
            var displays: [String] = []
            displays.reserveCapacity(results.count)
            for s in results {
                let display = Self.glyph(for: s.kind) + " " + s.text
                displayToSuggestion[display] = s
                displays.append(display)
            }
            // Do NOT pre-select. `index = 0` makes AppKit auto-insert the
            // first candidate as a typing-completion suffix, which steals
            // focus and hijacks every keystroke. `-1` lets the user pick.
            index?.pointee = -1
            return displays
        }

        /// Glyph prefix used to differentiate suggestion categories in the
        /// completion popup. AppKit's popup is `[String]`-only — no images,
        /// no attributed strings — so a leading symbol is the only viable
        /// visual distinction. Stripped on insertion via `displayToSuggestion`.
        private static func glyph(for kind: CompletionSuggestion.Kind) -> String {
            switch kind {
            case .keyword: return "⚡"
            case .function: return "ƒ"
            case .table: return "▦"
            case .column: return "▤"
            case .schema: return "◇"
            }
        }

        /// What actually gets inserted when the user accepts a suggestion.
        /// Tables and columns are auto-quoted per dialect (Postgres double
        /// quotes, MySQL backticks) so case-sensitive identifiers like `Seat`
        /// survive the unquoted-lowercasing rule. Keywords/functions stay
        /// bare — they're case-insensitive in both dialects.
        private static func resolvedInsertion(
            for suggestion: CompletionSuggestion,
            dialect: SQLDialect
        ) -> String {
            switch suggestion.kind {
            case .table, .column, .schema:
                return dialect.quoteQualified(suggestion.text)
            case .keyword, .function:
                return suggestion.text
            }
        }

        /// ⇥ accepts the top suggestion for the identifier under the caret,
        /// inserting it directly instead of leaning on the AppKit popup's
        /// selected row (which is intentionally `-1` so as-you-type completion
        /// never hijacks typing — that left Tab with nothing to accept). Returns
        /// false when there's no partial word or no match, so the caller can fall
        /// back to opening the popup. UTF-16 throughout to match caret offsets.
        @discardableResult
        func completeTopSuggestion(_ textView: NSTextView) -> Bool {
            let selection = textView.selectedRange()
            guard selection.length == 0 else { return false }
            let ns = textView.string as NSString
            let caret = min(selection.location, ns.length)
            var start = caret
            while start > 0, Self.isIdentifierUnit(ns.character(at: start - 1)) { start -= 1 }
            guard start < caret else { return false }

            let request = CompletionRequest(text: textView.string, cursor: caret, dialect: dialect)
            let results = SQLCompletionProvider.suggestions(for: request, schema: schema)
            guard let top = results.first else { return false }

            let insertion = Self.resolvedInsertion(for: top, dialect: dialect)
            let wordRange = NSRange(location: start, length: caret - start)
            guard textView.shouldChangeText(in: wordRange, replacementString: insertion) else { return false }
            // Guard re-entrant completion: the resulting textDidChange must not
            // immediately reopen the popup for the just-completed word.
            isCompleting = true
            textView.replaceCharacters(in: wordRange, with: insertion)
            textView.didChangeText()
            isCompleting = false
            return true
        }

        private static func isIdentifierUnit(_ c: unichar) -> Bool {
            (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || (c >= 48 && c <= 57) || c == 95
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            // ⌘↩ and ⇥ are handled in CompletionTextView.keyDown — see there.
            // This remains as a fallback to open the popup if a Tab ever reaches
            // the command machinery without a completable word under the caret.
            if commandSelector == #selector(NSTextView.insertTab(_:)) {
                isCompleting = true
                textView.complete(nil)
                isCompleting = false
                return true
            }
            return false
        }
    }
}

/// SwiftUI sizes an `NSViewRepresentable` from its underlying view's
/// `intrinsicContentSize` when the parent doesn't impose a definite size.
/// `NSScrollView` returns its current frame as the intrinsic size, which
/// pinned the editor to the seed `600×400` frame even though
/// `.frame(maxWidth: .infinity)` was applied upstream — until an unrelated
/// state change forced SwiftUI to re-resolve layout (e.g. clicking Run).
/// Reporting `noIntrinsicMetric` lets SwiftUI hand us the parent's available
/// space on the very first render. Pattern matches CodeEdit / STTextView.
final class NoIntrinsicScrollView: NSScrollView {
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }
}

/// Custom `NSTextView` that intercepts the completion-acceptance step
/// instead of the in-flight `shouldChangeTextIn:` callback. Why this hook
/// and not the delegate? `shouldChangeTextIn:` fires on every popup
/// preview-insert (not just user accept) and is reentrant with
/// `replaceCharacters`, which races against `NSTextStorageDelegate`'s
/// `didProcessEditing` and crashes drawRect. `insertCompletion` is the
/// canonical single customization point — Apple's intended hook.
final class CompletionTextView: NSTextView {
    var completionResolver: ((String, Bool) -> String?)?
    /// Invoked on ⌘↩ / ⇧⌘↩. The handler decides selection-vs-statement-vs-all
    /// (it reads the live shift modifier itself).
    var onCommandReturn: (() -> Void)?
    /// Invoked on ⇥. Returns true if it accepted a completion (so the Tab is
    /// swallowed); false to fall through to the default Tab behaviour.
    var onTab: (() -> Bool)?

    /// Catch ⌘↩ and ⇥ at the key level.
    ///
    /// ⌘↩: Command-modified Return does not reliably reach the delegate's
    /// `doCommandBy` as `insertNewline:` (the field-editor command machinery
    /// treats a Command-key chord as a key equivalent, not a text command), so
    /// the run shortcut was silently dropped.
    ///
    /// ⇥: handled here rather than in `doCommandBy` so it fires even while the
    /// completion popup is open (the popup keeps the text view as first
    /// responder, so keyDown still runs) — that's what lets Tab accept the top
    /// suggestion mid-popup. keyCodes: 36 = Return, 76 = numpad Enter, 48 = Tab.
    override func keyDown(with event: NSEvent) {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if mods.contains(.command), event.keyCode == 36 || event.keyCode == 76 {
            onCommandReturn?()
            return
        }
        if event.keyCode == 48,
           mods.isDisjoint(with: [.command, .option, .control, .shift]),
           onTab?() == true {
            return
        }
        super.keyDown(with: event)
    }

    override func insertCompletion(
        _ word: String,
        forPartialWordRange charRange: NSRange,
        movement: Int,
        isFinal flag: Bool
    ) {
        // ALWAYS rewrite via resolver, including preview (`flag == false`).
        // The popup paints its inline candidate by calling this method with
        // the popup display string ("⚡ FROM"); without rewriting we'd
        // splash the glyph into the user's editor every arrow-down. The
        // resolver returns the bare text on preview, glyph-stripped + quoted
        // on final accept. See Coordinator.resolveCompletion.
        if let resolved = completionResolver?(word, flag) {
            super.insertCompletion(resolved, forPartialWordRange: charRange, movement: movement, isFinal: flag)
        } else {
            super.insertCompletion(word, forPartialWordRange: charRange, movement: movement, isFinal: flag)
        }
    }
}

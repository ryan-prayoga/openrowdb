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

    func makeNSView(context: Context) -> NoIntrinsicScrollView {
        let scroll = NoIntrinsicScrollView(frame: .zero)
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        scroll.autoresizingMask = [.width, .height]
        scroll.translatesAutoresizingMaskIntoConstraints = true

        let textView = CompletionTextView(frame: .zero)
        textView.completionResolver = { [weak coordinator = context.coordinator] display, isFinal in
            coordinator?.resolveCompletion(display: display, isFinal: isFinal)
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

        scroll.documentView = textView
        context.coordinator.textView = textView

        let highlighter = SQLSyntaxHighlighter(dialect: dialect)
        textView.textStorage?.delegate = highlighter
        context.coordinator.highlighter = highlighter
        highlighter.highlightAll(textView)

        return scroll
    }

    func updateNSView(_ nsView: NoIntrinsicScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        context.coordinator.dialect = dialect
        context.coordinator.schema = schema
        context.coordinator.onSubmit = onSubmit
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
        Coordinator(text: $text, dialect: dialect, schema: schema, onSubmit: onSubmit)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        var dialect: SQLDialect
        var schema: SchemaSnapshot
        var onSubmit: (() -> Void)?
        weak var textView: NSTextView?
        var highlighter: SQLSyntaxHighlighter?
        var lastJumpRequest: Int = 0

        private var isCompleting = false

        /// Map from popup display string (with glyph prefix) back to the raw
        /// suggestion. Needed because `textView(_:completions:...)` hands AppKit
        /// `[String]` only — we can't attach metadata. On accept we look up the
        /// kind here to decide whether to auto-quote (tables/columns) and to
        /// strip the glyph before insertion.
        private var displayToSuggestion: [String: CompletionSuggestion] = [:]

        init(text: Binding<String>, dialect: SQLDialect, schema: SchemaSnapshot, onSubmit: (() -> Void)?) {
            self.text = text
            self.dialect = dialect
            self.schema = schema
            self.onSubmit = onSubmit
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            let newValue = textView.string
            if text.wrappedValue != newValue {
                text.wrappedValue = newValue
            }
            scheduleCompletion(in: textView)
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

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSTextView.insertNewline(_:)),
               NSEvent.modifierFlags.contains(.command) {
                onSubmit?()
                return true
            }
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

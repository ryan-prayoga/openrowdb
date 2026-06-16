// SQLSyntaxHighlighter.swift
import AppKit
import OpenrowDBCore

/// Applies token colors to an `NSTextView` via temporary attributes (layout-
/// manager scoped, never persisted into storage). Driven by
/// `NSTextStorageDelegate.didProcessEditing` so it runs after every edit
/// without polling.
///
/// Two correctness requirements:
///
/// 1. **Re-tokenize on a paragraph-expanded range, not just the edit range.**
///    A keystroke might end a multi-line block comment three paragraphs above,
///    so we extend the dirty range to whole paragraphs before lexing. The
///    tokenizer is fast enough (single-pass, allocation-light) that lexing the
///    expanded range every keystroke is cheaper than maintaining incremental
///    state.
/// 2. **Use `addTemporaryAttribute(.foregroundColor)` via the layout manager,
///    not `setAttributes:` on storage.** Mutating storage during
///    `didProcessEditing` re-enters the edit cycle and corrupts the cursor;
///    layout-manager temporary attributes are designed exactly for this case
///    and don't trigger a re-edit.
@MainActor
final class SQLSyntaxHighlighter: NSObject, @preconcurrency NSTextStorageDelegate {
    var dialect: SQLDialect

    /// Palette tuned to match the user's spec (biru/cyan/oranye/ungu/abu/putih)
    /// using NSColor system semantic colors so it auto-adapts to light/dark.
    private struct Palette {
        static let keyword = NSColor.systemBlue
        static let function = NSColor.systemTeal
        static let number = NSColor.systemOrange
        static let string = NSColor.systemOrange
        static let comment = NSColor.secondaryLabelColor
        static let quotedIdentifier = NSColor.systemPurple
        static let identifier = NSColor.labelColor
        static let punctuation = NSColor.labelColor
    }

    init(dialect: SQLDialect) {
        self.dialect = dialect
    }

    func highlightAll(_ textView: NSTextView) {
        guard let layoutManager = textView.layoutManager,
              let textStorage = textView.textStorage else { return }
        let full = NSRange(location: 0, length: textStorage.length)
        applyHighlight(text: textStorage.string, range: full, layoutManager: layoutManager)
    }

    func textStorage(
        _ textStorage: NSTextStorage,
        didProcessEditing editedMask: NSTextStorageEditActions,
        range editedRange: NSRange,
        changeInLength delta: Int
    ) {
        guard editedMask.contains(.editedCharacters) else { return }
        guard let layoutManager = textStorage.layoutManagers.first else { return }

        // CRITICAL: Defer attribute mutation to the next runloop tick.
        // `addTemporaryAttribute` synchronously inside `didProcessEditing`
        // can race with reentrant edits (e.g. NSTextView.complete() popups
        // calling replaceCharacters), causing NSLayoutManager to draw against
        // stale ranges and crash with EXC_BREAKPOINT in
        // `ensureAttributesAreFixedInRange:` during drawRect.
        // Async-on-main lets the current edit transaction finish first.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let full = textStorage.string as NSString
            let liveLen = full.length
            // The edit cycle may have continued after this was scheduled, so
            // re-clamp every range against the *current* storage length.
            let clamped = NSRange(
                location: min(max(0, editedRange.location), liveLen),
                length: min(editedRange.length, max(0, liveLen - editedRange.location))
            )
            guard clamped.length > 0 || liveLen == 0 else { return }
            let expanded = liveLen == 0
                ? NSRange(location: 0, length: 0)
                : full.paragraphRange(for: clamped)
            let safe = NSRange(
                location: min(max(0, expanded.location), liveLen),
                length: min(expanded.length, max(0, liveLen - expanded.location))
            )
            self.applyHighlight(text: textStorage.string, range: safe, layoutManager: layoutManager)
        }
    }

    private func applyHighlight(text: String, range: NSRange, layoutManager: NSLayoutManager) {
        let nsText = text as NSString
        guard range.location >= 0,
              range.length > 0,
              NSMaxRange(range) <= nsText.length else { return }

        layoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: range)

        let segment = nsText.substring(with: range)
        let tokens = SQLTokenizer.tokenize(segment, dialect: dialect)

        for token in tokens {
            guard let color = color(for: token.kind) else { continue }
            let absolute = NSRange(
                location: range.location + token.range.location,
                length: token.range.length
            )
            guard NSMaxRange(absolute) <= nsText.length else { continue }
            layoutManager.addTemporaryAttribute(.foregroundColor, value: color, forCharacterRange: absolute)
        }
    }

    private func color(for kind: SQLTokenKind) -> NSColor? {
        switch kind {
        case .keyword: return Palette.keyword
        case .function: return Palette.function
        case .numberLiteral: return Palette.number
        case .stringLiteral: return Palette.string
        case .lineComment, .blockComment: return Palette.comment
        case .quotedIdentifier: return Palette.quotedIdentifier
        case .identifier, .punctuation, .operator, .whitespace: return nil
        }
    }
}

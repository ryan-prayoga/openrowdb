// CodeEditor.swift
import AppKit
import OpenrowDBCore
import SwiftUI

struct CodeEditor: NSViewRepresentable {
    @Binding var text: String
    var dialect: SQLDialect
    var schema: SchemaSnapshot
    var onSubmit: (() -> Void)?

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        guard let textView = scroll.documentView as? NSTextView else { return scroll }

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
        textView.textContainerInset = NSSize(width: 6, height: 6)
        textView.drawsBackground = true
        textView.backgroundColor = .textBackgroundColor
        textView.textColor = .labelColor
        textView.insertionPointColor = .labelColor
        textView.string = text

        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false

        context.coordinator.textView = textView
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        context.coordinator.dialect = dialect
        context.coordinator.schema = schema
        context.coordinator.onSubmit = onSubmit
        if textView.string != text {
            let selected = textView.selectedRange()
            textView.string = text
            let length = (text as NSString).length
            let clamped = NSRange(
                location: min(selected.location, length),
                length: min(selected.length, max(0, length - min(selected.location, length)))
            )
            textView.setSelectedRange(clamped)
        }
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
            index?.pointee = -1
            return results.map(\.text)
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSTextView.insertNewline(_:)),
               NSEvent.modifierFlags.contains(.command) {
                onSubmit?()
                return true
            }
            if commandSelector == #selector(NSTextView.insertTab(_:)) {
                textView.complete(nil)
                return true
            }
            return false
        }
    }
}

// LineNumberRulerView.swift
import AppKit

/// Gutter ruler that paints 1-based line numbers aligned with an `NSTextView`.
final class LineNumberRulerView: NSRulerView {
    weak var textView: NSTextView?

    init(textView: NSTextView, scrollView: NSScrollView) {
        self.textView = textView
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        ruleThickness = 40
        clientView = textView
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        // Match the editor's background so the gutter and text form one surface
        // with no vertical seam between them.
        NSColor.textBackgroundColor.setFill()
        bounds.fill()

        // Hairline dividing the line-number gutter from the code. It is painted
        // inside the ruler, so it spans only the editor's height — it never
        // bleeds up behind the toolbar or down behind the results pane, which
        // live outside this scroll view. The earlier "clear gutter" approach
        // had the inverse problem: the gutter showed the lighter window colour
        // and its seam against the dark text read as a line running the full
        // pane height.
        NSColor.separatorColor.setStroke()
        let seamX = ruleThickness - 0.5
        let seam = NSBezierPath()
        seam.move(to: NSPoint(x: seamX, y: bounds.minY))
        seam.line(to: NSPoint(x: seamX, y: bounds.maxY))
        seam.lineWidth = 1
        seam.stroke()

        guard let textView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return }

        let nsString = textView.string as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]

        let visibleRect = textView.visibleRect
        let glyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)
        guard glyphRange.length > 0 || glyphRange.location < nsString.length else { return }

        let firstChar = min(glyphRange.location, max(0, nsString.length - 1))
        let prefix = nsString.substring(to: firstChar)
        var lineNumber = prefix.reduce(into: 1) { count, char in
            if char == "\n" { count += 1 }
        }

        layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { _, usedRect, _, _, _ in
            let y = usedRect.minY + textView.textContainerInset.height - visibleRect.minY
            let label = "\(lineNumber)" as NSString
            let size = label.size(withAttributes: attributes)
            let point = NSPoint(x: self.ruleThickness - size.width - 6, y: y + (usedRect.height - size.height) / 2)
            label.draw(at: point, withAttributes: attributes)
            lineNumber += 1
        }
    }

    func refresh() {
        needsDisplay = true
    }
}
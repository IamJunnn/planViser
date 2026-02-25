import AppKit

extension Notification.Name {
    static let checklistToggled = Notification.Name("checklistToggled")
}

final class ChecklistAttachmentCell: NSTextAttachmentCell {
    var isChecked = false

    private let boxSize: CGFloat = 14
    private let cornerRadius: CGFloat = 3

    override func cellSize() -> NSSize {
        NSSize(width: boxSize + 4, height: boxSize + 2)
    }

    override func cellBaselineOffset() -> NSPoint {
        NSPoint(x: 0, y: -2)
    }

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView?) {
        let rect = NSRect(
            x: cellFrame.origin.x + 1,
            y: cellFrame.origin.y + (cellFrame.height - boxSize) / 2,
            width: boxSize,
            height: boxSize
        )
        let path = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)

        if isChecked {
            NSColor.controlAccentColor.setFill()
            path.fill()

            // Draw checkmark
            let check = NSBezierPath()
            let inset: CGFloat = 3
            let left = NSPoint(x: rect.minX + inset, y: rect.midY)
            let mid = NSPoint(x: rect.minX + boxSize * 0.4, y: rect.maxY - inset)
            let right = NSPoint(x: rect.maxX - inset, y: rect.minY + inset)
            check.move(to: left)
            check.line(to: mid)
            check.line(to: right)
            check.lineWidth = 2
            check.lineCapStyle = .round
            check.lineJoinStyle = .round
            NSColor.white.setStroke()
            check.stroke()
        } else {
            NSColor.separatorColor.setStroke()
            path.lineWidth = 1.5
            path.stroke()
        }
    }

    override func wantsToTrackMouse() -> Bool { true }

    override func trackMouse(with theEvent: NSEvent, in cellFrame: NSRect, of controlView: NSView?, untilMouseUp flag: Bool) -> Bool {
        isChecked.toggle()
        controlView?.needsDisplay = true
        NotificationCenter.default.post(name: .checklistToggled, object: self)
        return true
    }

    override func cellFrame(for textContainer: NSTextContainer, proposedLineFragment lineFrag: NSRect, glyphPosition position: NSPoint, characterIndex charIndex: Int) -> NSRect {
        let size = cellSize()
        return NSRect(x: 0, y: (lineFrag.height - size.height) / 2, width: size.width, height: size.height)
    }
}

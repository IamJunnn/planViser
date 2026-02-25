import AppKit

final class DividerAttachmentCell: NSTextAttachmentCell {

    override func cellSize() -> NSSize {
        NSSize(width: 10000, height: 16)
    }

    override func cellBaselineOffset() -> NSPoint {
        NSPoint(x: 0, y: -4)
    }

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView?) {
        let lineY = cellFrame.midY
        let inset: CGFloat = 4
        let lineRect = NSRect(
            x: cellFrame.origin.x + inset,
            y: lineY - 0.5,
            width: cellFrame.width - inset * 2,
            height: 1
        )

        NSColor.separatorColor.setFill()
        lineRect.fill()
    }

    override func cellFrame(for textContainer: NSTextContainer, proposedLineFragment lineFrag: NSRect, glyphPosition position: NSPoint, characterIndex charIndex: Int) -> NSRect {
        NSRect(
            x: 0,
            y: 0,
            width: lineFrag.width,
            height: 16
        )
    }

    override func wantsToTrackMouse() -> Bool { false }
}

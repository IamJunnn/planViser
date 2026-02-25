import AppKit

final class CanvasNSView: NSView {

    var document = CanvasDocument() { didSet { needsDisplay = true } }
    var currentTool: CanvasTool = .pen
    var currentColor = CodableColor.black
    var currentLineWidth: CGFloat = 2
    var onDocumentChange: ((CanvasDocument) -> Void)?

    // Pan & Zoom
    private var panOffset = CGPoint.zero
    private var zoomScale: CGFloat = 1.0

    // Drawing state
    private var currentStrokePoints: [CGPoint] = []
    private var dragStart: CGPoint = .zero
    private var dragCurrent: CGPoint = .zero
    private var isDragging = false

    // Undo/Redo
    private var undoStack: [CanvasDocument] = []
    private var redoStack: [CanvasDocument] = []

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.textBackgroundColor.cgColor
    }

    // MARK: - Coordinate Conversion

    private func canvasPoint(from event: NSEvent) -> CGPoint {
        let viewPoint = convert(event.locationInWindow, from: nil)
        return CGPoint(
            x: (viewPoint.x - panOffset.x) / zoomScale,
            y: (viewPoint.y - panOffset.y) / zoomScale
        )
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.setFillColor(NSColor.textBackgroundColor.cgColor)
        ctx.fill(bounds)

        ctx.saveGState()
        ctx.translateBy(x: panOffset.x, y: panOffset.y)
        ctx.scaleBy(x: zoomScale, y: zoomScale)

        // Draw strokes
        for stroke in document.strokes {
            drawStroke(stroke, in: ctx)
        }

        // Draw shapes
        for shape in document.shapes {
            drawShape(shape, in: ctx)
        }

        // Draw text boxes
        for textBox in document.textBoxes {
            drawTextBox(textBox, in: ctx)
        }

        // Draw in-progress stroke/shape
        if isDragging {
            switch currentTool {
            case .pen:
                if !currentStrokePoints.isEmpty {
                    let stroke = CanvasStroke(points: currentStrokePoints, color: currentColor, lineWidth: currentLineWidth)
                    drawStroke(stroke, in: ctx)
                }
            case .rectangle, .circle, .line:
                let origin = CGPoint(x: min(dragStart.x, dragCurrent.x), y: min(dragStart.y, dragCurrent.y))
                let size = CGSize(width: abs(dragCurrent.x - dragStart.x), height: abs(dragCurrent.y - dragStart.y))
                let shapeType: ShapeType = currentTool == .rectangle ? .rectangle : currentTool == .circle ? .circle : .line
                if shapeType == .line {
                    let shape = CanvasShape(shapeType: .line, origin: dragStart, size: CGSize(width: dragCurrent.x - dragStart.x, height: dragCurrent.y - dragStart.y), color: currentColor, lineWidth: currentLineWidth, isFilled: false)
                    drawShape(shape, in: ctx)
                } else {
                    let shape = CanvasShape(shapeType: shapeType, origin: origin, size: size, color: currentColor, lineWidth: currentLineWidth, isFilled: false)
                    drawShape(shape, in: ctx)
                }
            default:
                break
            }
        }

        ctx.restoreGState()
    }

    private func drawStroke(_ stroke: CanvasStroke, in ctx: CGContext) {
        guard stroke.points.count > 1 else { return }
        ctx.setStrokeColor(stroke.color.cgColor)
        ctx.setLineWidth(stroke.lineWidth)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.beginPath()
        ctx.move(to: stroke.points[0])
        for i in 1..<stroke.points.count {
            ctx.addLine(to: stroke.points[i])
        }
        ctx.strokePath()
    }

    private func drawShape(_ shape: CanvasShape, in ctx: CGContext) {
        ctx.setStrokeColor(shape.color.cgColor)
        ctx.setLineWidth(shape.lineWidth)
        let rect = CGRect(origin: shape.origin, size: shape.size)

        switch shape.shapeType {
        case .rectangle:
            if shape.isFilled {
                ctx.setFillColor(shape.color.cgColor)
                ctx.fill(rect)
            } else {
                ctx.stroke(rect)
            }
        case .circle:
            if shape.isFilled {
                ctx.setFillColor(shape.color.cgColor)
                ctx.fillEllipse(in: rect)
            } else {
                ctx.strokeEllipse(in: rect)
            }
        case .line:
            ctx.beginPath()
            ctx.move(to: shape.origin)
            let endPoint = CGPoint(x: shape.origin.x + shape.size.width, y: shape.origin.y + shape.size.height)
            ctx.addLine(to: endPoint)
            ctx.strokePath()
        }
    }

    private func drawTextBox(_ textBox: CanvasTextBox, in ctx: CGContext) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: textBox.fontSize),
            .foregroundColor: textBox.color.nsColor
        ]
        let str = textBox.text as NSString
        let rect = CGRect(origin: textBox.origin, size: textBox.size)
        str.draw(in: rect, withAttributes: attrs)
    }

    // MARK: - Mouse Events

    override func mouseDown(with event: NSEvent) {
        let point = canvasPoint(from: event)
        isDragging = true
        dragStart = point
        dragCurrent = point

        switch currentTool {
        case .pen:
            currentStrokePoints = [point]
        case .eraser:
            eraseAt(point)
        case .textBox:
            promptForText(at: point)
            isDragging = false
        default:
            break
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let point = canvasPoint(from: event)
        dragCurrent = point

        switch currentTool {
        case .pen:
            currentStrokePoints.append(point)
            needsDisplay = true
        case .eraser:
            eraseAt(point)
        default:
            needsDisplay = true
        }
    }

    override func mouseUp(with event: NSEvent) {
        let point = canvasPoint(from: event)
        isDragging = false

        switch currentTool {
        case .pen:
            currentStrokePoints.append(point)
            if currentStrokePoints.count > 1 {
                pushUndo()
                document.strokes.append(CanvasStroke(points: currentStrokePoints, color: currentColor, lineWidth: currentLineWidth))
                notifyChange()
            }
            currentStrokePoints = []

        case .rectangle, .circle, .line:
            let origin = CGPoint(x: min(dragStart.x, point.x), y: min(dragStart.y, point.y))
            let size = CGSize(width: abs(point.x - dragStart.x), height: abs(point.y - dragStart.y))
            guard size.width > 2 || size.height > 2 else { break }

            pushUndo()
            let shapeType: ShapeType = currentTool == .rectangle ? .rectangle : currentTool == .circle ? .circle : .line
            if shapeType == .line {
                document.shapes.append(CanvasShape(shapeType: .line, origin: dragStart, size: CGSize(width: point.x - dragStart.x, height: point.y - dragStart.y), color: currentColor, lineWidth: currentLineWidth, isFilled: false))
            } else {
                document.shapes.append(CanvasShape(shapeType: shapeType, origin: origin, size: size, color: currentColor, lineWidth: currentLineWidth, isFilled: false))
            }
            notifyChange()

        default:
            break
        }

        needsDisplay = true
    }

    // MARK: - Scroll & Zoom

    override func scrollWheel(with event: NSEvent) {
        panOffset.x += event.scrollingDeltaX
        panOffset.y += event.scrollingDeltaY
        needsDisplay = true
    }

    override func magnify(with event: NSEvent) {
        let oldScale = zoomScale
        zoomScale = max(0.1, min(5.0, zoomScale + event.magnification))

        // Zoom toward cursor
        let viewPoint = convert(event.locationInWindow, from: nil)
        let scaleDiff = zoomScale / oldScale
        panOffset.x = viewPoint.x - (viewPoint.x - panOffset.x) * scaleDiff
        panOffset.y = viewPoint.y - (viewPoint.y - panOffset.y) * scaleDiff

        needsDisplay = true
    }

    // MARK: - Eraser

    private func eraseAt(_ point: CGPoint) {
        let eraserRadius: CGFloat = max(currentLineWidth * 2, 10)
        let before = document

        document.strokes.removeAll { stroke in
            stroke.points.contains { p in
                hypot(p.x - point.x, p.y - point.y) < eraserRadius
            }
        }

        document.shapes.removeAll { shape in
            let rect = CGRect(origin: shape.origin, size: shape.size).insetBy(dx: -eraserRadius, dy: -eraserRadius)
            return rect.contains(point)
        }

        if document != before {
            if undoStack.last != before { pushUndo(snapshot: before) }
            notifyChange()
            needsDisplay = true
        }
    }

    // MARK: - Text Box

    private func promptForText(at point: CGPoint) {
        let alert = NSAlert()
        alert.messageText = "Add Text"
        alert.addButton(withTitle: "Add")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 250, height: 24))
        field.placeholderString = "Enter text..."
        alert.accessoryView = field

        guard alert.runModal() == .alertFirstButtonReturn, !field.stringValue.isEmpty else { return }

        pushUndo()
        document.textBoxes.append(CanvasTextBox(
            text: field.stringValue,
            origin: point,
            size: CGSize(width: 200, height: 30),
            fontSize: 14,
            color: currentColor
        ))
        notifyChange()
        needsDisplay = true
    }

    // MARK: - Undo / Redo

    func performUndo() {
        guard let prev = undoStack.popLast() else { return }
        redoStack.append(document)
        document = prev
        notifyChange()
    }

    func performRedo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(document)
        document = next
        notifyChange()
    }

    private func pushUndo(snapshot: CanvasDocument? = nil) {
        undoStack.append(snapshot ?? document)
        redoStack.removeAll()
    }

    private func notifyChange() {
        onDocumentChange?(document)
    }

    // MARK: - Rasterize

    func rasterize(size: CGSize? = nil) -> NSImage {
        let targetSize = size ?? bounds.size
        let image = NSImage(size: targetSize)
        image.lockFocus()
        if let ctx = NSGraphicsContext.current?.cgContext {
            ctx.setFillColor(NSColor.textBackgroundColor.cgColor)
            ctx.fill(CGRect(origin: .zero, size: targetSize))
            for stroke in document.strokes { drawStroke(stroke, in: ctx) }
            for shape in document.shapes { drawShape(shape, in: ctx) }
            for textBox in document.textBoxes { drawTextBox(textBox, in: ctx) }
        }
        image.unlockFocus()
        return image
    }
}

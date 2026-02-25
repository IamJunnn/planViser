import SwiftUI
import AppKit

struct CanvasView: NSViewRepresentable {
    @Binding var document: CanvasDocument
    var tool: CanvasTool
    var color: CodableColor
    var lineWidth: CGFloat
    var onDocumentChange: ((CanvasDocument) -> Void)?

    // Expose the underlying view for undo/redo
    class ViewHolder {
        weak var canvasView: CanvasNSView?
    }

    var viewHolder: ViewHolder?

    func makeNSView(context: Context) -> CanvasNSView {
        let view = CanvasNSView(frame: .zero)
        view.document = document
        view.currentTool = tool
        view.currentColor = color
        view.currentLineWidth = lineWidth
        view.onDocumentChange = { newDoc in
            DispatchQueue.main.async {
                self.document = newDoc
                self.onDocumentChange?(newDoc)
            }
        }
        viewHolder?.canvasView = view
        return view
    }

    func updateNSView(_ nsView: CanvasNSView, context: Context) {
        nsView.currentTool = tool
        nsView.currentColor = color
        nsView.currentLineWidth = lineWidth
        if nsView.document != document {
            nsView.document = document
        }
        viewHolder?.canvasView = nsView
    }
}

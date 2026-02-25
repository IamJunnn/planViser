import SwiftUI
import AppKit

struct InlineSketchView: View {
    var initialImage: NSImage?
    var onDone: (NSImage) -> Void
    var onCancel: () -> Void

    @State private var document = CanvasDocument()
    @State private var selectedTool: CanvasTool = .pen
    @State private var strokeColor: Color = .primary
    @State private var lineWidth: CGFloat = 2
    @State private var viewHolder = CanvasView.ViewHolder()

    var body: some View {
        VStack(spacing: 0) {
            // Mini toolbar
            HStack(spacing: 4) {
                ForEach([CanvasTool.pen, .eraser]) { tool in
                    Button {
                        selectedTool = tool
                    } label: {
                        Image(systemName: tool.icon)
                            .font(.system(size: 12, weight: .medium))
                            .frame(width: 26, height: 22)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(selectedTool == tool ? Color.accentColor.opacity(0.2) : Color.clear)
                            )
                    }
                    .buttonStyle(.borderless)
                }

                Divider().frame(height: 14)

                ColorPicker("", selection: $strokeColor, supportsOpacity: false)
                    .labelsHidden()
                    .frame(width: 20, height: 20)

                Slider(value: $lineWidth, in: 1...10, step: 1)
                    .frame(width: 60)

                Spacer()

                Button("Cancel") { onCancel() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                Button("Done") {
                    let image = viewHolder.canvasView?.rasterize(size: CGSize(width: 500, height: 300))
                        ?? NSImage(size: CGSize(width: 500, height: 300))
                    onDone(image)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)

            Divider()

            // Canvas
            CanvasView(
                document: $document,
                tool: selectedTool,
                color: CodableColor(nsColor: NSColor(strokeColor)),
                lineWidth: lineWidth,
                viewHolder: viewHolder
            )
            .frame(width: 500, height: 300)
            .border(Color.secondary.opacity(0.3), width: 1)
        }
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

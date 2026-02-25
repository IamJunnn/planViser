import SwiftUI

struct CanvasToolbar: View {
    @Binding var selectedTool: CanvasTool
    @Binding var strokeColor: Color
    @Binding var lineWidth: CGFloat
    var onUndo: () -> Void
    var onRedo: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            // Tool picker
            HStack(spacing: 2) {
                ForEach(CanvasTool.allCases) { tool in
                    Button {
                        selectedTool = tool
                    } label: {
                        Image(systemName: tool.icon)
                            .font(.system(size: 13, weight: .medium))
                            .frame(width: 28, height: 24)
                            .contentShape(Rectangle())
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(selectedTool == tool ? Color.accentColor.opacity(0.2) : Color.clear)
                            )
                    }
                    .buttonStyle(.borderless)
                    .help(tool.label)
                }
            }

            toolbarDivider

            // Color picker
            ColorPicker("", selection: $strokeColor, supportsOpacity: false)
                .labelsHidden()
                .frame(width: 22, height: 22)
                .help("Stroke color")

            toolbarDivider

            // Line width
            HStack(spacing: 4) {
                Image(systemName: "lineweight")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Slider(value: $lineWidth, in: 1...20, step: 1)
                    .frame(width: 80)
                Text("\(Int(lineWidth))")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
            }

            toolbarDivider

            // Undo/Redo
            HStack(spacing: 2) {
                Button(action: onUndo) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: 26, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .help("Undo")

                Button(action: onRedo) {
                    Image(systemName: "arrow.uturn.forward")
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: 26, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .help("Redo")
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var toolbarDivider: some View {
        Divider()
            .frame(height: 16)
            .padding(.horizontal, 4)
    }
}

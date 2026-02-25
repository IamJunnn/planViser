import SwiftUI
import SwiftData

struct CanvasEditorView: View {
    @Bindable var note: SecureNote
    @Environment(\.modelContext) private var modelContext

    @State private var canvasDocument = CanvasDocument()
    @State private var selectedTool: CanvasTool = .pen
    @State private var strokeColor: Color = .primary
    @State private var lineWidth: CGFloat = 2
    @State private var saveTask: Task<Void, Never>?
    @State private var didLoad = false
    @State private var viewHolder = CanvasView.ViewHolder()

    var body: some View {
        VStack(spacing: 0) {
            // Title
            TextField("Title", text: $note.title)
                .textFieldStyle(.plain)
                .font(.system(size: 26, weight: .bold))
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 4)
                .onChange(of: note.title) { _, _ in debouncedSave() }

            // Timestamp
            Text(note.updatedAt.formatted(date: .long, time: .shortened))
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.bottom, 10)

            Divider().padding(.horizontal, 16)

            // Toolbar
            CanvasToolbar(
                selectedTool: $selectedTool,
                strokeColor: $strokeColor,
                lineWidth: $lineWidth,
                onUndo: { viewHolder.canvasView?.performUndo() },
                onRedo: { viewHolder.canvasView?.performRedo() }
            )

            Divider().padding(.horizontal, 16)

            // Canvas
            CanvasView(
                document: $canvasDocument,
                tool: selectedTool,
                color: CodableColor(nsColor: NSColor(strokeColor)),
                lineWidth: lineWidth,
                onDocumentChange: { _ in debouncedSave() },
                viewHolder: viewHolder
            )
            .onAppear { loadContent() }

            // Footer
            HStack(spacing: 4) {
                if note.encryptedBody != nil {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 9))
                    Text("Encrypted")
                        .font(.system(size: 10, weight: .medium))
                }

                Spacer()

                Text("Edited \(note.updatedAt.formatted(.relative(presentation: .named)))")
                    .font(.system(size: 10))
            }
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 20)
            .padding(.vertical, 6)
        }
    }

    private func loadContent() {
        guard !didLoad else { return }
        didLoad = true

        guard let encrypted = note.encryptedBody else { return }

        do {
            let jsonData = try NoteEncryptionService.shared.decrypt(encrypted)
            canvasDocument = try JSONDecoder().decode(CanvasDocument.self, from: jsonData)
        } catch {
            print("[CanvasEditor] Failed to load: \(error)")
        }
    }

    private func debouncedSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            await MainActor.run { saveContent() }
        }
    }

    private func saveContent() {
        note.updatedAt = Date()

        do {
            let jsonData = try JSONEncoder().encode(canvasDocument)
            note.encryptedBody = try NoteEncryptionService.shared.encrypt(jsonData)
        } catch {
            print("[CanvasEditor] Save failed: \(error)")
        }
    }
}

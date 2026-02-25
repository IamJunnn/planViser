import SwiftUI
import SwiftData

struct NoteEditorView: View {
    @Bindable var note: SecureNote
    @Environment(\.modelContext) private var modelContext

    @State private var attributedText = NSAttributedString()
    @State private var editorCoordinator: RichTextEditor.Coordinator?
    @State private var saveTask: Task<Void, Never>?
    @State private var didLoad = false

    var body: some View {
        VStack(spacing: 0) {
            // Title — large Apple Notes style
            TextField("Title", text: $note.title)
                .textFieldStyle(.plain)
                .font(.system(size: 26, weight: .bold, design: .default))
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 4)
                .onChange(of: note.title) { _, _ in
                    debouncedSave()
                }

            // Subtitle timestamp
            Text(note.updatedAt.formatted(date: .long, time: .shortened))
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.bottom, 10)

            Divider().padding(.horizontal, 16)

            // Toolbar
            RichTextToolbar(coordinator: editorCoordinator)

            Divider().padding(.horizontal, 16)

            // Editor
            RichTextEditor(attributedText: $attributedText, onTextChange: {
                debouncedSave()
            }, onCoordinatorReady: { coordinator in
                editorCoordinator = coordinator
            })
            .id(note.id)
            .onAppear {
                loadContent()
            }
            .onChange(of: note.id) { _, _ in
                didLoad = false
                attributedText = NSAttributedString()
                editorCoordinator = nil
                loadContent()
            }

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
            let rtfData = try NoteEncryptionService.shared.decrypt(encrypted)
            if let raw = NSMutableAttributedString(rtfd: rtfData, documentAttributes: nil) {
                AdaptiveTextView.normalizeColors(raw)
                attributedText = raw
            } else if let raw = try? NSMutableAttributedString(data: rtfData, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil) {
                AdaptiveTextView.normalizeColors(raw)
                attributedText = raw
            }
        } catch {
            print("[NoteEditor] Failed to decrypt: \(error)")
        }
    }

    private func debouncedSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                saveContent()
            }
        }
    }

    private func saveContent() {
        note.updatedAt = Date()

        let range = NSRange(location: 0, length: attributedText.length)
        guard let rtfData = attributedText.rtfd(from: range, documentAttributes: [.documentType: NSAttributedString.DocumentType.rtfd]) else {
            if let rtf = try? attributedText.data(from: range, documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]) {
                do {
                    note.encryptedBody = try NoteEncryptionService.shared.encrypt(rtf)
                } catch {
                    print("[NoteEditor] Encrypt failed: \(error)")
                }
            }
            return
        }

        do {
            note.encryptedBody = try NoteEncryptionService.shared.encrypt(rtfData)
        } catch {
            print("[NoteEditor] Encrypt failed: \(error)")
        }
    }
}

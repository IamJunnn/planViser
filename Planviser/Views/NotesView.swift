import SwiftUI
import SwiftData

struct NotesView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SecureNote.updatedAt, order: .reverse)
    private var notes: [SecureNote]

    @ObservedObject private var unlockManager = NoteUnlockManager.shared

    @State private var selectedNoteID: UUID?
    @State private var searchText = ""
    @State private var noteToDelete: SecureNote?

    private var filteredNotes: [SecureNote] {
        let base = searchText.isEmpty ? Array(notes) : notes.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
        return base.sorted { a, b in
            if a.isPinned != b.isPinned { return a.isPinned }
            return a.updatedAt > b.updatedAt
        }
    }

    private var selectedNote: SecureNote? {
        guard let id = selectedNoteID else { return nil }
        return notes.first { $0.id == id }
    }

    var body: some View {
        HSplitView {
            // MARK: - Note List
            VStack(spacing: 0) {
                // Search + New
                HStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.tertiary)
                        TextField("Search", text: $searchText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(.quaternary.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                    Menu {
                        Button(action: { createNote(type: .richText) }) {
                            Label("New Note", systemImage: "note.text")
                        }
                        Button(action: { createNote(type: .canvas) }) {
                            Label("New Canvas", systemImage: "scribble")
                        }
                    } label: {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .menuStyle(.borderlessButton)
                    .frame(width: 24)
                    .help("New note")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)

                // Note list
                if filteredNotes.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "note.text")
                            .font(.system(size: 32, weight: .thin))
                            .foregroundStyle(.tertiary)
                        Text(searchText.isEmpty ? "No Notes" : "No Results")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 1) {
                            ForEach(filteredNotes, id: \.id) { note in
                                NoteRowView(note: note, isSelected: selectedNoteID == note.id, isLocked: !unlockManager.isUnlocked)
                                    .onTapGesture(count: 2) {
                                        noteToDelete = note
                                    }
                                    .onTapGesture {
                                        selectedNoteID = note.id
                                    }
                                    .contextMenu {
                                        Button(note.isPinned ? "Unpin" : "Pin to Top") {
                                            note.isPinned.toggle()
                                        }
                                        Divider()
                                        Button(role: .destructive) {
                                            noteToDelete = note
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                                .foregroundStyle(.red)
                                        }
                                    }
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.top, 4)
                    }
                }
            }
            .frame(minWidth: 220, idealWidth: 260, maxWidth: 340)

            // MARK: - Detail Area
            Group {
                if let note = selectedNote {
                    if unlockManager.isUnlocked {
                        switch note.noteType {
                        case .richText:
                            NoteEditorView(note: note)
                                .id(note.id)
                        case .canvas:
                            CanvasEditorView(note: note)
                                .id(note.id)
                        }
                    } else {
                        lockedPlaceholder
                    }
                } else {
                    emptyPlaceholder
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .alert("Delete Note", isPresented: Binding(
            get: { noteToDelete != nil },
            set: { if !$0 { noteToDelete = nil } }
        )) {
            Button("Cancel", role: .cancel) {
                noteToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let note = noteToDelete {
                    deleteNote(note)
                    noteToDelete = nil
                }
            }
        } message: {
            if let note = noteToDelete {
                Text("Are you sure you want to delete \"\(note.title.isEmpty ? "Untitled Note" : note.title)\"? This cannot be undone.")
            }
        }
    }

    // MARK: - Locked Placeholder

    private var lockedPlaceholder: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.fill")
                .font(.system(size: 44, weight: .thin))
                .foregroundStyle(.tertiary)

            VStack(spacing: 6) {
                Text("Note Locked")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)

                Text("Authenticate to view this note")
                    .font(.system(size: 13))
                    .foregroundStyle(.tertiary)
            }

            Button(action: { unlockManager.authenticate() }) {
                HStack(spacing: 6) {
                    Image(systemName: "touchid")
                        .font(.system(size: 16))
                    Text("Unlock")
                        .font(.system(size: 13, weight: .medium))
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)

            if let error = unlockManager.authError {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(.red.opacity(0.8))
            }
        }
    }

    // MARK: - Empty Placeholder

    private var emptyPlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "note.text")
                .font(.system(size: 44, weight: .thin))
                .foregroundStyle(.tertiary)
            Text("Select a note or create a new one")
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Actions

    private func createNote(type: NoteType) {
        let note = SecureNote(noteType: type)
        if type == .canvas {
            note.title = "Untitled Canvas"
        }
        modelContext.insert(note)
        selectedNoteID = note.id

        if !unlockManager.isUnlocked {
            unlockManager.authenticate()
        }
    }

    private func deleteNote(_ note: SecureNote) {
        if selectedNoteID == note.id {
            selectedNoteID = nil
        }
        modelContext.delete(note)
    }
}

// MARK: - Note Row

struct NoteRowView: View {
    let note: SecureNote
    let isSelected: Bool
    var isLocked: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                if note.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.orange)
                }

                Image(systemName: isLocked ? "lock.fill" : (note.noteType == .canvas ? "scribble" : "note.text"))
                    .font(.system(size: 10))
                    .foregroundStyle(isSelected ? .white.opacity(0.7) : .secondary)

                if isLocked {
                    Text("Locked Note")
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .foregroundStyle(isSelected ? .white.opacity(0.7) : .secondary)
                } else {
                    Text(note.title.isEmpty ? "Untitled Note" : note.title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .foregroundStyle(isSelected ? .white : .primary)
                }
            }

            HStack(spacing: 6) {
                if isLocked {
                    Text("No additional information")
                        .font(.system(size: 11))
                        .foregroundStyle(isSelected ? Color.white.opacity(0.5) : Color.secondary.opacity(0.5))
                } else {
                    Text(note.updatedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(size: 11))
                        .foregroundStyle(isSelected ? .white.opacity(0.7) : .secondary)

                    if note.encryptedBody != nil {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 8))
                            .foregroundColor(isSelected ? .white.opacity(0.5) : .gray.opacity(0.4))
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? Color.accentColor : Color.clear)
        )
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

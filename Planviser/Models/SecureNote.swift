import Foundation
import SwiftData

enum NoteType: String, Codable {
    case richText
    case canvas
}

@Model
final class SecureNote {
    var id: UUID
    var title: String
    var encryptedBody: Data?
    var createdAt: Date
    var updatedAt: Date
    var isPinned: Bool
    var noteTypeRaw: String = NoteType.richText.rawValue

    var noteType: NoteType {
        get { NoteType(rawValue: noteTypeRaw) ?? .richText }
        set { noteTypeRaw = newValue.rawValue }
    }

    init(title: String = "Untitled Note", encryptedBody: Data? = nil, isPinned: Bool = false, noteType: NoteType = .richText) {
        self.id = UUID()
        self.title = title
        self.encryptedBody = encryptedBody
        self.createdAt = Date()
        self.updatedAt = Date()
        self.isPinned = isPinned
        self.noteTypeRaw = noteType.rawValue
    }
}

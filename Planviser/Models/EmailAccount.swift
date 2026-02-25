import Foundation
import SwiftData
import SwiftUI

enum EmailProvider: String, Codable {
    case gmail
    case outlook
    case imap
}

enum AccountStatus: String, Codable {
    case connected
    case disconnected
    case error
}

@Model
final class EmailAccount {
    var id: UUID
    var provider: EmailProvider
    var email: String
    var displayName: String
    var status: AccountStatus
    var lastSyncDate: Date?
    var colorHex: String?

    @Relationship(deleteRule: .cascade, inverse: \EmailMessage.account)
    var messages: [EmailMessage] = []

    @Transient
    var color: Color {
        if let hex = colorHex, let c = Color(hex: hex) { return c }
        switch provider {
        case .gmail: return .red
        case .outlook: return .blue
        case .imap: return .teal
        }
    }

    init(provider: EmailProvider, email: String, displayName: String) {
        self.id = UUID()
        self.provider = provider
        self.email = email
        self.displayName = displayName
        self.status = .connected
        switch provider {
        case .gmail: self.colorHex = "#FF3B30"
        case .outlook: self.colorHex = "#007AFF"
        case .imap: self.colorHex = "#30D5C8"
        }
    }
}

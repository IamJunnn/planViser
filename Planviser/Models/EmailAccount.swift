import Foundation
import SwiftData

enum EmailProvider: String, Codable {
    case gmail
    case outlook
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

    @Relationship(deleteRule: .cascade, inverse: \EmailMessage.account)
    var messages: [EmailMessage] = []

    init(provider: EmailProvider, email: String, displayName: String) {
        self.id = UUID()
        self.provider = provider
        self.email = email
        self.displayName = displayName
        self.status = .connected
    }
}

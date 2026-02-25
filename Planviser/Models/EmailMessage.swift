import Foundation
import SwiftData

@Model
final class EmailMessage {
    var id: UUID
    var messageId: String
    var sender: String
    var senderEmail: String
    var subject: String
    var preview: String
    var date: Date
    var isRead: Bool
    var hasCalendarInvite: Bool
    var icsData: Data?
    var htmlBody: String?

    var account: EmailAccount?

    init(
        messageId: String,
        sender: String,
        senderEmail: String,
        subject: String,
        preview: String,
        date: Date,
        isRead: Bool = false,
        hasCalendarInvite: Bool = false,
        icsData: Data? = nil,
        htmlBody: String? = nil
    ) {
        self.id = UUID()
        self.messageId = messageId
        self.sender = sender
        self.senderEmail = senderEmail
        self.subject = subject
        self.preview = preview
        self.date = date
        self.isRead = isRead
        self.hasCalendarInvite = hasCalendarInvite
        self.icsData = icsData
        self.htmlBody = htmlBody
    }
}

import Foundation
import SwiftData

enum MeetingResponse: String, Codable {
    case pending
    case accepted
    case declined
    case tentative
}

@Model
final class MeetingInvite {
    var id: UUID
    var title: String
    var organizer: String
    var organizerEmail: String
    var startTime: Date
    var endTime: Date
    var location: String
    var videoLink: String
    var responseStatus: MeetingResponse
    var eventId: String

    var sourceMessage: EmailMessage?

    init(
        title: String,
        organizer: String,
        organizerEmail: String,
        startTime: Date,
        endTime: Date,
        location: String = "",
        videoLink: String = "",
        responseStatus: MeetingResponse = .pending,
        eventId: String = ""
    ) {
        self.id = UUID()
        self.title = title
        self.organizer = organizer
        self.organizerEmail = organizerEmail
        self.startTime = startTime
        self.endTime = endTime
        self.location = location
        self.videoLink = videoLink
        self.responseStatus = responseStatus
        self.eventId = eventId
    }
}

import Foundation
import SwiftData

struct ParsedEvent {
    var summary: String = ""
    var organizer: String = ""
    var organizerEmail: String = ""
    var startDate: Date?
    var endDate: Date?
    var location: String = ""
    var description: String = ""
    var attendees: [String] = []
    var uid: String = ""
}

final class ICSParser {
    static let shared = ICSParser()

    // Regex patterns for video conference links
    private let videoLinkPatterns: [(name: String, pattern: String)] = [
        ("Zoom", "https?://[\\w.-]*zoom\\.us/[^\\s<\"]+"),
        ("Google Meet", "https?://meet\\.google\\.com/[^\\s<\"]+"),
        ("Teams", "https?://teams\\.microsoft\\.com/[^\\s<\"]+"),
        ("Webex", "https?://[\\w.-]*webex\\.com/[^\\s<\"]+")
    ]

    private let icsDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    private let icsDateOnlyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd"
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    private init() {}

    func parse(icsData: Data) -> [ParsedEvent] {
        guard let icsString = String(data: icsData, encoding: .utf8) else { return [] }
        return parse(icsString: icsString)
    }

    func parse(icsString: String) -> [ParsedEvent] {
        var events: [ParsedEvent] = []
        var currentEvent: ParsedEvent?
        var inEvent = false

        let lines = unfoldLines(icsString)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

            if trimmed == "BEGIN:VEVENT" {
                inEvent = true
                currentEvent = ParsedEvent()
                continue
            }

            if trimmed == "END:VEVENT" {
                if var event = currentEvent {
                    // Set defaults
                    if event.startDate == nil { event.startDate = Date() }
                    if event.endDate == nil { event.endDate = event.startDate?.addingTimeInterval(3600) }
                    events.append(event)
                }
                inEvent = false
                currentEvent = nil
                continue
            }

            guard inEvent, var event = currentEvent else { continue }

            let (key, value) = parseProperty(trimmed)

            switch key {
            case "SUMMARY":
                event.summary = value
            case "ORGANIZER":
                let (name, email) = parseOrganizer(value)
                event.organizer = name
                event.organizerEmail = email
            case "DTSTART":
                event.startDate = parseICSDate(value)
            case "DTEND":
                event.endDate = parseICSDate(value)
            case "LOCATION":
                event.location = value
            case "DESCRIPTION":
                event.description = value
            case "ATTENDEE":
                if let email = parseAttendeeEmail(trimmed) {
                    event.attendees.append(email)
                }
            case "UID":
                event.uid = value
            default:
                break
            }

            currentEvent = event
        }

        return events
    }

    func extractVideoLink(from event: ParsedEvent) -> String {
        let searchText = "\(event.location) \(event.description)"

        for (_, pattern) in videoLinkPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(searchText.startIndex..., in: searchText)
                if let match = regex.firstMatch(in: searchText, range: range) {
                    let matchRange = Range(match.range, in: searchText)!
                    return String(searchText[matchRange])
                }
            }
        }

        return ""
    }

    func createMeetingInvites(from icsData: Data, sourceMessage: EmailMessage, modelContext: ModelContext) {
        let events = parse(icsData: icsData)

        for event in events {
            let videoLink = extractVideoLink(from: event)

            // Check for existing meeting with same UID
            if !event.uid.isEmpty {
                let uid = event.uid
                let descriptor = FetchDescriptor<MeetingInvite>(
                    predicate: #Predicate { $0.eventId == uid }
                )
                let existing = (try? modelContext.fetch(descriptor)) ?? []
                if !existing.isEmpty { continue }
            }

            let invite = MeetingInvite(
                title: event.summary,
                organizer: event.organizer.isEmpty ? event.organizerEmail : event.organizer,
                organizerEmail: event.organizerEmail,
                startTime: event.startDate ?? Date(),
                endTime: event.endDate ?? Date().addingTimeInterval(3600),
                location: event.location,
                videoLink: videoLink,
                eventId: event.uid
            )
            invite.sourceMessage = sourceMessage
            modelContext.insert(invite)
        }

        try? modelContext.save()
    }

    // MARK: - Private Helpers

    private func unfoldLines(_ text: String) -> [String] {
        // ICS spec: long lines are folded with CRLF + whitespace
        let unfolded = text
            .replacingOccurrences(of: "\r\n ", with: "")
            .replacingOccurrences(of: "\r\n\t", with: "")
        return unfolded.components(separatedBy: .newlines)
    }

    private func parseProperty(_ line: String) -> (key: String, value: String) {
        // Handle properties with parameters like DTSTART;TZID=...:value
        guard let colonIndex = line.firstIndex(of: ":") else {
            return ("", "")
        }

        let keyPart = String(line[line.startIndex..<colonIndex])
        let value = String(line[line.index(after: colonIndex)...])

        // Extract base key name (before any ;parameters)
        let baseKey = keyPart.components(separatedBy: ";").first ?? keyPart

        return (baseKey.uppercased(), value)
    }

    private func parseICSDate(_ value: String) -> Date? {
        // Remove any TZID prefix that might remain
        let dateString = value.components(separatedBy: ";").last ?? value

        if let date = icsDateFormatter.date(from: dateString) {
            return date
        }
        if let date = icsDateOnlyFormatter.date(from: dateString) {
            return date
        }
        return nil
    }

    private func parseOrganizer(_ value: String) -> (name: String, email: String) {
        // Format: "CN=Name:mailto:email" or just "mailto:email"
        var name = ""
        var email = value

        if let cnRange = value.range(of: "CN=", options: .caseInsensitive) {
            let afterCN = value[cnRange.upperBound...]
            if let colonRange = afterCN.range(of: ":") {
                name = String(afterCN[afterCN.startIndex..<colonRange.lowerBound])
            }
        }

        if let mailtoRange = value.range(of: "mailto:", options: .caseInsensitive) {
            email = String(value[mailtoRange.upperBound...])
        }

        return (name, email)
    }

    private func parseAttendeeEmail(_ line: String) -> String? {
        if let mailtoRange = line.range(of: "mailto:", options: .caseInsensitive) {
            return String(line[mailtoRange.upperBound...])
        }
        return nil
    }
}

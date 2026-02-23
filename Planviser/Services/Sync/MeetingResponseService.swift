import Foundation
import SwiftData

final class MeetingResponseService {
    static let shared = MeetingResponseService()

    private init() {}

    func respond(to meeting: MeetingInvite, with response: MeetingResponse, modelContext: ModelContext) {
        // Determine which provider the meeting came from
        let provider = meeting.sourceMessage?.account?.provider

        switch provider {
        case .gmail:
            respondViaGmail(meeting: meeting, response: response, modelContext: modelContext)
        case .outlook:
            respondViaOutlook(meeting: meeting, response: response, modelContext: modelContext)
        default:
            // Just update locally if we can't determine the provider
            updateLocalStatus(meeting: meeting, response: response, modelContext: modelContext)
        }
    }

    // MARK: - Gmail Calendar Response

    private func respondViaGmail(meeting: MeetingInvite, response: MeetingResponse, modelContext: ModelContext) {
        GmailAuthService.shared.getValidAccessToken { [weak self] token in
            guard let token = token else { return }

            let calendarResponse = self?.gmailResponseBody(for: response) ?? ""
            let eventId = meeting.eventId

            guard !eventId.isEmpty else {
                self?.updateLocalStatus(meeting: meeting, response: response, modelContext: modelContext)
                return
            }

            // Use Google Calendar API to respond
            let urlString = "https://www.googleapis.com/calendar/v3/calendars/primary/events/\(eventId)"
            guard let url = URL(string: urlString) else { return }

            var request = URLRequest(url: url)
            request.httpMethod = "PATCH"
            request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")

            let body: [String: Any] = [
                "attendees": [
                    ["self": true, "responseStatus": calendarResponse]
                ]
            ]
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)

            URLSession.shared.dataTask(with: request) { _, httpResponse, error in
                if let httpResponse = httpResponse as? HTTPURLResponse,
                   (200...299).contains(httpResponse.statusCode) {
                    self?.updateLocalStatus(meeting: meeting, response: response, modelContext: modelContext)
                } else {
                    print("Gmail calendar response failed: \(error?.localizedDescription ?? "unknown")")
                    // Still update locally for UX
                    self?.updateLocalStatus(meeting: meeting, response: response, modelContext: modelContext)
                }
            }.resume()
        }
    }

    private func gmailResponseBody(for response: MeetingResponse) -> String {
        switch response {
        case .accepted: return "accepted"
        case .declined: return "declined"
        case .tentative: return "tentative"
        case .pending: return "needsAction"
        }
    }

    // MARK: - Outlook/Graph Response

    private func respondViaOutlook(meeting: MeetingInvite, response: MeetingResponse, modelContext: ModelContext) {
        OutlookAuthService.shared.getValidAccessToken { [weak self] token in
            guard let token = token else { return }

            let eventId = meeting.eventId
            guard !eventId.isEmpty else {
                self?.updateLocalStatus(meeting: meeting, response: response, modelContext: modelContext)
                return
            }

            let action: String
            switch response {
            case .accepted: action = "accept"
            case .declined: action = "decline"
            case .tentative: action = "tentativelyAccept"
            case .pending: return
            }

            let urlString = "https://graph.microsoft.com/v1.0/me/events/\(eventId)/\(action)"
            guard let url = URL(string: urlString) else { return }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")

            let body: [String: Any] = [
                "sendResponse": true
            ]
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)

            URLSession.shared.dataTask(with: request) { _, httpResponse, error in
                if let httpResponse = httpResponse as? HTTPURLResponse,
                   (200...299).contains(httpResponse.statusCode) {
                    self?.updateLocalStatus(meeting: meeting, response: response, modelContext: modelContext)
                } else {
                    print("Outlook calendar response failed: \(error?.localizedDescription ?? "unknown")")
                    self?.updateLocalStatus(meeting: meeting, response: response, modelContext: modelContext)
                }
            }.resume()
        }
    }

    // MARK: - Local Update

    private func updateLocalStatus(meeting: MeetingInvite, response: MeetingResponse, modelContext: ModelContext) {
        DispatchQueue.main.async {
            meeting.responseStatus = response
            try? modelContext.save()
        }
    }
}

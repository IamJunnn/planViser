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
        case .imap:
            // IMAP can't send calendar responses — update locally only
            updateLocalStatus(meeting: meeting, response: response, modelContext: modelContext)
        default:
            // Calendar-fetched events won't have a sourceMessage — check accountEmail
            if !meeting.accountEmail.isEmpty {
                respondViaGmail(meeting: meeting, response: response, modelContext: modelContext)
            } else {
                updateLocalStatus(meeting: meeting, response: response, modelContext: modelContext)
            }
        }
    }

    // MARK: - Gmail Calendar Response

    private func respondViaGmail(meeting: MeetingInvite, response: MeetingResponse, modelContext: ModelContext) {
        let accountEmail = meeting.sourceMessage?.account?.email ?? (meeting.accountEmail.isEmpty ? nil : meeting.accountEmail)
        guard let accountEmail = accountEmail else {
            updateLocalStatus(meeting: meeting, response: response, modelContext: modelContext)
            return
        }
        GmailAuthService.shared.getValidAccessToken(for: accountEmail) { [weak self] token in
            guard let token = token else { return }

            let calendarResponse = self?.gmailResponseBody(for: response) ?? ""
            let eventId = meeting.eventId

            guard !eventId.isEmpty else {
                self?.updateLocalStatus(meeting: meeting, response: response, modelContext: modelContext)
                return
            }

            // First GET the event to retrieve the full attendees list,
            // then PATCH with updated responseStatus for our attendee.
            let urlString = "https://www.googleapis.com/calendar/v3/calendars/primary/events/\(eventId)"
            guard let url = URL(string: urlString) else { return }

            var getRequest = URLRequest(url: url)
            getRequest.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            URLSession.shared.dataTask(with: getRequest) { data, _, getError in
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      var attendees = json["attendees"] as? [[String: Any]] else {
                    print("Gmail calendar response: failed to GET event attendees: \(getError?.localizedDescription ?? "no data")")
                    self?.updateLocalStatus(meeting: meeting, response: response, modelContext: modelContext)
                    return
                }

                // Update our own attendee entry
                var found = false
                for i in attendees.indices {
                    if let isSelf = attendees[i]["self"] as? Bool, isSelf {
                        attendees[i]["responseStatus"] = calendarResponse
                        found = true
                        break
                    }
                }
                if !found {
                    // Fallback: match by email
                    for i in attendees.indices {
                        if let email = attendees[i]["email"] as? String,
                           email.lowercased() == accountEmail.lowercased() {
                            attendees[i]["responseStatus"] = calendarResponse
                            found = true
                            break
                        }
                    }
                }
                if !found {
                    // Append ourselves if not in attendees list
                    attendees.append(["email": accountEmail, "responseStatus": calendarResponse])
                }

                var patchRequest = URLRequest(url: url)
                patchRequest.httpMethod = "PATCH"
                patchRequest.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                patchRequest.addValue("application/json", forHTTPHeaderField: "Content-Type")

                let patchBody: [String: Any] = ["attendees": attendees]
                patchRequest.httpBody = try? JSONSerialization.data(withJSONObject: patchBody)

                URLSession.shared.dataTask(with: patchRequest) { _, httpResponse, error in
                    if let httpResponse = httpResponse as? HTTPURLResponse,
                       (200...299).contains(httpResponse.statusCode) {
                        self?.updateLocalStatus(meeting: meeting, response: response, modelContext: modelContext)
                    } else {
                        print("Gmail calendar response PATCH failed: \(error?.localizedDescription ?? "unknown")")
                        self?.updateLocalStatus(meeting: meeting, response: response, modelContext: modelContext)
                    }
                }.resume()
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
        guard let accountEmail = meeting.sourceMessage?.account?.email else {
            updateLocalStatus(meeting: meeting, response: response, modelContext: modelContext)
            return
        }
        OutlookAuthService.shared.getValidAccessToken(for: accountEmail) { [weak self] token in
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

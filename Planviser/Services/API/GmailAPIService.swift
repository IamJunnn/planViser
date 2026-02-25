import Foundation

struct GmailMessageListResponse: Decodable {
    let messages: [GmailMessageRef]?
    let nextPageToken: String?
}

struct GmailMessageRef: Decodable {
    let id: String
    let threadId: String
}

struct GmailMessage: Decodable {
    let id: String
    let threadId: String
    let snippet: String
    let internalDate: String
    let labelIds: [String]?
    let payload: GmailPayload
}

struct GmailPayload: Decodable {
    let headers: [GmailHeader]
    let mimeType: String
    let body: GmailBody?
    let parts: [GmailPart]?
}

struct GmailHeader: Decodable {
    let name: String
    let value: String
}

struct GmailPart: Decodable {
    let mimeType: String
    let filename: String?
    let body: GmailBody?
    let parts: [GmailPart]?
}

struct GmailBody: Decodable {
    let attachmentId: String?
    let size: Int
    let data: String?
}

final class GmailAPIService {
    static let shared = GmailAPIService()
    private let baseURL = "https://gmail.googleapis.com/gmail/v1/users/me"

    private init() {}

    func fetchMessageList(
        accessToken: String,
        maxResults: Int = 50,
        pageToken: String? = nil,
        completion: @escaping (Result<GmailMessageListResponse, Error>) -> Void
    ) {
        var urlString = "\(baseURL)/messages?maxResults=\(maxResults)&q=in:inbox%20category:primary"
        if let pageToken = pageToken {
            urlString += "&pageToken=\(pageToken)"
        }

        var request = URLRequest(url: URL(string: urlString)!)
        request.addValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let data = data else {
                completion(.failure(APIError.noData))
                return
            }

            // Check for HTTP error
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                completion(.failure(APIError.httpError(httpResponse.statusCode)))
                return
            }

            do {
                let decoded = try JSONDecoder().decode(GmailMessageListResponse.self, from: data)
                completion(.success(decoded))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }

    func fetchMessageDetail(
        accessToken: String,
        messageId: String,
        completion: @escaping (Result<GmailMessage, Error>) -> Void
    ) {
        let urlString = "\(baseURL)/messages/\(messageId)?format=full"
        var request = URLRequest(url: URL(string: urlString)!)
        request.addValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { data, _, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let data = data else {
                completion(.failure(APIError.noData))
                return
            }
            do {
                let decoded = try JSONDecoder().decode(GmailMessage.self, from: data)
                completion(.success(decoded))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }

    func fetchAttachment(
        accessToken: String,
        messageId: String,
        attachmentId: String,
        completion: @escaping (Result<Data, Error>) -> Void
    ) {
        let urlString = "\(baseURL)/messages/\(messageId)/attachments/\(attachmentId)"
        var request = URLRequest(url: URL(string: urlString)!)
        request.addValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { data, _, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let data = data else {
                completion(.failure(APIError.noData))
                return
            }

            // The response is JSON with a "data" field containing base64url-encoded data
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let base64Data = json["data"] as? String {
                let standardBase64 = base64Data
                    .replacingOccurrences(of: "-", with: "+")
                    .replacingOccurrences(of: "_", with: "/")
                if let decoded = Data(base64Encoded: standardBase64) {
                    completion(.success(decoded))
                    return
                }
            }
            completion(.failure(APIError.decodingError))
        }.resume()
    }
    func markAsRead(
        accessToken: String,
        messageId: String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let urlString = "\(baseURL)/messages/\(messageId)/modify"
        var request = URLRequest(url: URL(string: urlString)!)
        request.httpMethod = "POST"
        request.addValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["removeLabelIds": ["UNREAD"]])

        URLSession.shared.dataTask(with: request) { _, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                completion(.failure(APIError.httpError(httpResponse.statusCode)))
                return
            }
            completion(.success(()))
        }.resume()
    }

    func trashMessage(
        accessToken: String,
        messageId: String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let urlString = "\(baseURL)/messages/\(messageId)/trash"
        var request = URLRequest(url: URL(string: urlString)!)
        request.httpMethod = "POST"
        request.addValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { _, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                completion(.failure(APIError.httpError(httpResponse.statusCode)))
                return
            }
            completion(.success(()))
        }.resume()
    }
}

// MARK: - Google Calendar API Models

struct GoogleCalendarEventsResponse: Decodable {
    let items: [GoogleCalendarEvent]?
    let nextPageToken: String?
}

struct GoogleCalendarEvent: Decodable {
    let id: String
    let summary: String?
    let status: String?
    let eventDescription: String?
    let organizer: GoogleCalendarActor?
    let start: GoogleCalendarDateTime?
    let end: GoogleCalendarDateTime?
    let location: String?
    let hangoutLink: String?
    let conferenceData: GoogleCalendarConferenceData?
    let attendees: [GoogleCalendarAttendee]?

    enum CodingKeys: String, CodingKey {
        case id, summary, status, organizer, start, end, location
        case hangoutLink, conferenceData, attendees
        case eventDescription = "description"
    }
}

struct GoogleCalendarActor: Decodable {
    let email: String?
    let displayName: String?
    let isSelf: Bool?

    enum CodingKeys: String, CodingKey {
        case email, displayName
        case isSelf = "self"
    }
}

struct GoogleCalendarDateTime: Decodable {
    let dateTime: String?
    let date: String?
    let timeZone: String?
}

struct GoogleCalendarConferenceData: Decodable {
    let entryPoints: [GoogleCalendarEntryPoint]?
}

struct GoogleCalendarEntryPoint: Decodable {
    let entryPointType: String?
    let uri: String?
}

struct GoogleCalendarAttendee: Decodable {
    let email: String?
    let displayName: String?
    let responseStatus: String?
    let isSelf: Bool?

    enum CodingKeys: String, CodingKey {
        case email, displayName, responseStatus
        case isSelf = "self"
    }
}

// MARK: - Google Calendar API

final class GoogleCalendarAPIService {
    static let shared = GoogleCalendarAPIService()
    private let baseURL = "https://www.googleapis.com/calendar/v3"

    private init() {}

    func fetchEvents(
        accessToken: String,
        timeMin: Date,
        timeMax: Date,
        pageToken: String? = nil,
        completion: @escaping (Result<GoogleCalendarEventsResponse, Error>) -> Void
    ) {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let minStr = formatter.string(from: timeMin)
        let maxStr = formatter.string(from: timeMax)

        var components = URLComponents(string: "\(baseURL)/calendars/primary/events")!
        var queryItems = [
            URLQueryItem(name: "singleEvents", value: "true"),
            URLQueryItem(name: "orderBy", value: "startTime"),
            URLQueryItem(name: "timeMin", value: minStr),
            URLQueryItem(name: "timeMax", value: maxStr),
            URLQueryItem(name: "maxResults", value: "250")
        ]
        if let pageToken = pageToken {
            queryItems.append(URLQueryItem(name: "pageToken", value: pageToken))
        }
        components.queryItems = queryItems

        guard let url = components.url else {
            completion(.failure(APIError.decodingError))
            return
        }

        print("[CalAPI] Fetching: \(url.absoluteString)")

        var request = URLRequest(url: url)
        request.addValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("[CalAPI] Network error: \(error.localizedDescription)")
                completion(.failure(error))
                return
            }
            guard let data = data else {
                completion(.failure(APIError.noData))
                return
            }
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                let body = String(data: data, encoding: .utf8) ?? "(no body)"
                print("[CalAPI] HTTP \(httpResponse.statusCode): \(body)")
                completion(.failure(APIError.httpError(httpResponse.statusCode)))
                return
            }
            do {
                let decoded = try JSONDecoder().decode(GoogleCalendarEventsResponse.self, from: data)
                print("[CalAPI] Decoded \(decoded.items?.count ?? 0) events")
                completion(.success(decoded))
            } catch {
                let body = String(data: data, encoding: .utf8) ?? "(no body)"
                print("[CalAPI] Decode error: \(error)\nBody: \(body.prefix(500))")
                completion(.failure(error))
            }
        }.resume()
    }
}

enum APIError: Error, LocalizedError {
    case noData
    case httpError(Int)
    case decodingError
    case unauthorized

    var errorDescription: String? {
        switch self {
        case .noData: return "No data received"
        case .httpError(let code): return "HTTP error \(code)"
        case .decodingError: return "Failed to decode response"
        case .unauthorized: return "Unauthorized — please re-authenticate"
        }
    }
}

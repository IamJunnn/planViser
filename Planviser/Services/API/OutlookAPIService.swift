import Foundation

struct GraphMessageListResponse: Decodable {
    let value: [GraphMessage]
    let nextLink: String?

    enum CodingKeys: String, CodingKey {
        case value
        case nextLink = "@odata.nextLink"
    }
}

struct GraphMessage: Decodable {
    let id: String
    let subject: String?
    let bodyPreview: String?
    let receivedDateTime: String
    let isRead: Bool
    let from: GraphEmailAddress?
    let hasAttachments: Bool
}

struct GraphEmailAddress: Decodable {
    let emailAddress: GraphEmailInfo
}

struct GraphEmailInfo: Decodable {
    let name: String?
    let address: String
}

struct GraphAttachmentListResponse: Decodable {
    let value: [GraphAttachment]
}

struct GraphAttachment: Decodable {
    let id: String
    let name: String
    let contentType: String?
    let contentBytes: String?
    let size: Int
}

final class OutlookAPIService {
    static let shared = OutlookAPIService()
    private let baseURL = "https://graph.microsoft.com/v1.0/me"

    private let dateFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private let fallbackDateFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private init() {}

    func fetchMessages(
        accessToken: String,
        top: Int = 50,
        completion: @escaping (Result<[GraphMessage], Error>) -> Void
    ) {
        let urlString = "\(baseURL)/mailFolders/inbox/messages?$top=\(top)&$orderby=receivedDateTime%20desc&$select=id,subject,bodyPreview,receivedDateTime,isRead,from,hasAttachments"
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
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                completion(.failure(APIError.httpError(httpResponse.statusCode)))
                return
            }
            do {
                let decoded = try JSONDecoder().decode(GraphMessageListResponse.self, from: data)
                completion(.success(decoded.value))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }

    func fetchAttachments(
        accessToken: String,
        messageId: String,
        completion: @escaping (Result<[GraphAttachment], Error>) -> Void
    ) {
        let urlString = "\(baseURL)/messages/\(messageId)/attachments"
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
                let decoded = try JSONDecoder().decode(GraphAttachmentListResponse.self, from: data)
                completion(.success(decoded.value))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }

    func parseDate(_ dateString: String) -> Date {
        dateFormatter.date(from: dateString)
            ?? fallbackDateFormatter.date(from: dateString)
            ?? Date()
    }
}

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
    let payload: GmailPayload
}

struct GmailPayload: Decodable {
    let headers: [GmailHeader]
    let mimeType: String
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
        var urlString = "\(baseURL)/messages?maxResults=\(maxResults)&q=in:inbox"
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

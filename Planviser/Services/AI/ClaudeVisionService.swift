import Foundation
import KeychainAccess

/// Lightweight struct for passing task context to the API (not a SwiftData @Model).
struct TaskSummary: Codable {
    let id: String
    let title: String
    let startTime: String
    let endTime: String
}

/// Response parsed from Claude's JSON output.
struct ScreenAnalysis: Codable {
    let currentTaskId: String?
    let activitySummary: String
    let confidence: Double
}

final class ClaudeVisionService {
    static let shared = ClaudeVisionService()

    private let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private let model = "claude-sonnet-4-6"
    private let keychainKey = "anthropic.apiKey"

    private init() {}

    // MARK: - API Key Management

    func saveAPIKey(_ key: String) {
        try? KeychainService.shared.save(key, forKey: keychainKey)
    }

    func getAPIKey() -> String? {
        try? KeychainService.shared.get(forKey: keychainKey)
    }

    func clearAPIKey() {
        try? KeychainService.shared.delete(forKey: keychainKey)
    }

    // MARK: - Vision Analysis

    func analyzeScreen(imageData: Data, tasks: [TaskSummary]) async throws -> ScreenAnalysis {
        guard let apiKey = getAPIKey(), !apiKey.isEmpty else {
            throw APIError.unauthorized
        }

        let base64Image = imageData.base64EncodedString()

        let tasksJSON = try JSONEncoder().encode(tasks)
        let tasksString = String(data: tasksJSON, encoding: .utf8) ?? "[]"

        let systemPrompt = """
        You are a screen activity detector. You will receive a screenshot and a list of today's scheduled tasks. \
        Analyze what the user is currently doing on their screen and match it to one of the provided tasks. \
        Respond ONLY with valid JSON in this exact format:
        {"currentTaskId": "<task id or null if no match>", "activitySummary": "<brief description of screen activity>", "confidence": <0.0-1.0>}
        """

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 256,
            "system": systemPrompt,
            "messages": [
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "image",
                            "source": [
                                "type": "base64",
                                "media_type": "image/jpeg",
                                "data": base64Image
                            ]
                        ],
                        [
                            "type": "text",
                            "text": "Today's tasks:\n\(tasksString)\n\nWhat is the user currently doing? Match to a task if possible."
                        ]
                    ]
                ]
            ]
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: body)

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = jsonData
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.noData
        }

        guard httpResponse.statusCode == 200 else {
            if httpResponse.statusCode == 401 {
                throw APIError.unauthorized
            }
            throw APIError.httpError(httpResponse.statusCode)
        }

        // Parse the Messages API response to extract Claude's text
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let firstBlock = content.first,
              let text = firstBlock["text"] as? String
        else {
            throw APIError.decodingError
        }

        // Parse Claude's JSON text response into ScreenAnalysis
        guard let analysisData = text.data(using: .utf8) else {
            throw APIError.decodingError
        }

        let analysis = try JSONDecoder().decode(ScreenAnalysis.self, from: analysisData)
        return analysis
    }
}

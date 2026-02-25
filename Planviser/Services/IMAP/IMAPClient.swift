import Foundation
import Network

/// Low-level IMAP protocol client using NWConnection over TLS (port 993).
/// Executes commands serially with tag-based request/response matching.
final class IMAPClient {
    private var connection: NWConnection?
    private let host: String
    private let port: UInt16
    private var tagCounter = 0
    private let queue = DispatchQueue(label: "com.planviser.imap", qos: .userInitiated)
    private let commandTimeout: TimeInterval = 30

    /// Buffer for accumulating partial TCP reads
    private var receiveBuffer = Data()

    init(host: String, port: UInt16 = 993) {
        self.host = host
        self.port = port
    }

    // MARK: - Connection Lifecycle

    func connect(completion: @escaping (Result<String, IMAPError>) -> Void) {
        let tlsOptions = NWProtocolTLS.Options()
        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.connectionTimeout = 15

        let params = NWParameters(tls: tlsOptions, tcp: tcpOptions)
        let nwHost = NWEndpoint.Host(host)
        let nwPort = NWEndpoint.Port(rawValue: port)!

        connection = NWConnection(host: nwHost, port: nwPort, using: params)
        connection?.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                // Read the server greeting (untagged)
                self?.readGreeting(completion: completion)
            case .failed(let error):
                completion(.failure(.connectionFailed(error.localizedDescription)))
            case .cancelled:
                break
            default:
                break
            }
        }
        connection?.start(queue: queue)
    }

    func disconnect() {
        sendCommandFireAndForget("LOGOUT")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.connection?.cancel()
            self?.connection = nil
        }
    }

    // MARK: - IMAP Commands

    func login(username: String, password: String, completion: @escaping (Result<String, IMAPError>) -> Void) {
        // Escape special characters in credentials for IMAP literal
        let escapedUser = username.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let escapedPass = password.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        sendCommand("LOGIN \"\(escapedUser)\" \"\(escapedPass)\"", completion: completion)
    }

    func selectMailbox(_ mailbox: String, completion: @escaping (Result<String, IMAPError>) -> Void) {
        sendCommand("SELECT \"\(mailbox)\"", completion: completion)
    }

    func uidSearch(criteria: String, completion: @escaping (Result<[UInt32], IMAPError>) -> Void) {
        sendCommand("UID SEARCH \(criteria)") { result in
            switch result {
            case .success(let response):
                let uids = Self.parseSearchResponse(response)
                completion(.success(uids))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    /// Fetch envelope, flags, body preview, and BODYSTRUCTURE for given UIDs.
    func uidFetch(uids: [UInt32], completion: @escaping (Result<[IMAPMessage], IMAPError>) -> Void) {
        guard !uids.isEmpty else {
            completion(.success([]))
            return
        }

        let uidSet = uids.map { String($0) }.joined(separator: ",")
        let fetchItems = "(UID FLAGS ENVELOPE BODY.PEEK[TEXT]<0.256> BODYSTRUCTURE)"
        sendCommand("UID FETCH \(uidSet) \(fetchItems)") { result in
            switch result {
            case .success(let response):
                let messages = Self.parseFetchResponse(response)
                completion(.success(messages))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    func uidStore(uid: UInt32, flags: String, completion: @escaping (Result<String, IMAPError>) -> Void) {
        sendCommand("UID STORE \(uid) \(flags)", completion: completion)
    }

    func listMailboxes(completion: @escaping (Result<String, IMAPError>) -> Void) {
        sendCommand("LIST \"\" \"*\"", completion: completion)
    }

    // MARK: - Send / Receive

    private func nextTag() -> String {
        tagCounter += 1
        return String(format: "A%03d", tagCounter)
    }

    private func sendCommandFireAndForget(_ command: String) {
        let tag = nextTag()
        let fullCommand = "\(tag) \(command)\r\n"
        guard let data = fullCommand.data(using: .utf8) else { return }
        connection?.send(content: data, completion: .contentProcessed { _ in })
    }

    private func sendCommand(_ command: String, completion: @escaping (Result<String, IMAPError>) -> Void) {
        let tag = nextTag()
        let fullCommand = "\(tag) \(command)\r\n"
        guard let data = fullCommand.data(using: .utf8) else {
            completion(.failure(.protocolError("Failed to encode command")))
            return
        }

        var completed = false
        let timeoutItem = DispatchWorkItem { [weak self] in
            guard !completed else { return }
            completed = true
            self?.receiveBuffer.removeAll()
            completion(.failure(.timeout))
        }
        queue.asyncAfter(deadline: .now() + commandTimeout, execute: timeoutItem)

        connection?.send(content: data, completion: .contentProcessed { [weak self] error in
            if let error = error {
                timeoutItem.cancel()
                if !completed {
                    completed = true
                    completion(.failure(.connectionFailed(error.localizedDescription)))
                }
                return
            }
            self?.readResponse(tag: tag) { result in
                timeoutItem.cancel()
                guard !completed else { return }
                completed = true
                completion(result)
            }
        })
    }

    private func readGreeting(completion: @escaping (Result<String, IMAPError>) -> Void) {
        receiveBuffer.removeAll()
        readUntilLine(containing: "* OK") { result in
            switch result {
            case .success(let line):
                completion(.success(line))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    private func readResponse(tag: String, completion: @escaping (Result<String, IMAPError>) -> Void) {
        var accumulated = ""
        readLines { line, stop in
            accumulated += line + "\n"
            // Check for tagged response (OK, NO, BAD)
            if line.hasPrefix("\(tag) ") {
                stop = true
                if line.contains("\(tag) OK") {
                    completion(.success(accumulated))
                } else if line.contains("\(tag) NO") {
                    completion(.failure(.commandFailed(line)))
                } else if line.contains("\(tag) BAD") {
                    completion(.failure(.protocolError(line)))
                } else {
                    completion(.failure(.protocolError("Unexpected response: \(line)")))
                }
            }
        }
    }

    /// Reads data from the connection and calls the handler for each complete line.
    /// The handler sets `stop = true` when it has received the terminal response.
    private func readLines(handler: @escaping (_ line: String, _ stop: inout Bool) -> Void) {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] content, _, isComplete, error in
            guard let self = self else { return }

            if let content = content {
                self.receiveBuffer.append(content)
            }

            // Process complete lines in the buffer
            while let range = self.receiveBuffer.range(of: Data("\r\n".utf8)) {
                let lineData = self.receiveBuffer[self.receiveBuffer.startIndex..<range.lowerBound]
                let line = String(data: lineData, encoding: .utf8) ?? ""
                self.receiveBuffer.removeSubrange(self.receiveBuffer.startIndex..<range.upperBound)

                var stop = false
                handler(line, &stop)
                if stop { return }
            }

            if isComplete {
                // Connection closed
                return
            }

            if error != nil {
                return
            }

            // Keep reading
            self.readLines(handler: handler)
        }
    }

    private func readUntilLine(containing substring: String, completion: @escaping (Result<String, IMAPError>) -> Void) {
        readLines { line, stop in
            if line.contains(substring) {
                stop = true
                completion(.success(line))
            }
        }
    }

    // MARK: - Response Parsing

    static func parseSearchResponse(_ response: String) -> [UInt32] {
        // Response contains lines like: * SEARCH 1 2 3 4
        for line in response.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("* SEARCH") {
                let parts = trimmed.dropFirst("* SEARCH".count)
                    .trimmingCharacters(in: .whitespaces)
                    .components(separatedBy: " ")
                return parts.compactMap { UInt32($0) }
            }
        }
        return []
    }

    static func parseFetchResponse(_ response: String) -> [IMAPMessage] {
        var messages: [IMAPMessage] = []
        let lines = response.components(separatedBy: "\n")
        var i = 0

        while i < lines.count {
            let line = lines[i].trimmingCharacters(in: .whitespacesAndNewlines)

            // Look for fetch response start: * N FETCH (
            if line.hasPrefix("*") && line.contains("FETCH") {
                // Collect all lines until we find the next fetch or tagged response
                var fetchBlock = line
                i += 1
                while i < lines.count {
                    let next = lines[i].trimmingCharacters(in: .whitespacesAndNewlines)
                    if (next.hasPrefix("*") && next.contains("FETCH")) || next.hasPrefix("A") {
                        break
                    }
                    fetchBlock += "\n" + next
                    i += 1
                }

                if let message = parseSingleFetch(fetchBlock) {
                    messages.append(message)
                }
            } else {
                i += 1
            }
        }

        return messages
    }

    private static func parseSingleFetch(_ block: String) -> IMAPMessage? {
        // Extract UID
        guard let uid = extractValue(from: block, key: "UID") else { return nil }
        guard let uidNum = UInt32(uid) else { return nil }

        // Extract FLAGS
        let flags = extractFlags(from: block)
        let isRead = flags.contains("\\Seen")

        // Extract ENVELOPE fields
        let envelope = extractEnvelope(from: block)

        // Extract body preview
        let preview = extractBodyPreview(from: block)

        // Check BODYSTRUCTURE for ICS attachments
        let hasCalendar = block.contains("text/calendar") ||
                          block.contains("TEXT/CALENDAR") ||
                          block.contains("application/ics") ||
                          block.contains("APPLICATION/ICS")

        return IMAPMessage(
            uid: uidNum,
            subject: decodeRFC2047(envelope.subject),
            from: decodeRFC2047(envelope.from),
            fromEmail: envelope.fromEmail,
            date: envelope.date,
            preview: cleanPreview(preview),
            isRead: isRead,
            hasCalendarInvite: hasCalendar
        )
    }

    private static func extractValue(from text: String, key: String) -> String? {
        guard let range = text.range(of: "\(key) ") else { return nil }
        let after = text[range.upperBound...]
        // Read until space or closing paren
        var value = ""
        for ch in after {
            if ch == " " || ch == ")" { break }
            value.append(ch)
        }
        return value.isEmpty ? nil : value
    }

    private static func extractFlags(from text: String) -> String {
        guard let start = text.range(of: "FLAGS (") else { return "" }
        let after = text[start.upperBound...]
        guard let end = after.firstIndex(of: ")") else { return "" }
        return String(after[after.startIndex..<end])
    }

    /// Extracts subject, from name, from email, and date from the ENVELOPE portion.
    private static func extractEnvelope(from text: String) -> (subject: String, from: String, fromEmail: String, date: Date) {
        let defaultDate = Date()

        // Find ENVELOPE (
        guard let envStart = text.range(of: "ENVELOPE (") else {
            return ("(no subject)", "Unknown", "", defaultDate)
        }

        // Extract the quoted strings from the envelope
        // ENVELOPE format: (date subject from sender reply-to to cc bcc in-reply-to message-id)
        let envContent = String(text[envStart.upperBound...])
        let quoted = extractQuotedStrings(from: envContent)

        let dateStr = quoted.count > 0 ? quoted[0] : ""
        let subject = quoted.count > 1 ? quoted[1] : "(no subject)"

        // Parse date
        let date = parseIMAPDate(dateStr) ?? defaultDate

        // From is structured as ((name route mailbox host)) — we extract from quoted strings
        // The from name is typically at index 2, mailbox at index 4, host at index 5
        var fromName = ""
        var fromEmail = ""
        if quoted.count > 4 {
            fromName = quoted[2]
            let mailbox = quoted.count > 4 ? quoted[4] : ""
            let host = quoted.count > 5 ? quoted[5] : ""
            if !mailbox.isEmpty && !host.isEmpty {
                fromEmail = "\(mailbox)@\(host)"
            }
            if fromName.isEmpty || fromName == "NIL" {
                fromName = fromEmail
            }
        }

        return (subject, fromName, fromEmail, date)
    }

    private static func extractQuotedStrings(from text: String) -> [String] {
        var results: [String] = []
        var i = text.startIndex
        while i < text.endIndex {
            if text[i] == "\"" {
                // Find closing quote (handle escaped quotes)
                var value = ""
                i = text.index(after: i)
                while i < text.endIndex && text[i] != "\"" {
                    if text[i] == "\\" {
                        i = text.index(after: i)
                        if i < text.endIndex {
                            value.append(text[i])
                        }
                    } else {
                        value.append(text[i])
                    }
                    i = text.index(after: i)
                }
                results.append(value)
                if i < text.endIndex { i = text.index(after: i) }
            } else if text[i] == "N" && text[i...].hasPrefix("NIL") {
                results.append("NIL")
                i = text.index(i, offsetBy: 3)
            } else {
                i = text.index(after: i)
            }
        }
        return results
    }

    private static func extractBodyPreview(from text: String) -> String {
        // Look for literal body content after BODY[TEXT]<0.256>
        guard let marker = text.range(of: "BODY[TEXT]<0>") ?? text.range(of: "BODY[TEXT]<0.256>") ?? text.range(of: "BODY[TEXT]") else {
            return ""
        }
        let after = String(text[marker.upperBound...])
        // The body content follows a {size}\r\n pattern or is in the next lines
        // Extract text between the first newline and the closing paren/next field
        let lines = after.components(separatedBy: "\n")
        var preview = ""
        for line in lines.dropFirst() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            if trimmed == ")" { break }
            if trimmed.hasPrefix("*") { break }
            preview += trimmed + " "
            if preview.count > 256 { break }
        }
        return preview
    }

    private static func cleanPreview(_ text: String) -> String {
        // Strip HTML tags and clean up whitespace
        var clean = text
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.count > 200 {
            clean = String(clean.prefix(200)) + "..."
        }
        return clean
    }

    // MARK: - RFC 2047 Decoding

    static func decodeRFC2047(_ text: String) -> String {
        // Decode =?charset?encoding?encoded_text?= patterns
        let pattern = "=\\?([^?]+)\\?([BbQq])\\?([^?]+)\\?="
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }

        var result = text
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))

        for match in matches.reversed() {
            guard let fullRange = Range(match.range, in: text),
                  let charsetRange = Range(match.range(at: 1), in: text),
                  let encodingRange = Range(match.range(at: 2), in: text),
                  let dataRange = Range(match.range(at: 3), in: text) else { continue }

            let charset = String(text[charsetRange])
            let encoding = text[encodingRange].uppercased()
            let encoded = String(text[dataRange])

            let cfEncoding = CFStringConvertIANACharSetNameToEncoding(charset as CFString)
            let nsEncoding = CFStringConvertEncodingToNSStringEncoding(cfEncoding)

            var decoded: String?
            if encoding == "B" {
                // Base64
                if let data = Data(base64Encoded: encoded) {
                    decoded = String(data: data, encoding: String.Encoding(rawValue: nsEncoding))
                }
            } else if encoding == "Q" {
                // Quoted-printable
                let qpDecoded = encoded
                    .replacingOccurrences(of: "_", with: " ")
                    .replacingOccurrences(of: "=([0-9A-Fa-f]{2})", with: "", options: .regularExpression)
                // Simple QP decode
                var data = Data()
                var i = qpDecoded.startIndex
                while i < qpDecoded.endIndex {
                    if qpDecoded[i] == "=" {
                        let hexStart = qpDecoded.index(after: i)
                        if hexStart < qpDecoded.endIndex {
                            let hexEnd = qpDecoded.index(hexStart, offsetBy: 2, limitedBy: qpDecoded.endIndex) ?? qpDecoded.endIndex
                            let hex = String(encoded[encoded.index(encoded.startIndex, offsetBy: qpDecoded.distance(from: qpDecoded.startIndex, to: hexStart))...])
                            if hex.count >= 2, let byte = UInt8(String(hex.prefix(2)), radix: 16) {
                                data.append(byte)
                                i = hexEnd
                                continue
                            }
                        }
                    }
                    if let byte = String(qpDecoded[i]).data(using: .utf8) {
                        data.append(byte)
                    }
                    i = qpDecoded.index(after: i)
                }
                decoded = String(data: data, encoding: String.Encoding(rawValue: nsEncoding))
            }

            if let decoded = decoded {
                result.replaceSubrange(fullRange, with: decoded)
            }
        }

        return result
    }

    // MARK: - Date Parsing

    private static func parseIMAPDate(_ dateString: String) -> Date? {
        let formatters: [String] = [
            "EEE, dd MMM yyyy HH:mm:ss Z",
            "dd MMM yyyy HH:mm:ss Z",
            "EEE, dd MMM yyyy HH:mm:ss z",
            "dd MMM yyyy HH:mm:ss z",
            "EEE, d MMM yyyy HH:mm:ss Z"
        ]

        for format in formatters {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = format
            if let date = formatter.date(from: dateString) {
                return date
            }
        }
        return nil
    }
}

// MARK: - Models

struct IMAPMessage {
    let uid: UInt32
    let subject: String
    let from: String
    let fromEmail: String
    let date: Date
    let preview: String
    let isRead: Bool
    let hasCalendarInvite: Bool
}

enum IMAPError: Error, LocalizedError {
    case connectionFailed(String)
    case timeout
    case commandFailed(String)
    case protocolError(String)
    case notConnected

    var errorDescription: String? {
        switch self {
        case .connectionFailed(let msg): return "Connection failed: \(msg)"
        case .timeout: return "Command timed out"
        case .commandFailed(let msg): return "Command failed: \(msg)"
        case .protocolError(let msg): return "Protocol error: \(msg)"
        case .notConnected: return "Not connected to server"
        }
    }
}

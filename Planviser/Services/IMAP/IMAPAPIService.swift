import Foundation

/// High-level IMAP operations service — matches the Gmail/Outlook API service pattern.
/// Manages a connection pool keyed by email address.
final class IMAPAPIService {
    static let shared = IMAPAPIService()

    /// Active IMAP client connections keyed by email
    private var clients: [String: IMAPClient] = [:]
    private let lock = NSLock()

    private init() {}

    // MARK: - Connection Management

    func connect(email: String, host: String, port: UInt16, password: String, completion: @escaping (Result<Void, Error>) -> Void) {
        let client = IMAPClient(host: host, port: port)

        client.connect { [weak self] result in
            switch result {
            case .success:
                client.login(username: email, password: password) { loginResult in
                    switch loginResult {
                    case .success:
                        self?.lock.lock()
                        self?.clients[email] = client
                        self?.lock.unlock()
                        completion(.success(()))
                    case .failure(let error):
                        client.disconnect()
                        completion(.failure(error))
                    }
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    func disconnect(email: String) {
        lock.lock()
        let client = clients.removeValue(forKey: email)
        lock.unlock()
        client?.disconnect()
    }

    func disconnectAll() {
        lock.lock()
        let allClients = clients
        clients.removeAll()
        lock.unlock()
        for (_, client) in allClients {
            client.disconnect()
        }
    }

    /// Test connection without keeping it in the pool.
    func testConnection(host: String, port: UInt16, email: String, password: String, completion: @escaping (Result<Void, Error>) -> Void) {
        let client = IMAPClient(host: host, port: port)

        client.connect { result in
            switch result {
            case .success:
                client.login(username: email, password: password) { loginResult in
                    // Always disconnect test connections
                    client.disconnect()
                    switch loginResult {
                    case .success:
                        completion(.success(()))
                    case .failure(let error):
                        completion(.failure(error))
                    }
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    // MARK: - Message Operations

    /// Fetches the last N messages from INBOX.
    func fetchInboxMessages(email: String, host: String, port: UInt16, password: String, maxMessages: Int = 50, completion: @escaping (Result<[IMAPMessage], Error>) -> Void) {
        // Always create a fresh connection for fetch operations (IMAP connections are stateful)
        let client = IMAPClient(host: host, port: port)

        client.connect { result in
            switch result {
            case .success:
                client.login(username: email, password: password) { loginResult in
                    switch loginResult {
                    case .success:
                        client.selectMailbox("INBOX") { selectResult in
                            switch selectResult {
                            case .success:
                                // Search for recent messages
                                client.uidSearch(criteria: "ALL") { searchResult in
                                    switch searchResult {
                                    case .success(let allUIDs):
                                        // Take the last N UIDs (most recent)
                                        let recentUIDs = Array(allUIDs.suffix(maxMessages))
                                        guard !recentUIDs.isEmpty else {
                                            client.disconnect()
                                            completion(.success([]))
                                            return
                                        }

                                        client.uidFetch(uids: recentUIDs) { fetchResult in
                                            client.disconnect()
                                            switch fetchResult {
                                            case .success(let messages):
                                                completion(.success(messages))
                                            case .failure(let error):
                                                completion(.failure(error))
                                            }
                                        }
                                    case .failure(let error):
                                        client.disconnect()
                                        completion(.failure(error))
                                    }
                                }
                            case .failure(let error):
                                client.disconnect()
                                completion(.failure(error))
                            }
                        }
                    case .failure(let error):
                        client.disconnect()
                        completion(.failure(error))
                    }
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    /// Marks a message as read on the server using UID STORE +FLAGS \\Seen.
    func markAsRead(email: String, host: String, port: UInt16, password: String, uid: UInt32, completion: @escaping (Result<Void, Error>) -> Void) {
        let client = IMAPClient(host: host, port: port)

        client.connect { result in
            switch result {
            case .success:
                client.login(username: email, password: password) { loginResult in
                    switch loginResult {
                    case .success:
                        client.selectMailbox("INBOX") { _ in
                            client.uidStore(uid: uid, flags: "+FLAGS (\\Seen)") { storeResult in
                                client.disconnect()
                                switch storeResult {
                                case .success:
                                    completion(.success(()))
                                case .failure(let error):
                                    completion(.failure(error))
                                }
                            }
                        }
                    case .failure(let error):
                        client.disconnect()
                        completion(.failure(error))
                    }
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    /// Marks a message as deleted on the server using UID STORE +FLAGS \\Deleted.
    func trashMessage(email: String, host: String, port: UInt16, password: String, uid: UInt32, completion: @escaping (Result<Void, Error>) -> Void) {
        let client = IMAPClient(host: host, port: port)

        client.connect { result in
            switch result {
            case .success:
                client.login(username: email, password: password) { loginResult in
                    switch loginResult {
                    case .success:
                        client.selectMailbox("INBOX") { _ in
                            client.uidStore(uid: uid, flags: "+FLAGS (\\Deleted)") { storeResult in
                                client.disconnect()
                                switch storeResult {
                                case .success:
                                    completion(.success(()))
                                case .failure(let error):
                                    completion(.failure(error))
                                }
                            }
                        }
                    case .failure(let error):
                        client.disconnect()
                        completion(.failure(error))
                    }
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    // MARK: - Message ID Helper

    /// Generates a unique message ID for SwiftData storage.
    static func messageId(uid: UInt32, accountEmail: String) -> String {
        "imap-\(uid)-\(accountEmail)"
    }

    /// Extracts the IMAP UID from a stored message ID.
    static func uidFromMessageId(_ messageId: String) -> UInt32? {
        let parts = messageId.components(separatedBy: "-")
        guard parts.count >= 2, parts[0] == "imap" else { return nil }
        return UInt32(parts[1])
    }
}

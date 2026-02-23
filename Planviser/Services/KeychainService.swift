import Foundation
import KeychainAccess

final class KeychainService {
    static let shared = KeychainService()

    private let keychain: Keychain

    private init() {
        keychain = Keychain(service: "com.planviser.app")
            .accessibility(.afterFirstUnlock)
    }

    // MARK: - Token Storage

    func saveAccessToken(_ token: String, for provider: String) throws {
        try keychain.set(token, key: "\(provider).accessToken")
    }

    func getAccessToken(for provider: String) throws -> String? {
        try keychain.get("\(provider).accessToken")
    }

    func saveRefreshToken(_ token: String, for provider: String) throws {
        try keychain.set(token, key: "\(provider).refreshToken")
    }

    func getRefreshToken(for provider: String) throws -> String? {
        try keychain.get("\(provider).refreshToken")
    }

    func deleteTokens(for provider: String) throws {
        try keychain.remove("\(provider).accessToken")
        try keychain.remove("\(provider).refreshToken")
    }

    // MARK: - Generic Key-Value

    func save(_ value: String, forKey key: String) throws {
        try keychain.set(value, key: key)
    }

    func get(forKey key: String) throws -> String? {
        try keychain.get(key)
    }

    func delete(forKey key: String) throws {
        try keychain.remove(key)
    }
}

import Foundation
import CryptoKit

final class NoteEncryptionService {
    static let shared = NoteEncryptionService()

    private let keychainKey = "secureNotes.encryptionKey"

    private init() {}

    // MARK: - Key Management

    private func getOrCreateKey() throws -> SymmetricKey {
        if let existing = try KeychainService.shared.get(forKey: keychainKey),
           let keyData = Data(base64Encoded: existing) {
            return SymmetricKey(data: keyData)
        }
        let newKey = SymmetricKey(size: .bits256)
        let keyData = newKey.withUnsafeBytes { Data($0) }
        try KeychainService.shared.save(keyData.base64EncodedString(), forKey: keychainKey)
        return newKey
    }

    // MARK: - Encrypt / Decrypt

    func encrypt(_ data: Data) throws -> Data {
        let key = try getOrCreateKey()
        let sealedBox = try AES.GCM.seal(data, using: key)
        guard let combined = sealedBox.combined else {
            throw EncryptionError.sealFailed
        }
        return combined
    }

    func decrypt(_ data: Data) throws -> Data {
        let key = try getOrCreateKey()
        let sealedBox = try AES.GCM.SealedBox(combined: data)
        return try AES.GCM.open(sealedBox, using: key)
    }

    enum EncryptionError: LocalizedError {
        case sealFailed

        var errorDescription: String? {
            switch self {
            case .sealFailed: return "Failed to seal encrypted data"
            }
        }
    }
}

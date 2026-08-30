import CryptoKit
import Foundation

enum SecretConversationVaultError: LocalizedError {
    case keyUnavailable(Int64)
    case invalidCiphertext

    var errorDescription: String? {
        switch self {
        case let .keyUnavailable(conversationID):
            return "Secret conversation key is unavailable: \(conversationID)"
        case .invalidCiphertext:
            return "Secret conversation ciphertext is invalid"
        }
    }
}

/// Holds secret-chat keys in process memory only. Keys are intentionally never
/// written to Keychain, UserDefaults, or the database; destroying the key makes
/// any SQLite/WAL remnants cryptographically unrecoverable.
final class SecretConversationVault: @unchecked Sendable {
    static let shared = SecretConversationVault()
    static let prefix = "yamabiko-secret:v1:"

    private let lock = NSLock()
    private var keys: [Int64: SymmetricKey] = [:]

    private init() {}

    func activate(conversationID: Int64) {
        lock.withLock {
            if keys[conversationID] == nil {
                keys[conversationID] = SymmetricKey(size: .bits256)
            }
        }
    }

    func destroy(conversationID: Int64) {
        _ = lock.withLock { keys.removeValue(forKey: conversationID) }
    }

    func destroyAll() {
        lock.withLock { keys.removeAll(keepingCapacity: false) }
    }

    func seal(_ plaintext: String, conversationID: Int64) throws -> String {
        let key = try key(for: conversationID)
        let sealed = try AES.GCM.seal(Data(plaintext.utf8), using: key)
        guard let combined = sealed.combined else {
            throw SecretConversationVaultError.invalidCiphertext
        }
        return Self.prefix + combined.base64EncodedString()
    }

    func open(_ value: String, conversationID: Int64) throws -> String {
        guard value.hasPrefix(Self.prefix) else { return value }
        let encoded = String(value.dropFirst(Self.prefix.count))
        guard let combined = Data(base64Encoded: encoded) else {
            throw SecretConversationVaultError.invalidCiphertext
        }
        let box = try AES.GCM.SealedBox(combined: combined)
        let plaintext = try AES.GCM.open(box, using: key(for: conversationID))
        return String(decoding: plaintext, as: UTF8.self)
    }

    private func key(for conversationID: Int64) throws -> SymmetricKey {
        guard let key = lock.withLock({ keys[conversationID] }) else {
            throw SecretConversationVaultError.keyUnavailable(conversationID)
        }
        return key
    }
}

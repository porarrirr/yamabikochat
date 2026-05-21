import Foundation
import Security

enum CredentialProvider: String, CaseIterable {
    case gemini = "GEMINI"
    case openRouter = "OPENROUTER"
    case openCodeGo = "OPENCODE_GO"
    case alibabaCodingPlan = "ALIBABA_CODING_PLAN"
    case openAI = "OPENAI"
    case openAICompat = "OPENAI_COMPAT"
    case miniMax = "MINIMAX"
    case codexAuth = "CODEX_AUTH"
    case zai = "ZAI"
}

protocol SecureCredentialStore {
    func saveSecret(_ value: String?, key: String) throws
    func readSecret(key: String) throws -> String?
    func deleteSecret(key: String) throws
}

enum KeychainStoreError: Error {
    case unexpectedStatus(OSStatus)
    case invalidEncoding
}

final class KeychainStore: SecureCredentialStore {
    private let service: String

    init(service: String = "com.porarri.yamabikochat.ios") {
        self.service = service
    }

    func saveSecret(_ value: String?, key: String) throws {
        if let value {
            guard let data = value.data(using: .utf8) else { throw KeychainStoreError.invalidEncoding }

            let query: [CFString: Any] = [
                kSecClass: kSecClassGenericPassword,
                kSecAttrService: service,
                kSecAttrAccount: key
            ]

            let attributes: [CFString: Any] = [
                kSecValueData: data,
                kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlock
            ]

            let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
            if updateStatus == errSecItemNotFound {
                var insert = query
                attributes.forEach { insert[$0.key] = $0.value }
                let addStatus = SecItemAdd(insert as CFDictionary, nil)
                guard addStatus == errSecSuccess else {
                    throw KeychainStoreError.unexpectedStatus(addStatus)
                }
            } else if updateStatus != errSecSuccess {
                throw KeychainStoreError.unexpectedStatus(updateStatus)
            }
        } else {
            try deleteSecret(key: key)
        }
    }

    func readSecret(key: String) throws -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw KeychainStoreError.unexpectedStatus(status)
        }
        guard let data = result as? Data else {
            throw KeychainStoreError.invalidEncoding
        }
        return String(data: data, encoding: .utf8)
    }

    func deleteSecret(key: String) throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainStoreError.unexpectedStatus(status)
        }
    }
}

extension SecureCredentialStore {
    func credential(for provider: CredentialProvider) throws -> String? {
        try readSecret(key: "provider_key_\(provider.rawValue)")
    }

    func setCredential(_ value: String?, for provider: CredentialProvider) throws {
        try saveSecret(value, key: "provider_key_\(provider.rawValue)")
    }

    func codexAccessToken() throws -> String? {
        try readSecret(key: "codex_access_token")
    }

    func setCodexAccessToken(_ value: String?) throws {
        try saveSecret(value, key: "codex_access_token")
    }

    func setOpenAICompatAPIKey(name: String, value: String?) throws {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }
        try saveSecret(value, key: "openai_compat_key_\(normalized)")
    }

    func openAICompatAPIKey(name: String) throws -> String? {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        return try readSecret(key: "openai_compat_key_\(normalized)")
    }

    func clearOpenAICompatAPIKey(name: String) throws {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }
        try deleteSecret(key: "openai_compat_key_\(normalized)")
    }
}

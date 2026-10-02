import Combine
import Foundation

typealias PiOAuthLoginHandler = @Sendable (
    PiOAuthProvider, PiOAuthLoginMethod,
    (@Sendable (SuperGrokDeviceCodeChallenge) async -> Void)?
) async throws -> PiOAuthResolution

typealias PiOAuthResolveHandler = @Sendable (PiOAuthProvider, String, Bool) async throws -> PiOAuthResolution
typealias PiChatGPTLoginHandler = @Sendable (
    String, String?, @escaping @Sendable (JSONValue) async throws -> Void
) async throws -> PiOAuthResolution
typealias PiChatGPTCatalogHandler = @Sendable (String, [String: PiCatalogModelContract]) async throws -> [PiCodexModel]

/// CODEX_AUTH now uses the official ChatGPT plan provider. OAuth belongs to Pi.
final class CodexAuthRepository {
    struct BearerToken: Sendable, Equatable {
        var token: String
        var isAPIKey: Bool
        var accountId: String?
    }

    private struct Accounts: Codable {
        var selectedClientID: String?
        var registrations: [String: JSONValue] = [:]
    }

    private enum Constants {
        static let accountsKey = "pi_chatgpt_accounts_v1"
        static let hostKey = "pi_chatgpt_host_v1"
        static let legacyCredentialKey = "pi_oauth_openai_codex_v1"
    }

    private let authLock = NSRecursiveLock()
    private var authGeneration = 0
    private var catalogCache: [PiCodexModel]?
    private var catalogRequestID = UUID()
    private var signingOut = false
    private var pendingResolution: (id: UUID, generation: Int, credential: String, task: Task<PiOAuthResolution, Error>)?
    private let credentialStore: SecureCredentialStore
    private let loginHandler: PiChatGPTLoginHandler
    private let resolveHandler: PiOAuthResolveHandler
    private let catalogHandler: PiChatGPTCatalogHandler
    private let revokeHandler: @Sendable (String) async throws -> Void
    private let subject: CurrentValueSubject<CodexAuthState, Never>

    init(
        credentialStore: SecureCredentialStore,
        loginHandler: @escaping PiChatGPTLoginHandler = { hostID, registration, onRegistration in
            try await PiAgentRuntime.shared.loginChatGPT(hostID: hostID, registrationJSON: registration, onRegistration: onRegistration)
        },
        resolveHandler: @escaping PiOAuthResolveHandler = { provider, credential, force in
            try await PiAgentRuntime.shared.resolveOAuth(provider: provider, credentialJSON: credential, force: force)
        },
        catalogHandler: @escaping PiChatGPTCatalogHandler = { credential, contracts in
            try await PiAgentRuntime.shared.chatGPTModels(credentialJSON: credential, contracts: contracts)
        },
        revokeHandler: @escaping @Sendable (String) async throws -> Void = { credential in
            try await PiAgentRuntime.shared.revokeChatGPT(credentialJSON: credential)
        }
    ) {
        self.credentialStore = credentialStore
        self.loginHandler = loginHandler
        self.resolveHandler = resolveHandler
        self.catalogHandler = catalogHandler
        self.revokeHandler = revokeHandler
        subject = CurrentValueSubject(Self.readState(credentialStore: credentialStore))
        if subject.value.requiresReauthentication {
            DiagnosticsLogger.log("Legacy Codex credential requires official ChatGPT authorization", category: .auth)
        }
    }

    var state: AnyPublisher<CodexAuthState, Never> { subject.eraseToAnyPublisher() }
    func currentState() -> CodexAuthState { subject.value }

    private func readAccounts() throws -> Accounts {
        guard let stored = try credentialStore.readSecret(key: Constants.accountsKey) else { return Accounts() }
        return try JSONDecoder().decode(Accounts.self, from: Data(stored.utf8))
    }

    private func saveAccounts(_ accounts: Accounts) throws {
        try credentialStore.saveSecret(String(decoding: JSONEncoder().encode(accounts), as: UTF8.self), key: Constants.accountsKey)
    }

    private func credentialJSON() throws -> String? {
        let accounts = try readAccounts()
        guard let id = accounts.selectedClientID, let registration = accounts.registrations[id],
              registration.objectValue?["access"]?.stringValue != nil else { return nil }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return String(decoding: try encoder.encode(registration), as: UTF8.self)
    }

    private func hostID() throws -> String {
        if let existing = try credentialStore.readSecret(key: Constants.hostKey) { return existing }
        let created = "urn:uuid:\(UUID().uuidString.lowercased())"
        try credentialStore.saveSecret(created, key: Constants.hostKey)
        return created
    }

    private func commit(_ resolution: PiOAuthResolution, generation: Int) throws {
        try authLock.withLock {
            guard generation == authGeneration else { throw CancellationError() }
            guard let object = resolution.credential.objectValue,
                  object["contract"]?.stringValue == "siwc-v1",
                  let id = object["clientId"]?.stringValue, id != "dynamic_agent_client",
                  object["subject"]?.stringValue != nil else {
                throw ProviderClientError.parseFailure("Pi returned an invalid official ChatGPT credential")
            }
            var accounts = try readAccounts()
            accounts.registrations[id] = resolution.credential
            accounts.selectedClientID = id
            try saveAccounts(accounts)
            try credentialStore.saveSecret(Self.nowISO8601(), key: "codex_last_refresh")
            subject.send(Self.readState(credentialStore: credentialStore))
        }
    }

    private func resolveCredential(_ credential: String, force: Bool, generation: Int) async throws -> PiOAuthResolution {
        let pending = try authLock.withLock {
            guard generation == authGeneration, !signingOut, let credential = try credentialJSON() else { throw CancellationError() }
            if let pendingResolution, pendingResolution.generation == generation, pendingResolution.credential == credential { return pendingResolution }
            let id = UUID()
            let task = Task {
                let resolution = try await resolveHandler(.chatgpt, credential, force)
                try commit(resolution, generation: generation)
                return resolution
            }
            let pending = (id: id, generation: generation, credential: credential, task: task)
            pendingResolution = pending
            return pending
        }
        defer { authLock.withLock { if pendingResolution?.id == pending.id { pendingResolution = nil } } }
        let result = try await pending.task.value
        return try authLock.withLock {
            guard generation == authGeneration else { throw CancellationError() }
            return result
        }
    }

    func loginWithBrowser(clientID: String? = nil, newAccount: Bool = false) async -> Result<CodexAuthState, Error> {
        do {
            let (generation, host, registration) = try authLock.withLock {
                guard !signingOut else { throw CancellationError() }
                authGeneration += 1
                catalogCache = nil
                let accounts = try readAccounts()
                if let clientID, accounts.registrations[clientID] == nil {
                    throw ProviderClientError.parseFailure("Selected ChatGPT registration is missing")
                }
                let selectedID = newAccount ? nil : (clientID ?? accounts.selectedClientID)
                let selected = selectedID.flatMap { accounts.registrations[$0] }
                let json = try selected.map { try PiAgentRuntime.credentialJSONString($0) }
                return (authGeneration, try hostID(), json)
            }
            DiagnosticsLogger.log("Official ChatGPT authorization delegated to Pi plugin", category: .auth)
            let resolution = try await loginHandler(host, registration) { registration in
                try self.authLock.withLock {
                    guard generation == self.authGeneration else { throw CancellationError() }
                    guard let id = registration.objectValue?["clientId"]?.stringValue, id != "dynamic_agent_client" else {
                        throw ProviderClientError.parseFailure("ChatGPT registration is incomplete")
                    }
                    var accounts = try self.readAccounts()
                    if accounts.registrations[id]?.objectValue?["access"] == nil { accounts.registrations[id] = registration }
                    if accounts.selectedClientID == nil { accounts.selectedClientID = id }
                    try self.saveAccounts(accounts)
                }
            }
            try commit(resolution, generation: generation)
            return .success(currentState())
        } catch {
            DiagnosticsLogger.log("Pi ChatGPT authorization failed", category: .auth, error: error)
            return .failure(error)
        }
    }

    func logout() async -> Result<CodexAuthState, Error> {
        do {
            let (generation, credential) = try authLock.withLock {
                let credential = try credentialJSON()
                authGeneration += 1
                catalogCache = nil
                signingOut = true
                return (authGeneration, credential)
            }
            defer { authLock.withLock { signingOut = false } }
            var revocationUnconfirmed = false
            if let credential {
                do { try await revokeHandler(credential) }
                catch {
                    // Official SIWC allows local sign-out when remote revocation is unconfirmed.
                    revocationUnconfirmed = true
                    DiagnosticsLogger.log("ChatGPT remote session revocation unconfirmed", category: .auth, error: error)
                }
            }
            return try authLock.withLock {
                guard generation == authGeneration else { throw CancellationError() }
                var accounts = try readAccounts()
                if let id = accounts.selectedClientID, let object = accounts.registrations[id]?.objectValue {
                    let retained = ["contract", "clientId", "hostId", "issuer", "subject", "email"]
                    accounts.registrations[id] = .object(object.filter { retained.contains($0.key) })
                }
                try saveAccounts(accounts)
                for key in [Constants.legacyCredentialKey, "codex_email", "codex_plan_type", "codex_account_id", "codex_last_refresh", "codex_auth_json_v2", "codex_access_token"] {
                    try credentialStore.deleteSecret(key: key)
                }
                try credentialStore.setCredential(nil, for: .codexAuth)
                var updated = Self.readState(credentialStore: credentialStore)
                updated.revocationUnconfirmed = revocationUnconfirmed
                subject.send(updated)
                return .success(updated)
            }
        } catch { return .failure(error) }
    }

    func refreshIfNeeded(force: Bool = false) async -> Result<CodexAuthState, Error> {
        do {
            let (generation, credential) = try authLock.withLock { (authGeneration, try credentialJSON()) }
            guard let credential else { return .success(currentState()) }
            _ = try await resolveCredential(credential, force: force, generation: generation)
            return .success(currentState())
        } catch {
            DiagnosticsLogger.log("Pi ChatGPT refresh failed", category: .auth, error: error)
            return .failure(error)
        }
    }

    func hasAuthToken() -> Bool { authLock.withLock { !signingOut && currentState().isLoggedIn && currentState().planUsageEnabled } }
    func getApiKey() async -> String? { nil }

    func getBearerToken() async -> BearerToken? {
        guard hasAuthToken() else { return nil }
        do {
            let (generation, credential) = try authLock.withLock { (authGeneration, try credentialJSON()) }
            guard let credential else { return nil }
            let resolution = try await resolveCredential(credential, force: false, generation: generation)
            return BearerToken(token: resolution.accessToken, isAPIKey: false, accountId: resolution.accountId)
        } catch {
            DiagnosticsLogger.log("Pi ChatGPT credential resolution failed", category: .auth, error: error)
            return nil
        }
    }

    /// Last account catalog successfully fetched for the current auth generation.
    /// Used for reasoning-effort options and shortcut model lists without a network call.
    func cachedModels() -> [PiCodexModel] {
        authLock.withLock { catalogCache ?? [] }
    }

    func models(contracts: [String: PiCatalogModelContract]) async throws -> [PiCodexModel] {
        guard hasAuthToken() else { return [] }
        let (generation, requestID, credential) = try authLock.withLock {
            let requestID = UUID()
            catalogRequestID = requestID
            return (authGeneration, requestID, try credentialJSON())
        }
        guard let credential else { return [] }
        let resolution = try await resolveCredential(credential, force: false, generation: generation)
        let models = try await catalogHandler(PiAgentRuntime.credentialJSONString(resolution.credential), contracts)
        return try authLock.withLock {
            guard generation == authGeneration, requestID == catalogRequestID else { throw CancellationError() }
            catalogCache = models
            return models
        }
    }

    private static func readState(credentialStore: SecureCredentialStore) -> CodexAuthState {
        guard let stored = try? credentialStore.readSecret(key: Constants.accountsKey),
              let accounts = try? JSONDecoder().decode(Accounts.self, from: Data(stored.utf8)) else {
            return CodexAuthState(requiresReauthentication: (try? credentialStore.readSecret(key: Constants.legacyCredentialKey)) != nil)
        }
        let object = accounts.selectedClientID.flatMap { accounts.registrations[$0]?.objectValue }
        let scopes = object?["scopes"]?.arrayValue?.compactMap(\.stringValue) ?? []
        return CodexAuthState(
            isLoggedIn: object?["contract"]?.stringValue == "siwc-v1" && object?["access"]?.stringValue != nil,
            email: object?["email"]?.stringValue,
            accountId: accounts.selectedClientID,
            lastRefreshISO8601: try? credentialStore.readSecret(key: "codex_last_refresh"),
            planUsageEnabled: scopes.contains("chatgpt.tokens.use.direct"),
            savedAccounts: accounts.registrations.keys.sorted().compactMap { id in
                guard let value = accounts.registrations[id]?.objectValue, value["subject"]?.stringValue != nil else { return nil }
                return CodexSavedAccount(clientID: id, email: value["email"]?.stringValue)
            }
        )
    }

    private static func nowISO8601() -> String { ISO8601DateFormatter().string(from: Date()) }
}

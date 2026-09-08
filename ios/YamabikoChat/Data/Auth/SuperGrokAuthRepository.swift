import Combine
import Foundation

final class SuperGrokAuthRepository {
    struct BearerToken: Sendable, Equatable {
        var token: String
    }

    private enum Constants {
        static let credentialKey = "pi_oauth_supergrok_v1"
    }

    private let authLock = NSRecursiveLock()
    private var authGeneration = 0
    private var pendingResolution: (id: UUID, generation: Int, credential: String, task: Task<PiOAuthResolution, Error>)?

    private func resolveCredential(_ credential: String, force: Bool, generation: Int) async throws -> PiOAuthResolution {
        let pending = try authLock.withLock {
            guard generation == authGeneration, try credentialStore.readSecret(key: Constants.credentialKey) == credential else { throw CancellationError() }
            if let pendingResolution, pendingResolution.generation == generation, pendingResolution.credential == credential {
                return pendingResolution
            }
            let id = UUID()
            let task = Task {
                let resolution = try await resolveHandler(.supergrok, credential, force)
                try commit(resolution, generation: generation)
                return resolution
            }
            let pending = (id: id, generation: generation, credential: credential, task: task)
            pendingResolution = pending
            return pending
        }
        defer {
            authLock.withLock {
                if pendingResolution?.id == pending.id { pendingResolution = nil }
            }
        }
        let result = try await pending.task.value
        return try authLock.withLock {
            guard generation == authGeneration else { throw CancellationError() }
            return result
        }
    }

    private func beginAuthOperation() -> Int {
        authLock.withLock {
            authGeneration += 1
            return authGeneration
        }
    }

    private func commit(_ resolution: PiOAuthResolution, generation: Int) throws {
        try authLock.withLock {
            guard generation == authGeneration else { throw CancellationError() }
            try persist(resolution)
            subject.send(Self.readState(credentialStore: credentialStore))
        }
    }

    private let credentialStore: SecureCredentialStore
    private let loginHandler: PiOAuthLoginHandler
    private let resolveHandler: PiOAuthResolveHandler
    private let subject: CurrentValueSubject<SuperGrokAuthState, Never>

    init(
        credentialStore: SecureCredentialStore,
        loginHandler: @escaping PiOAuthLoginHandler = { provider, method, onDeviceCode in
            try await PiAgentRuntime.shared.loginOAuth(
                provider: provider,
                method: method,
                onDeviceCode: onDeviceCode
            )
        },
        resolveHandler: @escaping PiOAuthResolveHandler = { provider, credential, force in
            try await PiAgentRuntime.shared.resolveOAuth(
                provider: provider,
                credentialJSON: credential,
                force: force
            )
        }
    ) {
        self.credentialStore = credentialStore
        self.loginHandler = loginHandler
        self.resolveHandler = resolveHandler
        subject = CurrentValueSubject(Self.readState(credentialStore: credentialStore))
    }

    var state: AnyPublisher<SuperGrokAuthState, Never> { subject.eraseToAnyPublisher() }

    func currentState() -> SuperGrokAuthState { subject.value }

    func loginWithBrowser() async -> Result<SuperGrokAuthState, Error> {
        await login(method: .browser)
    }

    func loginWithDeviceCode() async -> Result<SuperGrokAuthState, Error> {
        await login(method: .device)
    }

    func logout() async -> Result<SuperGrokAuthState, Error> {
        do {
            return try authLock.withLock {
                authGeneration += 1
                for key in [
                    Constants.credentialKey,
                    "supergrok_email",
                    "supergrok_last_refresh",
                    "supergrok_auth_json_v1",
                    "supergrok_access_token"
                ] {
                    try credentialStore.deleteSecret(key: key)
                }
                let updated = Self.readState(credentialStore: credentialStore)
                subject.send(updated)
                return .success(updated)
            }
        } catch {
            return .failure(error)
        }
    }

    func refreshIfNeeded(force: Bool = false) async -> Result<SuperGrokAuthState, Error> {
        let generation = authLock.withLock { authGeneration }
        do {
            guard let credential = try credentialStore.readSecret(key: Constants.credentialKey) else {
                let updated = Self.readState(credentialStore: credentialStore)
                subject.send(updated)
                return .success(updated)
            }
            _ = try await resolveCredential(credential, force: force, generation: generation)
            let updated = currentState()
            return .success(updated)
        } catch {
            DiagnosticsLogger.log("pi-grok token refresh failed", category: .auth, error: error)
            return .failure(error)
        }
    }

    func hasAuthToken() -> Bool {
        (try? credentialStore.readSecret(key: Constants.credentialKey))?.isEmpty == false
    }

    func getBearerToken() async -> BearerToken? {
        let generation = authLock.withLock { authGeneration }
        guard let credential = try? credentialStore.readSecret(key: Constants.credentialKey),
              !credential.isEmpty else { return nil }
        do {
            let resolution = try await resolveCredential(credential, force: false, generation: generation)
            return BearerToken(token: resolution.accessToken)
        } catch {
            DiagnosticsLogger.log("pi-grok credential resolution failed", category: .auth, error: error)
            return nil
        }
    }

    private func login(method: PiOAuthLoginMethod) async -> Result<SuperGrokAuthState, Error> {
        do {
            DiagnosticsLogger.log("SuperGrok auth delegated to pi-grok", category: .auth)
            let generation = beginAuthOperation()
            let resolution = try await loginHandler(.supergrok, method) { [weak self] challenge in
                guard let self else { return }
                self.authLock.withLock {
                    guard generation == self.authGeneration else { return }
                    var pending = self.subject.value
                    pending.pendingDeviceCode = challenge
                    self.subject.send(pending)
                }
            }
            try commit(resolution, generation: generation)
            let updated = currentState()
            return .success(updated)
        } catch {
            DiagnosticsLogger.log("pi-grok login failed", category: .auth, error: error)
            return .failure(error)
        }
    }

    private func persist(_ resolution: PiOAuthResolution) throws {
        try credentialStore.saveSecret(
            try PiAgentRuntime.credentialJSONString(resolution.credential),
            key: Constants.credentialKey
        )
        try credentialStore.saveSecret(resolution.profile.email, key: "supergrok_email")
        try credentialStore.saveSecret(Self.nowISO8601(), key: "supergrok_last_refresh")
        try credentialStore.deleteSecret(key: "supergrok_auth_json_v1")
        try credentialStore.deleteSecret(key: "supergrok_access_token")
    }

    private static func readState(credentialStore: SecureCredentialStore) -> SuperGrokAuthState {
        let credential = try? credentialStore.readSecret(key: Constants.credentialKey)
        return SuperGrokAuthState(
            isLoggedIn: credential?.isEmpty == false,
            email: try? credentialStore.readSecret(key: "supergrok_email"),
            lastRefreshISO8601: try? credentialStore.readSecret(key: "supergrok_last_refresh"),
            pendingDeviceCode: nil
        )
    }

    private static func nowISO8601() -> String { ISO8601DateFormatter().string(from: Date()) }
}

import Combine
import Foundation

final class SuperGrokAuthRepository {
    struct BearerToken: Sendable, Equatable {
        var token: String
    }

    private enum Constants {
        static let credentialKey = "pi_oauth_supergrok_v1"
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
        } catch {
            return .failure(error)
        }
    }

    func refreshIfNeeded(force: Bool = false) async -> Result<SuperGrokAuthState, Error> {
        do {
            guard let credential = try credentialStore.readSecret(key: Constants.credentialKey) else {
                let updated = Self.readState(credentialStore: credentialStore)
                subject.send(updated)
                return .success(updated)
            }
            let resolution = try await resolveHandler(.supergrok, credential, force)
            try persist(resolution)
            let updated = Self.readState(credentialStore: credentialStore)
            subject.send(updated)
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
        guard let credential = try? credentialStore.readSecret(key: Constants.credentialKey),
              !credential.isEmpty else { return nil }
        do {
            let resolution = try await resolveHandler(.supergrok, credential, false)
            try persist(resolution)
            subject.send(Self.readState(credentialStore: credentialStore))
            return BearerToken(token: resolution.accessToken)
        } catch {
            DiagnosticsLogger.log("pi-grok credential resolution failed", category: .auth, error: error)
            return nil
        }
    }

    private func login(method: PiOAuthLoginMethod) async -> Result<SuperGrokAuthState, Error> {
        do {
            DiagnosticsLogger.log("SuperGrok auth delegated to pi-grok", category: .auth)
            let resolution = try await loginHandler(.supergrok, method) { [weak self] challenge in
                guard let self else { return }
                var pending = self.subject.value
                pending.pendingDeviceCode = challenge
                self.subject.send(pending)
            }
            try persist(resolution)
            let updated = Self.readState(credentialStore: credentialStore)
            subject.send(updated)
            return .success(updated)
        } catch {
            var updated = Self.readState(credentialStore: credentialStore)
            updated.pendingDeviceCode = nil
            subject.send(updated)
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

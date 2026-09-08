import Combine
import Foundation
import UIKit

typealias PiOAuthLoginHandler = @Sendable (
    PiOAuthProvider,
    PiOAuthLoginMethod,
    (@Sendable (SuperGrokDeviceCodeChallenge) async -> Void)?
) async throws -> PiOAuthResolution

typealias PiOAuthResolveHandler = @Sendable (
    PiOAuthProvider,
    String,
    Bool
) async throws -> PiOAuthResolution

final class CodexAuthRepository {
    struct BearerToken: Sendable, Equatable {
        var token: String
        var isAPIKey: Bool
        var accountId: String?
    }

    private enum Constants {
        static let credentialKey = "pi_oauth_openai_codex_v1"
        static let usageURL = "https://chatgpt.com/backend-api/wham/usage"
        static let originator = "codex_cli_rs"
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
                let resolution = try await resolveHandler(.codex, credential, force)
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
    private let httpClient: HTTPClientProtocol
    private let loginHandler: PiOAuthLoginHandler
    private let resolveHandler: PiOAuthResolveHandler
    private let subject: CurrentValueSubject<CodexAuthState, Never>

    init(
        credentialStore: SecureCredentialStore,
        httpClient: HTTPClientProtocol = URLSessionHTTPClient(),
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
        self.httpClient = httpClient
        self.loginHandler = loginHandler
        self.resolveHandler = resolveHandler
        subject = CurrentValueSubject(Self.readState(credentialStore: credentialStore))
    }

    var state: AnyPublisher<CodexAuthState, Never> { subject.eraseToAnyPublisher() }

    func currentState() -> CodexAuthState { subject.value }

    func loginWithBrowser() async -> Result<CodexAuthState, Error> {
        do {
            DiagnosticsLogger.log("Codex auth delegated to Pi", category: .auth)
            let generation = beginAuthOperation()
            let resolution = try await loginHandler(.codex, .browser, nil)
            try commit(resolution, generation: generation)
            let updated = currentState()
            return .success(updated)
        } catch {
            DiagnosticsLogger.log("Pi Codex auth login failed", category: .auth, error: error)
            return .failure(error)
        }
    }

    func logout() async -> Result<CodexAuthState, Error> {
        do {
            return try authLock.withLock {
                authGeneration += 1
                for key in [
                    Constants.credentialKey,
                    "codex_email",
                    "codex_plan_type",
                    "codex_account_id",
                    "codex_last_refresh",
                    "codex_auth_json_v2",
                    "codex_access_token"
                ] {
                    try credentialStore.deleteSecret(key: key)
                }
                try credentialStore.setCredential(nil, for: .codexAuth)
                let updated = Self.readState(credentialStore: credentialStore)
                subject.send(updated)
                return .success(updated)
            }
        } catch {
            return .failure(error)
        }
    }

    func refreshIfNeeded(force: Bool = false) async -> Result<CodexAuthState, Error> {
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
            DiagnosticsLogger.log("Pi Codex auth refresh failed", category: .auth, error: error)
            return .failure(error)
        }
    }

    func hasAuthToken() -> Bool {
        (try? credentialStore.readSecret(key: Constants.credentialKey))?.isEmpty == false
    }

    func getApiKey() async -> String? { nil }

    func getBearerToken() async -> BearerToken? {
        let generation = authLock.withLock { authGeneration }
        guard let credential = try? credentialStore.readSecret(key: Constants.credentialKey),
              !credential.isEmpty else { return nil }
        do {
            let resolution = try await resolveCredential(credential, force: false, generation: generation)
            return BearerToken(token: resolution.accessToken, isAPIKey: false, accountId: resolution.accountId)
        } catch {
            DiagnosticsLogger.log("Pi Codex credential resolution failed", category: .auth, error: error)
            return nil
        }
    }

    func retrieveUsageStatus() async -> Result<CodexUsageStatus, Error> {
        do {
            guard let auth = await getBearerToken() else {
                return .failure(ProviderClientError.missingCredential("CODEX_AUTH access token"))
            }
            guard let accountId = auth.accountId?.trimmedNonEmpty else {
                return .failure(ProviderClientError.parseFailure("Codex account ID is required for usage API"))
            }
            let request = HTTPRequest(
                url: URL(string: Constants.usageURL)!,
                method: "GET",
                headers: [
                    "Authorization": "Bearer \(auth.token)",
                    "ChatGPT-Account-ID": accountId,
                    "originator": Constants.originator,
                    "User-Agent": buildDefaultUserAgent()
                ]
            )
            let (data, response) = try await httpClient.send(request)
            guard (200 ... 299).contains(response.statusCode) else {
                throw ProviderClientError.httpStatus(response.statusCode, String(data: data, encoding: .utf8) ?? "")
            }
            return .success(try Self.parseUsage(data: data))
        } catch {
            return .failure(error)
        }
    }

    private func persist(_ resolution: PiOAuthResolution) throws {
        try credentialStore.saveSecret(
            try PiAgentRuntime.credentialJSONString(resolution.credential),
            key: Constants.credentialKey
        )
        try credentialStore.saveSecret(resolution.profile.email, key: "codex_email")
        try credentialStore.saveSecret(resolution.profile.planType, key: "codex_plan_type")
        try credentialStore.saveSecret(resolution.accountId ?? resolution.profile.accountId, key: "codex_account_id")
        try credentialStore.saveSecret(Self.nowISO8601(), key: "codex_last_refresh")
        try credentialStore.deleteSecret(key: "codex_auth_json_v2")
        try credentialStore.deleteSecret(key: "codex_access_token")
        try credentialStore.setCredential(nil, for: .codexAuth)
    }

    private static func readState(credentialStore: SecureCredentialStore) -> CodexAuthState {
        let credential = try? credentialStore.readSecret(key: Constants.credentialKey)
        return CodexAuthState(
            isLoggedIn: credential?.isEmpty == false,
            email: try? credentialStore.readSecret(key: "codex_email"),
            planType: try? credentialStore.readSecret(key: "codex_plan_type"),
            accountId: try? credentialStore.readSecret(key: "codex_account_id"),
            hasApiKey: false,
            lastRefreshISO8601: try? credentialStore.readSecret(key: "codex_last_refresh")
        )
    }

    private static func parseUsage(data: Data) throws -> CodexUsageStatus {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProviderClientError.parseFailure("Invalid usage response")
        }
        let rateLimit = root["rate_limit"] as? [String: Any]
        return CodexUsageStatus(
            planType: root["plan_type"] as? String,
            primaryWindow: parseWindow(rateLimit?["primary_window"] as? [String: Any]),
            secondaryWindow: parseWindow(rateLimit?["secondary_window"] as? [String: Any]),
            credits: parseCredits(root["credits"] as? [String: Any])
        )
    }

    private static func parseWindow(_ object: [String: Any]?) -> CodexRateLimitWindow? {
        guard let object else { return nil }
        let used = (object["used_percent"] as? NSNumber)?.doubleValue
        let seconds = (object["limit_window_seconds"] as? NSNumber)?.intValue
        let reset = (object["reset_at"] as? NSNumber)?.int64Value
        if used == nil && seconds == nil && reset == nil { return nil }
        return CodexRateLimitWindow(usedPercent: used, limitWindowSeconds: seconds, resetAtEpochSeconds: reset)
    }

    private static func parseCredits(_ object: [String: Any]?) -> CodexCreditsStatus? {
        guard let object else { return nil }
        let rawBalance = object["balance"]
        return CodexCreditsStatus(
            hasCredits: object["has_credits"] as? Bool ?? false,
            unlimited: object["unlimited"] as? Bool ?? false,
            balance: (rawBalance as? String) ?? (rawBalance as? NSNumber)?.stringValue
        )
    }

    private static func nowISO8601() -> String { ISO8601DateFormatter().string(from: Date()) }

    private func buildDefaultUserAgent() -> String {
        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let version = appVersion?.trimmingCharacters(in: .whitespacesAndNewlines).trimmedNonEmpty ?? "unknown"
        let appID = Bundle.main.bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines).trimmedNonEmpty
            ?? "com.porarri.yamabikochat"
        return "YamabikoChat/\(version) (iOS \(UIDevice.current.systemVersion); \(Self.currentArchitecture())) \(appID)"
    }

    private static func currentArchitecture() -> String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #elseif arch(arm)
        return "arm"
        #else
        return "unknown"
        #endif
    }
}

import Foundation
import Combine
import CryptoKit
import Security
import UIKit

final class CodexAuthRepository {
    struct BearerToken: Sendable, Equatable {
        var token: String
        var isAPIKey: Bool
        var accountId: String?
    }

    private enum Constants {
        static let issuer = "https://auth.openai.com"
        static let clientID = "app_EMoamEEZ73f0CkXaXp7hrann"
        static let scope = "openid profile email offline_access api.connectors.read api.connectors.invoke"
        static let originator = "codex_cli_rs"
        static let loopbackRedirectHost = "localhost"
        static let defaultPort: UInt16 = 1455
        static let refreshIntervalDays: TimeInterval = 8 * 24 * 60 * 60
        static let usageURL = "https://chatgpt.com/backend-api/wham/usage"
        static let authStorageKey = "codex_auth_json_v2"
    }

    private struct PKCECodes {
        let verifier: String
        let challenge: String
    }

    private struct APIKeyExchangeResponse: Decodable {
        let accessToken: String

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
        }
    }

    private struct RefreshRequest: Encodable {
        let clientID: String
        let grantType: String
        let refreshToken: String
        let scope: String

        enum CodingKeys: String, CodingKey {
            case clientID = "client_id"
            case grantType = "grant_type"
            case refreshToken = "refresh_token"
            case scope
        }
    }

    private struct RefreshResponse: Decodable {
        let idToken: String?
        let accessToken: String?
        let refreshToken: String?

        enum CodingKeys: String, CodingKey {
            case idToken = "id_token"
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
        }
    }

    private let credentialStore: SecureCredentialStore
    private let httpClient: HTTPClientProtocol
    private let subject: CurrentValueSubject<CodexAuthState, Never>

    init(
        credentialStore: SecureCredentialStore,
        httpClient: HTTPClientProtocol = URLSessionHTTPClient()
    ) {
        self.credentialStore = credentialStore
        self.httpClient = httpClient
        subject = CurrentValueSubject(Self.readState(credentialStore: credentialStore))
    }

    var state: AnyPublisher<CodexAuthState, Never> {
        subject.eraseToAnyPublisher()
    }

    func currentState() -> CodexAuthState {
        subject.value
    }

    func login(
        apiKey: String?,
        accessToken: String?,
        email: String?,
        planType: String?,
        accountId: String?
    ) async -> Result<CodexAuthState, Error> {
        do {
            if let apiKey {
                try credentialStore.setCredential(apiKey.isEmpty ? nil : apiKey, for: .codexAuth)
            }
            if let accessToken {
                try credentialStore.setCodexAccessToken(accessToken.isEmpty ? nil : accessToken)
            }
            try credentialStore.saveSecret(email, key: "codex_email")
            try credentialStore.saveSecret(planType, key: "codex_plan_type")
            try credentialStore.saveSecret(accountId, key: "codex_account_id")
            try credentialStore.saveSecret(Self.nowISO8601(), key: "codex_last_refresh")

            if accessToken != nil || apiKey != nil {
                let tokens = accessToken?.isEmpty == false
                    ? CodexTokenData(idToken: "", accessToken: accessToken ?? "", refreshToken: "", accountId: accountId)
                    : nil
                try saveAuthJSON(
                    CodexAuthJSON(
                        openAIAPIKey: apiKey?.nilIfBlank,
                        tokens: tokens,
                        lastRefresh: Self.nowISO8601()
                    )
                )
            }

            let updated = Self.readState(credentialStore: credentialStore)
            subject.send(updated)
            return .success(updated)
        } catch {
            return .failure(error)
        }
    }

    func loginWithBrowser() async -> Result<CodexAuthState, Error> {
        do {
            let pkce = Self.generatePKCE()
            let stateToken = Self.generateState()
            DiagnosticsLogger.log("Codex auth login start", category: .auth)

            let callbackServer = LocalAuthCallbackServer(
                expectedPath: "/auth/callback",
                preferredPort: Constants.defaultPort
            )
            let port: UInt16
            do {
                port = try callbackServer.bind()
            } catch LocalAuthCallbackError.failedToBindAnyPort {
                DiagnosticsLogger.log(
                    "Codex auth callback bind failed after retries preferredPort=\(Constants.defaultPort)",
                    level: .error,
                    category: .auth
                )
                throw LocalAuthCallbackError.failedToBindAnyPort
            }
            let redirectURI = Self.redirectURI(port: port)
            DiagnosticsLogger.log("Codex auth callback server bound port=\(port)", category: .auth)

            let authorizeURL = try buildAuthorizeURL(
                redirectURI: redirectURI,
                pkce: pkce,
                state: stateToken
            )
            let listenerReady = AuthFlowReadySignal()
            let callbackTask = Task {
                try await callbackServer.awaitCallback(
                    on: port,
                    onReady: { listenerReady.signal() }
                )
            }
            defer { callbackTask.cancel() }

            let backgroundTask = await MainActor.run {
                UIApplication.shared.beginBackgroundTask(withName: "CodexAuthFlow")
            }
            defer {
                Task { @MainActor in
                    if backgroundTask != .invalid {
                        UIApplication.shared.endBackgroundTask(backgroundTask)
                    }
                }
            }

            do {
                try await waitForListenerReady(listenerReady)
            } catch {
                DiagnosticsLogger.log(
                    "Codex auth listener readiness timed out, continuing browser launch",
                    level: .warning,
                    category: .auth,
                    error: error
                )
            }

            try await launchBrowser(authorizeURL)
            DiagnosticsLogger.log("Codex auth browser launched", category: .auth)

            let callback = try await callbackTask.value
            let query = callback.queryItems.reduce(into: [String: String]()) { partialResult, item in
                partialResult[item.name] = item.value ?? ""
            }
            let returnedState = query["state"] ?? ""
            let code = query["code"] ?? ""
            if returnedState != stateToken || code.isEmpty {
                DiagnosticsLogger.log(
                    "Codex auth callback validation failed hasCode=\(!code.isEmpty)",
                    level: .warning,
                    category: .auth
                )
                return .failure(LocalAuthCallbackError.invalidCallback("Invalid callback state or code."))
            }
            DiagnosticsLogger.log("Codex auth callback received, exchanging tokens", category: .auth)

            var tokens = try await exchangeCodeForTokens(
                code: code,
                redirectURI: redirectURI,
                codeVerifier: pkce.verifier
            )
            var apiKey: String? = nil
            do {
                apiKey = try await exchangeIDTokenForAPIKey(idToken: tokens.idToken)
            } catch {
                // Keep bearer login functional even if API key exchange fails.
            }

            let idInfo = CodexJWTParser.parseIDToken(tokens.idToken)
            if tokens.accountId?.isEmpty != false {
                tokens.accountId = idInfo?.accountId
            }
            try persistAuth(apiKey: apiKey, tokens: tokens, idInfo: idInfo)

            let updated = Self.readState(credentialStore: credentialStore)
            subject.send(updated)
            DiagnosticsLogger.log("Codex auth login completed hasApiKey=\(updated.hasApiKey)", category: .auth)
            return .success(updated)
        } catch {
            if case LocalAuthCallbackError.failedToBindAnyPort = error {
                DiagnosticsLogger.log(
                    "Codex auth login failed because callback listener could not bind on loopback",
                    level: .error,
                    category: .auth
                )
            }
            DiagnosticsLogger.log("Codex auth login failed", category: .auth, error: error)
            return .failure(error)
        }
    }

    func logout() async -> Result<CodexAuthState, Error> {
        do {
            try credentialStore.setCredential(nil, for: .codexAuth)
            try credentialStore.setCodexAccessToken(nil)
            try credentialStore.deleteSecret(key: "codex_email")
            try credentialStore.deleteSecret(key: "codex_plan_type")
            try credentialStore.deleteSecret(key: "codex_account_id")
            try credentialStore.deleteSecret(key: "codex_last_refresh")
            try credentialStore.deleteSecret(key: Constants.authStorageKey)
            let updated = Self.readState(credentialStore: credentialStore)
            subject.send(updated)
            return .success(updated)
        } catch {
            return .failure(error)
        }
    }

    func refreshIfNeeded(force: Bool = false) async -> Result<CodexAuthState, Error> {
        do {
            guard hasAuthToken() else {
                let state = Self.readState(credentialStore: credentialStore)
                subject.send(state)
                return .success(state)
            }

            guard var auth = readAuthJSON(),
                  var tokens = auth.tokens
            else {
                let updated = Self.readState(credentialStore: credentialStore)
                subject.send(updated)
                return .success(updated)
            }

            guard !tokens.refreshToken.isEmpty else {
                if force || shouldRefresh() {
                    throw CodexAuthRefreshError.missingRefreshToken
                }
                let updated = Self.readState(credentialStore: credentialStore)
                subject.send(updated)
                return .success(updated)
            }

            if force || shouldRefresh() {
                do {
                    let refreshed = try await refreshTokens(refreshToken: tokens.refreshToken)
                    tokens.idToken = refreshed.idToken ?? tokens.idToken
                    tokens.accessToken = refreshed.accessToken ?? tokens.accessToken
                    tokens.refreshToken = refreshed.refreshToken ?? tokens.refreshToken
                    auth.tokens = tokens
                    auth.lastRefresh = Self.nowISO8601()
                    try persistAuth(
                        apiKey: auth.openAIAPIKey,
                        tokens: tokens,
                        idInfo: CodexJWTParser.parseIDToken(tokens.idToken)
                    )
                } catch let error as CodexAuthRefreshError where error.isUnrecoverable {
                    try clearOAuthTokensKeepingApiKey(from: auth)
                    let updated = Self.readState(credentialStore: credentialStore)
                    subject.send(updated)
                    return .failure(error)
                }
            }

            let updated = Self.readState(credentialStore: credentialStore)
            subject.send(updated)
            return .success(updated)
        } catch let error as CodexAuthRefreshError {
            DiagnosticsLogger.log(
                "Codex auth refresh failed message=\(error.localizedDescription ?? "")",
                level: .error,
                category: .auth
            )
            return .failure(error)
        } catch {
            return .failure(error)
        }
    }

    func hasAuthToken() -> Bool {
        let apiKey = try? credentialStore.credential(for: .codexAuth)
        if let apiKey, !apiKey.isEmpty { return true }

        let access = try? credentialStore.codexAccessToken()
        if let access, !access.isEmpty { return true }

        if let auth = readAuthJSON() {
            if auth.openAIAPIKey?.isEmpty == false { return true }
            if auth.tokens?.accessToken.isEmpty == false { return true }
        }
        return false
    }

    func getApiKey() async -> String? {
        _ = await refreshIfNeeded()
        if let key = try? credentialStore.credential(for: .codexAuth), !key.isEmpty {
            return key
        }
        guard let auth = readAuthJSON(), let tokens = auth.tokens else { return nil }
        do {
            let exchanged = try await exchangeIDTokenForAPIKey(idToken: tokens.idToken)
            try persistAuth(
                apiKey: exchanged,
                tokens: tokens,
                idInfo: CodexJWTParser.parseIDToken(tokens.idToken)
            )
            subject.send(Self.readState(credentialStore: credentialStore))
            return exchanged
        } catch {
            return nil
        }
    }

    func getBearerToken() async -> BearerToken? {
        _ = await refreshIfNeeded()
        if let apiKey = try? credentialStore.credential(for: .codexAuth), !apiKey.isEmpty {
            let accountId = try? credentialStore.readSecret(key: "codex_account_id")
            return BearerToken(token: apiKey, isAPIKey: true, accountId: accountId)
        }
        if let token = try? credentialStore.codexAccessToken(), !token.isEmpty {
            let accountId = try? credentialStore.readSecret(key: "codex_account_id")
            return BearerToken(token: token, isAPIKey: false, accountId: accountId)
        }
        return nil
    }

    func retrieveUsageStatus() async -> Result<CodexUsageStatus, Error> {
        do {
            _ = await refreshIfNeeded()
            let jsonTokens = readAuthJSON()?.tokens
            let accessToken = jsonTokens?.accessToken.nilIfBlank ?? (try? credentialStore.codexAccessToken())
            guard let accessToken, !accessToken.isEmpty else {
                return .failure(ProviderClientError.missingCredential("CODEX_AUTH access token"))
            }

            let accountFromTokens = jsonTokens?.accountId
            let accountFromIDToken: String?
            if let idToken = jsonTokens?.idToken, !idToken.isEmpty {
                accountFromIDToken = CodexJWTParser.extractAccountID(idToken)
            } else {
                accountFromIDToken = nil
            }
            let accountFromAccess = CodexJWTParser.extractAccountID(accessToken)
            let accountFromStore = try? credentialStore.readSecret(key: "codex_account_id")
            let accountId = accountFromTokens ?? accountFromIDToken ?? accountFromAccess ?? accountFromStore
            guard let accountId, !accountId.isEmpty else {
                return .failure(ProviderClientError.parseFailure("Codex account ID is required for usage API"))
            }

            let request = HTTPRequest(
                url: URL(string: Constants.usageURL)!,
                method: "GET",
                headers: [
                    "Authorization": "Bearer \(accessToken)",
                    "ChatGPT-Account-ID": accountId,
                    "originator": Constants.originator,
                    "User-Agent": buildDefaultUserAgent()
                ]
            )

            let (data, response) = try await httpClient.send(request)
            guard (200 ... 299).contains(response.statusCode) else {
                throw ProviderClientError.httpStatus(response.statusCode, String(data: data, encoding: .utf8) ?? "")
            }

            let usage = try Self.parseUsage(data: data)
            return .success(usage)
        } catch {
            return .failure(error)
        }
    }

    private func shouldRefresh() -> Bool {
        guard let raw = try? credentialStore.readSecret(key: "codex_last_refresh"),
              let last = ISO8601DateFormatter().date(from: raw)
        else {
            return true
        }
        return Date().timeIntervalSince(last) > Constants.refreshIntervalDays
    }

    private func readAuthJSON() -> CodexAuthJSON? {
        guard let raw = try? credentialStore.readSecret(key: Constants.authStorageKey),
              let data = raw.data(using: .utf8)
        else {
            return nil
        }
        return try? JSONDecoder().decode(CodexAuthJSON.self, from: data)
    }

    private func saveAuthJSON(_ value: CodexAuthJSON) throws {
        let data = try JSONEncoder().encode(value)
        try credentialStore.saveSecret(String(decoding: data, as: UTF8.self), key: Constants.authStorageKey)
    }

    private func persistAuth(
        apiKey: String?,
        tokens: CodexTokenData,
        idInfo: CodexIDTokenInfo?
    ) throws {
        let payload = CodexAuthJSON(
            openAIAPIKey: apiKey,
            tokens: tokens,
            lastRefresh: Self.nowISO8601()
        )
        try saveAuthJSON(payload)

        try credentialStore.setCredential(apiKey, for: .codexAuth)
        try credentialStore.setCodexAccessToken(tokens.accessToken)
        try credentialStore.saveSecret(idInfo?.email, key: "codex_email")
        try credentialStore.saveSecret(idInfo?.planType, key: "codex_plan_type")
        try credentialStore.saveSecret(tokens.accountId ?? idInfo?.accountId, key: "codex_account_id")
        try credentialStore.saveSecret(payload.lastRefresh, key: "codex_last_refresh")
    }

    private func buildAuthorizeURL(
        redirectURI: String,
        pkce: PKCECodes,
        state: String
    ) throws -> URL {
        var components = URLComponents(string: "\(Constants.issuer)/oauth/authorize")
        components?.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: Constants.clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: Constants.scope),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "id_token_add_organizations", value: "true"),
            URLQueryItem(name: "codex_cli_simplified_flow", value: "true"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "originator", value: Constants.originator)
        ]
        guard let url = components?.url else {
            throw ProviderClientError.invalidBaseURL(Constants.issuer)
        }
        return url
    }

    static func redirectURI(port: UInt16) -> String {
        "http://\(Constants.loopbackRedirectHost):\(port)/auth/callback"
    }

    private func launchBrowser(_ url: URL) async throws {
        try await MainActor.run {
            guard UIApplication.shared.canOpenURL(url) else {
                throw ProviderClientError.invalidBaseURL(url.absoluteString)
            }
        }
        try await withCheckedThrowingContinuation { continuation in
            Task { @MainActor in
                UIApplication.shared.open(url, options: [:]) { opened in
                    if opened {
                        continuation.resume(returning: ())
                    } else {
                        continuation.resume(throwing: ProviderClientError.invalidBaseURL(url.absoluteString))
                    }
                }
            }
        }
    }

    private func waitForListenerReady(
        _ signal: AuthFlowReadySignal,
        timeoutNanoseconds: UInt64 = 2_000_000_000
    ) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                await signal.wait()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: timeoutNanoseconds)
                throw LocalAuthCallbackError.timeout
            }
            _ = try await group.next()
            group.cancelAll()
        }
    }

    private func exchangeCodeForTokens(
        code: String,
        redirectURI: String,
        codeVerifier: String
    ) async throws -> CodexTokenData {
        let body = [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectURI,
            "client_id": Constants.clientID,
            "code_verifier": codeVerifier
        ]

        let requestBody = body
            .map { "\($0.key)=\(Self.formURLEncode($0.value))" }
            .joined(separator: "&")
        let request = HTTPRequest(
            url: URL(string: "\(Constants.issuer)/oauth/token")!,
            method: "POST",
            headers: [
                "Content-Type": "application/x-www-form-urlencoded"
            ],
            body: Data(requestBody.utf8)
        )
        let (data, response) = try await httpClient.send(request)
        guard (200 ... 299).contains(response.statusCode) else {
            throw ProviderClientError.httpStatus(response.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        let decoded = try JSONDecoder().decode(CodexTokenData.self, from: data)
        return decoded
    }

    private func exchangeIDTokenForAPIKey(idToken: String) async throws -> String {
        let form = [
            "grant_type": "urn:ietf:params:oauth:grant-type:token-exchange",
            "client_id": Constants.clientID,
            "requested_token": "openai-api-key",
            "subject_token": idToken,
            "subject_token_type": "urn:ietf:params:oauth:token-type:id_token"
        ]
            .map { "\($0.key)=\(Self.formURLEncode($0.value))" }
            .joined(separator: "&")

        let request = HTTPRequest(
            url: URL(string: "\(Constants.issuer)/oauth/token")!,
            method: "POST",
            headers: [
                "Content-Type": "application/x-www-form-urlencoded"
            ],
            body: Data(form.utf8)
        )
        let (data, response) = try await httpClient.send(request)
        guard (200 ... 299).contains(response.statusCode) else {
            throw ProviderClientError.httpStatus(response.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        let parsed = try JSONDecoder().decode(APIKeyExchangeResponse.self, from: data)
        return parsed.accessToken
    }

    private func refreshTokens(refreshToken: String) async throws -> RefreshResponse {
        let payload = RefreshRequest(
            clientID: Constants.clientID,
            grantType: "refresh_token",
            refreshToken: refreshToken,
            scope: "openid profile email"
        )
        let body = try JSONEncoder().encode(payload)
        let request = HTTPRequest(
            url: URL(string: "\(Constants.issuer)/oauth/token")!,
            method: "POST",
            headers: [
                "Content-Type": "application/json",
                "originator": Constants.originator,
                "User-Agent": buildDefaultUserAgent()
            ],
            body: body
        )
        let (data, response) = try await httpClient.send(request)
        guard (200 ... 299).contains(response.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            if response.statusCode == 401 {
                let classified = CodexAuthRefreshError.classified(from: body)
                let code = CodexAuthRefreshError.extractErrorCode(from: body) ?? "unknown"
                DiagnosticsLogger.log(
                    "Codex auth refresh failed code=\(code) message=\(classified.localizedDescription ?? "")",
                    level: .error,
                    category: .auth
                )
                throw classified
            }
            throw ProviderClientError.httpStatus(response.statusCode, body)
        }
        return try JSONDecoder().decode(RefreshResponse.self, from: data)
    }

    private func clearOAuthTokensKeepingApiKey(from auth: CodexAuthJSON) throws {
        let apiKey = auth.openAIAPIKey?.nilIfBlank
        if let apiKey {
            let payload = CodexAuthJSON(
                openAIAPIKey: apiKey,
                tokens: nil,
                lastRefresh: Self.nowISO8601()
            )
            try saveAuthJSON(payload)
            try credentialStore.setCredential(apiKey, for: .codexAuth)
        } else {
            try credentialStore.deleteSecret(key: Constants.authStorageKey)
            try credentialStore.setCredential(nil, for: .codexAuth)
        }
        try credentialStore.setCodexAccessToken(nil)
        try credentialStore.saveSecret(Self.nowISO8601(), key: "codex_last_refresh")
    }

    private static func readState(credentialStore: SecureCredentialStore) -> CodexAuthState {
        let apiKey = try? credentialStore.credential(for: .codexAuth)
        let token = try? credentialStore.codexAccessToken()
        let email = try? credentialStore.readSecret(key: "codex_email")
        let planType = try? credentialStore.readSecret(key: "codex_plan_type")
        let accountId = try? credentialStore.readSecret(key: "codex_account_id")
        let lastRefresh = try? credentialStore.readSecret(key: "codex_last_refresh")

        return CodexAuthState(
            isLoggedIn: !(token ?? "").isEmpty || !(apiKey ?? "").isEmpty,
            email: email,
            planType: planType,
            accountId: accountId,
            hasApiKey: !(apiKey ?? "").isEmpty,
            lastRefreshISO8601: lastRefresh
        )
    }

    private static func parseUsage(data: Data) throws -> CodexUsageStatus {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProviderClientError.parseFailure("Invalid usage response")
        }

        let rateLimit = root["rate_limit"] as? [String: Any]
        let primary = parseWindow(rateLimit?["primary_window"] as? [String: Any])
        let secondary = parseWindow(rateLimit?["secondary_window"] as? [String: Any])
        let credits = parseCredits(root["credits"] as? [String: Any])

        return CodexUsageStatus(
            planType: root["plan_type"] as? String,
            primaryWindow: primary,
            secondaryWindow: secondary,
            credits: credits
        )
    }

    private static func parseWindow(_ object: [String: Any]?) -> CodexRateLimitWindow? {
        guard let object else { return nil }
        let used = (object["used_percent"] as? NSNumber)?.doubleValue
        let seconds = (object["limit_window_seconds"] as? NSNumber)?.intValue
        let reset = (object["reset_at"] as? NSNumber)?.int64Value
        if used == nil && seconds == nil && reset == nil { return nil }
        return CodexRateLimitWindow(
            usedPercent: used,
            limitWindowSeconds: seconds,
            resetAtEpochSeconds: reset
        )
    }

    private static func parseCredits(_ object: [String: Any]?) -> CodexCreditsStatus? {
        guard let object else { return nil }
        let rawBalance = object["balance"]
        let balance = (rawBalance as? String) ?? (rawBalance as? NSNumber)?.stringValue
        return CodexCreditsStatus(
            hasCredits: object["has_credits"] as? Bool ?? false,
            unlimited: object["unlimited"] as? Bool ?? false,
            balance: balance
        )
    }

    private static func nowISO8601() -> String {
        ISO8601DateFormatter().string(from: Date())
    }

    private static func generatePKCE() -> PKCECodes {
        let verifierData = randomBytes(count: 64)
        let verifier = base64URL(verifierData)
        let challenge = base64URL(sha256(verifier))
        return PKCECodes(verifier: verifier, challenge: challenge)
    }

    private static func generateState() -> String {
        base64URL(randomBytes(count: 32))
    }

    private static func randomBytes(count: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        bytes.withUnsafeMutableBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }
            _ = SecRandomCopyBytes(kSecRandomDefault, count, baseAddress)
        }
        return Data(bytes)
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func formURLEncode(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private static func sha256(_ string: String) -> Data {
        guard let data = string.data(using: .utf8) else { return Data() }
        return Data(SHA256.hash(data: data))
    }

    private func buildDefaultUserAgent() -> String {
        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return CodexUserAgentPresetCatalog.buildUserAgent(
            originator: Constants.originator,
            cliVersion: CodexUserAgentPresetCatalog.defaultCodexCLIVersion,
            preset: CodexUserAgentPresetCatalog.presetAndroid,
            mobileOSVersion: UIDevice.current.systemVersion,
            mobileArch: CodexUserAgentPresetCatalog.currentArchitecture(),
            appID: Bundle.main.bundleIdentifier,
            appVersion: appVersion
        )
    }

}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

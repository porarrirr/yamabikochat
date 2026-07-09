import Combine
import CryptoKit
import Foundation
import UIKit

final class SuperGrokAuthRepository {
    struct BearerToken: Sendable, Equatable {
        var token: String
    }

    private struct PKCECodes {
        let verifier: String
        let challenge: String
    }

    private let credentialStore: SecureCredentialStore
    private let httpClient: HTTPClientProtocol
    private let subject: CurrentValueSubject<SuperGrokAuthState, Never>
    /// Boxes the in-flight Task so we can use identity (`===`) for single-flight cleanup.
    private final class RefreshTaskBox {
        let task: Task<Result<SuperGrokAuthState, Error>, Never>
        init(_ task: Task<Result<SuperGrokAuthState, Error>, Never>) {
            self.task = task
        }
    }
    private let refreshLock = NSLock()
    private var refreshInFlight: RefreshTaskBox?

    init(
        credentialStore: SecureCredentialStore,
        httpClient: HTTPClientProtocol = URLSessionHTTPClient()
    ) {
        self.credentialStore = credentialStore
        self.httpClient = httpClient
        subject = CurrentValueSubject(Self.readState(credentialStore: credentialStore))
    }

    var state: AnyPublisher<SuperGrokAuthState, Never> {
        subject.eraseToAnyPublisher()
    }

    func currentState() -> SuperGrokAuthState {
        subject.value
    }

    func loginWithBrowser() async -> Result<SuperGrokAuthState, Error> {
        do {
            let pkce = Self.generatePKCE()
            let stateToken = Self.generateState()
            let nonce = Self.generateState()
            DiagnosticsLogger.log("SuperGrok auth browser login start", category: .auth)

            let callbackServer = LocalAuthCallbackServer(
                expectedPath: SuperGrokAuthConstants.oauthRedirectPath,
                preferredPort: SuperGrokAuthConstants.oauthPort
            )
            let port: UInt16
            do {
                port = try callbackServer.bind()
            } catch LocalAuthCallbackError.failedToBindAnyPort {
                DiagnosticsLogger.log(
                    "SuperGrok auth callback bind failed port=\(SuperGrokAuthConstants.oauthPort)",
                    level: .error,
                    category: .auth
                )
                throw SuperGrokAuthCallbackError.portInUse
            }

            guard port == SuperGrokAuthConstants.oauthPort else {
                throw SuperGrokAuthCallbackError.portMismatch(expected: SuperGrokAuthConstants.oauthPort, actual: port)
            }

            let redirectURI = SuperGrokAuthConstants.redirectURI
            let authorizeURL = try buildAuthorizeURL(
                redirectURI: redirectURI,
                pkce: pkce,
                state: stateToken,
                nonce: nonce
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
                UIApplication.shared.beginBackgroundTask(withName: "SuperGrokAuthFlow")
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
                    "SuperGrok auth listener readiness timed out, continuing browser launch",
                    level: .warning,
                    category: .auth,
                    error: error
                )
            }

            try await launchBrowser(authorizeURL)
            DiagnosticsLogger.log("SuperGrok auth browser launched", category: .auth)

            let callback = try await callbackTask.value
            let query = callback.queryItems.reduce(into: [String: String]()) { partialResult, item in
                partialResult[item.name] = item.value ?? ""
            }

            if let error = query["error"]?.trimmedNonEmpty {
                let description = query["error_description"]?.trimmedNonEmpty ?? error
                return .failure(LocalAuthCallbackError.invalidCallback(description))
            }

            let returnedState = query["state"] ?? ""
            let code = query["code"] ?? ""
            guard returnedState == stateToken, !code.isEmpty else {
                return .failure(LocalAuthCallbackError.invalidCallback("Invalid callback state or code."))
            }

            let tokens = try await exchangeCodeForTokens(
                code: code,
                redirectURI: redirectURI,
                codeVerifier: pkce.verifier
            )
            try persistAuth(tokens: tokens)

            let updated = Self.readState(credentialStore: credentialStore)
            subject.send(updated)
            DiagnosticsLogger.log("SuperGrok auth browser login completed", category: .auth)
            return .success(updated)
        } catch {
            DiagnosticsLogger.log("SuperGrok auth browser login failed", category: .auth, error: error)
            return .failure(error)
        }
    }

    func loginWithDeviceCode() async -> Result<SuperGrokAuthState, Error> {
        do {
            let device = try await requestDeviceCode()
            let challenge = SuperGrokDeviceCodeChallenge(
                verificationURI: device.verificationURI,
                userCode: device.userCode,
                browserURL: device.verificationURIComplete ?? device.verificationURI
            )
            var pending = Self.readState(credentialStore: credentialStore)
            pending.pendingDeviceCode = challenge
            subject.send(pending)

            if let url = URL(string: challenge.browserURL) {
                do {
                    try await launchBrowser(url)
                    DiagnosticsLogger.log("SuperGrok device-code browser launched", category: .auth)
                } catch {
                    DiagnosticsLogger.log(
                        "SuperGrok device-code browser open failed; user can open URL manually",
                        level: .warning,
                        category: .auth,
                        error: error
                    )
                }
            }

            let tokens = try await pollDeviceCodeToken(device: device)
            try persistAuth(tokens: tokens)

            let updated = Self.readState(credentialStore: credentialStore)
            subject.send(updated)
            DiagnosticsLogger.log("SuperGrok auth device-code login completed", category: .auth)
            return .success(updated)
        } catch {
            var cleared = Self.readState(credentialStore: credentialStore)
            cleared.pendingDeviceCode = nil
            subject.send(cleared)
            DiagnosticsLogger.log("SuperGrok auth device-code login failed", category: .auth, error: error)
            return .failure(error)
        }
    }

    func logout() async -> Result<SuperGrokAuthState, Error> {
        do {
            try credentialStore.setSuperGrokAccessToken(nil)
            try credentialStore.deleteSecret(key: "supergrok_email")
            try credentialStore.deleteSecret(key: "supergrok_last_refresh")
            try credentialStore.deleteSecret(key: SuperGrokAuthConstants.authStorageKey)
            let updated = Self.readState(credentialStore: credentialStore)
            subject.send(updated)
            return .success(updated)
        } catch {
            return .failure(error)
        }
    }

    func refreshIfNeeded(force: Bool = false) async -> Result<SuperGrokAuthState, Error> {
        // Single-flight: concurrent 401 retries must share one refresh (refresh tokens are single-use).
        let box = beginRefreshIfNeeded(force: force)
        let result = await box.task.value
        endRefresh(box)
        return result
    }

    private func beginRefreshIfNeeded(force: Bool) -> RefreshTaskBox {
        refreshLock.lock()
        defer { refreshLock.unlock() }
        if let existing = refreshInFlight {
            return existing
        }
        let box = RefreshTaskBox(Task { await self.performRefreshIfNeeded(force: force) })
        refreshInFlight = box
        return box
    }

    private func endRefresh(_ box: RefreshTaskBox) {
        refreshLock.lock()
        defer { refreshLock.unlock() }
        if refreshInFlight === box {
            refreshInFlight = nil
        }
    }

    private func performRefreshIfNeeded(force: Bool) async -> Result<SuperGrokAuthState, Error> {
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
                if force {
                    throw SuperGrokAuthRefreshError.missingRefreshToken
                }
                let updated = Self.readState(credentialStore: credentialStore)
                subject.send(updated)
                return .success(updated)
            }

            if force || shouldRefresh(auth: auth, accessToken: tokens.accessToken) {
                do {
                    let refreshed = try await refreshAccessToken(refreshToken: tokens.refreshToken)
                    tokens.accessToken = refreshed.accessToken
                    tokens.refreshToken = refreshed.refreshToken.nilIfBlank ?? tokens.refreshToken
                    tokens.idToken = refreshed.idToken ?? tokens.idToken
                    tokens.tokenType = refreshed.tokenType ?? tokens.tokenType
                    tokens.scope = refreshed.scope ?? tokens.scope
                    auth.tokens = tokens
                    auth.expiresAtEpochMs = Self.expiresAtEpochMs(from: refreshed.expiresIn)
                    auth.lastRefresh = Self.nowISO8601()
                    try persistAuth(tokens: tokens, expiresAtEpochMs: auth.expiresAtEpochMs)
                } catch let error as SuperGrokAuthRefreshError where error.isUnrecoverable {
                    try clearOAuthTokens()
                    let updated = Self.readState(credentialStore: credentialStore)
                    subject.send(updated)
                    return .failure(error)
                }
            }

            let updated = Self.readState(credentialStore: credentialStore)
            subject.send(updated)
            return .success(updated)
        } catch let error as SuperGrokAuthRefreshError {
            DiagnosticsLogger.log(
                "SuperGrok auth refresh failed message=\(error.localizedDescription)",
                level: .error,
                category: .auth
            )
            return .failure(error)
        } catch {
            return .failure(error)
        }
    }

    func hasAuthToken() -> Bool {
        if let access = try? credentialStore.superGrokAccessToken(), !access.isEmpty {
            return true
        }
        if let auth = readAuthJSON(), auth.tokens?.accessToken.isEmpty == false {
            return true
        }
        return false
    }

    func getBearerToken() async -> BearerToken? {
        _ = await refreshIfNeeded()
        if let token = try? credentialStore.superGrokAccessToken(), !token.isEmpty {
            return BearerToken(token: token)
        }
        return nil
    }

    private func buildAuthorizeURL(
        redirectURI: String,
        pkce: PKCECodes,
        state: String,
        nonce: String
    ) throws -> URL {
        var components = URLComponents(string: SuperGrokAuthConstants.authorizeURL)
        components?.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: SuperGrokAuthConstants.clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: SuperGrokAuthConstants.scope),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "nonce", value: nonce),
            URLQueryItem(name: "plan", value: "generic"),
            URLQueryItem(name: "referrer", value: "opencode")
        ]
        guard let url = components?.url else {
            throw ProviderClientError.invalidBaseURL(SuperGrokAuthConstants.authorizeURL)
        }
        return url
    }

    static func accessTokenIsExpiring(_ token: String?, skewMs: Int64 = SuperGrokAuthConstants.accessTokenRefreshSkewMs) -> Bool {
        SuperGrokJWTParser.accessTokenIsExpiring(token, skewMs: skewMs)
    }

    // MARK: - Private

    private func shouldRefresh(auth: SuperGrokAuthJSON, accessToken: String) -> Bool {
        if SuperGrokJWTParser.accessTokenIsExpiring(accessToken) {
            return true
        }
        if let expiresAtEpochMs = auth.expiresAtEpochMs {
            let nowMs = Int64(Date().timeIntervalSince1970 * 1_000)
            return expiresAtEpochMs - nowMs <= SuperGrokAuthConstants.accessTokenRefreshSkewMs
        }
        return true
    }

    private func readAuthJSON() -> SuperGrokAuthJSON? {
        guard let raw = try? credentialStore.readSecret(key: SuperGrokAuthConstants.authStorageKey),
              let data = raw.data(using: .utf8)
        else {
            return nil
        }
        return try? JSONDecoder().decode(SuperGrokAuthJSON.self, from: data)
    }

    private func saveAuthJSON(_ value: SuperGrokAuthJSON) throws {
        let data = try JSONEncoder().encode(value)
        try credentialStore.saveSecret(String(decoding: data, as: UTF8.self), key: SuperGrokAuthConstants.authStorageKey)
    }

    private func persistAuth(tokens: SuperGrokTokenResponse) throws {
        let tokenData = SuperGrokTokenData(
            idToken: tokens.idToken,
            accessToken: tokens.accessToken,
            refreshToken: tokens.refreshToken,
            tokenType: tokens.tokenType,
            scope: tokens.scope
        )
        try persistAuth(tokens: tokenData, expiresAtEpochMs: Self.expiresAtEpochMs(from: tokens.expiresIn))
    }

    private func persistAuth(tokens: SuperGrokTokenData, expiresAtEpochMs: Int64?) throws {
        let payload = SuperGrokAuthJSON(
            tokens: tokens,
            expiresAtEpochMs: expiresAtEpochMs,
            lastRefresh: Self.nowISO8601()
        )
        try saveAuthJSON(payload)
        try credentialStore.setSuperGrokAccessToken(tokens.accessToken)
        let idInfo = tokens.idToken.flatMap { SuperGrokJWTParser.parseIDToken($0) }
        try credentialStore.saveSecret(idInfo?.email, key: "supergrok_email")
        try credentialStore.saveSecret(payload.lastRefresh, key: "supergrok_last_refresh")
    }

    private func clearOAuthTokens() throws {
        try credentialStore.setSuperGrokAccessToken(nil)
        try credentialStore.deleteSecret(key: SuperGrokAuthConstants.authStorageKey)
        try credentialStore.deleteSecret(key: "supergrok_email")
        try credentialStore.saveSecret(Self.nowISO8601(), key: "supergrok_last_refresh")
    }

    private func requestDeviceCode() async throws -> SuperGrokDeviceCodeResponse {
        let body = [
            "client_id": SuperGrokAuthConstants.clientID,
            "scope": SuperGrokAuthConstants.scope
        ]
            .map { "\($0.key)=\(Self.formURLEncode($0.value))" }
            .joined(separator: "&")

        let request = HTTPRequest(
            url: URL(string: SuperGrokAuthConstants.deviceAuthorizationURL)!,
            method: "POST",
            headers: authHeaders(),
            body: Data(body.utf8)
        )
        let (data, response) = try await httpClient.send(request)
        guard (200 ... 299).contains(response.statusCode) else {
            throw ProviderClientError.httpStatus(response.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        let decoded = try JSONDecoder().decode(SuperGrokDeviceCodeResponse.self, from: data)
        guard !decoded.deviceCode.isEmpty, !decoded.userCode.isEmpty, !decoded.verificationURI.isEmpty else {
            throw ProviderClientError.parseFailure("xAI device code response is missing required fields")
        }
        return decoded
    }

    private func pollDeviceCodeToken(device: SuperGrokDeviceCodeResponse) async throws -> SuperGrokTokenResponse {
        let expiresInMs = Self.positiveSecondsToMs(device.expiresIn, defaultMs: SuperGrokAuthConstants.deviceCodeDefaultExpiresMs)
        let deadline = Date().addingTimeInterval(TimeInterval(expiresInMs) / 1_000)
        var intervalMs = max(
            Self.positiveSecondsToMs(device.interval, defaultMs: SuperGrokAuthConstants.deviceCodeDefaultIntervalMs),
            SuperGrokAuthConstants.deviceCodeMinIntervalMs
        )

        while Date() < deadline {
            let body = [
                "grant_type": SuperGrokAuthConstants.deviceCodeGrantType,
                "client_id": SuperGrokAuthConstants.clientID,
                "device_code": device.deviceCode
            ]
                .map { "\($0.key)=\(Self.formURLEncode($0.value))" }
                .joined(separator: "&")

            let request = HTTPRequest(
                url: URL(string: SuperGrokAuthConstants.tokenURL)!,
                method: "POST",
                headers: authHeaders(),
                body: Data(body.utf8)
            )
            let (data, response) = try await httpClient.send(request)
            if (200 ... 299).contains(response.statusCode) {
                return try JSONDecoder().decode(SuperGrokTokenResponse.self, from: data)
            }

            let errorBody = (try? JSONDecoder().decode(SuperGrokDeviceTokenErrorBody.self, from: data))
            let remaining = max(0, deadline.timeIntervalSinceNow)
            switch errorBody?.error {
            case "authorization_pending":
                try await Task.sleep(nanoseconds: UInt64(min(
                    Double(intervalMs + SuperGrokAuthConstants.deviceCodePollingSafetyMarginMs) / 1_000,
                    remaining
                ) * 1_000_000_000))
                continue
            case "slow_down":
                intervalMs += SuperGrokAuthConstants.deviceCodeSlowDownIncrementMs
                try await Task.sleep(nanoseconds: UInt64(min(
                    Double(intervalMs + SuperGrokAuthConstants.deviceCodePollingSafetyMarginMs) / 1_000,
                    remaining
                ) * 1_000_000_000))
                continue
            case "access_denied", "authorization_denied":
                throw ProviderClientError.parseFailure("xAI device authorization was denied")
            case "expired_token":
                throw ProviderClientError.parseFailure("xAI device code expired - please re-run login")
            default:
                let detail = errorBody?.errorDescription ?? errorBody?.error ?? ""
                throw ProviderClientError.httpStatus(response.statusCode, detail)
            }
        }
        throw ProviderClientError.parseFailure("xAI device authorization timed out")
    }

    private func exchangeCodeForTokens(
        code: String,
        redirectURI: String,
        codeVerifier: String
    ) async throws -> SuperGrokTokenResponse {
        let body = [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectURI,
            "client_id": SuperGrokAuthConstants.clientID,
            "code_verifier": codeVerifier
        ]
            .map { "\($0.key)=\(Self.formURLEncode($0.value))" }
            .joined(separator: "&")

        let request = HTTPRequest(
            url: URL(string: SuperGrokAuthConstants.tokenURL)!,
            method: "POST",
            headers: authHeaders(),
            body: Data(body.utf8)
        )
        let (data, response) = try await httpClient.send(request)
        guard (200 ... 299).contains(response.statusCode) else {
            throw ProviderClientError.httpStatus(response.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        return try JSONDecoder().decode(SuperGrokTokenResponse.self, from: data)
    }

    private func refreshAccessToken(refreshToken: String) async throws -> SuperGrokTokenResponse {
        let body = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": SuperGrokAuthConstants.clientID
        ]
            .map { "\($0.key)=\(Self.formURLEncode($0.value))" }
            .joined(separator: "&")

        let request = HTTPRequest(
            url: URL(string: SuperGrokAuthConstants.tokenURL)!,
            method: "POST",
            headers: authHeaders(),
            body: Data(body.utf8)
        )
        let (data, response) = try await httpClient.send(request)
        guard (200 ... 299).contains(response.statusCode) else {
            let bodyText = String(data: data, encoding: .utf8) ?? ""
            if response.statusCode == 401 || response.statusCode == 400 {
                throw SuperGrokAuthRefreshError.classified(from: bodyText)
            }
            throw ProviderClientError.httpStatus(response.statusCode, bodyText)
        }
        return try JSONDecoder().decode(SuperGrokTokenResponse.self, from: data)
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

    private func authHeaders() -> [String: String] {
        [
            "Content-Type": "application/x-www-form-urlencoded",
            "Accept": "application/json",
            "User-Agent": buildUserAgent()
        ]
    }

    private func buildUserAgent() -> String {
        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        return "YamabikoChat/iOS \(appVersion)"
    }

    private static func readState(credentialStore: SecureCredentialStore) -> SuperGrokAuthState {
        let token = try? credentialStore.superGrokAccessToken()
        let email = try? credentialStore.readSecret(key: "supergrok_email")
        let lastRefresh = try? credentialStore.readSecret(key: "supergrok_last_refresh")
        return SuperGrokAuthState(
            isLoggedIn: !(token ?? "").isEmpty,
            email: email,
            lastRefreshISO8601: lastRefresh,
            pendingDeviceCode: nil
        )
    }

    private static func expiresAtEpochMs(from expiresIn: Int?) -> Int64? {
        guard let expiresIn, expiresIn > 0 else { return nil }
        return Int64(Date().timeIntervalSince1970 * 1_000) + Int64(expiresIn) * 1_000
    }

    private static func positiveSecondsToMs(_ value: Int?, defaultMs: Int64) -> Int64 {
        guard let value, value > 0 else { return defaultMs }
        return Int64(value) * 1_000
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
}

enum SuperGrokAuthCallbackError: LocalizedError {
    case portInUse
    case portMismatch(expected: UInt16, actual: UInt16)

    var errorDescription: String? {
        switch self {
        case .portInUse:
            return L10n.text("SuperGrok OAuth のコールバックポート 56121 が使用中です。OpenCode や他の Grok クライアントを終了してから再試行してください。")
        case let .portMismatch(expected, actual):
            return L10n.text("SuperGrok OAuth はポート \(expected) が必要ですが \(actual) にバインドされました。再試行してください。")
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
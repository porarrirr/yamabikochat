import Foundation
import Combine
import CryptoKit
import Security
import UIKit

final class QwenAuthRepository {
    private enum Constants {
        static let oauthBaseURL = "https://chat.qwen.ai"
        static let deviceCodeEndpoint = "https://chat.qwen.ai/api/v1/oauth2/device/code"
        static let tokenEndpoint = "https://chat.qwen.ai/api/v1/oauth2/token"
        static let clientID = "f0304373b74a44d2b584a3fb70ca9e56"
        static let scope = "openid profile email model.completion"
        static let deviceGrantType = "urn:ietf:params:oauth:grant-type:device_code"
        static let refreshBufferMs: Int64 = 30_000
        static let initialPollIntervalMs: UInt64 = 5_000
        static let maxPollIntervalMs: UInt64 = 15_000
        static let storageKey = "qwen_auth_json_v1"
    }

    private struct DeviceAuthorizationResponse: Decodable {
        var deviceCode: String
        var userCode: String
        var verificationURI: String
        var verificationURIComplete: String
        var expiresIn: Int

        enum CodingKeys: String, CodingKey {
            case deviceCode = "device_code"
            case userCode = "user_code"
            case verificationURI = "verification_uri"
            case verificationURIComplete = "verification_uri_complete"
            case expiresIn = "expires_in"
        }
    }

    private struct TokenResponse: Decodable {
        var accessToken: String?
        var refreshToken: String?
        var tokenType: String?
        var expiresIn: Int?
        var scope: String?
        var resourceURL: String?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case tokenType = "token_type"
            case expiresIn = "expires_in"
            case scope
            case resourceURL = "resource_url"
        }
    }

    private struct OAuthErrorResponse: Decodable {
        var error: String?
        var errorDescription: String?

        enum CodingKeys: String, CodingKey {
            case error
            case errorDescription = "error_description"
        }
    }

    private enum DeviceTokenPollResult {
        case pending
        case slowDown
        case success(TokenResponse)
    }

    private let credentialStore: SecureCredentialStore
    private let httpClient: HTTPClientProtocol
    private let subject: CurrentValueSubject<QwenAuthState, Never>

    init(
        credentialStore: SecureCredentialStore,
        httpClient: HTTPClientProtocol = URLSessionHTTPClient()
    ) {
        self.credentialStore = credentialStore
        self.httpClient = httpClient
        subject = CurrentValueSubject(Self.readState(credentialStore: credentialStore))
    }

    var state: AnyPublisher<QwenAuthState, Never> {
        subject.eraseToAnyPublisher()
    }

    func currentState() -> QwenAuthState {
        subject.value
    }

    func login(
        accessToken: String,
        refreshToken: String?,
        expiryDate: Int64?,
        tokenType: String? = "Bearer",
        scope: String? = nil,
        resourceURL: String? = nil
    ) async -> Result<QwenAuthState, Error> {
        do {
            let payload = QwenAuthJSON(
                accessToken: accessToken.nilIfBlank,
                refreshToken: refreshToken.nilIfBlank,
                tokenType: tokenType.nilIfBlank ?? "Bearer",
                scope: scope.nilIfBlank,
                resourceURL: resourceURL.nilIfBlank,
                expiryDate: expiryDate,
                lastRefresh: Self.nowISO8601()
            )
            try persistAuth(payload)
            let updated = Self.readState(credentialStore: credentialStore)
            subject.send(updated)
            return .success(updated)
        } catch {
            return .failure(error)
        }
    }

    func loginWithBrowser() async -> Result<QwenAuthState, Error> {
        do {
            let pkce = try Self.generatePKCE()
            DiagnosticsLogger.log("Qwen auth login start", category: .auth)

            let deviceAuth = try await requestDeviceAuthorization(codeChallenge: pkce.challenge)
            guard let verificationURL = URL(string: deviceAuth.verificationURIComplete) else {
                throw ProviderClientError.invalidBaseURL(deviceAuth.verificationURIComplete)
            }

            let backgroundTask = await MainActor.run {
                UIApplication.shared.beginBackgroundTask(withName: "QwenAuthFlow")
            }
            defer {
                Task { @MainActor in
                    if backgroundTask != .invalid {
                        UIApplication.shared.endBackgroundTask(backgroundTask)
                    }
                }
            }

            try await launchBrowser(verificationURL)
            DiagnosticsLogger.log(
                "Qwen auth browser launched userCode=\(deviceAuth.userCode)",
                category: .auth
            )

            let token = try await pollForToken(
                deviceCode: deviceAuth.deviceCode,
                codeVerifier: pkce.verifier,
                timeoutSeconds: deviceAuth.expiresIn
            )

            let payload = QwenAuthJSON(
                accessToken: token.accessToken?.nilIfBlank,
                refreshToken: token.refreshToken?.nilIfBlank,
                tokenType: token.tokenType?.nilIfBlank ?? "Bearer",
                scope: token.scope?.nilIfBlank,
                resourceURL: token.resourceURL?.nilIfBlank,
                expiryDate: Self.expiryDate(fromExpiresIn: token.expiresIn),
                lastRefresh: Self.nowISO8601()
            )
            try persistAuth(payload)

            let updated = Self.readState(credentialStore: credentialStore)
            subject.send(updated)
            DiagnosticsLogger.log("Qwen auth login completed", category: .auth)
            return .success(updated)
        } catch {
            DiagnosticsLogger.log("Qwen auth login failed", category: .auth, error: error)
            return .failure(error)
        }
    }

    func logout() async -> Result<QwenAuthState, Error> {
        do {
            try credentialStore.setCredential(nil, for: .qwenCode)
            try credentialStore.setQwenResourceURL(nil)
            try credentialStore.deleteSecret(key: Constants.storageKey)
            let updated = Self.readState(credentialStore: credentialStore)
            subject.send(updated)
            return .success(updated)
        } catch {
            return .failure(error)
        }
    }

    func refreshIfNeeded(force: Bool = false) async -> Result<QwenAuthState, Error> {
        do {
            guard hasAuthToken() else {
                let updated = Self.readState(credentialStore: credentialStore)
                subject.send(updated)
                return .success(updated)
            }

            guard var auth = readAuthJSON() else {
                let updated = Self.readState(credentialStore: credentialStore)
                subject.send(updated)
                return .success(updated)
            }

            let shouldRefresh = force || auth.expiryDate.map { Self.nowEpochMs() >= ($0 - Constants.refreshBufferMs) } ?? false
            if shouldRefresh {
                guard let refreshToken = auth.refreshToken?.nilIfBlank else {
                    throw ProviderClientError.parseFailure("Qwen refresh token is missing. Please sign in again.")
                }
                let refreshed = try await refreshTokens(refreshToken: refreshToken)
                auth.accessToken = refreshed.accessToken?.nilIfBlank
                auth.refreshToken = refreshed.refreshToken?.nilIfBlank ?? refreshToken
                auth.tokenType = refreshed.tokenType?.nilIfBlank ?? auth.tokenType
                auth.scope = refreshed.scope?.nilIfBlank ?? auth.scope
                auth.resourceURL = refreshed.resourceURL?.nilIfBlank ?? auth.resourceURL
                auth.expiryDate = Self.expiryDate(fromExpiresIn: refreshed.expiresIn)
                auth.lastRefresh = Self.nowISO8601()
                try persistAuth(auth)
            }

            let updated = Self.readState(credentialStore: credentialStore)
            subject.send(updated)
            return .success(updated)
        } catch {
            return .failure(error)
        }
    }

    func hasAuthToken() -> Bool {
        if let token = try? credentialStore.credential(for: .qwenCode),
           let token,
           !token.isEmpty {
            return true
        }
        return readAuthJSON()?.accessToken?.isEmpty == false
    }

    static func normalizedBaseURL(resourceURL: String?) -> String {
        let fallback = AppConstants.defaultQwenCodeBaseURL.absoluteString
        guard let resourceURL = resourceURL?.nilIfBlank else {
            return fallback
        }

        var normalized = resourceURL.lowercased().hasPrefix("http")
            ? resourceURL
            : "https://\(resourceURL)"
        normalized = normalized.trimmingCharacters(in: .whitespacesAndNewlines)
        while normalized.hasSuffix("/") {
            normalized.removeLast()
        }
        return normalized.lowercased().hasSuffix("/v1") ? normalized : "\(normalized)/v1"
    }

    private func requestDeviceAuthorization(codeChallenge: String) async throws -> DeviceAuthorizationResponse {
        let body = [
            "client_id": Constants.clientID,
            "scope": Constants.scope,
            "code_challenge": codeChallenge,
            "code_challenge_method": "S256"
        ]
        let request = HTTPRequest(
            url: URL(string: Constants.deviceCodeEndpoint)!,
            method: "POST",
            headers: [
                "Content-Type": "application/x-www-form-urlencoded",
                "Accept": "application/json",
                "x-request-id": UUID().uuidString
            ],
            body: Data(Self.formURLEncode(body).utf8)
        )
        let (data, response) = try await httpClient.send(request)
        guard (200 ... 299).contains(response.statusCode) else {
            throw ProviderClientError.httpStatus(response.statusCode, String(data: data, encoding: .utf8) ?? "")
        }

        let decoded = try JSONDecoder().decode(DeviceAuthorizationResponse.self, from: data)
        guard !decoded.deviceCode.isEmpty, !decoded.verificationURIComplete.isEmpty else {
            throw ProviderClientError.parseFailure("Qwen device authorization response is incomplete.")
        }
        return decoded
    }

    private func pollForToken(
        deviceCode: String,
        codeVerifier: String,
        timeoutSeconds: Int
    ) async throws -> TokenResponse {
        let deadline = Date().addingTimeInterval(TimeInterval(timeoutSeconds))
        var intervalMs = Constants.initialPollIntervalMs

        while Date() < deadline {
            try await Task.sleep(nanoseconds: intervalMs * 1_000_000)
            switch try await pollDeviceToken(deviceCode: deviceCode, codeVerifier: codeVerifier) {
            case .pending:
                continue
            case .slowDown:
                intervalMs = min(intervalMs + 5_000, Constants.maxPollIntervalMs)
            case let .success(token):
                return token
            }
        }

        throw ProviderClientError.parseFailure("Qwen device authorization timed out.")
    }

    private func pollDeviceToken(
        deviceCode: String,
        codeVerifier: String
    ) async throws -> DeviceTokenPollResult {
        let body = [
            "grant_type": Constants.deviceGrantType,
            "client_id": Constants.clientID,
            "device_code": deviceCode,
            "code_verifier": codeVerifier
        ]
        let request = HTTPRequest(
            url: URL(string: Constants.tokenEndpoint)!,
            method: "POST",
            headers: [
                "Content-Type": "application/x-www-form-urlencoded",
                "Accept": "application/json"
            ],
            body: Data(Self.formURLEncode(body).utf8)
        )
        let (data, response) = try await httpClient.send(request)
        if (200 ... 299).contains(response.statusCode) {
            return .success(try JSONDecoder().decode(TokenResponse.self, from: data))
        }

        let errorPayload = try? JSONDecoder().decode(OAuthErrorResponse.self, from: data)
        if response.statusCode == 400, errorPayload?.error == "authorization_pending" {
            return .pending
        }
        if response.statusCode == 429, errorPayload?.error == "slow_down" {
            return .slowDown
        }
        throw ProviderClientError.httpStatus(
            response.statusCode,
            errorPayload?.errorDescription ?? String(data: data, encoding: .utf8) ?? ""
        )
    }

    private func refreshTokens(refreshToken: String) async throws -> TokenResponse {
        let body = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": Constants.clientID
        ]
        let request = HTTPRequest(
            url: URL(string: Constants.tokenEndpoint)!,
            method: "POST",
            headers: [
                "Content-Type": "application/x-www-form-urlencoded",
                "Accept": "application/json"
            ],
            body: Data(Self.formURLEncode(body).utf8)
        )
        let (data, response) = try await httpClient.send(request)
        guard (200 ... 299).contains(response.statusCode) else {
            throw ProviderClientError.httpStatus(response.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        return try JSONDecoder().decode(TokenResponse.self, from: data)
    }

    private func persistAuth(_ auth: QwenAuthJSON) throws {
        try saveAuthJSON(auth)
        try credentialStore.setCredential(auth.accessToken?.nilIfBlank, for: .qwenCode)
        try credentialStore.setQwenResourceURL(auth.resourceURL?.nilIfBlank)
    }

    private func readAuthJSON() -> QwenAuthJSON? {
        guard let raw = try? credentialStore.readSecret(key: Constants.storageKey),
              let value = raw,
              let data = value.data(using: .utf8)
        else {
            return nil
        }
        return try? JSONDecoder().decode(QwenAuthJSON.self, from: data)
    }

    private func saveAuthJSON(_ value: QwenAuthJSON) throws {
        let data = try JSONEncoder().encode(value)
        try credentialStore.saveSecret(String(decoding: data, as: UTF8.self), key: Constants.storageKey)
    }

    private static func readState(credentialStore: SecureCredentialStore) -> QwenAuthState {
        let storedJSON: QwenAuthJSON? = {
            guard let raw = try? credentialStore.readSecret(key: Constants.storageKey),
                  let value = raw,
                  let data = value.data(using: .utf8)
            else {
                return nil
            }
            return try? JSONDecoder().decode(QwenAuthJSON.self, from: data)
        }()
        let accessToken = (try? credentialStore.credential(for: .qwenCode)) ?? storedJSON?.accessToken
        let isLoggedIn = accessToken?.isEmpty == false
        let resourceURL = storedJSON?.resourceURL?.nilIfBlank ?? ((try? credentialStore.qwenResourceURL()) ?? nil)
        return QwenAuthState(
            isLoggedIn: isLoggedIn,
            resourceURL: resourceURL,
            baseURL: isLoggedIn ? normalizedBaseURL(resourceURL: resourceURL) : nil,
            expiresAtEpochMs: storedJSON?.expiryDate,
            lastRefreshISO8601: storedJSON?.lastRefresh
        )
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

    private static func generatePKCE() throws -> (verifier: String, challenge: String) {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            throw KeychainStoreError.unexpectedStatus(status)
        }
        let verifier = Data(bytes).base64URLEncodedString()
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncodedString()
        return (verifier, challenge)
    }

    private static func expiryDate(fromExpiresIn expiresIn: Int?) -> Int64? {
        guard let expiresIn else { return nil }
        return nowEpochMs() + Int64(expiresIn) * 1000
    }

    private static func nowEpochMs() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1000)
    }

    private static func nowISO8601() -> String {
        ISO8601DateFormatter().string(from: Date())
    }

    private static func formURLEncode(_ value: [String: String]) -> String {
        value
            .map { key, item in
                "\(key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? key)=\(item.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? item)"
            }
            .sorted()
            .joined(separator: "&")
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

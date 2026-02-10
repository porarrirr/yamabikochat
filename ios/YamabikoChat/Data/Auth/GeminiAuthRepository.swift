import Foundation
import Combine
import Security
import UIKit

struct GeminiOAuthClientConfig: Equatable, Sendable {
    var clientID: String
    var clientSecret: String
}

protocol GeminiOAuthConfigProviding {
    func loadOAuthClientConfig() -> GeminiOAuthClientConfig
}

struct BundleGeminiOAuthConfigProvider: GeminiOAuthConfigProviding {
    private let bundle: Bundle
    private let dedicatedPlistName: String

    private enum ConfigKey {
        static let clientID = "GEMINI_OAUTH_CLIENT_ID"
        static let clientSecret = "GEMINI_OAUTH_CLIENT_SECRET"
    }

    init(bundle: Bundle = .main, dedicatedPlistName: String = "GeminiAuthInfo") {
        self.bundle = bundle
        self.dedicatedPlistName = dedicatedPlistName
    }

    func loadOAuthClientConfig() -> GeminiOAuthClientConfig {
        if let fromDedicatedPlist = loadFromDedicatedPlist() {
            return fromDedicatedPlist
        }
        return loadFromInfoDictionary()
    }

    private func loadFromDedicatedPlist() -> GeminiOAuthClientConfig? {
        guard let url = bundle.url(forResource: dedicatedPlistName, withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let raw = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let dictionary = raw as? [String: Any]
        else {
            return nil
        }

        return GeminiOAuthClientConfig(
            clientID: dictionary[ConfigKey.clientID] as? String ?? "",
            clientSecret: dictionary[ConfigKey.clientSecret] as? String ?? ""
        )
    }

    private func loadFromInfoDictionary() -> GeminiOAuthClientConfig {
        GeminiOAuthClientConfig(
            clientID: bundle.object(forInfoDictionaryKey: ConfigKey.clientID) as? String ?? "",
            clientSecret: bundle.object(forInfoDictionaryKey: ConfigKey.clientSecret) as? String ?? ""
        )
    }
}

final class GeminiAuthRepository {
    struct BearerToken: Sendable, Equatable {
        var token: String
        var projectId: String?
        var userTier: String?
        var userEmail: String?
    }

    private enum Constants {
        static let authURL = "https://accounts.google.com/o/oauth2/v2/auth"
        static let tokenURL = "https://oauth2.googleapis.com/token"
        static let userInfoURL = "https://www.googleapis.com/oauth2/v2/userinfo"
        static let codeAssistEndpoint = "https://cloudcode-pa.googleapis.com"
        static let codeAssistVersion = "v1internal"
        static let defaultPort: UInt16 = 1456
        static let refreshBufferSeconds: TimeInterval = 60
        static let refreshFallbackSeconds: TimeInterval = 45 * 60
        static let storageKey = "gemini_auth_json_v2"
        static let importedOAuthClientIDKey = "gemini_oauth_client_id_imported"
        static let importedOAuthClientSecretKey = "gemini_oauth_client_secret_imported"
        static let invalidOAuthValueTokens: Set<String> = [
            "?",
            "??",
            "???",
            "__set_me__",
            "set_me",
            "todo",
            "changeme",
            "replace_me"
        ]
    }

    private let scopes = [
        "https://www.googleapis.com/auth/cloud-platform",
        "https://www.googleapis.com/auth/userinfo.email",
        "https://www.googleapis.com/auth/userinfo.profile"
    ]

    private let credentialStore: SecureCredentialStore
    private let httpClient: HTTPClientProtocol
    private let oauthConfigProvider: any GeminiOAuthConfigProviding
    private let subject: CurrentValueSubject<GeminiAuthState, Never>

    init(
        credentialStore: SecureCredentialStore,
        httpClient: HTTPClientProtocol = URLSessionHTTPClient(),
        oauthConfigProvider: any GeminiOAuthConfigProviding = BundleGeminiOAuthConfigProvider()
    ) {
        self.credentialStore = credentialStore
        self.httpClient = httpClient
        self.oauthConfigProvider = oauthConfigProvider
        subject = CurrentValueSubject(Self.readState(credentialStore: credentialStore))
    }

    var state: AnyPublisher<GeminiAuthState, Never> {
        subject.eraseToAnyPublisher()
    }

    func isOAuthClientConfigured() -> Bool {
        Self.missingOAuthClientParts(from: resolvedOAuthClientConfig()).isEmpty
    }

    static func isDefaultOAuthClientConfigured(bundle: Bundle = .main) -> Bool {
        let provider = BundleGeminiOAuthConfigProvider(bundle: bundle)
        return missingOAuthClientParts(from: provider.loadOAuthClientConfig()).isEmpty
    }

    func hasImportedOAuthClientConfig() -> Bool {
        guard let imported = readImportedOAuthClientConfig() else {
            return false
        }
        return Self.missingOAuthClientParts(from: imported).isEmpty
    }

    func importOAuthClientConfig(fileURL: URL) throws -> GeminiOAuthClientConfig {
        let data = try Data(contentsOf: fileURL)
        let raw = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        guard let dictionary = raw as? [String: Any] else {
            throw ProviderClientError.parseFailure("Selected file is not a plist dictionary.")
        }

        let imported = GeminiOAuthClientConfig(
            clientID: dictionary["GEMINI_OAUTH_CLIENT_ID"] as? String ?? "",
            clientSecret: dictionary["GEMINI_OAUTH_CLIENT_SECRET"] as? String ?? ""
        )
        let normalized = Self.normalizedOAuthClientConfig(imported)
        let missing = Self.missingOAuthClientParts(from: normalized)
        if !missing.isEmpty {
            throw ProviderClientError.parseFailure(
                "Selected file is missing Gemini OAuth \(missing.joined(separator: ", "))."
            )
        }

        try credentialStore.saveSecret(normalized.clientID, key: Constants.importedOAuthClientIDKey)
        try credentialStore.saveSecret(normalized.clientSecret, key: Constants.importedOAuthClientSecretKey)
        return normalized
    }

    func clearImportedOAuthClientConfig() throws {
        try credentialStore.deleteSecret(key: Constants.importedOAuthClientIDKey)
        try credentialStore.deleteSecret(key: Constants.importedOAuthClientSecretKey)
    }

    func currentState() -> GeminiAuthState {
        subject.value
    }

    func login(
        accessToken: String,
        projectId: String?,
        email: String?,
        userTier: String?,
        userTierName: String?
    ) async -> Result<GeminiAuthState, Error> {
        do {
            try credentialStore.setGeminiAccessToken(accessToken.isEmpty ? nil : accessToken)
            try credentialStore.saveSecret(projectId, key: "gemini_project_id")
            try credentialStore.saveSecret(email, key: "gemini_email")
            try credentialStore.saveSecret(userTier, key: "gemini_user_tier")
            try credentialStore.saveSecret(userTierName, key: "gemini_user_tier_name")
            try credentialStore.saveSecret(Self.nowISO8601(), key: "gemini_last_refresh")

            let payload = GeminiAuthJSON(
                tokens: GeminiTokenData(accessToken: accessToken),
                lastRefresh: Self.nowISO8601(),
                accessExpiresAt: nil,
                userEmail: email,
                projectId: projectId,
                userTier: userTier,
                userTierName: userTierName
            )
            try saveAuthJSON(payload)

            let updated = Self.readState(credentialStore: credentialStore)
            subject.send(updated)
            return .success(updated)
        } catch {
            return .failure(error)
        }
    }

    func loginWithBrowser() async -> Result<GeminiAuthState, Error> {
        do {
            let oauthConfig = Self.normalizedOAuthClientConfig(
                resolvedOAuthClientConfig()
            )
            let missingOAuthParts = Self.missingOAuthClientParts(from: oauthConfig)
            if !missingOAuthParts.isEmpty {
                DiagnosticsLogger.log(
                    "Gemini auth oauth client config missing parts=\(missingOAuthParts.joined(separator: ","))",
                    level: .error,
                    category: .auth
                )
                throw ProviderClientError.missingCredential("GEMINI_OAUTH_CLIENT")
            }
            let stateToken = Self.generateState()
            DiagnosticsLogger.log("Gemini auth login start", category: .auth)
            let callbackServer = LocalAuthCallbackServer(
                expectedPath: "/oauth2callback",
                preferredPort: Constants.defaultPort
            )
            let port = try callbackServer.bind()
            let redirectURI = "http://127.0.0.1:\(port)/oauth2callback"
            DiagnosticsLogger.log("Gemini auth callback server bound port=\(port)", category: .auth)

            let authURL = try buildAuthorizeURL(
                clientID: oauthConfig.clientID,
                redirectURI: redirectURI,
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
                UIApplication.shared.beginBackgroundTask(withName: "GeminiAuthFlow")
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
                    "Gemini auth listener readiness timed out, continuing browser launch",
                    level: .warning,
                    category: .auth,
                    error: error
                )
            }

            try await launchBrowser(authURL)
            DiagnosticsLogger.log("Gemini auth browser launched", category: .auth)

            let callback = try await callbackTask.value
            let query = callback.queryItems.reduce(into: [String: String]()) { partialResult, item in
                partialResult[item.name] = item.value ?? ""
            }
            let oauthError = query["error"] ?? ""
            if !oauthError.isEmpty {
                let desc = query["error_description"] ?? oauthError
                DiagnosticsLogger.log(
                    "Gemini auth callback returned oauth error=\(desc)",
                    level: .warning,
                    category: .auth
                )
                throw LocalAuthCallbackError.invalidCallback(desc)
            }
            guard query["state"] == stateToken, let code = query["code"], !code.isEmpty else {
                DiagnosticsLogger.log(
                    "Gemini auth callback validation failed hasCode=\(!(query["code"] ?? "").isEmpty)",
                    level: .warning,
                    category: .auth
                )
                throw LocalAuthCallbackError.invalidCallback("Invalid callback state or code.")
            }
            DiagnosticsLogger.log("Gemini auth callback received, exchanging tokens", category: .auth)

            var auth = try await exchangeCodeForTokens(
                code: code,
                redirectURI: redirectURI,
                clientID: oauthConfig.clientID,
                clientSecret: oauthConfig.clientSecret
            )
            guard let accessToken = auth.tokens?.accessToken, !accessToken.isEmpty else {
                throw ProviderClientError.missingCredential("GEMINI_AUTH")
            }

            let email = try await fetchUserEmail(accessToken: accessToken)
            let userData = try await resolveUserData(accessToken: accessToken, projectOverride: auth.projectId)
            auth.projectId = userData.projectId
            auth.userTier = userData.userTier
            auth.userTierName = userData.userTierName
            auth.userEmail = email ?? auth.userEmail

            try persistAuth(auth)

            let updated = Self.readState(credentialStore: credentialStore)
            subject.send(updated)
            DiagnosticsLogger.log("Gemini auth login completed projectId=\(updated.projectId ?? "-")", category: .auth)
            return .success(updated)
        } catch {
            DiagnosticsLogger.log("Gemini auth login failed", category: .auth, error: error)
            return .failure(error)
        }
    }

    func logout() async -> Result<GeminiAuthState, Error> {
        do {
            try credentialStore.setGeminiAccessToken(nil)
            try credentialStore.deleteSecret(key: "gemini_project_id")
            try credentialStore.deleteSecret(key: "gemini_email")
            try credentialStore.deleteSecret(key: "gemini_user_tier")
            try credentialStore.deleteSecret(key: "gemini_user_tier_name")
            try credentialStore.deleteSecret(key: "gemini_last_refresh")
            try credentialStore.deleteSecret(key: Constants.storageKey)
            let updated = Self.readState(credentialStore: credentialStore)
            subject.send(updated)
            return .success(updated)
        } catch {
            return .failure(error)
        }
    }

    func refreshIfNeeded(force: Bool = false) async -> Result<GeminiAuthState, Error> {
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

            let now = Date()
            let expiresAtDate = auth.accessExpiresAt.flatMap { ISO8601DateFormatter().date(from: $0) }
            let shouldRefresh: Bool
            if force {
                shouldRefresh = true
            } else if let expiresAtDate {
                shouldRefresh = now >= expiresAtDate.addingTimeInterval(-Constants.refreshBufferSeconds)
            } else if let lastRefresh = auth.lastRefresh.flatMap({ ISO8601DateFormatter().date(from: $0) }) {
                shouldRefresh = now.timeIntervalSince(lastRefresh) >= Constants.refreshFallbackSeconds
            } else {
                shouldRefresh = true
            }

            if shouldRefresh, let refreshToken = tokens.refreshToken, !refreshToken.isEmpty {
                let oauthConfig = Self.normalizedOAuthClientConfig(
                    resolvedOAuthClientConfig()
                )
                let missingOAuthParts = Self.missingOAuthClientParts(from: oauthConfig)
                if !missingOAuthParts.isEmpty {
                    DiagnosticsLogger.log(
                        "Gemini auth refresh blocked because oauth config is missing parts=\(missingOAuthParts.joined(separator: ","))",
                        level: .warning,
                        category: .auth
                    )
                    throw ProviderClientError.missingCredential("GEMINI_OAUTH_CLIENT")
                }
                let refreshed = try await refreshTokens(
                    refreshToken: refreshToken,
                    clientID: oauthConfig.clientID,
                    clientSecret: oauthConfig.clientSecret
                )
                tokens.accessToken = refreshed.accessToken.isEmpty ? tokens.accessToken : refreshed.accessToken
                tokens.refreshToken = refreshed.refreshToken ?? tokens.refreshToken
                tokens.idToken = refreshed.idToken ?? tokens.idToken
                tokens.expiresIn = refreshed.expiresIn ?? tokens.expiresIn
                tokens.scope = refreshed.scope ?? tokens.scope
                tokens.tokenType = refreshed.tokenType ?? tokens.tokenType
                auth.tokens = tokens
                auth.lastRefresh = Self.nowISO8601()
                if let expiresIn = tokens.expiresIn {
                    auth.accessExpiresAt = ISO8601DateFormatter().string(from: Date().addingTimeInterval(TimeInterval(expiresIn)))
                }
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
        let token = try? credentialStore.geminiAccessToken()
        if let token, !token.isEmpty { return true }
        return readAuthJSON()?.tokens?.accessToken.isEmpty == false
    }

    func saveProjectId(_ projectId: String?) -> Bool {
        do {
            try credentialStore.saveSecret(projectId?.nilIfBlank, key: "gemini_project_id")
            if var auth = readAuthJSON() {
                auth.projectId = projectId?.nilIfBlank
                try persistAuth(auth)
            }
            subject.send(Self.readState(credentialStore: credentialStore))
            return true
        } catch {
            return false
        }
    }

    func getAccessToken() async -> String? {
        _ = await refreshIfNeeded()
        return try? credentialStore.geminiAccessToken()
    }

    func getBearerToken() async -> BearerToken? {
        guard let token = await getAccessToken(), !token.isEmpty else { return nil }

        let projectId = try? credentialStore.readSecret(key: "gemini_project_id")
        let tier = try? credentialStore.readSecret(key: "gemini_user_tier")
        let email = try? credentialStore.readSecret(key: "gemini_email")

        return BearerToken(
            token: token,
            projectId: projectId,
            userTier: tier,
            userEmail: email
        )
    }

    func retrieveUserQuota() async -> Result<GeminiUserQuota, Error> {
        do {
            guard let bearer = await getBearerToken() else {
                return .failure(ProviderClientError.missingCredential("GEMINI_AUTH"))
            }
            guard let projectID = bearer.projectId, !projectID.isEmpty else {
                return .failure(ProviderClientError.parseFailure("Project ID is required"))
            }

            let payload: [String: Any] = ["project": projectID]
            let body = try JSONSerialization.data(withJSONObject: payload)
            let request = HTTPRequest(
                url: URL(string: "\(Constants.codeAssistEndpoint)/\(Constants.codeAssistVersion):retrieveUserQuota")!,
                method: "POST",
                headers: [
                    "Authorization": "Bearer \(bearer.token)",
                    "Content-Type": "application/json"
                ],
                body: body
            )

            let (data, response) = try await httpClient.send(request)
            guard (200 ... 299).contains(response.statusCode) else {
                throw ProviderClientError.httpStatus(response.statusCode, String(data: data, encoding: .utf8) ?? "")
            }

            let parsed = try Self.parseQuota(data: data)
            return .success(parsed)
        } catch {
            return .failure(error)
        }
    }

    private func readAuthJSON() -> GeminiAuthJSON? {
        guard let raw = try? credentialStore.readSecret(key: Constants.storageKey),
              let data = raw.data(using: .utf8)
        else {
            return nil
        }
        return try? JSONDecoder().decode(GeminiAuthJSON.self, from: data)
    }

    private func saveAuthJSON(_ value: GeminiAuthJSON) throws {
        let data = try JSONEncoder().encode(value)
        try credentialStore.saveSecret(String(decoding: data, as: UTF8.self), key: Constants.storageKey)
    }

    private func persistAuth(_ auth: GeminiAuthJSON) throws {
        try saveAuthJSON(auth)
        try credentialStore.setGeminiAccessToken(auth.tokens?.accessToken)
        try credentialStore.saveSecret(auth.projectId, key: "gemini_project_id")
        try credentialStore.saveSecret(auth.userEmail, key: "gemini_email")
        try credentialStore.saveSecret(auth.userTier, key: "gemini_user_tier")
        try credentialStore.saveSecret(auth.userTierName, key: "gemini_user_tier_name")
        try credentialStore.saveSecret(auth.lastRefresh, key: "gemini_last_refresh")
    }

    private func buildAuthorizeURL(clientID: String, redirectURI: String, state: String) throws -> URL {
        var components = URLComponents(string: Constants.authURL)
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "scope", value: scopes.joined(separator: " ")),
            URLQueryItem(name: "state", value: state)
        ]
        guard let url = components?.url else {
            throw ProviderClientError.invalidBaseURL(Constants.authURL)
        }
        return url
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
        clientID: String,
        clientSecret: String
    ) async throws -> GeminiAuthJSON {
        let form = [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectURI,
            "client_id": clientID,
            "client_secret": clientSecret
        ]
            .map { "\($0.key)=\(Self.formURLEncode($0.value))" }
            .joined(separator: "&")

        let request = HTTPRequest(
            url: URL(string: Constants.tokenURL)!,
            method: "POST",
            headers: ["Content-Type": "application/x-www-form-urlencoded"],
            body: Data(form.utf8)
        )
        let (data, response) = try await httpClient.send(request)
        guard (200 ... 299).contains(response.statusCode) else {
            throw ProviderClientError.httpStatus(response.statusCode, String(data: data, encoding: .utf8) ?? "")
        }

        let tokenData = try JSONDecoder().decode(GeminiTokenData.self, from: data)
        let expiresAt = tokenData.expiresIn.map { ISO8601DateFormatter().string(from: Date().addingTimeInterval(TimeInterval($0))) }
        return GeminiAuthJSON(
            tokens: tokenData,
            lastRefresh: Self.nowISO8601(),
            accessExpiresAt: expiresAt,
            userEmail: nil,
            projectId: nil,
            userTier: nil,
            userTierName: nil
        )
    }

    private func refreshTokens(
        refreshToken: String,
        clientID: String,
        clientSecret: String
    ) async throws -> GeminiTokenData {
        let form = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": clientID,
            "client_secret": clientSecret
        ]
            .map { "\($0.key)=\(Self.formURLEncode($0.value))" }
            .joined(separator: "&")

        let request = HTTPRequest(
            url: URL(string: Constants.tokenURL)!,
            method: "POST",
            headers: ["Content-Type": "application/x-www-form-urlencoded"],
            body: Data(form.utf8)
        )
        let (data, response) = try await httpClient.send(request)
        guard (200 ... 299).contains(response.statusCode) else {
            throw ProviderClientError.httpStatus(response.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        return try JSONDecoder().decode(GeminiTokenData.self, from: data)
    }

    private func fetchUserEmail(accessToken: String) async throws -> String? {
        let request = HTTPRequest(
            url: URL(string: Constants.userInfoURL)!,
            method: "GET",
            headers: ["Authorization": "Bearer \(accessToken)"]
        )
        let (data, response) = try await httpClient.send(request)
        guard (200 ... 299).contains(response.statusCode) else { return nil }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return root["email"] as? String
    }

    private func resolveUserData(accessToken: String, projectOverride: String?) async throws -> (projectId: String, userTier: String, userTierName: String?) {
        let metadata: [String: Any?] = [
            "ideType": "IDE_UNSPECIFIED",
            "platform": "PLATFORM_UNSPECIFIED",
            "pluginType": "GEMINI",
            "duetProject": projectOverride
        ]
        var loadRequest: [String: Any] = [
            "metadata": metadata.compactMapValues { $0 }
        ]
        if let projectOverride, !projectOverride.isEmpty {
            loadRequest["cloudaicompanionProject"] = projectOverride
        }
        let loadResponse = try await postCodeAssist(
            path: ":loadCodeAssist",
            accessToken: accessToken,
            payload: loadRequest
        )

        let currentTier = (loadResponse["currentTier"] as? [String: Any])
        if let currentTier {
            let projectID = (loadResponse["cloudaicompanionProject"] as? String) ?? projectOverride
            guard let projectID, !projectID.isEmpty else {
                throw ProviderClientError.parseFailure("Google Workspace account requires a Cloud project ID.")
            }
            return (
                projectId: projectID,
                userTier: (currentTier["id"] as? String) ?? "legacy-tier",
                userTierName: currentTier["name"] as? String
            )
        }

        let allowedTiers = (loadResponse["allowedTiers"] as? [[String: Any]]) ?? []
        let defaultTier = allowedTiers.first(where: { ($0["isDefault"] as? Bool) == true }) ?? ["id": "legacy-tier"]
        let tierID = (defaultTier["id"] as? String) ?? "legacy-tier"
        let isFreeTier = tierID == "free-tier"
        let projectForOnboard = isFreeTier ? nil : projectOverride
        if !isFreeTier && (projectForOnboard?.isEmpty ?? true) {
            throw ProviderClientError.parseFailure("Google Workspace account requires a Cloud project ID.")
        }

        var onboardRequest: [String: Any] = [
            "tierId": tierID,
            "metadata": metadata.compactMapValues { $0 }
        ]
        if let projectForOnboard, !projectForOnboard.isEmpty {
            onboardRequest["cloudaicompanionProject"] = projectForOnboard
        }
        let operation = try await postCodeAssist(
            path: ":onboardUser",
            accessToken: accessToken,
            payload: onboardRequest
        )

        var finalOperation = operation
        if (operation["done"] as? Bool) != true, let name = operation["name"] as? String, !name.isEmpty {
            finalOperation = try await pollOperation(accessToken: accessToken, name: name)
        }

        let response = finalOperation["response"] as? [String: Any]
        let projectBlock = response?["cloudaicompanionProject"] as? [String: Any]
        let projectID = (projectBlock?["id"] as? String) ?? projectForOnboard
        guard let projectID, !projectID.isEmpty else {
            throw ProviderClientError.parseFailure("Failed to obtain Cloud project ID for Gemini Auth.")
        }

        return (
            projectId: projectID,
            userTier: tierID,
            userTierName: defaultTier["name"] as? String
        )
    }

    private func pollOperation(accessToken: String, name: String) async throws -> [String: Any] {
        var current = try await getCodeAssistOperation(accessToken: accessToken, name: name)
        var attempts = 0
        while (current["done"] as? Bool) != true && attempts < 6 {
            attempts += 1
            try await Task.sleep(nanoseconds: 5_000_000_000)
            current = try await getCodeAssistOperation(accessToken: accessToken, name: name)
        }
        return current
    }

    private func postCodeAssist(path: String, accessToken: String, payload: [String: Any]) async throws -> [String: Any] {
        let data = try JSONSerialization.data(withJSONObject: payload)
        let request = HTTPRequest(
            url: URL(string: "\(Constants.codeAssistEndpoint)/\(Constants.codeAssistVersion)\(path)")!,
            method: "POST",
            headers: [
                "Authorization": "Bearer \(accessToken)",
                "Content-Type": "application/json"
            ],
            body: data
        )
        let (responseData, response) = try await httpClient.send(request)
        guard (200 ... 299).contains(response.statusCode) else {
            throw ProviderClientError.httpStatus(response.statusCode, String(data: responseData, encoding: .utf8) ?? "")
        }
        guard let root = try JSONSerialization.jsonObject(with: responseData) as? [String: Any] else {
            throw ProviderClientError.parseFailure("Invalid Gemini auth response")
        }
        return root
    }

    private func getCodeAssistOperation(accessToken: String, name: String) async throws -> [String: Any] {
        let request = HTTPRequest(
            url: URL(string: "\(Constants.codeAssistEndpoint)/\(Constants.codeAssistVersion)/\(name)")!,
            method: "GET",
            headers: [
                "Authorization": "Bearer \(accessToken)",
                "Content-Type": "application/json"
            ]
        )
        let (data, response) = try await httpClient.send(request)
        guard (200 ... 299).contains(response.statusCode) else {
            throw ProviderClientError.httpStatus(response.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProviderClientError.parseFailure("Invalid operation response")
        }
        return root
    }

    private func resolvedOAuthClientConfig() -> GeminiOAuthClientConfig {
        if let imported = readImportedOAuthClientConfig() {
            return imported
        }
        return oauthConfigProvider.loadOAuthClientConfig()
    }

    private func readImportedOAuthClientConfig() -> GeminiOAuthClientConfig? {
        guard let clientID = try? credentialStore.readSecret(key: Constants.importedOAuthClientIDKey),
              let clientSecret = try? credentialStore.readSecret(key: Constants.importedOAuthClientSecretKey)
        else {
            return nil
        }

        let normalized = Self.normalizedOAuthClientConfig(
            GeminiOAuthClientConfig(clientID: clientID, clientSecret: clientSecret)
        )
        if Self.missingOAuthClientParts(from: normalized).isEmpty {
            return normalized
        }
        return nil
    }

    private static func readState(credentialStore: SecureCredentialStore) -> GeminiAuthState {
        let token = try? credentialStore.geminiAccessToken()
        let email = try? credentialStore.readSecret(key: "gemini_email")
        let projectID = try? credentialStore.readSecret(key: "gemini_project_id")
        let tier = try? credentialStore.readSecret(key: "gemini_user_tier")
        let tierName = try? credentialStore.readSecret(key: "gemini_user_tier_name")
        let last = try? credentialStore.readSecret(key: "gemini_last_refresh")

        return GeminiAuthState(
            isLoggedIn: !(token ?? "").isEmpty,
            email: email,
            projectId: projectID,
            userTier: tier,
            userTierName: tierName,
            hasAccessToken: !(token ?? "").isEmpty,
            lastRefreshISO8601: last
        )
    }

    private static func parseQuota(data: Data) throws -> GeminiUserQuota {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProviderClientError.parseFailure("Invalid quota response")
        }

        let bucketsRaw = root["buckets"] as? [[String: Any]] ?? []
        let buckets = bucketsRaw.map { bucket in
            let remainingAmount: String?
            if let raw = bucket["remainingAmount"] as? String {
                remainingAmount = raw
            } else if let raw = bucket["remainingAmount"] as? NSNumber {
                remainingAmount = raw.stringValue
            } else {
                remainingAmount = nil
            }

            return GeminiQuotaBucket(
                modelId: bucket["modelId"] as? String,
                tokenType: bucket["tokenType"] as? String,
                remainingAmount: remainingAmount,
                remainingFraction: parseDouble(bucket["remainingFraction"]),
                resetTime: bucket["resetTime"] as? String
            )
        }
        return GeminiUserQuota(buckets: buckets)
    }

    private static func parseDouble(_ value: Any?) -> Double? {
        if let number = value as? NSNumber {
            return number.doubleValue
        }
        if let text = value as? String {
            return Double(text)
        }
        return nil
    }

    private static func nowISO8601() -> String {
        ISO8601DateFormatter().string(from: Date())
    }

    private static func generateState() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let count = bytes.count
        bytes.withUnsafeMutableBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }
            _ = SecRandomCopyBytes(kSecRandomDefault, count, baseAddress)
        }
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func formURLEncode(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private static func missingOAuthClientParts(from config: GeminiOAuthClientConfig) -> [String] {
        var missing: [String] = []
        let normalized = normalizedOAuthClientConfig(config)
        let normalizedClientID = normalized.clientID
        let normalizedClientSecret = normalized.clientSecret
        if isInvalidOAuthConfigValue(normalizedClientID) {
            missing.append("client_id")
        }
        if isInvalidOAuthConfigValue(normalizedClientSecret) {
            missing.append("client_secret")
        }
        return missing
    }

    private static func normalizeOAuthConfigValue(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizedOAuthClientConfig(_ config: GeminiOAuthClientConfig) -> GeminiOAuthClientConfig {
        GeminiOAuthClientConfig(
            clientID: normalizeOAuthConfigValue(config.clientID),
            clientSecret: normalizeOAuthConfigValue(config.clientSecret)
        )
    }

    private static func isInvalidOAuthConfigValue(_ value: String) -> Bool {
        if value.isEmpty { return true }
        let normalized = value.lowercased()
        if Constants.invalidOAuthValueTokens.contains(normalized) {
            return true
        }
        if normalized.contains("set_me") || normalized.contains("changeme") {
            return true
        }
        return false
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

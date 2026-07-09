import Foundation

struct SuperGrokAuthJSON: Codable, Equatable, Sendable {
    var tokens: SuperGrokTokenData?
    var expiresAtEpochMs: Int64?
    var lastRefresh: String?

    enum CodingKeys: String, CodingKey {
        case tokens
        case expiresAtEpochMs = "expires_at_epoch_ms"
        case lastRefresh = "last_refresh"
    }
}

struct SuperGrokTokenData: Codable, Equatable, Sendable {
    var idToken: String?
    var accessToken: String
    var refreshToken: String
    var tokenType: String?
    var scope: String?

    enum CodingKeys: String, CodingKey {
        case idToken = "id_token"
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case tokenType = "token_type"
        case scope
    }
}

struct SuperGrokIDTokenInfo: Equatable, Sendable {
    var email: String?
}

enum SuperGrokJWTParser {
    static func parseIDToken(_ rawJWT: String) -> SuperGrokIDTokenInfo? {
        guard let payload = parsePayload(rawJWT) else { return nil }
        return SuperGrokIDTokenInfo(email: payload["email"] as? String)
    }

    static func accessTokenIsExpiring(_ token: String?, skewMs: Int64 = SuperGrokAuthConstants.accessTokenRefreshSkewMs) -> Bool {
        guard let token, !token.isEmpty else { return false }
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return false }

        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 {
            payload += "="
        }
        guard let decoded = Data(base64Encoded: payload),
              let object = try? JSONSerialization.jsonObject(with: decoded) as? [String: Any],
              let exp = jwtExpSeconds(object)
        else {
            return false
        }
        let expiresAtMs = exp * 1_000
        return expiresAtMs <= Int64(Date().timeIntervalSince1970 * 1_000) + max(0, skewMs)
    }

    /// JSONSerialization may surface JWT `exp` as Int, Double, or NSNumber depending on magnitude/path.
    private static func jwtExpSeconds(_ object: [String: Any]) -> Int64? {
        switch object["exp"] {
        case let value as Int:
            return Int64(value)
        case let value as Int64:
            return value
        case let value as Double:
            return Int64(value)
        case let value as NSNumber:
            return value.int64Value
        case let value as String:
            return Int64(value.trimmingCharacters(in: .whitespacesAndNewlines))
        default:
            return nil
        }
    }

    private static func parsePayload(_ rawJWT: String) -> [String: Any]? {
        let parts = rawJWT.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var payload = String(parts[1])
        while payload.count % 4 != 0 {
            payload += "="
        }
        let normalized = payload
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        guard let decoded = Data(base64Encoded: normalized),
              let object = try? JSONSerialization.jsonObject(with: decoded) as? [String: Any]
        else {
            return nil
        }
        return object
    }
}

enum SuperGrokAuthConstants {
    static let clientID = "b1a00492-073a-47ea-816f-4c329264a828"
    static let authorizeURL = "https://auth.x.ai/oauth2/authorize"
    static let tokenURL = "https://auth.x.ai/oauth2/token"
    static let deviceAuthorizationURL = "https://auth.x.ai/oauth2/device/code"
    static let deviceCodeGrantType = "urn:ietf:params:oauth:grant-type:device_code"
    static let scope = "openid profile email offline_access grok-cli:access api:access"
    static let oauthHost = "127.0.0.1"
    static let oauthPort: UInt16 = 56_121
    static let oauthRedirectPath = "/callback"
    static let redirectURI = "http://\(oauthHost):\(oauthPort)\(oauthRedirectPath)"
    static let authStorageKey = "supergrok_auth_json_v1"
    static let accessTokenRefreshSkewMs: Int64 = 120_000
    static let deviceCodeDefaultIntervalMs: Int64 = 5_000
    static let deviceCodeMinIntervalMs: Int64 = 1_000
    static let deviceCodeSlowDownIncrementMs: Int64 = 5_000
    static let deviceCodeDefaultExpiresMs: Int64 = 5 * 60 * 1_000
    static let deviceCodePollingSafetyMarginMs: Int64 = 3_000
}

enum SuperGrokAuthRefreshError: LocalizedError, Equatable, Sendable {
    case expired
    case reused
    case invalidated
    case missingRefreshToken
    case unknown

    var isUnrecoverable: Bool {
        switch self {
        case .expired, .reused, .invalidated:
            return true
        case .missingRefreshToken, .unknown:
            return false
        }
    }

    var errorDescription: String? {
        switch self {
        case .expired:
            return L10n.text("SuperGrokのリフレッシュトークンの有効期限が切れました。ログアウトして再度サインインしてください。")
        case .reused:
            return L10n.text("SuperGrokのリフレッシュトークンは既に使用済みです。ログアウトして再度サインインしてください。")
        case .invalidated:
            return L10n.text("SuperGrokのリフレッシュトークンは無効化されました。ログアウトして再度サインインしてください。")
        case .missingRefreshToken:
            return L10n.text("SuperGrokのリフレッシュトークンがありません。再度サインインしてください。")
        case .unknown:
            return L10n.text("SuperGrokのアクセストークンを更新できませんでした。ログアウトして再度サインインしてください。")
        }
    }

    static func classified(from body: String) -> SuperGrokAuthRefreshError {
        switch extractErrorCode(from: body)?.lowercased() {
        case "invalid_grant", "refresh_token_expired":
            return .expired
        case "refresh_token_reused":
            return .reused
        case "refresh_token_invalidated":
            return .invalidated
        default:
            return .unknown
        }
    }

    static func extractErrorCode(from body: String) -> String? {
        guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let data = body.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }

        if let error = object["error"] as? String {
            return error.trimmedNonEmpty
        }
        return (object["code"] as? String)?.trimmedNonEmpty
    }
}

struct SuperGrokDeviceCodeChallenge: Equatable, Sendable {
    var verificationURI: String
    var userCode: String
    var browserURL: String
}

struct SuperGrokAuthState: Equatable, Sendable {
    var isLoggedIn: Bool = false
    var email: String? = nil
    var lastRefreshISO8601: String? = nil
    var pendingDeviceCode: SuperGrokDeviceCodeChallenge? = nil
}

struct SuperGrokDeviceCodeResponse: Decodable, Equatable, Sendable {
    var deviceCode: String
    var userCode: String
    var verificationURI: String
    var verificationURIComplete: String?
    var expiresIn: Int?
    var interval: Int?

    enum CodingKeys: String, CodingKey {
        case deviceCode = "device_code"
        case userCode = "user_code"
        case verificationURI = "verification_uri"
        case verificationURIComplete = "verification_uri_complete"
        case expiresIn = "expires_in"
        case interval
    }
}

struct SuperGrokTokenResponse: Decodable, Equatable, Sendable {
    var accessToken: String
    var refreshToken: String
    var idToken: String?
    var tokenType: String?
    var expiresIn: Int?
    var scope: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case idToken = "id_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
        case scope
    }
}

struct SuperGrokDeviceTokenErrorBody: Decodable, Equatable, Sendable {
    var error: String?
    var errorDescription: String?

    enum CodingKeys: String, CodingKey {
        case error
        case errorDescription = "error_description"
    }
}
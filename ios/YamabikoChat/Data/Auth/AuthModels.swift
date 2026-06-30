import Foundation

struct CodexAuthJSON: Codable, Equatable, Sendable {
    var openAIAPIKey: String?
    var tokens: CodexTokenData?
    var lastRefresh: String?

    enum CodingKeys: String, CodingKey {
        case openAIAPIKey = "OPENAI_API_KEY"
        case tokens
        case lastRefresh = "last_refresh"
    }
}

struct CodexTokenData: Codable, Equatable, Sendable {
    var idToken: String
    var accessToken: String
    var refreshToken: String
    var accountId: String?

    enum CodingKeys: String, CodingKey {
        case idToken = "id_token"
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case accountId = "account_id"
    }
}

struct CodexIDTokenInfo: Equatable, Sendable {
    var email: String?
    var planType: String?
    var accountId: String?
}

enum CodexJWTParser {
    static func parseIDToken(_ rawJWT: String) -> CodexIDTokenInfo? {
        guard let payload = parsePayload(rawJWT) else { return nil }
        let email = payload["email"] as? String
        let auth = payload["https://api.openai.com/auth"] as? [String: Any]
        return CodexIDTokenInfo(
            email: email,
            planType: auth?["chatgpt_plan_type"] as? String,
            accountId: auth?["chatgpt_account_id"] as? String
        )
    }

    static func extractAccountID(_ rawJWT: String) -> String? {
        guard let payload = parsePayload(rawJWT),
              let auth = payload["https://api.openai.com/auth"] as? [String: Any]
        else {
            return nil
        }
        return auth["chatgpt_account_id"] as? String
    }

    private static func parsePayload(_ rawJWT: String) -> [String: Any]? {
        let parts = rawJWT.split(separator: ".")
        guard parts.count >= 3 else { return nil }
        let payload = String(parts[1])
        let paddedPayload = payload + String(repeating: "=", count: (4 - payload.count % 4) % 4)
        let normalized = paddedPayload
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

enum CodexAuthRefreshError: LocalizedError, Equatable, Sendable {
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
            return L10n.text("Codexのリフレッシュトークンの有効期限が切れました。ログアウトして再度サインインしてください。")
        case .reused:
            return L10n.text("Codexのリフレッシュトークンは既に使用済みです。ログアウトして再度サインインしてください。")
        case .invalidated:
            return L10n.text("Codexのリフレッシュトークンは無効化されました。ログアウトして再度サインインしてください。")
        case .missingRefreshToken:
            return L10n.text("Codexのリフレッシュトークンがありません。ブラウザで再度サインインしてください。")
        case .unknown:
            return L10n.text("Codexのアクセストークンを更新できませんでした。ログアウトして再度サインインしてください。")
        }
    }

    static func classified(from body: String) -> CodexAuthRefreshError {
        switch extractErrorCode(from: body)?.lowercased() {
        case "refresh_token_expired":
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
        guard body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
              let data = body.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }

        switch object["error"] {
        case let nested as [String: Any]:
            return (nested["code"] as? String)?.trimmedNonEmpty
        case let code as String:
            return code.trimmedNonEmpty
        default:
            return (object["code"] as? String)?.trimmedNonEmpty
        }
    }
}

struct CodexAuthState: Equatable, Sendable {
    var isLoggedIn: Bool = false
    var email: String? = nil
    var planType: String? = nil
    var accountId: String? = nil
    var hasApiKey: Bool = false
    var lastRefreshISO8601: String? = nil
}

struct CodexRateLimitWindow: Equatable, Sendable {
    var usedPercent: Double?
    var limitWindowSeconds: Int?
    var resetAtEpochSeconds: Int64?
}

struct CodexCreditsStatus: Equatable, Sendable {
    var hasCredits: Bool
    var unlimited: Bool
    var balance: String?
}

struct CodexUsageStatus: Equatable, Sendable {
    var planType: String?
    var primaryWindow: CodexRateLimitWindow?
    var secondaryWindow: CodexRateLimitWindow?
    var credits: CodexCreditsStatus?
}


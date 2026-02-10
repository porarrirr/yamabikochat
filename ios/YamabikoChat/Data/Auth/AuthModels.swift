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

struct GeminiAuthJSON: Codable, Equatable, Sendable {
    var tokens: GeminiTokenData?
    var lastRefresh: String?
    var accessExpiresAt: String?
    var userEmail: String?
    var projectId: String?
    var userTier: String?
    var userTierName: String?

    enum CodingKeys: String, CodingKey {
        case tokens
        case lastRefresh = "last_refresh"
        case accessExpiresAt = "access_expires_at"
        case userEmail = "user_email"
        case projectId = "project_id"
        case userTier = "user_tier"
        case userTierName = "user_tier_name"
    }
}

struct GeminiTokenData: Codable, Equatable, Sendable {
    var accessToken: String
    var refreshToken: String?
    var idToken: String?
    var expiresIn: Int?
    var scope: String?
    var tokenType: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case idToken = "id_token"
        case expiresIn = "expires_in"
        case scope
        case tokenType = "token_type"
    }
}

struct GeminiAuthState: Equatable, Sendable {
    var isLoggedIn: Bool = false
    var email: String? = nil
    var projectId: String? = nil
    var userTier: String? = nil
    var userTierName: String? = nil
    var hasAccessToken: Bool = false
    var lastRefreshISO8601: String? = nil
}

struct GeminiQuotaBucket: Equatable, Sendable, Identifiable {
    var id: String { "\(modelId ?? "unknown")_\(tokenType ?? "unknown")" }
    var modelId: String?
    var tokenType: String?
    var remainingAmount: String?
    var remainingFraction: Double?
    var resetTime: String?
}

struct GeminiUserQuota: Equatable, Sendable {
    var buckets: [GeminiQuotaBucket]
}

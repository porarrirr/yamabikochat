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

    func displayRows(limit: Int? = nil) -> [GeminiQuotaDisplayRow] {
        var grouped: [String: GeminiQuotaDisplayRow] = [:]
        var order: [String] = []

        for bucket in buckets {
            guard let modelID = bucket.modelId?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !modelID.isEmpty
            else {
                continue
            }

            let candidate = GeminiQuotaDisplayRow(
                modelId: modelID,
                detail: Self.detailText(for: bucket),
                resetTime: bucket.resetTime,
                remainingFraction: bucket.remainingFraction
            )

            if grouped[modelID] == nil {
                grouped[modelID] = candidate
                order.append(modelID)
                continue
            }

            if candidate.isPreferred(over: grouped[modelID]!) {
                grouped[modelID] = candidate
            }
        }

        let rows = order.compactMap { grouped[$0] }
        guard let limit else { return rows }
        return Array(rows.prefix(limit))
    }

    private static func detailText(for bucket: GeminiQuotaBucket) -> String {
        let remainingAmount = normalizedRemainingAmount(bucket.remainingAmount)
        if let remainingFraction = bucket.remainingFraction {
            let usedPercentage = max(0, min(100, (1 - remainingFraction) * 100))
            let usedText = "\(Int(usedPercentage.rounded()))% used"
            if let remainingAmount {
                return "\(usedText) (\(remainingAmount) remaining)"
            }
            return usedText
        }
        return remainingAmount ?? "-"
    }

    private static func normalizedRemainingAmount(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty
        else {
            return nil
        }
        return value
    }
}

struct GeminiQuotaDisplayRow: Equatable, Sendable, Identifiable {
    var id: String { modelId }
    var modelId: String
    var detail: String
    var resetTime: String?

    fileprivate var remainingFraction: Double?

    init(
        modelId: String,
        detail: String,
        resetTime: String?,
        remainingFraction: Double? = nil
    ) {
        self.modelId = modelId
        self.detail = detail
        self.resetTime = resetTime
        self.remainingFraction = remainingFraction
    }

    fileprivate func isPreferred(over other: GeminiQuotaDisplayRow) -> Bool {
        switch (remainingFraction, other.remainingFraction) {
        case let (lhs?, rhs?):
            return lhs < rhs
        case (.some, .none):
            return true
        case (.none, .some):
            return false
        case (.none, .none):
            return detail != "-" && other.detail == "-"
        }
    }
}

struct QwenAuthJSON: Codable, Equatable, Sendable {
    var accessToken: String?
    var refreshToken: String?
    var tokenType: String?
    var scope: String?
    var resourceURL: String?
    var expiryDate: Int64?
    var lastRefresh: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case tokenType = "token_type"
        case scope
        case resourceURL = "resource_url"
        case expiryDate = "expiry_date"
        case lastRefresh = "last_refresh"
    }
}

struct QwenAuthState: Equatable, Sendable {
    var isLoggedIn: Bool = false
    var resourceURL: String? = nil
    var baseURL: String? = nil
    var expiresAtEpochMs: Int64? = nil
    var lastRefreshISO8601: String? = nil
}

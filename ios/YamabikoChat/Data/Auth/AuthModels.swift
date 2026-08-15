import Foundation

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

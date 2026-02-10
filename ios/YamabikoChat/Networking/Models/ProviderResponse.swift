import Foundation

struct ProviderUsage: Codable, Sendable, Equatable {
    var inputTokens: Int?
    var outputTokens: Int?
    var reasoningTokens: Int?
}

struct ProviderResponse: Codable, Sendable, Equatable {
    var text: String
    var reasoningSummary: String?
    var raw: String?
    var usage: ProviderUsage?
}

enum ProviderStreamEvent: Sendable, Equatable {
    case textDelta(String)
    case reasoningDelta(String)
    case toolCallDelta(String)
    case completed(ProviderResponse)
}

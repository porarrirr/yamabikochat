import Foundation

enum AppConstants {
    static let appGroupIdentifier = "group.com.porarri.yamabikochat"
    static let sharePayloadDefaultsKey = "share_payload"
    static let sharePayloadDidChangeNotification = Notification.Name("YamabikoSharePayloadDidChange")
    static let alibabaMCPAuthorizationTokenKey = "alibaba_mcp_authorization_token"
    static let alibabaMCPDefaultServerName = "firecrawl"
    static let firecrawlRemoteMCPURLTemplate = "https://mcp.firecrawl.dev/fc-YOUR_API_KEY/v2/mcp"

    static let maxAttachmentSizeBytes: Int = 10 * 1024 * 1024

    static let defaultOpenAIBaseURL = URL(string: "https://api.openai.com/v1/")!
    static let defaultAlibabaCodingPlanBaseURL = URL(string: "https://coding-intl.dashscope.aliyuncs.com/apps/anthropic/")!
    static let defaultMiniMaxBaseURL = URL(string: "https://api.minimax.io/v1/")!
}

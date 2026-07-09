import Foundation

enum AppConstants {
    static let appGroupIdentifier = "group.com.porarri.yamabikochat"
    static let sharePayloadDidChangeNotification = Notification.Name("YamabikoSharePayloadDidChange")
    static let sharePayloadDarwinNotification = "com.porarri.yamabikochat.share_payload.changed"
    static let importShareURL = URL(string: "yamabikochat://import-share")!
    static let alibabaMCPAuthorizationTokenKey = "alibaba_mcp_authorization_token"
    static let alibabaMCPDefaultServerName = "firecrawl"
    static let firecrawlRemoteMCPURLTemplate = "https://mcp.firecrawl.dev/fc-YOUR_API_KEY/v2/mcp"

    static let maxAttachmentSizeBytes: Int = 10 * 1024 * 1024

    static let defaultOpenAIBaseURL = URL(string: "https://api.openai.com/v1/")!
    static let defaultOpenCodeGoBaseURL = URL(string: "https://opencode.ai/zen/go/v1/")!
    static let defaultClinePassBaseURL = URL(string: "https://api.cline.bot/api/v1/")!
    static let defaultAlibabaCodingPlanBaseURL = URL(string: "https://coding-intl.dashscope.aliyuncs.com/apps/anthropic/")!
    static let defaultMiniMaxBaseURL = URL(string: "https://api.minimax.io/v1/")!
    static let defaultSuperGrokBaseURL = URL(string: "https://api.x.ai/v1/")!

    /// GitHub Pages (`docs/`). Enable Pages on the repo before App Store submission.
    static let marketingURL = URL(string: "https://porarrirr.github.io/yamabikochat/")!
    static let privacyPolicyURL = URL(string: "https://porarrirr.github.io/yamabikochat/privacy.html")!
    static let supportURL = URL(string: "https://porarrirr.github.io/yamabikochat/support.html")!
    static let termsOfUseURL = URL(string: "https://porarrirr.github.io/yamabikochat/terms.html")!
}

import Foundation

enum AppConstants {
    static let appGroupIdentifier = "group.com.porarri.yamabikochat"
    static let sharePayloadDefaultsKey = "share_payload"
    static let sharePayloadDidChangeNotification = Notification.Name("YamabikoSharePayloadDidChange")

    static let maxAttachmentSizeBytes: Int = 10 * 1024 * 1024

    static let defaultOpenAIBaseURL = URL(string: "https://api.openai.com/v1/")!
    static let defaultAlibabaCodingPlanBaseURL = URL(string: "https://coding-intl.dashscope.aliyuncs.com/v1/")!
    static let defaultMiniMaxBaseURL = URL(string: "https://api.minimax.io/v1/")!
}

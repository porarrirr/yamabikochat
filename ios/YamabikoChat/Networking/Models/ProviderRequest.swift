import Foundation

struct ProviderTool: Codable, Sendable, Equatable {
    var type: String
    var payload: [String: String]
}

struct ProviderThinkingConfig: Codable, Sendable, Equatable {
    var enabled: Bool?
    var budget: Int?
    var effort: String?
    var includeThoughts: Bool?
    var exclude: Bool?
}

struct ProviderMaxPriceConfig: Codable, Sendable, Equatable {
    var prompt: Double?
    var completion: Double?
    var request: Double?
    var image: Double?
    var audio: Double?
}

struct ProviderRoutingConfig: Codable, Sendable, Equatable {
    var order: [String]?
    var allowFallbacks: Bool?
    var requireParameters: Bool?
    var dataCollection: String?
    var quantizations: [String]?
    var maxPrice: ProviderMaxPriceConfig?
    var only: [String]?
    var ignore: [String]?
    var sort: String?

    enum CodingKeys: String, CodingKey {
        case order
        case allowFallbacks = "allow_fallbacks"
        case requireParameters = "require_parameters"
        case dataCollection = "data_collection"
        case quantizations
        case maxPrice = "max_price"
        case only
        case ignore
        case sort
    }
}

struct ProviderRequestMessage: Codable, Sendable, Equatable, Identifiable {
    let id = UUID()
    var role: String
    var content: String
    var attachments: [String]
    var reasoningContent: String?
    var toolCalls: [ToolCall]?
    var toolCallId: String?
    var toolName: String?
    var toolResultIsError: Bool?

    init(
        role: String,
        content: String,
        attachments: [String] = [],
        reasoningContent: String? = nil,
        toolCalls: [ToolCall]? = nil,
        toolCallId: String? = nil,
        toolName: String? = nil,
        toolResultIsError: Bool? = nil
    ) {
        self.role = role
        self.content = content
        self.attachments = attachments
        self.reasoningContent = reasoningContent
        self.toolCalls = toolCalls
        self.toolCallId = toolCallId
        self.toolName = toolName
        self.toolResultIsError = toolResultIsError
    }
}

struct ProviderRequest: Codable, Sendable, Equatable {
    var model: String
    var messages: [ProviderRequestMessage]
    var systemPrompt: String?
    var stream: Bool
    var tools: [ProviderTool]
    var thinking: ProviderThinkingConfig?
    var provider: ProviderRoutingConfig?
    var metadata: [String: String]
    var timeoutInterval: TimeInterval?
    /// Ephemeral user-priority Agent Skill context. Never persisted to chat storage.
    var skillContext: SkillRequestContext?

    init(
        model: String,
        messages: [ProviderRequestMessage],
        systemPrompt: String? = nil,
        stream: Bool = true,
        tools: [ProviderTool] = [],
        thinking: ProviderThinkingConfig? = nil,
        provider: ProviderRoutingConfig? = nil,
        metadata: [String: String] = [:],
        timeoutInterval: TimeInterval? = nil,
        skillContext: SkillRequestContext? = nil
    ) {
        self.model = model
        self.messages = messages
        self.systemPrompt = systemPrompt
        self.stream = stream
        self.tools = tools
        self.thinking = thinking
        self.provider = provider
        self.metadata = metadata
        self.timeoutInterval = timeoutInterval
        self.skillContext = skillContext
    }
}

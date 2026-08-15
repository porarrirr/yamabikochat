import Foundation

struct OpenAICompatibleWireFunctionCall: Encodable {
    var name: String
    var arguments: String
}

struct OpenAICompatibleWireToolCall: Encodable {
    var id: String
    var type: String = "function"
    var function: OpenAICompatibleWireFunctionCall
}

/// Canonical message representation for every OpenAI-compatible endpoint.
/// Keeping this mapping in one place prevents provider clients from silently
/// dropping tool calls, tool results, or reasoning when replaying history.
struct OpenAICompatibleWireMessage: Encodable {
    var role: String
    var content: ProviderAttachmentEncoder.OpenAIMessageContent?
    var toolCalls: [OpenAICompatibleWireToolCall]?
    var toolCallId: String?
    var name: String?
    var reasoningContent: String?

    enum CodingKeys: String, CodingKey {
        case role
        case content
        case toolCalls = "tool_calls"
        case toolCallId = "tool_call_id"
        case name
        case reasoningContent = "reasoning_content"
    }
}

enum OpenAICompatibleWireMapper {
    static func messages(
        _ messages: [ProviderRequestMessage],
        systemPrompt: String?,
        embedImages: Bool,
        cacheBreakpointIndex: Int? = nil,
        providerLabel: String = "OpenAI compatible"
    ) -> [OpenAICompatibleWireMessage] {
        var mapped: [OpenAICompatibleWireMessage] = []
        if let systemPrompt = systemPrompt?.trimmedNonEmpty {
            mapped.append(
                OpenAICompatibleWireMessage(
                    role: "system",
                    content: .plain(systemPrompt)
                )
            )
        }

        for (index, message) in messages.enumerated() {
            let role = message.role.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if role == "tool" {
                mapped.append(
                    OpenAICompatibleWireMessage(
                        role: "tool",
                        content: .plain(message.content),
                        toolCalls: nil,
                        toolCallId: message.toolCallId,
                        name: message.toolName,
                        reasoningContent: nil
                    )
                )
                continue
            }

            ProviderAttachmentEncoder.logSkippedAttachmentsIfNeeded(
                message.attachments,
                providerLabel: providerLabel,
                embedImages: embedImages
            )
            let toolCalls = message.toolCalls?.map {
                OpenAICompatibleWireToolCall(
                    id: $0.id,
                    function: OpenAICompatibleWireFunctionCall(
                        name: $0.name,
                        arguments: $0.argumentsJSON
                    )
                )
            }
            mapped.append(
                OpenAICompatibleWireMessage(
                    role: role,
                    content: ProviderAttachmentEncoder.buildOpenAIMessageContent(
                        text: message.content,
                        attachments: message.attachments,
                        embedImages: embedImages,
                        cacheControl: index == cacheBreakpointIndex
                    ),
                    toolCalls: toolCalls?.isEmpty == true ? nil : toolCalls,
                    toolCallId: nil,
                    name: nil,
                    reasoningContent: role == "assistant" ? message.reasoningContent?.trimmedNonEmpty : nil
                )
            )
        }
        return mapped
    }
}

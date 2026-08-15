import Foundation

struct AnthropicCompatibleWireMessage: Encodable {
    var role: String
    var content: [AnyEncodable]
}

enum AnthropicCompatibleWireMapper {
    static func messages(
        _ messages: [ProviderRequestMessage],
        embedImages: Bool,
        providerLabel: String
    ) -> [AnthropicCompatibleWireMessage] {
        messages.map { message in
            let rawRole = message.role.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if rawRole == "tool" {
                var result: [String: AnyEncodable] = [
                    "type": AnyEncodable("tool_result"),
                    "tool_use_id": AnyEncodable(message.toolCallId ?? ""),
                    "content": AnyEncodable(message.content)
                ]
                if let isError = message.toolResultIsError {
                    result["is_error"] = AnyEncodable(isError)
                }
                return AnthropicCompatibleWireMessage(role: "user", content: [AnyEncodable(result)])
            }

            ProviderAttachmentEncoder.logSkippedAttachmentsIfNeeded(
                message.attachments,
                providerLabel: providerLabel,
                embedImages: embedImages
            )
            let role = rawRole == "assistant" ? "assistant" : "user"
            var blocks: [AnyEncodable] = []
            if !message.content.isEmpty || !message.attachments.isEmpty {
                blocks = ProviderAttachmentEncoder.buildAnthropicContentBlocks(
                    text: message.content,
                    attachments: message.attachments,
                    embedImages: embedImages
                ).map(AnyEncodable.init)
            }
            if role == "assistant" {
                for call in message.toolCalls ?? [] {
                    let input = jsonValue(from: call.argumentsJSON) ?? .object([:])
                    blocks.append(AnyEncodable([
                        "type": AnyEncodable("tool_use"),
                        "id": AnyEncodable(call.id),
                        "name": AnyEncodable(call.name),
                        "input": AnyEncodable(input)
                    ]))
                }
            }
            if blocks.isEmpty {
                blocks.append(AnyEncodable(ProviderAttachmentEncoder.AnthropicContentBlock.textBlock("")))
            }
            return AnthropicCompatibleWireMessage(role: role, content: blocks)
        }
    }

    static func tools(_ tools: [ProviderTool]) -> [AnyEncodable]? {
        let mapped = tools.compactMap { tool -> AnyEncodable? in
            guard tool.type == "function",
                  let name = tool.payload["name"]?.trimmedNonEmpty,
                  let parameters = tool.payload["parameters"].flatMap(jsonValue(from:)) else { return nil }
            var definition: [String: AnyEncodable] = [
                "name": AnyEncodable(name),
                "input_schema": AnyEncodable(parameters)
            ]
            if let description = tool.payload["description"]?.trimmedNonEmpty {
                definition["description"] = AnyEncodable(description)
            }
            return AnyEncodable(definition)
        }
        return mapped.isEmpty ? nil : mapped
    }

    private static func jsonValue(from raw: String) -> JSONValue? {
        guard let data = raw.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(JSONValue.self, from: data)
    }
}

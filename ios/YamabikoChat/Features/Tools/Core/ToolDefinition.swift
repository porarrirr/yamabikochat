import Foundation

enum JSONValue: Codable, Sendable, Equatable {
    case object([String: JSONValue])
    case array([JSONValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .object(value):
            try container.encode(value)
        case let .array(value):
            try container.encode(value)
        case let .string(value):
            try container.encode(value)
        case let .number(value):
            try container.encode(value)
        case let .bool(value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }
}

struct ToolDefinition: Codable, Sendable, Equatable {
    var name: String
    var description: String
    var parametersJSON: String

    var providerTool: ProviderTool {
        ProviderTool(
            type: "function",
            payload: [
                "name": name,
                "description": description,
                "parameters": parametersJSON
            ]
        )
    }
}

struct ToolCall: Codable, Sendable, Equatable, Identifiable {
    var id: String
    var name: String
    var argumentsJSON: String
    var providerMetadata: [String: String]?
}

struct ToolResult: Codable, Sendable, Equatable {
    var callId: String
    var name: String
    var content: String
    var isError: Bool
    var sources: [ToolSource]

    init(
        callId: String,
        name: String,
        content: String,
        isError: Bool = false,
        sources: [ToolSource] = []
    ) {
        self.callId = callId
        self.name = name
        self.content = content
        self.isError = isError
        self.sources = sources
    }
}

extension Collection where Element == ProviderTool {
    var containsWebSearchTool: Bool {
        contains {
            $0.type == "function" && $0.payload["name"] == WebSearchTool.name
        }
    }
}

struct ToolSource: Codable, Sendable, Equatable, Identifiable {
    var title: String
    var url: String

    var id: String { url }
}

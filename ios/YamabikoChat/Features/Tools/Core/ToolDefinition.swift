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

struct ToolSource: Codable, Sendable, Equatable, Identifiable {
    var title: String
    var url: String

    var id: String { url }
}

struct ToolCallDelta: Sendable, Equatable {
    var index: Int
    var id: String?
    var name: String?
    var argumentsFragment: String
    var providerMetadata: [String: String]?

    init(
        index: Int,
        id: String? = nil,
        name: String? = nil,
        argumentsFragment: String = "",
        providerMetadata: [String: String]? = nil
    ) {
        self.index = index
        self.id = id
        self.name = name
        self.argumentsFragment = argumentsFragment
        self.providerMetadata = providerMetadata
    }
}

struct ToolCallAccumulator: Sendable {
    private struct PartialCall: Sendable {
        var id = ""
        var name = ""
        var argumentsJSON = ""
        var providerMetadata: [String: String]?
    }

    private var partials: [Int: PartialCall] = [:]

    mutating func append(_ delta: ToolCallDelta) {
        var partial = partials[delta.index] ?? PartialCall()
        if let id = delta.id, !id.isEmpty {
            partial.id += StreamDeltaAccumulator.incrementalDelta(buffer: partial.id, incoming: id)
        }
        if let name = delta.name, !name.isEmpty {
            partial.name += StreamDeltaAccumulator.incrementalDelta(buffer: partial.name, incoming: name)
        }
        if !delta.argumentsFragment.isEmpty {
            partial.argumentsJSON += StreamDeltaAccumulator.incrementalDelta(
                buffer: partial.argumentsJSON,
                incoming: delta.argumentsFragment
            )
        }
        if let metadata = delta.providerMetadata {
            partial.providerMetadata = (partial.providerMetadata ?? [:]).merging(metadata) { _, new in new }
        }
        partials[delta.index] = partial
    }

    var toolCalls: [ToolCall] {
        partials.keys.sorted().compactMap { index in
            guard let partial = partials[index],
                  let name = partial.name.trimmedNonEmpty
            else {
                return nil
            }
            let id = partial.id.trimmedNonEmpty ?? "tool-call-\(index)"
            return ToolCall(
                id: id,
                name: name,
                argumentsJSON: partial.argumentsJSON.trimmedNonEmpty ?? "{}",
                providerMetadata: partial.providerMetadata
            )
        }
    }
}

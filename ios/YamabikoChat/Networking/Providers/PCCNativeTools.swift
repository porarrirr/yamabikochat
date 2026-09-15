import Foundation
import FoundationModels

/// User-authorized PCC exception: Apple owns the tool loop; tools use the app's
/// existing executors. Pi still resolves the model and stores the native history.
@available(iOS 27.0, *)
struct PCCNativeTool: Tool {
    typealias Arguments = GeneratedContent
    typealias Output = Prompt

    let name: String
    let description: String
    let parameters: GenerationSchema
    let execute: @Sendable (ToolCall) async throws -> ToolResult

    init(definition: PCCNativeRequest.ToolDefinition,
         execute: @escaping @Sendable (ToolCall) async throws -> ToolResult) throws {
        name = definition.name
        description = definition.description
        parameters = try PCCNativeToolSchema.make(definition.parameters, name: definition.name)
        self.execute = execute
    }

    func call(arguments: GeneratedContent) async throws -> Prompt {
        try Task.checkCancellation()
        guard arguments.isComplete else { throw PCCFailure(code: "pcc_tool_arguments_incomplete") }
        let call = ToolCall(id: UUID().uuidString, name: name, argumentsJSON: arguments.jsonString)
        let result = try await execute(call)
        try Task.checkCancellation()
        // Tool errors are returned to the model so it can explain or correct the
        // call. Cancellation and transport errors throw and stop the session.
        var parts = [Prompt(result.content)]
        for image in try PiAgentRuntime.toolResultImages(from: result.artifacts) {
            let segments = try PCCSDK.segments(.array([.object([
                "type": .string("image"), "data": .string(image.data), "mimeType": .string(image.mimeType)
            ])]), allowImages: true)
            parts.append(contentsOf: try PCCSDK.prompts(segments))
        }
        return Prompt(parts)
    }
}

/// Converts the JSON Schema subset used by the app's local tools using public
/// SDK constructors. Unsupported constraints fail rather than being discarded.
@available(iOS 27.0, *)
enum PCCNativeToolSchema {
    static func make(_ value: JSONValue, name: String) throws -> GenerationSchema {
        try GenerationSchema(root: node(value, name: name), dependencies: [])
    }

    private static func node(_ value: JSONValue, name: String) throws -> DynamicGenerationSchema {
        guard case .object(let fields) = value, case .string(let type) = fields["type"] else {
            throw PCCFailure(code: "pcc_tool_schema_unsupported")
        }
        let common: Set<String> = ["type", "description", "default", "title"]
        let permitted: Set<String>
        switch type {
        case "object": permitted = ["properties", "required", "additionalProperties"]
        case "array": permitted = ["items", "minItems", "maxItems"]
        case "string": permitted = ["enum"]
        case "integer", "number": permitted = ["minimum", "maximum"]
        case "boolean": permitted = []
        default: throw PCCFailure(code: "pcc_tool_schema_unsupported")
        }
        guard Set(fields.keys).isSubset(of: common.union(permitted)) else {
            throw PCCFailure(code: "pcc_tool_schema_unsupported")
        }
        func string(_ field: String) -> String? {
            if case .string(let value) = fields[field] { return value }
            return nil
        }
        func number(_ field: String) throws -> Double? {
            guard let value = fields[field] else { return nil }
            guard case .number(let result) = value, result.isFinite else {
                throw PCCFailure(code: "pcc_tool_schema_unsupported")
            }
            return result
        }
        func integer(_ field: String) throws -> Int? {
            guard let value = try number(field) else { return nil }
            guard let result = Int(exactly: value) else { throw PCCFailure(code: "pcc_tool_schema_unsupported") }
            return result
        }
        switch type {
        case "object":
            guard case .object(let properties) = fields["properties"] ?? .object([:]),
                  fields["additionalProperties"] == nil || fields["additionalProperties"] == .bool(false),
                  case .array(let requiredValues) = fields["required"] ?? .array([]) else {
                throw PCCFailure(code: "pcc_tool_schema_unsupported")
            }
            let required = try Set(requiredValues.map { value -> String in
                guard case .string(let key) = value, properties[key] != nil else {
                    throw PCCFailure(code: "pcc_tool_schema_unsupported")
                }
                return key
            })
            return .init(name: name, description: string("description"), properties: try properties.keys.sorted().map { key in
                let property = properties[key]!
                var description: String?
                if case .object(let values) = property, case .string(let text) = values["description"] { description = text }
                return .init(name: key, description: description,
                             schema: try node(property, name: name + "_" + key), isOptional: !required.contains(key))
            })
        case "array":
            guard let items = fields["items"] else { throw PCCFailure(code: "pcc_tool_schema_unsupported") }
            return .init(arrayOf: try node(items, name: name + "_item"),
                         minimumElements: try integer("minItems"), maximumElements: try integer("maxItems"))
        case "string":
            if let choices = fields["enum"] {
                guard case .array(let values) = choices, !values.isEmpty else { throw PCCFailure(code: "pcc_tool_schema_unsupported") }
                let strings = try values.map { value -> String in
                    guard case .string(let text) = value else { throw PCCFailure(code: "pcc_tool_schema_unsupported") }
                    return text
                }
                return .init(type: String.self, guides: [.anyOf(strings)])
            }
            return .init(type: String.self)
        case "integer":
            var guides: [GenerationGuide<Int>] = []
            if let minimum = try integer("minimum") { guides.append(.minimum(minimum)) }
            if let maximum = try integer("maximum") { guides.append(.maximum(maximum)) }
            return .init(type: Int.self, guides: guides)
        case "number":
            var guides: [GenerationGuide<Double>] = []
            if let minimum = try number("minimum") { guides.append(.minimum(minimum)) }
            if let maximum = try number("maximum") { guides.append(.maximum(maximum)) }
            return .init(type: Double.self, guides: guides)
        default: return .init(type: Bool.self)
        }
    }
}

/// A run-scoped queue preserves Python namespace/editor ordering even when the
/// SDK calls several tools concurrently. Cancellation reaches queued/running work.
actor PCCLocalToolRunner {
    private var tail: Task<Void, Never>?

    func run(_ operation: @escaping @Sendable () async throws -> ToolResult) async throws -> ToolResult {
        let previous = tail
        let task = Task {
            await previous?.value
            try Task.checkCancellation()
            return try await operation()
        }
        tail = Task { _ = try? await task.value }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }
}

import Foundation

/// Read-only access to the actual recovered template contract on the existing local tool path.
struct GenUIReferenceTool: LocalToolExecutor {
    static let name = "genui_reference"
    static let definition = ToolDefinition(
        name: name,
        description: "Read the original GenUI component source and observed state field names before composing a GenUI with a canonical component. Supply componentName (or * to list names). The source is the actual recovered template, including local calculations and interactions. Populate __state with verified supplied data matching that source. Server actions require the reference backend and cannot execute here. sourceOffset and maxCharacters page long sources.",
        parametersJSON: #"{"type":"object","properties":{"componentName":{"type":"string"},"sourceOffset":{"type":"integer","minimum":0},"maxCharacters":{"type":"integer","minimum":1,"maximum":65536}},"required":["componentName"],"additionalProperties":false}"#
    )
    var definition: ToolDefinition { Self.definition }

    func execute(call: ToolCall) async throws -> ToolResult {
        struct Arguments: Decodable {
            let componentName: String
            let sourceOffset: Int?
            let maxCharacters: Int?
        }
        let arguments = try JSONDecoder().decode(Arguments.self, from: Data(call.argumentsJSON.utf8))
        let content: [String: Any]
        if arguments.componentName == "*" {
            content = ["componentNames": GenUIReferenceCatalog.components.keys.sorted()]
        } else {
            let name = arguments.componentName
            guard let properties = GenUIReferenceCatalog.components[name],
                  let source = Self.source(named: name) else {
                throw GenUIError.invalid("unknown reference component: \(name)")
            }
            let characters = Array(source)
            let offset = arguments.sourceOffset ?? 0
            let limit = arguments.maxCharacters ?? 65_536
            guard offset >= 0, offset <= characters.count, limit > 0, limit <= 65_536 else {
                throw GenUIError.invalid("invalid source page")
            }
            let end = min(offset + limit, characters.count)
            content = ["componentName": name, "properties": properties,
                       "stateFields": GenUIReferenceCatalog.stateFields[name] ?? [],
                       "source": String(characters[offset..<end]), "sourceOffset": offset,
                       "sourceLength": characters.count, "nextOffset": end < characters.count ? end as Any : NSNull()]
        }
        let data = try JSONSerialization.data(withJSONObject: content, options: [.sortedKeys])
        return ToolResult(callId: call.id, name: Self.name, content: String(decoding: data, as: UTF8.self))
    }

    private static let factorySource: String? = {
        let url = Bundle.main.url(forResource: "reference-components", withExtension: "js", subdirectory: "genui")
            ?? Bundle.main.url(forResource: "reference-components", withExtension: "js")
        return url.flatMap { try? String(contentsOf: $0, encoding: .utf8) }
    }()

    static func source(named name: String) -> String? {
        guard let source = factorySource else { return nil }
        let names = GenUIReferenceCatalog.components.keys.sorted()
        guard let index = names.firstIndex(of: name) else { return nil }
        func marker(_ name: String) -> String {
            "\"\(name)\": (DIL, GenUI, __dil, OpGenuiResolvedComponentBoundary) => ("
        }
        guard let start = source.range(of: marker(name))?.upperBound else { return nil }
        let remainder = start..<source.endIndex
        let endMarker = index + 1 < names.count ? "),\n" + marker(names[index + 1]) : "),\n};"
        guard let end = source.range(of: endMarker, range: remainder)?.lowerBound else { return nil }
        return String(source[start..<end])
    }
}

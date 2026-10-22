import Foundation

/// Read-only access to the actual recovered template contract on the existing local tool path.
struct GenUIReferenceTool: LocalToolExecutor {
    static let name = "genui_reference"
    static let definition = ToolDefinition(
        name: name,
        description: """
        Search widget names for required GenUI categories or retrieve component documentation on demand. This tool returns contracts, not live data, and does not render a UI. Reuse exact contracts already in history.

        componentName:"*" searches supported names by case-insensitive substring query, not by semantic meaning. Results use offset and maxResults (default 32, maximum 64); pass nextOffset as offset for the next page. An empty result means no name matched; try another name term if needed.

        An exact componentName returns accepted properties. Original templates also return recovered source and observed state fields: inspect these before rendering with genui, and supply verified data in props.__state matching the source. Backend actions are unsupported. To continue a template source, pass nextOffset as sourceOffset with the same componentName; maxCharacters controls page length. componentName:"@guide" returns runtime, state-binding, and layout guidance.
        """,
        parametersJSON: #"{"type":"object","properties":{"componentName":{"type":"string","description":"@guide, *, or an exact supported component name"},"query":{"type":"string","description":"Substring of a component name; only for *"},"offset":{"type":"integer","minimum":0,"description":"Name-search offset for componentName:*; continue with the returned nextOffset."},"maxResults":{"type":"integer","minimum":1,"maximum":64},"sourceOffset":{"type":"integer","minimum":0,"description":"Character offset for an exact template source; continue with the returned nextOffset."},"maxCharacters":{"type":"integer","minimum":1,"maximum":65536}},"required":["componentName"],"additionalProperties":false}"#
    )
    var definition: ToolDefinition { Self.definition }

    func execute(call: ToolCall) async throws -> ToolResult {
        struct Arguments: Decodable {
            let componentName: String
            let query: String?
            let offset: Int?
            let maxResults: Int?
            let sourceOffset: Int?
            let maxCharacters: Int?
        }
        let arguments = try JSONDecoder().decode(Arguments.self, from: Data(call.argumentsJSON.utf8))
        let content: [String: Any]
        if arguments.componentName == "@guide" {
            content = ["guide": GenUITool.usageGuide]
        } else if arguments.componentName == "*" {
            let query = (arguments.query ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let names = GenUIDocument.componentCatalog.keys.sorted().filter {
                query.isEmpty || $0.lowercased().contains(query)
            }
            let offset = arguments.offset ?? 0
            let limit = arguments.maxResults ?? 32
            guard offset >= 0, offset <= names.count, limit > 0, limit <= 64 else {
                throw GenUIError.invalid("invalid component search page")
            }
            let end = offset + min(limit, names.count - offset)
            content = ["componentNames": Array(names[offset..<end]), "totalMatches": names.count,
                       "offset": offset, "nextOffset": end < names.count ? end as Any : NSNull()]
        } else {
            let name = arguments.componentName
            guard let properties = GenUIDocument.componentCatalog[name] else {
                throw GenUIError.invalid("unknown reference component: \(name)")
            }
            if GenUIReferenceCatalog.components[name] == nil {
                content = ["componentName": name, "properties": properties,
                           "canonicalName": GenUIDocument.widgetAliases[name] ?? name]
                return try Self.result(content, call: call)
            }
            guard let source = Self.source(named: name) else {
                throw GenUIError.invalid("reference component source unavailable: \(name)")
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
        return try Self.result(content, call: call)
    }

    private static func result(_ content: [String: Any], call: ToolCall) throws -> ToolResult {
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

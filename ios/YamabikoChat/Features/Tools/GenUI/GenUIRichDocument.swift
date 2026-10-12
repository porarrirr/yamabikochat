import Foundation

struct GenUINode: Codable, Sendable, Equatable {
    var type: String
    var props: [String: JSONValue]?
    var children: [GenUIChild]?
}

indirect enum GenUIChild: Codable, Sendable, Equatable {
    case node(GenUINode)
    case string(String)
    case number(Double)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) { self = .string(string) }
        else if let number = try? container.decode(Double.self) { self = .number(number) }
        else { self = .node(try container.decode(GenUINode.self)) }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .node(let node): try container.encode(node)
        case .string(let string): try container.encode(string)
        case .number(let number): try container.encode(number)
        }
    }
}

struct GenUIResource: Codable, Sendable, Equatable {
    var title: String?
    var url: String?
    var src: String?
    var text: String?
    var mime: String?
}

extension GenUIDocument {
    /// Shared with the web runtime and tool schema; component names are case sensitive.
    static let componentCatalog: [String: [String]] = [
            "text": ["bind", "color", "highlight", "inline", "italic", "key", "lineThrough", "maxLines", "minLines", "preserveWhitespace", "x", "y", "dx", "dy", "textAnchor", "dominantBaseline", "fill", "stroke", "fontSize", "transform", "size", "strong", "tabularNums", "textAlign", "truncate", "underline", "weight", "width"],
            "title": ["bind", "color", "italic", "key", "maxLines", "size", "strong", "tabularNums", "textAlign", "truncate", "weight", "width"],
            "caption": ["bind", "color", "key", "maxLines", "textAlign", "truncate", "weight"],
            "label": ["bind", "color", "htmlFor", "key", "size", "textAlign", "truncate", "weight", "width"],
            "badge": ["bind", "color", "key", "label", "maxWidth", "onHover", "padding", "pill", "size", "variant", "weight"],
            "bold": ["bind", "key", "weight"],
            "italic": ["bind", "key"],
            "underline": ["bind", "key"],
            "strikethrough": ["bind", "key"],
            "code": ["bind", "key"],
            "math": ["bind", "block", "key", "value"],
            "box": ["align", "aspectRatio", "background", "bind", "border", "clip", "columnGap", "direction", "disableAutoSpacing", "flex", "flush", "gap", "height", "justify", "key", "maxHeight", "maxSize", "maxWidth", "minHeight", "minSize", "minWidth", "padding", "radius", "role", "rowGap", "scrollable", "size", "theme", "width", "wrap"],
            "row": ["align", "aspectRatio", "background", "bind", "border", "clip", "direction", "disableAutoSpacing", "flex", "flush", "gap", "height", "justify", "key", "maxHeight", "maxSize", "maxWidth", "minHeight", "minSize", "minWidth", "padding", "radius", "role", "rowGap", "scrollable", "size", "theme", "width", "wrap"],
            "col": ["align", "aspectRatio", "background", "bind", "border", "clip", "columnGap", "direction", "disableAutoSpacing", "flex", "flush", "gap", "height", "justify", "key", "maxHeight", "maxSize", "maxWidth", "minHeight", "minSize", "minWidth", "padding", "radius", "role", "scrollable", "size", "theme", "width", "wrap"],
            "grid": ["bind", "columnGap", "columns", "gap", "key", "minChildWidth", "rowGap", "rows"],
            "grid-item": ["bind", "key", "rowSpan", "span"],
            "flow": ["bind", "columns", "gap", "key", "layout", "rows"],
            "flow-item": ["align", "aspectMode", "aspectRatio", "background", "bind", "border", "clip", "direction", "disableAutoSpacing", "flex", "flush", "gap", "height", "justify", "key", "maxHeight", "maxWidth", "minHeight", "minWidth", "padding", "radius", "role", "rowSpan", "scrollable", "span", "theme", "width", "wrap"],
            "card": ["background", "bind", "disableAutoSpacing", "gap", "height", "justify", "key", "padding", "shadow", "size", "theme", "variant", "width"],
            "divider": ["bind", "color", "flush", "key", "size", "spacing"],
            "spacer": ["bind", "key", "minSize"],
            "blockquote": ["bind", "key"],
            "button": ["bind", "block", "color", "disabled", "key", "label", "loading", "onClick", "pill", "size", "submit", "uniform", "variant"],
            "input": ["autoSelect", "bind", "defaultValue", "disabled", "fontSize", "inputType", "invalid", "key", "mask", "name", "onChange", "pill", "placeholder", "required", "size", "value", "variant"],
            "textarea": ["autoResize", "autoSelect", "bind", "defaultValue", "disabled", "invalid", "key", "maxRows", "name", "onChange", "placeholder", "required", "rows", "size", "value", "variant"],
            "slider": ["bind", "defaultValue", "disabled", "key", "marks", "max", "min", "name", "onChange", "required", "sliderStyle", "step", "value"],
            "checkbox": ["bind", "checked", "defaultChecked", "disabled", "key", "label", "lineThrough", "name", "onChange", "required", "shape", "value"],
            "select": ["align", "bind", "block", "clearable", "defaultValue", "disabled", "icon", "key", "name", "onChange", "options", "pill", "placeholder", "required", "side", "size", "value", "variant"],
            "segmented-control": ["bind", "defaultValue", "disabled", "key", "label", "onChange", "options", "pill", "size", "value", "variant"],
            "radio-group": ["bind", "defaultValue", "direction", "disabled", "key", "label", "name", "onChange", "required", "value"],
            "radio": ["bind", "disabled", "id", "key", "required", "value"],
            "date-picker": ["align", "bind", "block", "clearable", "defaultValue", "disabled", "key", "max", "min", "onChange", "pill", "placeholder", "required", "side", "size", "value", "variant"],
            "form": ["align", "background", "bind", "border", "clip", "direction", "disableAutoSpacing", "flex", "flush", "gap", "height", "justify", "key", "maxHeight", "maxWidth", "minHeight", "minWidth", "onSubmit", "padding", "radius", "role", "scrollable", "theme", "width", "wrap"],
            "pressable": ["align", "aspectRatio", "background", "bind", "border", "clip", "direction", "disableAutoSpacing", "disabled", "flex", "flush", "gap", "height", "inline", "justify", "key", "maxHeight", "maxSize", "maxWidth", "minHeight", "minSize", "minWidth", "onClick", "padding", "radius", "role", "scrollable", "size", "theme", "tooltip", "width", "wrap"],
            "table": ["bind", "columnSizing", "dividers", "emptyLabel", "key", "stickyHeader"],
            "table-section": ["bind", "header", "key", "rowDivider"],
            "table-row": ["bind", "header", "key", "label", "labelColSpan"],
            "table-cell": ["align", "bind", "colSpan", "header", "key", "padding", "rowSpan", "vAlign", "width"],
            "list": ["bind", "connector", "gap", "key", "marker", "maxMarkerSize", "start"],
            "list-item": ["bind", "description", "disabled", "key", "label", "marker", "markerSize"],
            "carousel": ["activeIndex", "bind", "flush", "gap", "key", "onChange", "showArrows", "snap", "snapAlign", "visibleItems"],
            "carousel-item": ["aspectRatio", "background", "bind", "border", "gap", "height", "key", "maxHeight", "maxWidth", "minHeight", "minWidth", "padding", "radius", "variant", "width"],
            "carousel-media-item": ["aspectRatio", "background", "bind", "border", "gap", "height", "key", "maxHeight", "maxWidth", "media", "minHeight", "minWidth", "padding", "radius", "size", "variant", "width"],
            "popover": ["bind", "hoverOpenDelay", "key", "open", "showOnHover"],
            "popover-trigger": ["bind", "block", "key", "onClick"],
            "popover-content": ["align", "bind", "key", "showCloseButton", "side", "sideOffset"],
            "AsyncImage": ["alt", "aspectRatio", "bind", "fallback", "fit", "frame", "group", "height", "key", "maxHeight", "maxWidth", "minHeight", "minWidth", "query", "radius", "ref", "src", "width"],
            "AsyncImageGroup": ["aspectRatio", "bind", "fallback", "key", "layout", "numPerQuery", "query", "ref", "refs", "size"],
            "AsyncVideo": ["bind", "key", "ref"],
            "Chart": ["bind", "content", "key"],
            "MapWidgetV2": ["answer", "arrive_by", "bind", "carousel", "depart_at", "fill", "groups", "groups_title", "key", "minHeight", "narrative", "optimize_stop_order", "origin", "points", "show_route", "title", "travel_mode"],
            "icon": ["bind", "color", "inline", "key", "name", "size"],
            "favicon": ["alt", "bind", "frame", "inline", "key", "size", "url"],
            "svg": ["bind", "color", "fill", "height", "key", "preserveAspectRatio", "size", "stroke", "strokeLinecap", "strokeLinejoin", "strokeWidth", "viewBox", "width", "xmlns"],
            "Link": ["bind", "key", "ref", "title", "url"],
            "Entity": ["address", "bind", "category", "disambig", "key", "location", "query", "ref", "value"],
            "Cite": ["bind", "key", "params", "ref", "refs"],
            "FileCite": ["bind", "key", "line_range_end", "line_range_start", "ref"],
            "CodeCite": ["bind", "citation_id", "key", "line_range_end", "line_range_start", "tool"],
            "FileNavList": ["bind", "items", "key"],
            "FollowUp": ["bind", "key", "query", "source", "value"],
            "MemoryCite": ["bind", "key"],
            "AppBlock": ["app_block_id", "bind", "bundle_version", "content", "entrypoint", "icon", "key", "language", "title", "variant"],
            "CodeBlock": ["bind", "editable", "interactive", "key", "language", "model_previewable"],
            "WritingBlock": ["bind", "id", "key", "options", "subject", "variant"],
            "g": ["clipPath", "fill", "fillOpacity", "fillRule", "id", "key", "opacity", "stroke", "strokeDasharray", "strokeDashoffset", "strokeLinecap", "strokeLinejoin", "strokeOpacity", "strokeWidth", "transform"],
            "path": ["clipPath", "d", "fill", "fillOpacity", "fillRule", "id", "key", "opacity", "pathLength", "stroke", "strokeDasharray", "strokeDashoffset", "strokeLinecap", "strokeLinejoin", "strokeOpacity", "strokeWidth", "transform"],
            "circle": ["clipPath", "cx", "cy", "fill", "fillOpacity", "fillRule", "id", "key", "opacity", "r", "stroke", "strokeDasharray", "strokeDashoffset", "strokeLinecap", "strokeLinejoin", "strokeOpacity", "strokeWidth", "transform"],
            "ellipse": ["clipPath", "cx", "cy", "fill", "fillOpacity", "fillRule", "id", "key", "opacity", "rx", "ry", "stroke", "strokeDasharray", "strokeDashoffset", "strokeLinecap", "strokeLinejoin", "strokeOpacity", "strokeWidth", "transform"],
            "rect": ["clipPath", "fill", "fillOpacity", "fillRule", "height", "id", "key", "opacity", "rx", "ry", "stroke", "strokeDasharray", "strokeDashoffset", "strokeLinecap", "strokeLinejoin", "strokeOpacity", "strokeWidth", "transform", "width", "x", "y"],
            "line": ["clipPath", "fill", "fillOpacity", "fillRule", "id", "key", "opacity", "stroke", "strokeDasharray", "strokeDashoffset", "strokeLinecap", "strokeLinejoin", "strokeOpacity", "strokeWidth", "transform", "x1", "x2", "y1", "y2"],
            "polyline": ["clipPath", "fill", "fillOpacity", "fillRule", "id", "key", "opacity", "points", "stroke", "strokeDasharray", "strokeDashoffset", "strokeLinecap", "strokeLinejoin", "strokeOpacity", "strokeWidth", "transform"],
            "polygon": ["clipPath", "fill", "fillOpacity", "fillRule", "id", "key", "opacity", "points", "stroke", "strokeDasharray", "strokeDashoffset", "strokeLinecap", "strokeLinejoin", "strokeOpacity", "strokeWidth", "transform"],
            "defs": ["clipPath", "fill", "fillOpacity", "fillRule", "id", "key", "opacity", "stroke", "strokeDasharray", "strokeDashoffset", "strokeLinecap", "strokeLinejoin", "strokeOpacity", "strokeWidth", "transform"],
            "linearGradient": ["clipPath", "fill", "fillOpacity", "fillRule", "gradientTransform", "gradientUnits", "id", "key", "opacity", "spreadMethod", "stroke", "strokeDasharray", "strokeDashoffset", "strokeLinecap", "strokeLinejoin", "strokeOpacity", "strokeWidth", "transform", "x1", "x2", "y1", "y2"],
            "radialGradient": ["clipPath", "cx", "cy", "fill", "fillOpacity", "fillRule", "fr", "fx", "fy", "gradientTransform", "gradientUnits", "id", "key", "opacity", "r", "spreadMethod", "stroke", "strokeDasharray", "strokeDashoffset", "strokeLinecap", "strokeLinejoin", "strokeOpacity", "strokeWidth", "transform"],
            "stop": ["clipPath", "fill", "fillOpacity", "fillRule", "id", "key", "offset", "opacity", "stopColor", "stopOpacity", "stroke", "strokeDasharray", "strokeDashoffset", "strokeLinecap", "strokeLinejoin", "strokeOpacity", "strokeWidth", "transform"],
            "clipPath": ["clipPath", "clipPathUnits", "fill", "fillOpacity", "fillRule", "id", "key", "opacity", "stroke", "strokeDasharray", "strokeDashoffset", "strokeLinecap", "strokeLinejoin", "strokeOpacity", "strokeWidth", "transform"],
    ]

    static func isAllowedURL(_ value: String) -> Bool {
        guard let url = URL(string: value), url.scheme?.lowercased() == "https",
              let host = url.host, !host.isEmpty, url.user == nil, url.password == nil else { return false }
        return true
    }

    func validateRichDocument() throws {
        func require(_ condition: Bool, _ message: String) throws {
            guard condition else { throw GenUIError.invalid(message) }
        }
        try require((ui != nil) != (code != nil), "choose exactly one renderer: ui or code")
        try require((subtitle?.count ?? 0) <= 4096, "subtitle exceeds 4096 characters")
        if let code {
            try require(!code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "code is empty")
            try require(code.utf8.count <= 65_536, "code exceeds 64 KiB")
            try GenUICodeValidator.validate(code)
        }
        try require((state?.count ?? 0) <= 64, "state exceeds 64 keys")
        try require((resources?.count ?? 0) <= 64, "resources exceeds 64 entries")
        func value(_ item: JSONValue, depth: Int = 0) throws {
            try require(depth <= 32, "JSON nesting exceeds 32 levels")
            switch item {
            case .number(let number): try require(number.isFinite, "non-finite number")
            case .array(let array):
                try require(array.count <= 512, "array exceeds 512 entries")
                for element in array { try value(element, depth: depth + 1) }
            case .object(let object):
                try require(object.count <= 128, "object exceeds 128 keys")
                for element in object.values { try value(element, depth: depth + 1) }
            default: break
            }
        }
        for item in state?.values ?? Dictionary<String, JSONValue>().values { try value(item) }
        for resource in resources?.values ?? Dictionary<String, GenUIResource>().values {
            for url in [resource.url, resource.src].compactMap({ $0 }) {
                try require(Self.isAllowedURL(url), "resource URL must be an explicit HTTPS URL")
            }
        }
        func action(_ item: JSONValue) throws {
            guard case .object(let object) = item, case .string(let type) = object["type"] else {
                throw GenUIError.invalid("event requires an action object with type")
            }
            try require(["setState", "resetState", "copy", "openUrl", "issueNewTurn", "openEntityDetail"].contains(type), "unknown action type")
            try require(Set(object.keys).isSubset(of: ["type", "key", "value", "query", "url", "text", "args"]), "unknown action property")
            func string(_ key: String) -> String? { if case .string(let text) = object[key] { return text }; return nil }
            switch type {
            case "setState": try require(string("key")?.isEmpty == false && object["value"] != nil, "setState requires key and value")
            case "copy": try require(string("text") != nil, "copy requires text")
            case "openUrl": try require(string("url").map(Self.isAllowedURL) == true, "openUrl requires an explicit HTTPS URL")
            case "issueNewTurn": try require(string("query")?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false, "issueNewTurn requires query")
            case "openEntityDetail": guard case .object = object["args"] else { throw GenUIError.invalid("openEntityDetail requires args") }
            default: break
            }
        }
        var count = 0
        func node(_ node: GenUINode, depth: Int, inSVG: Bool = false) throws {
            let svgPrimitive = Set(["g", "path", "circle", "ellipse", "rect", "line", "polyline", "polygon", "defs", "linearGradient", "radialGradient", "stop", "clipPath"])
            try require(!svgPrimitive.contains(node.type) || inSVG, "SVG primitives require an svg ancestor")
            let svgContext = inSVG || node.type == "svg"
            count += 1
            try require(depth <= 32 && count <= 512, "UI exceeds 32 levels or 512 nodes")
            guard let allowedProps = Self.componentCatalog[node.type] else { throw GenUIError.invalid("unknown component type: \(node.type)") }
            for (key, item) in node.props ?? [:] {
                try require(allowedProps.contains(key), "unsupported property \(key) on \(node.type)")
                try value(item)
                if ["onClick", "onChange", "onSubmit", "onHover"].contains(key) { try action(item) }
                if ["url", "src"].contains(key), case .string(let url) = item {
                    try require(Self.isAllowedURL(url), "component URL must be an explicit HTTPS URL")
                }
                if node.type == "AppBlock", ["content", "entrypoint"].contains(key), case .object = item {
                    let nested = try JSONDecoder().decode(GenUINode.self, from: JSONEncoder().encode(item))
                    try nodeVisit(nested, depth: depth + 1, inSVG: svgContext)
                }
                if svgContext, ["fill", "stroke", "clipPath"].contains(key), case .string(let paint) = item, paint.lowercased().contains("url(") {
                    try require(paint.range(of: #"^url\(#[A-Za-z_][A-Za-z0-9_-]*\)$"#, options: .regularExpression) != nil, "SVG references must be local fragment IDs")
                }
                if key == "bind" { guard case .string(let key) = item, !key.isEmpty else { throw GenUIError.invalid("bind requires a state key") }; }
            }
            try require((node.children?.count ?? 0) <= 512, "too many children")
            for child in node.children ?? [] {
                switch child {
                case .node(let child): try nodeVisit(child, depth: depth + 1, inSVG: svgContext)
                case .number(let number): try require(number.isFinite, "non-finite child number")
                case .string: break
                }
            }
        }
        func nodeVisit(_ item: GenUINode, depth: Int, inSVG: Bool) throws { try node(item, depth: depth, inSVG: inSVG) }
        if let ui { try node(ui, depth: 1) }
    }
}

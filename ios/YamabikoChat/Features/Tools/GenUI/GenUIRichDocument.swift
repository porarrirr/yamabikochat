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
    var isRich: Bool { ui != nil || code != nil }
    /// Shared with the web runtime and tool schema; component names are case sensitive.
    static let commonProperties = ["id", "visible", "ariaLabel", "ariaHidden", "accessibilityId", "margin", "marginTop", "marginRight", "marginBottom", "marginLeft", "paddingTop", "paddingRight", "paddingBottom", "paddingLeft"]

    static let elementProperties: [String: [String]] = [
        "audio-player": ["src", "title", "subtitle", "compact", "autoPlay", "loop", "muted", "preload", "defaultPlaybackRate", "playbackRates", "initialCurrentTimeSeconds", "durationSeconds", "downloadUrl", "downloadFilename"],
        "run-interval": ["interval", "leadingTick", "maxTicks", "onTickAction", "running"],
        "text": ["value", "bind", "color", "dominantBaseline", "dx", "dy", "fill", "fontSize", "highlight", "inline", "italic", "key", "lineThrough", "maxLines", "minLines", "preserveWhitespace", "size", "stroke", "strong", "tabularNums", "textAlign", "textAnchor", "transform", "truncate", "underline", "weight", "width", "x", "y"],
        "title": ["value", "bind", "color", "italic", "key", "maxLines", "size", "strong", "tabularNums", "textAlign", "truncate", "weight", "width"],
        "caption": ["value", "bind", "color", "key", "maxLines", "textAlign", "truncate", "weight"],
        "label": ["value", "bind", "color", "htmlFor", "key", "size", "textAlign", "truncate", "weight", "width"],
        "badge": ["bind", "color", "key", "label", "maxWidth", "onHover", "padding", "pill", "size", "variant", "weight"],
        "bold": ["value", "bind", "key", "weight"],
        "italic": ["value", "bind", "key"],
        "underline": ["value", "bind", "key"],
        "strikethrough": ["value", "bind", "key"],
        "code": ["value", "bind", "key"],
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
        "input": ["autoSelect", "bind", "defaultValue", "disabled", "fontSize", "inputType", "invalid", "key", "label", "mask", "name", "onChange", "pill", "placeholder", "required", "size", "value", "variant"],
        "textarea": ["autoResize", "autoSelect", "bind", "defaultValue", "disabled", "invalid", "key", "label", "maxRows", "name", "onChange", "placeholder", "required", "rows", "size", "value", "variant"],
        "slider": ["bind", "defaultValue", "disabled", "key", "label", "marks", "max", "min", "name", "onChange", "required", "sliderStyle", "step", "value"],
        "checkbox": ["bind", "checked", "defaultChecked", "disabled", "key", "label", "lineThrough", "name", "onChange", "required", "shape", "value"],
        "select": ["align", "bind", "block", "clearable", "defaultValue", "disabled", "icon", "key", "label", "name", "onChange", "options", "pill", "placeholder", "required", "side", "size", "value", "variant"],
        "segmented-control": ["bind", "defaultValue", "disabled", "key", "label", "onChange", "options", "pill", "size", "value", "variant"],
        "radio-group": ["bind", "defaultValue", "direction", "disabled", "key", "label", "name", "onChange", "required", "value"],
        "radio": ["bind", "disabled", "key", "label", "required", "value"],
        "date-picker": ["align", "bind", "block", "clearable", "defaultValue", "disabled", "key", "label", "max", "min", "onChange", "pill", "placeholder", "required", "side", "size", "value", "variant"],
        "form": ["align", "background", "bind", "border", "clip", "direction", "disableAutoSpacing", "flex", "flush", "gap", "height", "justify", "key", "maxHeight", "maxWidth", "minHeight", "minWidth", "onSubmit", "padding", "radius", "role", "scrollable", "theme", "width", "wrap"],
        "pressable": ["align", "aspectRatio", "background", "bind", "border", "clip", "direction", "disableAutoSpacing", "disabled", "flex", "flush", "gap", "height", "inline", "justify", "key", "maxHeight", "maxSize", "maxWidth", "minHeight", "minSize", "minWidth", "onClick", "padding", "radius", "role", "scrollable", "size", "theme", "tooltip", "width", "wrap"],
        "table": ["bind", "columnSizing", "dividers", "emptyLabel", "key", "stickyHeader"],
        "table-section": ["bind", "header", "key", "rowDivider"],
        "table-row": ["bind", "header", "key", "label", "labelColSpan"],
        "table-cell": ["align", "bind", "colSpan", "header", "key", "padding", "rowSpan", "vAlign", "width"],
        "list": ["bind", "connector", "gap", "key", "marker", "maxMarkerSize", "start"],
        "list-item": ["bind", "description", "disabled", "icon", "iconColor", "key", "label", "marker", "markerSize", "variant"],
        "carousel": ["activeIndex", "bind", "flush", "gap", "key", "onChange", "showArrows", "snap", "snapAlign", "visibleItems"],
        "carousel-item": ["aspectRatio", "background", "bind", "border", "gap", "height", "key", "maxHeight", "maxWidth", "minHeight", "minWidth", "padding", "radius", "variant", "width"],
        "carousel-media-item": ["aspectRatio", "background", "bind", "border", "gap", "height", "key", "maxHeight", "maxWidth", "media", "minHeight", "minWidth", "padding", "radius", "size", "variant", "width"],
        "popover": ["bind", "hoverOpenDelay", "key", "open", "showOnHover"],
        "popover-trigger": ["bind", "block", "key", "onClick"],
        "popover-content": ["align", "bind", "key", "showCloseButton", "side", "sideOffset"],
        "AsyncImage": ["alt", "aspectRatio", "bind", "fallback", "fit", "frame", "group", "height", "key", "maxHeight", "maxWidth", "minHeight", "minWidth", "query", "radius", "ref", "src", "width"],
        "AsyncImageGroup": ["aspectRatio", "bind", "fallback", "key", "layout", "numPerQuery", "query", "ref", "refs", "size"],
        "AsyncVideo": ["bind", "key", "ref", "src", "title"],
        "Chart": ["data", "series", "xAxis", "yAxis", "onHover", "chartType", "size", "bind", "content", "key", "alt", "height", "showLegend", "showXAxis", "showYAxis", "showGrid", "showPoints", "showValues"],
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
        "CodeBlock": ["bind", "editable", "interactive", "key", "language", "model_previewable", "value"],
        "WritingBlock": ["bind", "key", "options", "subject", "variant"],
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
        "markdown": ["bind", "inline", "key", "text", "value"],
        "text-only-markdown": ["bind", "inline", "key", "text", "value"],
        "highlight": ["bind", "key"],
        "loading": ["bind", "key", "label"],
        "loading-indicator": ["bind", "key", "label", "size"],
        "loading-block": ["bind", "height", "key", "label", "lines"],
        "pulse-indicator": ["bind", "color", "key", "label", "size"],
        "shimmer-text": ["bind", "key", "text", "value"],
        "flashcard-flip": ["activeKey", "disabled", "reducedMotion", "onSwipeLeft", "onSwipeRight", "onSwipeProgress", "onInteractionChange", "back", "bind", "flipped", "front", "key", "label", "onChange"],
        "animate": ["initial", "enter", "exit", "preventInitialTransition", "bind", "delay", "duration", "key", "name"],
        "animate-group": ["bind", "delay", "duration", "key", "name", "stagger"],
        "animate-item": ["bind", "delay", "duration", "key", "name"],
        "transition": ["bind", "delay", "duration", "key", "name"],
        "celebration": ["active", "bind", "key", "label"],
        "tooltip": ["bind", "key", "label", "text"],
        "component": ["bind", "content", "key", "name"],
        "component-content": ["bind", "content", "key"],
        "transparent": ["bind", "key"],
        "CLIENT_DEFINED_WIDGET_TYPE": ["bind", "content", "key", "name"],
        "DIL_RENDERED_PROP_ELEMENT_TYPE": ["bind", "content", "key", "value"],
        "lottie": ["animationData", "data", "url", "loop", "autoplay", "speed", "onComplete", "width", "height", "bind", "fallback", "key", "label", "ref", "src"],
        "youtube": ["bind", "key", "title", "url", "videoId"],
        "choice": ["bind", "disabled", "key", "label", "onClick", "selected", "value"],
        "follow-up-action-bar": ["bind", "key"],
        "horizontal-swipe-surface": ["bind", "gap", "key", "snap"],
        "Each": ["of", "itemName", "item", "indexName", "index", "as", "bind", "indexAs", "items", "key", "keyField"],
        "Scope": ["bind", "key", "values"],
        "Show": ["bind", "key", "when"],
        "Show.Else": ["bind", "key"],
        "image": ["alt", "aspectRatio", "bind", "fallback", "fit", "frame", "group", "height", "key", "maxHeight", "maxWidth", "minHeight", "minWidth", "query", "radius", "ref", "src", "width"],
        "search-image": ["alt", "aspectRatio", "bind", "fallback", "fit", "frame", "group", "height", "key", "maxHeight", "maxWidth", "minHeight", "minWidth", "query", "radius", "ref", "src", "width"],
        "chart": ["series", "xAxis", "yAxis", "onHover", "chartType", "size", "alt", "bind", "content", "height", "key", "showGrid", "showLegend", "showPoints", "showValues", "showXAxis", "showYAxis"],
        "pie-chart": ["series", "xAxis", "innerRadius", "outerRadius", "paddingAngle", "cornerRadius", "size", "alt", "bind", "content", "data", "height", "key", "nameKey", "showGrid", "showLegend", "showPoints", "showValues", "showXAxis", "showYAxis", "valueKey"],
        "link": ["bind", "key", "ref", "title", "url"],
    ]

    static let componentCatalog: [String: [String]] = {
        let svgPrimitives = Set(["g", "path", "circle", "ellipse", "rect", "line", "polyline", "polygon", "defs", "linearGradient", "radialGradient", "stop", "clipPath"])
        var catalog = elementProperties
        for type in catalog.keys where !svgPrimitives.contains(type) {
            catalog[type] = Array(Set(catalog[type, default: []] + commonProperties)).sorted()
        }
        for (alias, type) in widgetAliases { catalog[alias] = catalog[type] }
        for (name, properties) in GenUIReferenceCatalog.components { catalog[name] = properties }
        return catalog
    }()

    /// A fixed, useful core keeps short conversations cacheable as well as avoiding discovery
    /// calls for ordinary layouts. Templates and aliases are retrieved through genui_reference;
    /// never vary this prefix by query, conversation, retrieved component or provider.
    static var coreComponentGuide: String {
        let guide: [String: Any] = ["commonProperties": commonProperties, "elements": elementProperties]
        return String(decoding: try! JSONSerialization.data(withJSONObject: guide, options: [.sortedKeys]), as: UTF8.self)
    }

    /// Complete catalog for documentation and size comparisons, not the advertised tool prefix.
    static var componentGuide: String {
        let guide: [String: Any] = ["commonProperties": commonProperties,
                                    "elements": elementProperties, "widgetAliases": widgetAliases, "referenceComponents": GenUIReferenceCatalog.components]
        return String(decoding: try! JSONSerialization.data(withJSONObject: guide, options: [.sortedKeys]), as: UTF8.self)
    }

    static let widgetAliases: [String: String] = [
        "AudioPlayer": "audio-player",
        "RunInterval": "run-interval",
        "ListView": "list",
        "ListViewItem": "list-item",
        "ChartsWidgetV2": "Chart",
        "Animate": "animate",
        "Animate.Item": "animate-item",
        "AnimateGroup": "animate-group",
        "Transition": "transition",
        "Response": "col",
        "Basic": "box",
        "Box": "box",
        "Row": "row",
        "Col": "col",
        "Inline": "row",
        "Grid": "grid",
        "Grid.Item": "grid-item",
        "Flow": "flow",
        "Flow.Item": "flow-item",
        "Card": "card",
        "Button": "button",
        "Badge": "badge",
        "Input": "input",
        "Textarea": "textarea",
        "Checkbox": "checkbox",
        "Slider": "slider",
        "Select": "select",
        "DatePicker": "date-picker",
        "SegmentedControl": "segmented-control",
        "RadioGroup": "radio-group",
        "List": "list",
        "List.Item": "list-item",
        "Item": "list-item",
        "Table": "table",
        "Table.Row": "table-row",
        "Table.Cell": "table-cell",
        "Table.Section": "table-section",
        "Carousel": "carousel",
        "Carousel.Item": "carousel-item",
        "Carousel.MediaItem": "carousel-media-item",
        "BaseCarousel": "carousel",
        "BaseCarousel.Item": "carousel-item",
        "BaseCarousel.MediaItem": "carousel-media-item",
        "CardCarousel": "carousel",
        "Popover": "popover",
        "Popover.Trigger": "popover-trigger",
        "Popover.Content": "popover-content",
        "Pressable": "pressable",
        "Form": "form",
        "Spacer": "spacer",
        "Divider": "divider",
        "Icon": "icon",
        "Image": "AsyncImage",
        "Favicon": "favicon",
        "SearchImage": "search-image",
        "HorizontalSwipeSurface": "horizontal-swipe-surface",
        "FollowUpActionBar": "follow-up-action-bar",
        "LoadingDot": "pulse-indicator",
        "LoadingBlock": "loading-block",
        "LoadingIndicator": "loading-indicator",
        "PulseIndicator": "pulse-indicator",
        "Celebration": "celebration",
        "PieChart": "pie-chart",
        "DILMap": "MapWidgetV2",
        "YouTubeEmbed": "youtube",
        "OverflowRow": "horizontal-swipe-surface",
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
        if let code {
            try require(!code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "code is empty")
            try GenUICodeValidator.validate(code)
        }
        func value(_ item: JSONValue) throws {
            var pending = [item]
            while let item = pending.popLast() {
                switch item {
                case .number(let number): try require(number.isFinite, "non-finite number")
                case .array(let array): pending.append(contentsOf: array)
                case .object(let object): pending.append(contentsOf: object.values)
                default: break
                }
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
            case "setState": try require(string("key")?.isEmpty == false && object["value"] != nil && !["__proto__", "prototype", "constructor"].contains(string("key") ?? ""), "setState requires a safe key and value")
            case "copy": try require(string("text") != nil, "copy requires text")
            case "openUrl": try require(string("url").map(Self.isAllowedURL) == true, "openUrl requires an explicit HTTPS URL")
            case "issueNewTurn": try require(string("query")?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false, "issueNewTurn requires query")
            case "openEntityDetail": guard case .object = object["args"] else { throw GenUIError.invalid("openEntityDetail requires args") }
            default: break
            }
        }
        let svgPrimitive = Set(["g", "path", "circle", "ellipse", "rect", "line", "polyline", "polygon", "defs", "linearGradient", "radialGradient", "stop", "clipPath"])
        var pending: [(GenUINode, Bool)] = ui.map { [($0, false)] } ?? []
        while let (node, inSVG) = pending.popLast() {
            try require(!svgPrimitive.contains(node.type) || inSVG, "SVG primitives require an svg ancestor")
            let svgContext = inSVG || node.type == "svg"
            guard let allowedProps = Self.componentCatalog[node.type] else { throw GenUIError.invalid("unknown component type: \(node.type)") }
            for (key, item) in node.props ?? [:] {
                let property = key.hasPrefix("$") ? String(key.dropFirst()) : key
                try require(allowedProps.contains(property), "unsupported property \(key) on \(node.type)")
                try value(item)
                if key.hasPrefix("$") {
                    guard case .string(let expression) = item, !expression.isEmpty else { throw GenUIError.invalid("CEL properties require an expression string") }
                }
                if ["onClick", "onChange", "onSubmit", "onHover"].contains(key) { try action(item) }
                if ["url", "src"].contains(key), case .string(let url) = item {
                    try require(Self.isAllowedURL(url), "component URL must be an explicit HTTPS URL")
                }
                if ["AppBlock", "component", "component-content", "CLIENT_DEFINED_WIDGET_TYPE", "DIL_RENDERED_PROP_ELEMENT_TYPE", "flashcard-flip"].contains(node.type), ["content", "entrypoint", "front", "back"].contains(key) {
                    var embedded = [item]
                    while let child = embedded.popLast() {
                        switch child {
                        case .array(let children): embedded.append(contentsOf: children)
                        case .object:
                            let nested = try JSONDecoder().decode(GenUINode.self, from: JSONEncoder().encode(child))
                            pending.append((nested, svgContext))
                        default: break
                        }
                    }
                }
                if svgContext, ["fill", "stroke", "clipPath"].contains(key), case .string(let paint) = item, paint.lowercased().contains("url(") {
                    try require(paint.range(of: #"^url\(#[A-Za-z_][A-Za-z0-9_-]*\)$"#, options: .regularExpression) != nil, "SVG references must be local fragment IDs")
                }
                if key == "bind" { guard case .string(let key) = item, !key.isEmpty, !["__proto__", "prototype", "constructor"].contains(key) else { throw GenUIError.invalid("bind requires a safe state key") }; }
            }
            for child in node.children ?? [] {
                switch child {
                case .node(let child): pending.append((child, svgContext))
                case .number(let number): try require(number.isFinite, "non-finite child number")
                case .string: break
                }
            }
        }
    }
}

import Foundation

struct GenUIOption: Codable, Sendable, Equatable { var label: String; var value: Double }
struct GenUIInput: Codable, Sendable, Equatable {
    var id: String
    var label: String
    var kind: String
    var value: Double? = 0
    var text: String? = ""
    var min: Double?
    var max: Double?
    var step: Double?
    var unit: String?
    var options: [GenUIOption]?
    enum CodingKeys: String, CodingKey { case id, label, kind, value, text, min, max, step, unit, options }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        label = try c.decode(String.self, forKey: .label)
        kind = try c.decode(String.self, forKey: .kind)
        value = try c.decodeIfPresent(Double.self, forKey: .value) ?? 0
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        min = try c.decodeIfPresent(Double.self, forKey: .min)
        max = try c.decodeIfPresent(Double.self, forKey: .max)
        step = try c.decodeIfPresent(Double.self, forKey: .step)
        unit = try c.decodeIfPresent(String.self, forKey: .unit)
        options = try c.decodeIfPresent([GenUIOption].self, forKey: .options)
    }
}
struct GenUIPoint: Codable, Sendable, Equatable { var label: String; var value: String }
struct GenUISeries: Codable, Sendable, Equatable { var name: String; var points: [GenUIPoint] }
struct GenUICard: Codable, Sendable, Equatable { var title: String; var value: String; var detail: String? }
struct GenUIComponent: Codable, Sendable, Equatable {
    var id: String
    var kind: String
    var title: String?
    var text: String?
    var value: String?
    var format: String?
    var unit: String?
    var columns: [String]?
    var rows: [[String]]?
    var series: [GenUISeries]?
    var items: [GenUICard]?
    var chartType: String? = nil

    var resolvedChartType: String { chartType ?? "line" }

    func pieValues(values: [String: Double]) -> [Double]? {
        guard let series, series.count == 1 else { return nil }
        let numbers = series[0].points.compactMap { point -> Double? in
            let value = point.value.hasPrefix("=")
                ? try? GenUIExpression.evaluate(point.value, values: values)
                : Double(point.value)
            guard let value, value.isFinite, value >= 0 else { return nil }
            return value
        }
        let total = numbers.reduce(0, +)
        guard numbers.count == series[0].points.count, total.isFinite, total > 0 else { return nil }
        return numbers
    }
}
struct GenUIDocument: Codable, Sendable, Equatable {
    var title: String
    var subtitle: String?
    var inputs: [GenUIInput] = []
    var components: [GenUIComponent] = []
    var ui: GenUINode?
    var code: String?
    var state: [String: JSONValue]?
    var resources: [String: GenUIResource]?

    enum CodingKeys: String, CodingKey { case title, subtitle, inputs, components, ui, code, state, resources }
    init(title: String, subtitle: String? = nil, inputs: [GenUIInput] = [], components: [GenUIComponent] = [], ui: GenUINode? = nil, code: String? = nil, state: [String: JSONValue]? = nil, resources: [String: GenUIResource]? = nil) {
        self.title = title; self.subtitle = subtitle; self.inputs = inputs; self.components = components
        self.ui = ui; self.code = code; self.state = state; self.resources = resources
    }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decode(String.self, forKey: .title)
        subtitle = try container.decodeIfPresent(String.self, forKey: .subtitle)
        inputs = try container.decodeIfPresent([GenUIInput].self, forKey: .inputs) ?? []
        components = try container.decodeIfPresent([GenUIComponent].self, forKey: .components) ?? []
        ui = try container.decodeIfPresent(GenUINode.self, forKey: .ui)
        code = try container.decodeIfPresent(String.self, forKey: .code)
        state = try container.decodeIfPresent([String: JSONValue].self, forKey: .state)
        resources = try container.decodeIfPresent([String: GenUIResource].self, forKey: .resources)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(subtitle, forKey: .subtitle)
        if ui == nil && code == nil {
            try container.encode(inputs, forKey: .inputs)
            try container.encode(components, forKey: .components)
        }
        try container.encodeIfPresent(ui, forKey: .ui)
        try container.encodeIfPresent(code, forKey: .code)
        try container.encodeIfPresent(state, forKey: .state)
        try container.encodeIfPresent(resources, forKey: .resources)
    }

    static func validated(from json: String) throws -> Self {
        let document = try JSONDecoder().decode(Self.self, from: Data(json.utf8))
        try document.validate()
        return document
    }

    func render(_ value: String, values: [String: Double], texts: [String: String]) -> String {
        if value.hasPrefix("=") {
            guard let result = try? GenUIExpression.evaluate(value, values: values) else { return "—" }
            return String(result)
        }
        var rendered = value
        for input in inputs {
            let replacement = input.kind == "text" ? (texts[input.id] ?? "") : (values[input.id].map { $0.formatted(.number.precision(.fractionLength(0...6))) } ?? "")
            rendered = rendered.replacingOccurrences(of: "{{\(input.id)}}", with: replacement)
        }
        return rendered
    }

    private func validate() throws {
        func check(_ condition: Bool, _ reason: String) throws { guard condition else { throw GenUIError.invalid(reason) } }
        func short(_ string: String) throws { try check(string.count <= 4096, "string exceeds 4096 characters") }
        func identifier(_ string: String) -> Bool {
            string.range(of: "^[A-Za-z_][A-Za-z0-9_]{0,63}$", options: .regularExpression) != nil
        }
        try check(!title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "title is required")
        if ui != nil || code != nil {
            try check(components.isEmpty && inputs.isEmpty, "choose exactly one renderer: components, ui or code")
            try validateRichDocument()
            return
        }
        try short(title)
        try check(state == nil && resources == nil, "state and resources require ui or code")
        try check(inputs.count <= 24 && !components.isEmpty && components.count <= 48, "input/component count exceeds limits")
        var ids = Set<String>()
        var values: [String: Double] = [:]
        for input in inputs {
            try check(identifier(input.id) && ids.insert(input.id).inserted, "input ids must be unique identifiers")
            try short(input.label); try short(input.text ?? ""); try short(input.unit ?? "")
            try check(!input.label.isEmpty && ["slider", "number", "select", "text", "toggle"].contains(input.kind), "invalid input kind/label")
            for value in [input.value, input.min, input.max, input.step].compactMap({ $0 }) { try check(value.isFinite, "non-finite input value") }
            let value = input.value ?? 0
            if let min = input.min { try check(value >= min, "input value below minimum") }
            if let max = input.max { try check(value <= max, "input value above maximum") }
            if let min = input.min, let max = input.max {
                try check(min < max && (max - min).isFinite, "input range must be finite with minimum below maximum")
            }
            if let step = input.step { try check(step > 0, "step must be positive") }
            if input.kind == "slider" { try check(input.min != nil && input.max != nil, "slider requires min and max") }
            if input.kind == "toggle" { try check(value == 0 || value == 1, "toggle value must be 0 or 1") }
            if let options = input.options {
                try check(options.count <= 32 && Set(options.map(\.value)).count == options.count, "too many or duplicate select options")
                for option in options { try short(option.label); try check(!option.label.isEmpty && option.value.isFinite, "invalid option") }
            }
            if input.kind == "select" { try check(input.options?.contains(where: { $0.value == value }) == true, "select requires options containing its default value") }
            if input.kind != "text" { values[input.id] = value }
        }
        func display(_ string: String?) throws {
            guard let string else { return }
            try short(string)
            if string.hasPrefix("=") { _ = try GenUIExpression.evaluate(string, values: values) }
            let pattern = #"\{\{([^{}]+)\}\}"#
            let regex = try NSRegularExpression(pattern: pattern)
            let range = NSRange(string.startIndex..., in: string)
            for match in regex.matches(in: string, range: range) {
                if let range = Range(match.range(at: 1), in: string) { try check(ids.contains(String(string[range])), "unknown interpolation input") }
            }
        }
        try display(title)
        try display(subtitle)
        var componentIDs = Set<String>()
        for component in components {
            try check(identifier(component.id) && componentIDs.insert(component.id).inserted, "component ids must be unique identifiers")
            try check(["text", "metric", "table", "chart", "cards"].contains(component.kind), "unknown component kind")
            try check(component.format == nil || ["number", "currency", "percent"].contains(component.format!), "unknown format")
            try display(component.title); try display(component.text); try display(component.value); try display(component.unit)
            switch component.kind {
            case "text": try check(component.text != nil, "text requires text")
            case "metric": try check(component.value != nil, "metric requires value")
            case "table":
                let columns = component.columns ?? []; let rows = component.rows ?? []
                try check(!columns.isEmpty && columns.count <= 12 && rows.count <= 100, "invalid table dimensions")
                for column in columns { try display(column) }
                for row in rows { try check(row.count == columns.count, "table row width differs from columns"); for cell in row { try display(cell) } }
            case "chart":
                try check(["line", "pie"].contains(component.resolvedChartType), "unsupported chartType; use line or pie")
                let series = component.series ?? []
                if component.resolvedChartType == "pie" {
                    try check(component.pieValues(values: values) != nil, "pie requires exactly one series with finite nonnegative values and a positive finite total")
                }
                try check(!series.isEmpty && series.count <= 8, "chart requires 1–8 series")
                for series in series {
                    try display(series.name); try check(!series.points.isEmpty && series.points.count <= 100, "chart requires 1–100 points")
                    for point in series.points {
                        try display(point.label); try display(point.value)
                        if !point.value.hasPrefix("=") { try check(Double(point.value)?.isFinite == true, "chart value must be numeric or a formula") }
                    }
                }
            case "cards":
                let items = component.items ?? []
                try check(!items.isEmpty && items.count <= 24, "cards requires 1–24 items")
                for item in items { try display(item.title); try display(item.value); try display(item.detail) }
            default: break
            }
        }
    }
}

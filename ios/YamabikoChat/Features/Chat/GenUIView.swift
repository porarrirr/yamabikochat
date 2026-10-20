import SwiftUI
import Charts

@MainActor
final class GenUIState: ObservableObject {
    var document: GenUIDocument
    @Published var values: [String: Double]
    @Published var texts: [String: String]
    @Published var numberDrafts: [String: String]
    // WebKit owns interactive rendering. Keep its restoration snapshot without
    // invalidating the SwiftUI host on every slider input event.
    var richSnapshot: [String: JSONValue]?
    let renderCacheID = UUID()
    // Visible hosts own their renderer. Only a bounded shared cache keeps offscreen ones.
    weak var richRenderer: GenUIRichWebView.Coordinator?
    @Published var richHeight: CGFloat = 60 {
        didSet { if abs(richHeight - oldValue) > 1 { onLayoutChange?() } }
    }
    var onLayoutChange: (() -> Void)?
    @Published var showsInputs = false

    init(document: GenUIDocument) {
        self.document = document
        let initial = document.inputs.reduce(into: [String: Double]()) { $0[$1.id] = $1.value ?? $1.min ?? 0 }
        values = initial
        texts = document.inputs.reduce(into: [String: String]()) { $0[$1.id] = $1.text ?? "" }
        numberDrafts = initial.mapValues { String($0) }
    }
}

/// Retrieves state owned by the conversation row so recycled hosting cells retain input edits.
struct GenUITimelineView: View {
    @EnvironmentObject private var row: ChatTimelineRowStore
    let document: GenUIDocument
    let toolCallID: String

    var body: some View {
        if document.ui != nil || document.code != nil {
            GenUIRichView(document: document, state: row.genUIState(id: toolCallID, document: document))
        } else {
            GenUIView(document: document, state: row.genUIState(id: toolCallID, document: document))
        }
    }
}

/// A local, declarative canvas. Input changes never execute remote code or make requests.
struct GenUIView: View {
    let document: GenUIDocument
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dynamicTypeSize) private var dynamicType
    @ObservedObject private var state: GenUIState

    init(document: GenUIDocument, state: GenUIState? = nil) {
        self.document = document
        _state = ObservedObject(wrappedValue: state ?? GenUIState(document: document))
    }

    private var values: [String: Double] {
        get { state.values }
        nonmutating set { state.values = newValue }
    }
    private var texts: [String: String] {
        get { state.texts }
        nonmutating set { state.texts = newValue }
    }
    private var numberDrafts: [String: String] {
        get { state.numberDrafts }
        nonmutating set { state.numberDrafts = newValue }
    }

    private var compact: Bool { sizeClass != .regular }
    private var primaryComponent: GenUIComponent? {
        document.components.first { $0.kind == "metric" || $0.kind == "cards" }
    }
    private var firstChart: GenUIComponent? { document.components.first { $0.kind == "chart" } }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            if let primary = primaryComponent { componentView(primary) }
            if !document.inputs.isEmpty {
                Picker(L10n.text("表示"), selection: $state.showsInputs) {
                    Text(L10n.text("結果")).tag(false)
                    Text(L10n.text("条件")).tag(true)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("genui-section-picker")
            }
            if state.showsInputs && !document.inputs.isEmpty {
                VStack(alignment: .leading, spacing: compact ? 8 : 16) {
                    ForEach(document.inputs, id: \.id) { input in inputView(input) }
                }
                .padding(compact ? 10 : 16)
                .background(Color.amoledSubtleSurface(lightOpacity: 0.035), in: RoundedRectangle(cornerRadius: 12))
            } else {
                ForEach(document.components.filter { $0.id != primaryComponent?.id }, id: \.id) { component in
                    if component.id == firstChart?.id || document.components.count == 1 {
                        componentView(component)
                    } else {
                        DisclosureGroup {
                            componentView(component, showsTitle: false).padding(.top, 8)
                        } label: {
                            Text(render(component.title ?? componentLabel(component.kind)))
                                .font(.subheadline.weight(.medium))
                        }
                    }
                }
            }
        }
        .padding(.vertical, compact ? 12 : 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .amoledSystemBackground))
        .tint(.primary)
    }

    private func componentLabel(_ kind: String) -> String {
        switch kind {
        case "table": return L10n.text("表")
        case "chart": return L10n.text("グラフ")
        case "cards", "metric": return L10n.text("詳細")
        default: return L10n.text("補足")
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(render(document.title)).font(.title3.weight(.bold)).fixedSize(horizontal: false, vertical: true)
                if let subtitle = document.subtitle {
                    Text(render(subtitle)).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            if !document.inputs.isEmpty {
                Button(action: reset) { Image(systemName: "arrow.counterclockwise").frame(width: 44, height: 44) }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                    .accessibilityLabel(L10n.text("条件をリセット"))
                    .accessibilityIdentifier("genui-reset")
            }
        }
    }

    @ViewBuilder private func inputView(_ input: GenUIInput) -> some View {
        switch input.kind {
        case "slider":
            VStack(alignment: .leading, spacing: compact ? 2 : 8) {
                ViewThatFits(in: .horizontal) {
                    HStack { Text(input.label); Spacer(); Text(inputValue(input)).fontWeight(.semibold).monospacedDigit() }
                    VStack(alignment: .leading) { Text(input.label); Text(inputValue(input)).fontWeight(.semibold).monospacedDigit() }
                }
                let lower = input.min ?? 0
                let upper = max(input.max ?? 100, lower + 0.0001)
                Slider(value: numericBinding(input, range: lower...upper), in: lower...upper, step: max(input.step ?? 1, 0.0001))
                    .frame(minHeight: 44)
                    .accessibilityLabel(input.label).accessibilityValue(inputValue(input))
                    .accessibilityIdentifier("genui-slider-\(input.id)")
                if !compact {
                    HStack { Text(number(lower)); Spacer(); Text(number(upper)) }.font(.caption).foregroundStyle(.secondary)
                }
            }
        case "toggle":
            Toggle(input.label, isOn: Binding(get: { (values[input.id] ?? 0) != 0 }, set: { values[input.id] = $0 ? 1 : 0 }))
                .frame(minHeight: 44)
        case "select":
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { Text(input.label).font(.subheadline); Spacer(minLength: 0); selectionEditor(input) }
                VStack(alignment: .leading, spacing: 4) { Text(input.label).font(.subheadline); selectionEditor(input) }
            }
        case "number":
            VStack(alignment: .leading, spacing: 4) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { Text(input.label).font(.subheadline); Spacer(minLength: 0); numberEditor(input) }
                    VStack(alignment: .leading, spacing: 4) { Text(input.label).font(.subheadline); numberEditor(input) }
                }
                if validNumber(numberDrafts[input.id] ?? "", input: input) == nil {
                    Text(numberHint(input)).font(.caption).foregroundStyle(.secondary)
                        .accessibilityLabel(numberHint(input))
                }
            }
        default:
            VStack(alignment: .leading, spacing: 6) {
                Text(input.label).font(.subheadline)
                TextField(input.label, text: Binding(get: { texts[input.id] ?? "" }, set: { texts[input.id] = $0 }))
                    .textFieldStyle(.roundedBorder).frame(minHeight: 44).accessibilityLabel(input.label)
            }
        }
    }

    private func selectionEditor(_ input: GenUIInput) -> some View {
        Picker(input.label, selection: numericBinding(input)) {
            ForEach(input.options ?? [], id: \.value) { option in Text(option.label).tag(option.value) }
        }
        .pickerStyle(.menu).frame(minHeight: 44)
        .background(Color.amoledSubtleSurface(lightOpacity: 0.045), in: RoundedRectangle(cornerRadius: 8))
    }

    private func numberEditor(_ input: GenUIInput) -> some View {
        HStack(spacing: 4) {
            TextField(input.label, text: Binding(get: { numberDrafts[input.id] ?? "" }, set: { draft in
                numberDrafts[input.id] = draft
                if let value = validNumber(draft, input: input) { values[input.id] = value }
            }))
            .keyboardType(.numbersAndPunctuation).accessibilityLabel(input.label)
            .multilineTextAlignment(.trailing).frame(minWidth: 80, maxWidth: 140)
            if let unit = input.unit { Text(unit).font(.subheadline).foregroundStyle(.secondary) }
        }.padding(.horizontal, 8).frame(minHeight: 44)
            .background(Color.amoledSubtleSurface(lightOpacity: 0.045), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder private func componentView(_ component: GenUIComponent, showsTitle: Bool = true) -> some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 12) {
            if showsTitle, let title = component.title { Text(render(title)).font(.headline).fixedSize(horizontal: false, vertical: true) }
            switch component.kind {
            case "metric":
                VStack(alignment: .leading, spacing: 6) {
                    Text(formatted(component.value ?? "—", format: component.format, unit: component.unit))
                        .font(.system(compact ? .title : .largeTitle).weight(.semibold)).foregroundStyle(.primary)
                        .contentTransition(.numericText()).minimumScaleFactor(0.65)
                        .accessibilityIdentifier("genui-metric-\(component.id)")
                    if let text = component.text { Text(render(text)).font(.subheadline).foregroundStyle(.secondary) }
                }.frame(maxWidth: .infinity, alignment: .leading)
            case "table": table(component).accessibilityIdentifier("genui-component-\(component.id)")
            case "chart": chart(component).accessibilityIdentifier("genui-component-\(component.id)")
            case "cards":
                LazyVGrid(columns: [GridItem(.adaptive(minimum: dynamicType.isAccessibilitySize ? 240 : 120), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(Array((component.items ?? []).enumerated()), id: \.offset) { _, item in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(render(item.title)).font(.subheadline).foregroundStyle(.secondary)
                            Text(render(item.value)).font(.title2.weight(.semibold)).monospacedDigit()
                            if let detail = item.detail {
                                DisclosureGroup(L10n.text("前提")) { Text(render(detail)).font(.caption).foregroundStyle(.secondary) }
                                    .font(.caption)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(compact ? 10 : 14)
                            .background(Color.amoledSubtleSurface(lightOpacity: 0.04), in: RoundedRectangle(cornerRadius: 14))
                    }
                }
            default:
                Text(render(component.text ?? component.value ?? ""))
                    .font(.body).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func table(_ component: GenUIComponent) -> some View {
        ScrollView(.horizontal) {
            Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 0) {
                if let columns = component.columns {
                    GridRow { ForEach(Array(columns.enumerated()), id: \.offset) { _, column in
                        Text(render(column)).font(.subheadline.weight(.semibold)).padding(.vertical, compact ? 8 : 12)
                    } }
                    Divider().gridCellUnsizedAxes(.horizontal)
                }
                ForEach(Array((component.rows ?? []).enumerated()), id: \.offset) { index, row in
                    GridRow { ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                        Text(render(cell)).font(.subheadline).monospacedDigit().padding(.vertical, compact ? 8 : 12)
                            .frame(minWidth: 80, alignment: .leading)
                    } }.background(index.isMultiple(of: 2) ? Color.amoledSubtleSurface(lightOpacity: 0.025) : .clear)
                }
            }.padding(.horizontal, 12)
        }.background(Color.amoledSubtleSurface(lightOpacity: 0.025), in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func chart(_ component: GenUIComponent) -> some View {
        if component.resolvedChartType == "pie" {
            if let amounts = component.pieValues(values: values), let series = component.series?.first {
                Chart {
                    ForEach(Array(series.points.enumerated()), id: \.offset) { index, point in
                        SectorMark(angle: .value(L10n.text("値"), amounts[index]))
                            .foregroundStyle(by: .value(L10n.text("項目"), render(point.label)))
                    }
                }
                .chartForegroundStyleScale(range: [Color.blue, Color.green, Color.purple, Color.orange, Color.pink, Color.yellow])
                .chartLegend(position: .bottom, alignment: .leading)
                .frame(height: compact ? 200 : 260)
                .accessibilityLabel(render(component.title ?? L10n.text("グラフ")))
                .accessibilityValue(chartSummary(component))
            } else {
                Text(L10n.text("—"))
                    .accessibilityValue("Pie chart requires nonnegative values with a positive total")
            }
        } else {
            lineChart(component)
        }
    }

    private func lineChart(_ component: GenUIComponent) -> some View {
        Chart {
            ForEach(Array((component.series ?? []).enumerated()), id: \.offset) { _, series in
                ForEach(Array(series.points.enumerated()), id: \.offset) { _, point in
                    if let value = chartNumber(point.value) {
                        LineMark(x: .value(L10n.text("項目"), render(point.label)), y: .value(L10n.text("値"), value))
                            .foregroundStyle(by: .value(L10n.text("系列"), series.name))
                        PointMark(x: .value(L10n.text("項目"), render(point.label)), y: .value(L10n.text("値"), value))
                            .foregroundStyle(by: .value(L10n.text("系列"), series.name))
                    }
                }
            }
        }
        .chartForegroundStyleScale(range: [Color.blue, Color.green, Color.purple, Color.orange])
        .chartLegend(position: .bottom, alignment: .leading)
        .frame(height: compact ? 160 : 220)
        .accessibilityLabel(render(component.title ?? L10n.text("グラフ")))
        .accessibilityValue(chartSummary(component))
    }

    private func numericBinding(_ input: GenUIInput, range: ClosedRange<Double>? = nil) -> Binding<Double> {
        Binding(get: {
            let value = values[input.id] ?? input.value ?? 0
            return range.map { min(max(value, $0.lowerBound), $0.upperBound) } ?? value
        }, set: { values[input.id] = $0 })
    }

    private func render(_ string: String) -> String {
        if string.hasPrefix("="), let value = try? GenUIExpression.evaluate(string, values: values), value.isFinite {
            return number(value)
        }
        return document.render(string, values: values, texts: texts)
    }
    private func number(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(0...2))) }
    private func inputValue(_ input: GenUIInput) -> String { number(values[input.id] ?? 0) + (input.unit.map { " " + $0 } ?? "") }
    private func numeric(_ string: String) -> Double? {
        let result: Double?
        if string.hasPrefix("=") {
            result = try? GenUIExpression.evaluate(string, values: values)
        } else {
            let rendered = render(string)
            let formatter = NumberFormatter()
            formatter.locale = .current
            formatter.numberStyle = .decimal
            result = Double(rendered) ?? formatter.number(from: rendered)?.doubleValue
        }
        return result.flatMap { $0.isFinite ? $0 : nil }
    }
    private func formatted(_ string: String, format: String?, unit: String?) -> String {
        guard let value = numeric(string) else { return render(string) }
        let amount = format == "currency" ? value.formatted(.number.precision(.fractionLength(0))) : number(value)
        let suffix = unit ?? (format == "percent" ? "%" : "")
        return amount + (suffix.isEmpty ? "" : " " + suffix)
    }
    private func validNumber(_ draft: String, input: GenUIInput) -> Double? {
        guard let value = Double(draft), value.isFinite,
              input.min.map({ value >= $0 }) ?? true,
              input.max.map({ value <= $0 }) ?? true else { return nil }
        return value
    }
    private func numberHint(_ input: GenUIInput) -> String {
        if let lower = input.min, let upper = input.max {
            return L10n.format("%@〜%@の数値を入力してください", number(lower), number(upper))
        }
        if let lower = input.min { return L10n.format("%@以上の数値を入力してください", number(lower)) }
        if let upper = input.max { return L10n.format("%@以下の数値を入力してください", number(upper)) }
        return L10n.text("有効な数値を入力してください")
    }
    private func chartNumber(_ string: String) -> Double? {
        guard let value = numeric(string), abs(value) <= 1e100 else { return nil }
        return value
    }
    private func chartSummary(_ component: GenUIComponent) -> String {
        (component.series ?? []).map { series in
            let points = series.points.map { point in
                render(point.label) + ": " + (chartNumber(point.value).map(number) ?? "—")
            }.joined(separator: ", ")
            return render(series.name) + ": " + points
        }.joined(separator: ". ")
    }
    private func reset() {
        for input in document.inputs {
            let value = input.value ?? input.min ?? 0
            values[input.id] = value
            texts[input.id] = input.text ?? ""
            numberDrafts[input.id] = String(value)
        }
    }
}

#Preview("Loan calculator") {
    let json = #"""
    {
      "title": "住宅ローンの目安",
      "subtitle": "借入額と返済期間を変えて、月々の返済を比較できます。",
      "inputs": [
        {"id":"principal","label":"借入額","kind":"slider","value":30000000,"min":10000000,"max":60000000,"step":1000000,"unit":"円"},
        {"id":"years","label":"返済期間","kind":"number","value":35,"min":1,"max":50,"unit":"年"}
      ],
      "components": [
        {"id":"monthly","kind":"metric","title":"月々の元金返済","value":"=principal / years / 12","format":"currency","unit":"円","text":"金利・諸費用を除く概算です。"},
        {"id":"compare","kind":"chart","title":"返済期間ごとの比較","series":[{"name":"月々の元金","points":[{"label":"20年","value":"=principal / 20 / 12"},{"label":"25年","value":"=principal / 25 / 12"},{"label":"30年","value":"=principal / 30 / 12"},{"label":"35年","value":"=principal / 35 / 12"}]}]}
      ]
    }
    """#
    if let document = try? GenUIDocument.validated(from: json) {
        ScrollView { GenUIView(document: document).padding() }
    }
}

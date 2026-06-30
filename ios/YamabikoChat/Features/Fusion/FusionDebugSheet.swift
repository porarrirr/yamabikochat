import SwiftUI

struct FusionDebugSheet: View {
    let trace: FusionTrace
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section(L10n.text("概要")) {
                    LabeledContent(L10n.text("Trace ID"), value: trace.requestId)
                    LabeledContent(L10n.text("Preset"), value: trace.preset)
                    LabeledContent(L10n.text("Status"), value: trace.status)
                    if let latency = trace.totalLatencyMs {
                        LabeledContent(L10n.text("Latency"), value: "\(latency) ms")
                    }
                    if let cost = trace.totalCost {
                        LabeledContent(L10n.text("Cost"), value: String(format: "$%.4f", cost))
                    }
                }

                Section(L10n.text("Panel outputs")) {
                    ForEach(Array(trace.panelResults.enumerated()), id: \.offset) { _, panel in
                        VStack(alignment: .leading, spacing: 6) {
                            Text("\(panel.modelId) · \(panel.success ? "OK" : "FAIL")")
                                .font(.headline)
                            if let error = panel.error {
                                Text(error).font(.caption).foregroundStyle(.red)
                            }
                            if !panel.content.isEmpty {
                                Text(panel.content)
                                    .font(.caption)
                                    .textSelection(.enabled)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                if let judge = trace.judgeResult {
                    Section(L10n.text("Judge")) {
                        LabeledContent(
                            L10n.text("Parse"),
                            value: judge.parseSucceeded ? "OK" : "FAIL"
                        )
                        if let analysis = judge.analysis,
                           let json = encodeJSON(analysis) {
                            Text(json)
                                .font(.caption)
                                .textSelection(.enabled)
                        } else if let raw = judge.rawJSON {
                            Text(raw)
                                .font(.caption)
                                .textSelection(.enabled)
                        }
                    }
                }

                if let finalAnswer = trace.finalAnswer {
                    Section(L10n.text("Final answer")) {
                        Text(finalAnswer)
                            .font(.caption)
                            .textSelection(.enabled)
                    }
                }
            }
            .navigationTitle(L10n.text("Fusion Debug"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.text("閉じる")) { dismiss() }
                }
            }
        }
    }

    private func encodeJSON<T: Encodable>(_ value: T) -> String? {
        guard let data = try? JSONEncoder().encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
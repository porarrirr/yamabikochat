import SwiftUI

struct FusionDetailSheet: View {
    let trace: FusionTrace
    var debugModeEnabled: Bool = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                overviewSection
                pipelineSection
                panelSection

                if let judge = trace.judgeResult {
                    judgeSection(judge)
                }

                if let synthesis = trace.synthesisResult {
                    synthesisSection(synthesis)
                }

                if debugModeEnabled {
                    developerSection
                }
            }
            .navigationTitle(L10n.text("Fusion 詳細"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.text("閉じる")) { dismiss() }
                }
            }
        }
    }

    private var overviewSection: some View {
        Section(L10n.text("概要")) {
            LabeledContent(L10n.text("Preset"), value: trace.preset)
            LabeledContent(L10n.text("Status"), value: trace.status)
            if let latency = trace.totalLatencyMs {
                LabeledContent(L10n.text("Latency"), value: FusionTracePresentation.formatLatency(ms: latency))
            }
            if let cost = FusionTracePresentation.formatCost(trace.totalCost) {
                LabeledContent(L10n.text("Cost"), value: cost)
            }
            if !trace.failedModels.isEmpty {
                LabeledContent(
                    L10n.text("Failed models"),
                    value: trace.failedModels
                        .map { FusionTracePresentation.shortModelLabel($0) }
                        .joined(separator: ", ")
                )
            }
        }
    }

    private var pipelineSection: some View {
        Section(L10n.text("パイプライン")) {
            pipelineRow(
                phase: .panel,
                latencyMs: trace.panelResults.map(\.latencyMs).max(),
                detail: L10n.format(
                    "%d/%d OK",
                    trace.panelResults.filter(\.success).count,
                    trace.panelResults.count
                )
            )
            if let judge = trace.judgeResult {
                pipelineRow(
                    phase: .judge,
                    latencyMs: judge.latencyMs,
                    detail: judge.parseSucceeded ? "OK" : "FAIL"
                )
            }
            if let synthesis = trace.synthesisResult {
                pipelineRow(
                    phase: .synthesizer,
                    latencyMs: synthesis.latencyMs,
                    detail: FusionTracePresentation.shortModelLabel(synthesis.modelId)
                )
            }
        }
    }

    private func pipelineRow(phase: FusionPhase, latencyMs: Int64?, detail: String) -> some View {
        HStack {
            Text(FusionTracePresentation.phaseLabel(phase))
                .font(.subheadline.weight(.semibold))
            Spacer()
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
            if let latencyMs {
                Text(FusionTracePresentation.formatLatency(ms: latencyMs))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var panelSection: some View {
        Section(L10n.text("Panel outputs")) {
            ForEach(Array(trace.panelResults.enumerated()), id: \.offset) { _, panel in
                DisclosureGroup {
                    if let error = panel.error {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    if !panel.content.isEmpty {
                        Text(panel.content)
                            .font(.caption)
                            .textSelection(.enabled)
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(FusionTracePresentation.shortModelLabel(panel.modelId))
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Text(panel.success ? "OK" : "FAIL")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(panel.success ? .green : .red)
                        }
                        HStack(spacing: 8) {
                            Text(FusionTracePresentation.formatLatency(ms: panel.latencyMs))
                            if let tokens = FusionTracePresentation.formatTokens(
                                input: panel.inputTokens,
                                output: panel.outputTokens
                            ) {
                                Text(tokens)
                            }
                            if let cost = FusionTracePresentation.formatCost(panel.cost) {
                                Text(cost)
                            }
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func judgeSection(_ judge: JudgePhaseResult) -> some View {
        Section(L10n.text("Judge")) {
            LabeledContent(
                L10n.text("Parse"),
                value: judge.parseSucceeded ? "OK" : "FAIL"
            )
            if let latency = judge.latencyMs as Int64? {
                LabeledContent(
                    L10n.text("Latency"),
                    value: FusionTracePresentation.formatLatency(ms: latency)
                )
            }
            if let tokens = FusionTracePresentation.formatTokens(
                input: judge.inputTokens,
                output: judge.outputTokens
            ) {
                LabeledContent(L10n.text("Tokens"), value: tokens)
            }
            if let cost = FusionTracePresentation.formatCost(judge.cost) {
                LabeledContent(L10n.text("Cost"), value: cost)
            }
            if let analysis = judge.analysis, JudgeAnalysisPresentation.hasVisibleContent(analysis) {
                JudgeAnalysisView(analysis: analysis)
                    .padding(.vertical, 4)
            } else if let error = judge.error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder
    private func synthesisSection(_ synthesis: SynthesisPhaseResult) -> some View {
        Section(L10n.text("合成")) {
            LabeledContent(
                L10n.text("Model"),
                value: FusionTracePresentation.shortModelLabel(synthesis.modelId)
            )
            LabeledContent(
                L10n.text("Status"),
                value: synthesis.success ? "OK" : "FAIL"
            )
            LabeledContent(
                L10n.text("Latency"),
                value: FusionTracePresentation.formatLatency(ms: synthesis.latencyMs)
            )
            if let tokens = FusionTracePresentation.formatTokens(
                input: synthesis.inputTokens,
                output: synthesis.outputTokens
            ) {
                LabeledContent(L10n.text("Tokens"), value: tokens)
            }
            if let cost = FusionTracePresentation.formatCost(synthesis.cost) {
                LabeledContent(L10n.text("Cost"), value: cost)
            }
            if let error = synthesis.error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder
    private var developerSection: some View {
        Section(L10n.text("開発者向け")) {
            LabeledContent(L10n.text("Trace ID"), value: trace.requestId)
            if let userPrompt = trace.userPrompt {
                DisclosureGroup(L10n.text("User prompt")) {
                    Text(userPrompt)
                        .font(.caption)
                        .textSelection(.enabled)
                }
            }
            if let finalAnswer = trace.finalAnswer {
                DisclosureGroup(L10n.text("Final answer (logged)")) {
                    Text(finalAnswer)
                        .font(.caption)
                        .textSelection(.enabled)
                }
            }
            if let rawJSON = trace.judgeResult?.rawJSON {
                DisclosureGroup(L10n.text("Judge raw JSON")) {
                    Text(rawJSON)
                        .font(.caption)
                        .textSelection(.enabled)
                }
            }
        }
    }
}

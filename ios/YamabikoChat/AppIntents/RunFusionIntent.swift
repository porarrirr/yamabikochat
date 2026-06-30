import AppIntents
import Foundation

struct RunFusionIntent: AppIntent {
    static var title: LocalizedStringResource = "Fusion に聞く"
    static var description = IntentDescription("Run Fusion multi-model orchestration")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Prompt")
    var prompt: String

    @Parameter(title: "Debug", default: false)
    var debug: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("Fusion: \(\.$prompt)")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else {
            throw FusionError.invalidPreset(L10n.text("プロンプトが空です。"))
        }

        let result = try await AppServices.shared.fusionService.runFusion(
            userPrompt: trimmedPrompt,
            options: FusionRunOptions(
                debugMode: debug,
                logPrompts: debug
            )
        )

        if debug {
            var lines = [result.finalAnswer, "", "--- Debug ---", "traceId: \(result.traceId)"]
            if let latency = result.totalLatencyMs {
                lines.append("latencyMs: \(latency)")
            }
            if let cost = result.totalCost {
                lines.append(String(format: "costUsd: %.6f", cost))
            }
            if let panels = result.rawPanelResults {
                for panel in panels {
                    lines.append("[\(panel.modelId)] \(panel.success ? "ok" : "fail"): \(panel.content.prefix(200))")
                }
            }
            if let judge = result.judgeAnalysis?.recommendedFinalPosition {
                lines.append("judge position: \(judge)")
            }
            return .result(value: lines.joined(separator: "\n"))
        }

        return .result(value: result.finalAnswer)
    }
}
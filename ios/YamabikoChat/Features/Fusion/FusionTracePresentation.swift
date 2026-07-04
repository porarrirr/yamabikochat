import Foundation

enum FusionTracePresentation {
    static func shortModelLabel(_ model: String) -> String {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }
        if let slash = trimmed.lastIndex(of: "/") {
            return String(trimmed[trimmed.index(after: slash)...])
        }
        if trimmed.count > 24 {
            return String(trimmed.prefix(22)) + "…"
        }
        return trimmed
    }

    static func confidenceLabel(_ confidence: FusionConfidence) -> String {
        switch confidence {
        case .low:
            return L10n.text("低信頼")
        case .medium:
            return L10n.text("中信頼")
        case .high:
            return L10n.text("高信頼")
        }
    }

    static func phaseLabel(_ phase: FusionPhase) -> String {
        switch phase {
        case .panel:
            return L10n.text("パネル")
        case .judge:
            return L10n.text("ジャッジ")
        case .synthesizer:
            return L10n.text("合成")
        case .fallback:
            return L10n.text("フォールバック")
        }
    }

    static func progressPhaseTitle(_ snapshot: FusionProgressSnapshot) -> String {
        switch snapshot.phase {
        case .panel:
            return L10n.format(
                "パネル実行中 (%d/%d)",
                snapshot.completedPanelCount,
                snapshot.totalPanelCount
            )
        case .judge:
            return L10n.text("ジャッジ中")
        case .synthesizer:
            return L10n.text("回答を合成中")
        case .fallback:
            return L10n.text("フォールバックで回答中")
        }
    }

    static func summaryLine(for trace: FusionTrace) -> String {
        let successCount = trace.panelResults.filter(\.success).count
        let totalPanels = trace.panelResults.count
        var parts = [
            L10n.format("Fusion · %d/%d panels", successCount, totalPanels)
        ]
        if let analysis = trace.judgeResult?.analysis {
            parts.append(confidenceLabel(analysis.confidence))
        }
        if let latencyMs = trace.totalLatencyMs {
            parts.append(formatLatency(ms: latencyMs))
        }
        if let cost = trace.totalCost {
            parts.append(String(format: "$%.4f", cost))
        }
        return parts.joined(separator: " · ")
    }

    static func formatLatency(ms: Int64) -> String {
        if ms < 1_000 {
            return L10n.format("%d ms", ms)
        }
        let seconds = Double(ms) / 1_000.0
        return L10n.format("%.1f s", seconds)
    }

    static func formatCost(_ cost: Double?) -> String? {
        guard let cost else { return nil }
        return String(format: "$%.4f", cost)
    }

    static func formatTokens(input: Int?, output: Int?) -> String? {
        guard input != nil || output != nil else { return nil }
        let inputValue = input ?? 0
        let outputValue = output ?? 0
        return L10n.format("%d in / %d out", inputValue, outputValue)
    }
}
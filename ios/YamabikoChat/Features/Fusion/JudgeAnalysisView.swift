import SwiftUI

struct JudgeAnalysisView: View {
    let analysis: JudgeAnalysis

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L10n.text("信頼度"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(FusionTracePresentation.confidenceLabel(analysis.confidence))
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(confidenceColor.opacity(0.15))
                    .foregroundStyle(confidenceColor)
                    .clipShape(Capsule())
            }

            if !analysis.recommendedFinalPosition.isEmpty {
                analysisSection(title: L10n.text("推奨方針")) {
                    Text(analysis.recommendedFinalPosition)
                        .font(.caption)
                        .textSelection(.enabled)
                }
            }

            if !analysis.consensus.isEmpty {
                analysisSection(title: L10n.text("合意点")) {
                    bulletList(analysis.consensus)
                }
            }

            if !analysis.contradictions.isEmpty {
                analysisSection(title: L10n.text("矛盾点")) {
                    ForEach(Array(analysis.contradictions.enumerated()), id: \.offset) { _, item in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.topic)
                                .font(.caption.weight(.semibold))
                            if !item.positions.isEmpty {
                                bulletList(item.positions)
                            }
                            if !item.likelyResolution.isEmpty {
                                Text(item.likelyResolution)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            let insights = analysis.uniqueInsights.filter(\.useInFinal)
            if !insights.isEmpty {
                analysisSection(title: L10n.text("独自の洞察")) {
                    ForEach(Array(insights.enumerated()), id: \.offset) { _, item in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(FusionTracePresentation.shortModelLabel(item.model))
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(item.insight)
                                .font(.caption)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            if !analysis.coverageGaps.isEmpty {
                analysisSection(title: L10n.text("不足点")) {
                    bulletList(analysis.coverageGaps)
                }
            }

            if !analysis.suspectedErrors.isEmpty {
                analysisSection(title: L10n.text("疑わしい点")) {
                    ForEach(Array(analysis.suspectedErrors.enumerated()), id: \.offset) { _, item in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(FusionTracePresentation.shortModelLabel(item.model))
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(item.claim)
                                .font(.caption)
                            Text(item.reason)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            if let notes = analysis.notes?.trimmingCharacters(in: .whitespacesAndNewlines),
               !notes.isEmpty {
                analysisSection(title: L10n.text("メモ")) {
                    Text(notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var confidenceColor: Color {
        switch analysis.confidence {
        case .low:
            return .orange
        case .medium:
            return .blue
        case .high:
            return .green
        }
    }

    @ViewBuilder
    private func analysisSection<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func bulletList(_ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .top, spacing: 6) {
                    Text("•")
                    Text(item)
                        .font(.caption)
                        .textSelection(.enabled)
                }
            }
        }
    }
}

enum JudgeAnalysisPresentation {
    static func hasVisibleContent(_ analysis: JudgeAnalysis?) -> Bool {
        guard let analysis else { return false }
        return !analysis.recommendedFinalPosition.isEmpty
            || !analysis.consensus.isEmpty
            || !analysis.contradictions.isEmpty
            || analysis.uniqueInsights.contains(where: \.useInFinal)
            || !analysis.coverageGaps.isEmpty
            || !analysis.suspectedErrors.isEmpty
            || !(analysis.notes?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }
}
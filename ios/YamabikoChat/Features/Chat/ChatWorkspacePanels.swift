import SwiftUI
import UIKit

struct ChatEmptyState: View {
    let title: String
    let systemImage: String
    let description: String

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 56, height: 56)
                .background(Color(uiColor: .secondarySystemBackground), in: Circle())
            Text(title)
                .font(.title3.weight(.semibold))
            Text(description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .padding(32)
        .accessibilityElement(children: .combine)
    }
}

struct ChatWorkspaceRouteSheet: View {
    let route: ChatWorkspaceRoute

    var body: some View {
        switch route {
        case let .runInspector(_, steps):
            ChatRunInspector(steps: steps)
        case let .thinkingInspector(_, text):
            ChatThinkingInspector(text: text)
        case let .fusionInspector(_, trace, debugModeEnabled):
            FusionDetailSheet(trace: trace, debugModeEnabled: debugModeEnabled)
        case let .artifactViewer(_, block):
            ChatArtifactViewer(block: block)
        case let .mermaidViewer(_, source):
            MermaidDiagramViewer(source: source)
        case .modelPicker, .modePicker:
            EmptyView()
        }
    }
}

private struct MermaidDiagramViewer: View {
    let source: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            MermaidDiagramView(source: source, expanded: true)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle("Mermaid")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button {
                            UIPasteboard.general.string = source
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .accessibilityLabel(Text(L10n.text("コピー")))

                        Button(L10n.text("閉じる")) { dismiss() }
                    }
                }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}

private struct ChatRunInspector: View {
    let steps: [ToolActivityStep]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(steps) { step in
                    Section {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 8) {
                                statusIcon(step.status)
                                Text(step.title)
                                    .font(.headline)
                                Spacer()
                                if let duration = step.durationMs {
                                    Text(String(format: "%.1fs", Double(duration) / 1_000))
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                            }

                            if let detail = step.detail.trimmedNonEmpty {
                                Text(detail)
                                    .font(.subheadline)
                                    .textSelection(.enabled)
                            }
                            if let preview = step.resultPreview?.trimmedNonEmpty ?? step.outputPreview?.trimmedNonEmpty {
                                Text(preview)
                                    .font(.system(.caption, design: .monospaced))
                                    .textSelection(.enabled)
                                    .padding(10)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                            }
                            if let error = step.errorMessage?.trimmedNonEmpty {
                                Text(error)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                                    .textSelection(.enabled)
                            }

                            ForEach(step.sources) { source in
                                if let url = URL(string: source.url) {
                                    Link(destination: url) {
                                        HStack(spacing: 8) {
                                            Image(systemName: "link")
                                            Text(source.title.trimmedNonEmpty ?? source.url)
                                                .lineLimit(2)
                                            Spacer()
                                            Image(systemName: "arrow.up.right")
                                                .font(.caption)
                                        }
                                        .font(.subheadline)
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    } header: {
                        Text(step.isWebActivity ? L10n.text("Web検索") : step.toolName)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(L10n.text("実行の詳細"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.text("閉じる")) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private func statusIcon(_ status: ToolActivityStep.Status) -> some View {
        switch status {
        case .running:
            ProgressView().controlSize(.small)
        case .completed:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.red)
        }
    }
}

private struct ChatThinkingInspector: View {
    let text: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ThinkingStreamTextView(text: text)
                .padding(16)
                .navigationTitle(L10n.text("Thinking"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(L10n.text("閉じる")) { dismiss() }
                    }
                }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

private struct ChatArtifactViewer: View {
    let block: ChatArtifactBlock
    @Environment(\.dismiss) private var dismiss
    @State private var htmlTitle = ""
    @State private var svgError: String?

    var body: some View {
        NavigationStack {
            Group {
                switch block {
                case let .html(content):
                    HtmlPreviewWebView(html: content, pageTitle: $htmlTitle)
                case let .svg(content):
                    if let svgError {
                        ContentUnavailableView(
                            L10n.text("プレビューを表示できません"),
                            systemImage: "exclamationmark.triangle",
                            description: Text(svgError)
                        )
                    } else {
                        SvgPreviewWebView(svgContent: content) { svgError = $0 }
                            .padding(16)
                    }
                }
            }
            .navigationTitle(block.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.text("閉じる")) { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}

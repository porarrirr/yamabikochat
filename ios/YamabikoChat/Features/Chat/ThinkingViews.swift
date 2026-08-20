import SwiftUI

/// Plain-text thinking panel for streaming updates (avoids WebView reload flicker).
struct ThinkingStreamTextView: View {
    let text: String
    private let bottomAnchorID = "thinking-stream-bottom"

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Text(text)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .id(bottomAnchorID)
            }
            .onChange(of: text) { oldValue, newValue in
                guard newValue.count >= oldValue.count else { return }
                proxy.scrollTo(bottomAnchorID, anchor: .bottom)
            }
            .onAppear {
                proxy.scrollTo(bottomAnchorID, anchor: .bottom)
            }
        }
    }
}

struct ThinkingSheet: View {
    let thinkingText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "brain.head.profile")
                Text("Thinking")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 10)

            Divider()

            ThinkingStreamTextView(text: thinkingText)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

struct ToolActivityDisclosure: View {
    let steps: [ToolActivityStep]
    @State private var isExpanded = false

    private var isRunning: Bool {
        steps.contains(where: { $0.status == .running })
    }

    private var currentStep: ToolActivityStep? {
        steps.last(where: { $0.status == .running })
    }

    private var hasFailure: Bool {
        steps.contains(where: { $0.status == .failed })
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(steps) { step in
                    HStack(alignment: .top, spacing: 9) {
                        statusView(for: step)
                            .frame(width: 18, height: 18)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(step.title)
                                .font(.caption.weight(.semibold))
                            Text(step.detail)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                                .textSelection(.enabled)
                            if let resultCount = step.resultCount {
                                Text(L10n.format("%d件の結果", resultCount))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            if let error = step.errorMessage?.trimmedNonEmpty {
                                Text(error)
                                    .font(.caption2)
                                    .foregroundStyle(.red)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }
                let sources = deduplicatedSources
                if !sources.isEmpty {
                    ToolSourcesView(sources: sources)
                }
            }
            .padding(.top, 8)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isRunning ? runningIcon : (hasFailure ? "exclamationmark.circle.fill" : "checkmark.circle.fill"))
                    .font(.caption)
                    .foregroundStyle(hasFailure && !isRunning ? Color.red : Color.secondary)
                if isRunning {
                    ProgressView()
                        .controlSize(.mini)
                    Text(runningLabel)
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.tail)
                } else {
                    Text(completedLabel)
                        .font(.caption)
                        .lineLimit(1)
                }
            }
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .accessibilityLabel(isRunning ? runningLabel : completedLabel)
    }

    private var hasPython: Bool { steps.contains { $0.toolName == PythonExecuteTool.name } }

    private var runningIcon: String {
        currentStep?.toolName == PythonExecuteTool.name ? "chevron.left.forwardslash.chevron.right" : "globe"
    }

    private var completedLabel: String {
        hasPython ? L10n.format("ツール実行・%dステップ", steps.count) : L10n.format("Web検索・%dステップ", steps.count)
    }

    private var runningLabel: String {
        guard let currentStep else { return L10n.text("検索中") }
        let prefix = currentStep.toolName == PythonExecuteTool.name
            ? L10n.text("Pythonを実行中")
            : (currentStep.toolName == FetchUrlTool.name ? L10n.text("確認中") : L10n.text("検索中"))
        return "\(prefix)：\(currentStep.detail)"
    }

    private var deduplicatedSources: [ToolSource] {
        var seen: Set<String> = []
        return steps.flatMap(\.sources).filter { seen.insert($0.url).inserted }
    }

    @ViewBuilder
    private func statusView(for step: ToolActivityStep) -> some View {
        switch step.status {
        case .running:
            ProgressView()
                .controlSize(.small)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
        }
    }
}

struct ToolSourcesView: View {
    let sources: [ToolSource]

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(L10n.text("出典"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach(Array(sources.enumerated()), id: \.element.id) { index, source in
                if let url = URL(string: source.url) {
                    Link(destination: url) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("[\(index + 1)]")
                                .monospacedDigit()
                            Text(source.title.trimmedNonEmpty ?? source.url)
                                .lineLimit(2)
                            Image(systemName: "arrow.up.right.square")
                                .font(.caption2)
                        }
                        .font(.caption)
                    }
                }
            }
        }
        .padding(.top, 4)
    }
}

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

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            let webSteps = steps.filter(\.isWebActivity)
            let executionSteps = steps.filter { !$0.isWebActivity }
            if !webSteps.isEmpty {
                ToolActivitySectionDisclosure(kind: .web, steps: webSteps)
            }
            if !executionSteps.isEmpty {
                ToolActivitySectionDisclosure(kind: .execution, steps: executionSteps)
            }
        }
    }
}

private enum ToolActivitySectionKind: Equatable {
    case web
    case execution

    var title: String {
        switch self {
        case .web: L10n.text("Web検索")
        case .execution: L10n.text("ツール実行")
        }
    }

    var icon: String {
        switch self {
        case .web: "globe"
        case .execution: "terminal"
        }
    }

    var tint: Color {
        switch self {
        case .web: .blue
        case .execution: .purple
        }
    }
}

private struct ToolActivitySectionDisclosure: View {
    let kind: ToolActivitySectionKind
    let steps: [ToolActivityStep]
    @State private var isExpanded = false

    private var isRunning: Bool { steps.contains { $0.status == .running } }
    private var hasFailure: Bool { steps.contains { $0.status == .failed } }
    private var currentStep: ToolActivityStep? { steps.last { $0.status == .running } }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(steps) { step in
                    ToolActivityStepCard(kind: kind, step: step)
                }
                if kind == .web, !deduplicatedSources.isEmpty {
                    ToolSourcesView(sources: deduplicatedSources)
                        .padding(.horizontal, 4)
                }
            }
            .padding(.top, 8)
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(kind.tint.opacity(0.12))
                    if isRunning {
                        ProgressView()
                            .controlSize(.mini)
                            .tint(kind.tint)
                    } else {
                        Image(systemName: hasFailure ? "exclamationmark" : kind.icon)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(hasFailure ? Color.red : kind.tint)
                    }
                }
                .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 1) {
                    Text(kind.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(summary)
                        .font(.caption2)
                        .foregroundStyle(hasFailure && !isRunning ? Color.red : Color.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 3)
        .accessibilityLabel("\(kind.title), \(summary)")
    }

    private var summary: String {
        if let currentStep {
            return "\(L10n.text("実行中"))：\(currentStep.title)"
        }
        return L10n.format("%dステップ", steps.count)
    }

    private var deduplicatedSources: [ToolSource] {
        var seen: Set<String> = []
        return steps.flatMap(\.sources).filter { seen.insert($0.url).inserted }
    }
}

private struct ToolActivityStepCard: View {
    let kind: ToolActivitySectionKind
    let step: ToolActivityStep

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 7) {
                statusIcon
                    .frame(width: 17, height: 17)
                Text(step.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer(minLength: 4)
                if let duration = formattedDuration {
                    Text(duration)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
                statusBadge
            }

            if kind == .execution {
                ToolActivityValueBlock(
                    title: step.toolName == PythonExecuteTool.name ? L10n.text("コード") : L10n.text("入力"),
                    value: step.detail,
                    icon: step.toolName == PythonExecuteTool.name ? "chevron.left.forwardslash.chevron.right" : "slider.horizontal.3",
                    monospaced: true
                )
                if let result = step.resultPreview?.trimmedNonEmpty {
                    ToolActivityValueBlock(
                        title: L10n.text("結果"),
                        value: result,
                        icon: "return",
                        monospaced: true
                    )
                }
                if let output = step.outputPreview?.trimmedNonEmpty {
                    ToolActivityValueBlock(
                        title: L10n.text("出力"),
                        value: output,
                        icon: "text.alignleft",
                        monospaced: true
                    )
                }
                if let names = step.artifactNames, !names.isEmpty {
                    VStack(alignment: .leading, spacing: 5) {
                        Label(L10n.text("生成ファイル"), systemImage: "doc.badge.plus")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        ForEach(Array(names.enumerated()), id: \.offset) { _, name in
                            Label(name, systemImage: "doc")
                                .font(.caption2)
                                .lineLimit(1)
                                .foregroundStyle(.primary)
                        }
                    }
                }
            } else {
                Text(step.detail)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(4)
                    .textSelection(.enabled)
                if let resultCount = step.resultCount {
                    Label(L10n.format("%d件の結果", resultCount), systemImage: "list.bullet")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if let error = step.errorMessage?.trimmedNonEmpty {
                Label {
                    Text(error)
                        .textSelection(.enabled)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                .font(.caption2)
                .foregroundStyle(.red)
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch step.status {
        case .running:
            ProgressView().controlSize(.small)
        case .completed:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.red)
        }
    }

    private var statusBadge: some View {
        Text(statusText)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(statusColor)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(statusColor.opacity(0.11), in: Capsule())
    }

    private var statusText: String {
        switch step.status {
        case .running: L10n.text("実行中")
        case .completed: L10n.text("完了")
        case .failed: L10n.text("失敗")
        }
    }

    private var statusColor: Color {
        switch step.status {
        case .running: kind.tint
        case .completed: .green
        case .failed: .red
        }
    }

    private var formattedDuration: String? {
        guard let durationMs = step.durationMs else { return nil }
        if durationMs < 1_000 { return "\(durationMs) ms" }
        return String(format: "%.1f s", Double(durationMs) / 1_000)
    }
}

private struct ToolActivityValueBlock: View {
    let title: String
    let value: String
    let icon: String
    let monospaced: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: icon)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(monospaced ? .system(.caption2, design: .monospaced) : .caption2)
                .foregroundStyle(.primary)
                .lineLimit(10)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
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

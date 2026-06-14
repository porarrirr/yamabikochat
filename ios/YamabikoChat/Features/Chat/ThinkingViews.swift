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
            }
            .padding(.top, 8)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "globe")
                    .font(.caption)
                Text(L10n.text("Web検索"))
                    .font(.caption)
                if isRunning {
                    ProgressView()
                        .controlSize(.mini)
                } else {
                    Text(L10n.format("%dステップ", steps.count))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
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

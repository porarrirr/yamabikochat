import SwiftUI

struct SubagentFleetView: View {
    @Environment(\.appAccent) private var appAccent
    let runs: [SubagentRun]
    var onLayoutChange: () -> Void = {}
    @State private var expanded = false
    @State private var selection: String?
    @State private var showAll = false

    private var running: Int { runs.filter { $0.status == .running }.count }
    private var completed: Int { runs.filter { $0.status == .completed }.count }
    private var failed: Int { runs.count - running - completed }
    private var summary: String {
        [running > 0 ? "\(running)実行中" : nil, completed > 0 ? "\(completed)完了" : nil, failed > 0 ? "\(failed)中断・失敗" : nil]
            .compactMap { $0 }.joined(separator: " · ")
    }

    /// Pi sends snapshots for every parallel child in an interleaved stream.
    /// Showing the most recently updated child made this line alternate between
    /// "researcher 1", "researcher 2", ... on every token, so pin the first
    /// running child instead. It advances only after that child finishes.
    static func summaryRun(in runs: [SubagentRun]) -> SubagentRun? {
        runs.first { $0.status == .running }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                expanded.toggle()
                onLayoutChange()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "person.3.fill").font(.title3).foregroundStyle(.tint)
                        .frame(width: 34, height: 34)
                        .background(appAccent.color.opacity(0.10), in: Circle())
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text("\(runs.count) サブエージェント").font(.subheadline.weight(.semibold))
                            Spacer(minLength: 0)
                            Text(summary).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Text(Self.summaryRun(in: runs).map { "\($0.agent) · \($0.activity)" } ?? "結果と処理履歴を確認")
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                }
                .frame(minHeight: 44)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("subagent-fleet-summary")
            .accessibilityLabel("\(runs.count) サブエージェント、\(summary)")
            .accessibilityHint(expanded ? "一覧を折りたたむ" : "一覧を開く")

            if expanded {
                Divider().padding(.horizontal, 12)
                ForEach(Array(runs.prefix(3))) { run in
                    Button { selection = run.id } label: { SubagentRunRow(run: run) }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("subagent-row-\(run.id)")
                }
                if runs.count > 3 {
                    Button("すべて表示（\(runs.count)）") { showAll = true }
                        .font(.subheadline).frame(maxWidth: .infinity, minHeight: 44)
                }
            }
        }
        .background(Color(uiColor: .amoledSecondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.primary.opacity(0.06)))
        .sheet(isPresented: Binding(get: { selection != nil }, set: { if !$0 { selection = nil } })) {
            if let run = runs.first(where: { $0.id == selection }) {
                SubagentDetailSheet(run: run)
            }
        }
        .sheet(isPresented: $showAll) {
            NavigationStack {
                List(runs) { run in
                    NavigationLink(value: run.id) { SubagentRunRow(run: run) }
                }
                .navigationDestination(for: String.self) { id in
                    if let run = runs.first(where: { $0.id == id }) { SubagentDetailContent(run: run) }
                }
                .navigationTitle("サブエージェント")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("閉じる") { showAll = false } } }
            }
        }
    }
}

private struct SubagentRunRow: View {
    let run: SubagentRun

    var body: some View {
        HStack(spacing: 10) {
            SubagentStatusIcon(status: run.status)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(run.agent).font(.subheadline.weight(.medium)).lineLimit(1)
                Text(run.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? run.activity : String(run.output.suffix(160)))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.forward").font(.caption).foregroundStyle(.tertiary)
        }
        .frame(minHeight: 44)
        .padding(.horizontal, 14).padding(.vertical, 5)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

private struct SubagentStatusIcon: View {
    let status: SubagentRun.Status

    var body: some View {
        switch status {
        case .running: ProgressView().controlSize(.small).accessibilityLabel("実行中")
        case .completed: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).accessibilityLabel("完了")
        case .failed: Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange).accessibilityLabel("失敗")
        case .cancelled: Image(systemName: "stop.circle").foregroundStyle(.secondary).accessibilityLabel("中断")
        }
    }
}

private struct SubagentDetailSheet: View {
    let run: SubagentRun
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            SubagentDetailContent(run: run)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("閉じる") { dismiss() } } }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}

private struct SubagentDetailContent: View {
    let run: SubagentRun
    @State private var tab = 0
    @State private var route: ChatWorkspaceRoute?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        SubagentStatusIcon(status: run.status)
                        Text(run.activity).font(.subheadline.weight(.semibold))
                        Spacer()
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            let end = run.finishedAtMs ?? Int64(context.date.timeIntervalSince1970 * 1000)
                            Text(Duration.milliseconds(max(0, end - run.startedAtMs)).formatted(.time(pattern: .minuteSecond)))
                                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                    }
                    Text("\(run.provider) / \(run.model)").font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    HStack {
                        Text("Effort: \(AppleIntelligenceModelCatalog.effortDisplayName(run.effort, provider: run.provider, model: run.model))")
                        if let tokens = run.usage?.totalTokens { Text("· \(tokens) tokens") }
                    }.font(.caption).foregroundStyle(.secondary)
                }
                if let error = run.error, !error.isEmpty {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.callout).foregroundStyle(.orange).textSelection(.enabled)
                }
                Picker("表示内容", selection: $tab) {
                    Text("出力").tag(0)
                    Text("処理履歴（\(run.events.count)）").tag(1)
                }.pickerStyle(.segmented)
                if tab == 0 {
                    messageRow(role: "user", text: run.task)
                        .accessibilityIdentifier("subagent-prompt")
                    if let artifacts = run.artifacts, !artifacts.isEmpty {
                        MessageAttachmentList(attachments: artifacts.map { ChatAttachmentItem(rawValue: $0.path) }, isOutgoing: false)
                    }
                    if run.outputTruncated { Text("長い出力の末尾を表示しています。").font(.caption).foregroundStyle(.secondary) }
                    if run.output.isEmpty {
                        Label(run.status == .running ? "出力を待っています。処理履歴で現在の動作を確認できます。" : "テキスト出力はありません。処理履歴を確認してください。", systemImage: "text.bubble")
                            .font(.callout).foregroundStyle(.secondary).padding(.vertical, 18)
                    } else {
                        SubagentResponseView(run: run, onRoute: { route = $0 })
                            .id(run.id)
                            .accessibilityIdentifier("subagent-output")
                    }
                } else {
                    if run.eventsTruncated { Text("直近80件の処理履歴を表示しています。").font(.caption).foregroundStyle(.secondary) }
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(run.events) { event in
                            VStack(alignment: .leading, spacing: 5) {
                                HStack(alignment: .firstTextBaseline) {
                                    Image(systemName: event.kind.hasPrefix("tool") ? "wrench.and.screwdriver" : "bubble.left")
                                        .foregroundStyle(.secondary)
                                    Text(event.title).font(.subheadline.weight(.medium))
                                    Spacer()
                                    Text(Date(timeIntervalSince1970: Double(event.createdAtMs) / 1000), style: .time)
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                                if !event.detail.isEmpty {
                                    Text(event.detail).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                    }
                }
            }
            .padding(18)
        }
        .background(Color(uiColor: .amoledSystemBackground))
        .sheet(item: $route) { ChatWorkspaceRouteSheet(route: $0) }
        .navigationTitle(run.agent)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func messageRow(role: String, text: String) -> some View {
        ChatMessageRow(
            message: FullChatMessage(id: role == "user" ? 0 : 1,
                message: ChatMessage(conversationId: 0, role: role, text: text),
                thinkingStream: nil, variants: []),
            streamingSnapshot: nil, streamingMarkdownBlocks: nil,
            canRegenerate: false,
            onRoute: { route = $0 }, onPreviousVariant: { _ in }, onNextVariant: { _ in },
            onBranch: { _ in }, onRegenerate: {}, onEditUserMessage: { _ in },
            onSelectUserMessageText: { _ in }, onMarkdownLayoutChange: {}, isReadOnly: true
        )
    }

}

/// Use the main conversation's presentation state as well as its message view.
/// In particular, live child output must not be reparsed as a completed answer
/// on every progress snapshot.
private struct SubagentResponseView: View {
    let run: SubagentRun
    let onRoute: (ChatWorkspaceRoute) -> Void
    @StateObject private var store: ChatTimelineRowStore

    init(run: SubagentRun, onRoute: @escaping (ChatWorkspaceRoute) -> Void) {
        self.run = run
        self.onRoute = onRoute
        _store = StateObject(wrappedValue: ChatTimelineRowStore(subagent: run))
    }

    var body: some View {
        if case let .message(message) = store.item {
            ChatMessageRow(
                message: message,
                streamingSnapshot: store.streamingSnapshot,
                streamingMarkdownBlocks: store.streamingMarkdownBlocks,
                canRegenerate: false,
                onRoute: onRoute, onPreviousVariant: { _ in }, onNextVariant: { _ in },
                onBranch: { _ in }, onRegenerate: {}, onEditUserMessage: { _ in },
                onSelectUserMessageText: { _ in },
                onMarkdownLayoutChange: store.contentLayoutDidChange, isReadOnly: true
            )
            .environment(\.markdownPresentationCache, store.markdownPresentationCache)
            .onChange(of: run) { _, updated in
                store.apply(subagent: updated)
            }
        }
    }
}

extension ChatTimelineRowStore {
    convenience init(subagent: SubagentRun) {
        self.init(item: .message(FullChatMessage(
            id: 1,
            message: ChatMessage(conversationId: 0, role: "assistant", text: ""),
            thinkingStream: nil, variants: []
        )))
        apply(subagent: subagent)
    }

    func apply(subagent: SubagentRun) {
        apply(snapshot: ChatStreamingSnapshot(
            targetId: 1, text: subagent.output, thinking: "", toolActivity: nil,
            isFinal: subagent.status != .running
        ))
    }
}

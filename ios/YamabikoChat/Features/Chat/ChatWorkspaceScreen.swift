import SwiftUI
import UIKit

enum ChatWorkspacePrimaryAction: Equatable {
    case createConversation
    case enableSecretMode
    case disableSecretMode

    static func resolve(hasConversationContent: Bool, isSecretConversation: Bool) -> Self {
        if hasConversationContent {
            return .createConversation
        }
        return isSecretConversation ? .disableSecretMode : .enableSecretMode
    }
}

struct ChatWorkspaceScreen: View {
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var appState: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    let conversationID: Int64
    @ObservedObject var viewModel: ChatViewModel
    var onSelectConversation: ((Int64) -> Void)?
    @State private var exportedArchive: ConversationExportShareItem?
    @State private var isExporting = false
    @State private var topBarMetrics = ChatTopBarMetrics()
    @StateObject private var workspaceStore = ChatWorkspaceStore()

    var body: some View {
        ChatScreen(
            viewModel: viewModel,
            questionCoordinator: container.userQuestionCoordinator,
            timelineTopInset: topBarMetrics.topOffset + topBarMetrics.height,
            onNavigateToConversation: { newConversationId in
                if let onSelectConversation {
                    onSelectConversation(newConversationId)
                } else {
                    if reduceMotion {
                        appState.selectedConversationID = newConversationId
                    } else {
                        withAnimation(.easeOut(duration: 0.25)) {
                            appState.selectedConversationID = newConversationId
                        }
                    }
                }
            }
        )
        // The timeline runs edge to edge behind the header, so the messages
        // scrolling underneath remain visible through it.
        .ignoresSafeArea(.container, edges: .top)
        .safeAreaInset(edge: .top, spacing: 0) {
            topBar
                .background(alignment: .bottom) {
                    ChatTopBarScrim()
                        .frame(height: topBarMetrics.height + topBarMetrics.topOffset)
                }
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: ChatTopBarMetricsKey.self,
                            value: ChatTopBarMetrics(
                                height: proxy.size.height,
                                topOffset: proxy.frame(in: .global).minY
                            )
                        )
                    }
                )
        }
        .onPreferenceChange(ChatTopBarMetricsKey.self) { metrics in
            topBarMetrics = metrics
        }
        .siriConversationContext(id: conversationID, isSecret: viewModel.isSecretConversation || !viewModel.isConversationLoaded)
        .background(workspaceBackground.ignoresSafeArea())
        .secretChatCaptureProtected(viewModel.isSecretConversation || !viewModel.isConversationLoaded)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .task {
            viewModel.bind(
                repository: container.chatRepository,
                attachmentRepository: container.attachmentRepository,
                skillRepository: container.skillRepository
            )
            applyShareImportDraftIfNeeded()
            applyPendingInitialMessageIfNeeded()
        }
        .onChange(of: appState.shareImportDraft) { _, _ in
            applyShareImportDraftIfNeeded()
        }
        .sheet(item: $exportedArchive) { item in
            ConversationExportShareSheet(url: item.url)
        }
        .sheet(item: $workspaceStore.presentedRoute) { route in
            workspaceSheet(for: route)
                .secretChatCaptureProtected(viewModel.isSecretConversation || !viewModel.isConversationLoaded)
        }
    }

    private func applyShareImportDraftIfNeeded() {
        guard let text = try? container.chatRepository.shareImportText(conversationID: conversationID) else { return }
        viewModel.applySharedText(text)
        appState.clearShareImportDraft(for: conversationID)
    }

    private func applyPendingInitialMessageIfNeeded() {
        do {
            guard let text = try container.chatRepository.pendingInitialMessage(conversationId: conversationID) else {
                return
            }
            viewModel.inputText = text
            viewModel.sendMessage()
        } catch {
            viewModel.recordFailure(error)
            DiagnosticsLogger.log(
                "Could not load pending initial message",
                category: .chat,
                metadata: ["conversationId": String(conversationID)],
                error: error
            )
        }
    }

    private var workspaceBackground: Color {
        Color(uiColor: .amoledSystemBackground)
    }

    private var currentProvider: String {
        viewModel.conversationProvider.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    private var currentModel: String {
        viewModel.conversationModel.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSwitchChatModel: Bool {
        !viewModel.settings.isDualModeEnabled &&
            !viewModel.settings.isAutoConversationEnabled
    }

    private var modelSwitcherTitle: String {
        if viewModel.settings.isDualModeEnabled {
            return L10n.text("デュアルモード")
        }
        if viewModel.settings.isAutoConversationEnabled {
            return L10n.text("自動会話")
        }
        let model = currentModel.trimmingCharacters(in: .whitespacesAndNewlines)
        if !model.isEmpty {
            return ChatViewModel.shortModelLabel(model)
        }
        let provider = currentProvider.trimmingCharacters(in: .whitespacesAndNewlines)
        return provider.isEmpty ? L10n.text("Chat") : ProviderCatalog.displayName(for: provider)
    }

    private var workspaceContextTitle: String {
        let title = viewModel.workspaceConversationTitleLabel
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if viewModel.isSecretConversation {
            return L10n.format("シークレット · %@", title)
        }
        return title
    }

    private func isActiveChatPreset(_ preset: ModelPreset) -> Bool {
        guard !viewModel.settings.isDualModeEnabled,
              !viewModel.settings.isAutoConversationEnabled
        else {
            return false
        }
        let presetProvider = preset.apiProvider.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let presetModel = preset.model.trimmingCharacters(in: .whitespacesAndNewlines)
        return presetProvider == currentProvider && presetModel == currentModel
    }

    private func isActiveSystemPromptPreset(_ preset: SystemPromptPreset) -> Bool {
        guard let active = viewModel.activeSystemPromptPresetName?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !active.isEmpty
        else {
            return false
        }
        return preset.name.caseInsensitiveCompare(active) == .orderedSame
    }

    private var topBar: some View {
        HStack(spacing: 8) {
            Button {
                openConversationHistory()
            } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Color(uiColor: .label))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("チャット履歴"))
            .accessibilityIdentifier("chat-history-button")

            modelTitleControl
                .frame(minWidth: 0, maxWidth: .infinity)
                .layoutPriority(-1)
                .clipped()

            HStack(spacing: 8) {
                Button {
                    performPrimaryAction()
                } label: {
                    primaryActionLabel
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(primaryActionAccessibilityLabel))
                .accessibilityIdentifier("chat-primary-action-button")

                moreMenu
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 7)
        // The gradient leaves the message text visible behind the controls, so
        // keep them separated from it with a halo in the opposite tone.
        .shadow(color: colorScheme == .dark ? .black.opacity(0.65) : .white.opacity(0.9), radius: 5, y: 1)
        .overlay(alignment: .bottom) {
            Divider()
                .opacity(0.18)
        }
    }

    private var primaryAction: ChatWorkspacePrimaryAction {
        ChatWorkspacePrimaryAction.resolve(
            hasConversationContent: viewModel.hasConversationContent,
            isSecretConversation: viewModel.isSecretConversation
        )
    }

    @ViewBuilder
    private var primaryActionLabel: some View {
        switch primaryAction {
        case .createConversation:
            Image(systemName: "square.and.pencil")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
        case .enableSecretMode:
            SecretChatToggleIcon(isSecret: false)
        case .disableSecretMode:
            SecretChatToggleIcon(isSecret: true)
        }
    }

    private var primaryActionAccessibilityLabel: String {
        switch primaryAction {
        case .createConversation:
            L10n.text("新しいチャット")
        case .enableSecretMode:
            L10n.text("シークレットチャットに切り替え")
        case .disableSecretMode:
            L10n.text("通常チャットに戻す")
        }
    }

    private func performPrimaryAction() {
        switch primaryAction {
        case .createConversation:
            createConversation()
        case .enableSecretMode:
            viewModel.setSecretModeForEmptyConversation(true)
        case .disableSecretMode:
            viewModel.setSecretModeForEmptyConversation(false)
        }
    }

    @ViewBuilder
    private var modelTitleControl: some View {
        Button {
            if canSwitchChatModel {
                workspaceStore.present(.modelPicker)
            } else {
                workspaceStore.present(.modePicker)
            }
        } label: {
            modelTitleLabel(showsChevron: true)
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isSending)
        .accessibilityLabel(Text(canSwitchChatModel ? "モデルを切り替え" : "会話モードを変更"))
        .accessibilityIdentifier("chat-model-button")
    }

    private var moreMenu: some View {
            Menu {
                Button("再生成") {
                    viewModel.regenerateLastAssistantVariant()
                }
                .disabled(!viewModel.canRegenerateLastAssistant)

                Button {
                    exportConversation(mode: .standard)
                } label: {
                    Label(L10n.text("チャットを書き出す"), systemImage: "square.and.arrow.up")
                }
                .disabled(isExporting)

                Button {
                    exportConversation(mode: .fullDiagnostics)
                } label: {
                    Label(L10n.text("完全診断を書き出す"), systemImage: "stethoscope")
                }
                .disabled(isExporting)

                Button {
                    workspaceStore.present(.modePicker)
                } label: {
                    Label(L10n.text("会話モード"), systemImage: ChatMode(settings: viewModel.settings).systemImage)
                }
                .disabled(viewModel.isSending)

                if viewModel.isAutoConversationRunning {
                    Button("自動会話を一時停止") {
                        viewModel.pauseAutoConversation()
                    }
                    Button("自動会話を停止") {
                        viewModel.stopAutoConversation()
                    }
                } else if viewModel.isAutoConversationPaused {
                    Button("自動会話を再開") {
                        viewModel.resumeAutoConversation()
                    }
                    Button("自動会話を停止") {
                        viewModel.stopAutoConversation()
                    }
                }

                Divider()
                Button {
                    viewModel.disableSystemPromptForConversation()
                } label: {
                    if viewModel.isSystemPromptDisabledForConversation {
                        Label(L10n.text("Prompt: なし"), systemImage: "checkmark")
                    } else {
                        Text(L10n.text("Prompt: なし"))
                    }
                }
                Button {
                    viewModel.applyCustomSystemPrompt()
                } label: {
                    if viewModel.isCustomSystemPromptActive {
                        Label(L10n.text("Prompt: Custom"), systemImage: "checkmark")
                    } else {
                        Text(L10n.text("Prompt: Custom"))
                    }
                }
                ForEach(viewModel.availableSystemPromptPresets()) { preset in
                    Button {
                        viewModel.applySystemPromptPreset(name: preset.name)
                    } label: {
                        if isActiveSystemPromptPreset(preset) {
                            Label(L10n.format("Prompt: %@", preset.name), systemImage: "checkmark")
                        } else {
                            Text(L10n.format("Prompt: %@", preset.name))
                        }
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("その他"))
    }

    @ViewBuilder
    private func workspaceSheet(for route: ChatWorkspaceRoute) -> some View {
        switch route {
        case .modelPicker:
            ChatModelPickerSheet(viewModel: viewModel)
        case .modePicker:
            ChatModePickerSheet(viewModel: viewModel)
        default:
            ChatWorkspaceRouteSheet(route: route)
        }
    }

    private func modelTitleLabel(showsChevron: Bool) -> some View {
        VStack(spacing: 1) {
            HStack(spacing: 5) {
                Text(modelSwitcherTitle)
                    .font(.system(size: 17, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                if showsChevron {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .foregroundStyle(.primary)

            Text(workspaceContextTitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
    }

    private func createConversation() {
        do {
            let conversationID = try container.chatRepository.createConversation()
            if let onSelectConversation {
                onSelectConversation(conversationID)
            } else {
                appState.selectedConversationID = conversationID
            }
        } catch {
            viewModel.recordFailure(error)
            DiagnosticsLogger.log(
                "Create conversation from workspace failed",
                category: .chat,
                error: error
            )
        }
    }

    private func exportConversation(mode: ConversationExportMode) {
        guard !isExporting else { return }
        isExporting = true
        Task { @MainActor in
            defer { isExporting = false }
            do {
                let url = try await viewModel.exportConversation(mode: mode)
                exportedArchive = ConversationExportShareItem(url: url)
            } catch {
                viewModel.recordFailure(error)
                DiagnosticsLogger.log(
                    "Conversation export failed",
                    category: .chat,
                    metadata: ["conversation": String(conversationID)],
                    error: error
                )
            }
        }
    }

    private func openConversationHistory() {
        appState.requestConversationSidebarReveal()
    }
}

private struct ChatTopBarMetrics: Equatable {
    var height: CGFloat = 0
    /// Distance from the top of the window to the header. The scrim background
    /// grows by this much so it also covers the status bar.
    var topOffset: CGFloat = 0
}

private struct ChatTopBarMetricsKey: PreferenceKey {
    static var defaultValue = ChatTopBarMetrics()

    static func reduce(value: inout ChatTopBarMetrics, nextValue: () -> ChatTopBarMetrics) {
        let next = nextValue()
        guard next.height > 0 else { return }
        value = next
    }
}

// The header keeps its current tint at the top of the screen and fades to fully
// transparent at its bottom edge, so scrolled messages blend into view instead
// of meeting a hard cut. The status bar is part of the fade. A UIKit blur cannot
// sample the SwiftUI-hosted timeline cells, so the see-through comes from this
// gradient.
private struct ChatTopBarScrim: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let tint = Color(uiColor: .amoledSystemBackground)
        LinearGradient(
            stops: [
                .init(color: tint.opacity(fullOpacity), location: 0),
                .init(color: tint.opacity(0), location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var fullOpacity: Double {
        colorScheme == .dark ? 0.88 : 0.92
    }
}

private struct SecretChatToggleIcon: View {
    let isSecret: Bool

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(Color.black.opacity(0.22), lineWidth: 0.45)

            Image(isSecret ? "TemporaryChatMarkSelected" : "TemporaryChatMark")
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .frame(width: 21, height: 21)
                .offset(x: -1.0 / 3.0, y: -1.0 / 3.0)
        }
        .foregroundStyle(.primary)
        .frame(width: 45, height: 45)
        .contentShape(Circle())
    }
}

private struct ConversationExportShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

private struct ConversationExportShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url)
    }

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        controller.completionWithItemsHandler = { [weak coordinator = context.coordinator] _, _, _, _ in
            coordinator?.removeExport()
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}

    static func dismantleUIViewController(_ uiViewController: UIActivityViewController, coordinator: Coordinator) {
        coordinator.removeExport()
    }

    final class Coordinator {
        private let url: URL
        private var removed = false

        init(url: URL) {
            self.url = url
        }

        func removeExport() {
            guard !removed else { return }
            removed = true
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                if (error as NSError).code != NSFileNoSuchFileError {
                    DiagnosticsLogger.log("Temporary export cleanup failed", category: .app, error: error)
                }
            }
        }
    }
}

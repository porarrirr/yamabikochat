import SwiftUI
import UIKit

struct ChatWorkspaceScreen: View {
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var appState: AppState
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    let conversationID: Int64
    @ObservedObject var viewModel: ChatViewModel
    var onSelectConversation: ((Int64) -> Void)?
    @State private var exportedArchive: ConversationExportShareItem?
    @State private var isExporting = false

    var body: some View {
        VStack(spacing: 0) {
            topBar

            ChatScreen(
                viewModel: viewModel,
                onNavigateToConversation: { newConversationId in
                    if let onSelectConversation {
                        onSelectConversation(newConversationId)
                    } else {
                        appState.selectedConversationID = newConversationId
                    }
                }
            )
        }
        .background(workspaceBackground.ignoresSafeArea())
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
        }
        .onChange(of: appState.shareImportDraft) { _, _ in
            applyShareImportDraftIfNeeded()
        }
        .sheet(item: $exportedArchive) { item in
            ConversationExportShareSheet(items: [item.url])
        }
    }

    private func applyShareImportDraftIfNeeded() {
        guard let text = appState.shareImportText(for: conversationID) else { return }
        viewModel.applySharedText(text)
        appState.clearShareImportDraft(for: conversationID)
    }

    private var workspaceBackground: Color {
        Color(uiColor: .systemBackground)
    }

    private var currentProvider: String {
        viewModel.settings.apiProvider.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    private var currentModel: String {
        viewModel.settings.currentModel().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSwitchChatModel: Bool {
        !viewModel.settings.isDualModeEnabled &&
            !viewModel.settings.isAutoConversationEnabled &&
            !viewModel.settings.isFusionModeEnabled
    }

    private var modelSwitcherTitle: String {
        if viewModel.settings.isFusionModeEnabled {
            return L10n.text("Fusion")
        }
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
              !viewModel.settings.isAutoConversationEnabled,
              !viewModel.settings.isFusionModeEnabled
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

    private var isCustomSystemPromptActive: Bool {
        let active = viewModel.activeSystemPromptPresetName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return active?.isEmpty ?? true
    }

    private var topBar: some View {
        HStack(spacing: 8) {
            Button {
                openConversationHistory()
            } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Color(uiColor: .label))
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("チャット履歴"))

            modelTitleControl
                .frame(minWidth: 0, maxWidth: .infinity)
                .layoutPriority(-1)
                .clipped()

            HStack(spacing: 8) {
                Button {
                    createConversation()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 36, height: 36)
                        .overlay {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .stroke(Color(uiColor: .label), lineWidth: 1.7)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("新規チャット"))

                moreMenu
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 7)
        .background(
            Rectangle()
                .fill(Color(uiColor: .systemBackground).opacity(0.98))
                .overlay(alignment: .bottom) {
                    Divider()
                        .opacity(0.18)
                }
        )
    }

    @ViewBuilder
    private var modelTitleControl: some View {
        if canSwitchChatModel {
            Menu {
                let chatPresets = viewModel.availableChatPresets()
                if chatPresets.isEmpty {
                    Button("利用可能なプリセットがありません") {}
                        .disabled(true)
                } else {
                    ForEach(chatPresets) { preset in
                        Button {
                            viewModel.applyChatPreset(preset)
                        } label: {
                            if isActiveChatPreset(preset) {
                                Label(preset.name, systemImage: "checkmark")
                            } else {
                                Text(preset.name)
                            }
                        }
                    }
                }
            } label: {
                modelTitleLabel(showsChevron: true)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("モデルを切り替え"))
        } else {
            modelTitleLabel(showsChevron: false)
        }
    }

    private var moreMenu: some View {
            Menu {
                Button("再生成") {
                    viewModel.regenerateLastAssistantVariant()
                }
                .disabled(!viewModel.canRegenerateLastAssistant)

                Button {
                    exportConversation()
                } label: {
                    Label(L10n.text("チャットを書き出す"), systemImage: "square.and.arrow.up")
                }
                .disabled(isExporting)

                Button {
                    viewModel.toggleDualMode()
                } label: {
                    if viewModel.settings.isDualModeEnabled {
                        Label(L10n.text("デュアルモード"), systemImage: "checkmark")
                    } else {
                        Text(L10n.text("デュアルモード"))
                    }
                }
                .disabled(
                    (viewModel.settings.isAutoConversationEnabled || viewModel.settings.isFusionModeEnabled)
                        && !viewModel.settings.isDualModeEnabled
                )

                Button {
                    viewModel.toggleFusionMode()
                } label: {
                    if viewModel.settings.isFusionModeEnabled {
                        Label(L10n.text("Fusion モード"), systemImage: "checkmark")
                    } else {
                        Text(L10n.text("Fusion モード"))
                    }
                }
                .disabled(
                    (viewModel.settings.isDualModeEnabled || viewModel.settings.isAutoConversationEnabled)
                        && !viewModel.settings.isFusionModeEnabled
                )

                Button {
                    viewModel.toggleAutoConversation()
                } label: {
                    if viewModel.settings.isAutoConversationEnabled {
                        Label(L10n.text("自動会話"), systemImage: "checkmark")
                    } else {
                        Text(L10n.text("自動会話"))
                    }
                }
                .disabled(
                    (viewModel.settings.isDualModeEnabled || viewModel.settings.isFusionModeEnabled)
                        && !viewModel.settings.isAutoConversationEnabled
                )

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
                    viewModel.applySystemPromptPreset(name: nil)
                } label: {
                    if isCustomSystemPromptActive {
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
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("その他"))
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
            viewModel.errorMessage = error.localizedDescription
            DiagnosticsLogger.log(
                "Create conversation from workspace failed",
                category: .chat,
                error: error
            )
        }
    }

    private func exportConversation() {
        guard !isExporting else { return }
        isExporting = true
        Task { @MainActor in
            defer { isExporting = false }
            do {
                let url = try await viewModel.exportConversation()
                exportedArchive = ConversationExportShareItem(url: url)
            } catch {
                viewModel.errorMessage = error.localizedDescription
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
        if horizontalSizeClass == .compact {
            appState.isConversationHistoryPresented = true
        } else {
            appState.requestConversationSidebarReveal()
        }
    }
}

private struct ConversationExportShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

private struct ConversationExportShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

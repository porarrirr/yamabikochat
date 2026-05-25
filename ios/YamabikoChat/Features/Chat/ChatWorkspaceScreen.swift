import SwiftUI
import UIKit

struct ChatWorkspaceScreen: View {
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var appState: AppState
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    let conversationID: Int64
    @ObservedObject var viewModel: ChatViewModel
    var onSelectConversation: ((Int64) -> Void)?

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
                attachmentRepository: container.attachmentRepository
            )
            applyShareImportDraftIfNeeded()
        }
        .onChange(of: appState.shareImportDraft) { _, _ in
            applyShareImportDraftIfNeeded()
        }
    }

    private func applyShareImportDraftIfNeeded() {
        guard let text = appState.shareImportText(for: conversationID) else { return }
        viewModel.applySharedText(text)
        appState.clearShareImportDraft(for: conversationID)
    }

    private var workspaceBackground: Color {
        Color(uiColor: .systemGroupedBackground)
    }

    private var currentProvider: String {
        viewModel.settings.apiProvider.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    private var currentModel: String {
        viewModel.settings.currentModel().trimmingCharacters(in: .whitespacesAndNewlines)
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

    private var isCustomSystemPromptActive: Bool {
        let active = viewModel.activeSystemPromptPresetName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return active?.isEmpty ?? true
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            Button {
                openConversationHistory()
            } label: {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color(uiColor: .label))
                    .frame(width: 32, height: 32)
                    .background(
                        Circle()
                            .fill(Color(uiColor: .tertiarySystemBackground))
                    )
                    .overlay {
                        Circle()
                            .stroke(Color(uiColor: .separator).opacity(0.35), lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("チャット履歴"))

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
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(viewModel.workspaceTitleLabel)
                            .font(.system(size: 19, weight: .semibold))
                            .lineLimit(1)
                        if !viewModel.settings.isDualModeEnabled,
                           !viewModel.settings.isAutoConversationEnabled {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let subtitle = viewModel.workspaceSubtitleLabel {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .disabled(viewModel.settings.isDualModeEnabled || viewModel.settings.isAutoConversationEnabled)

            Button {
                createConversation()
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.primary)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)

            Menu {
                Button("再生成") {
                    viewModel.regenerateLastAssistantVariant()
                }
                .disabled(!viewModel.canRegenerateLastAssistant)

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
                    viewModel.settings.isAutoConversationEnabled && !viewModel.settings.isDualModeEnabled
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
                    viewModel.settings.isDualModeEnabled && !viewModel.settings.isAutoConversationEnabled
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
                    .frame(width: 32, height: 32)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Rectangle()
                .fill(Color(uiColor: .systemBackground).opacity(0.96))
                .overlay(alignment: .bottom) {
                    Divider()
                        .opacity(0.45)
                }
        )
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

    private func openConversationHistory() {
        if horizontalSizeClass == .compact {
            appState.isConversationHistoryPresented = true
        } else {
            appState.requestConversationSidebarReveal()
        }
    }
}

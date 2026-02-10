import SwiftUI
import UIKit

struct ChatWorkspaceScreen: View {
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var appState: AppState
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @ObservedObject var viewModel: ChatViewModel
    var onSelectConversation: ((Int64) -> Void)?

    private enum WorkspaceMode {
        case chat
        case dual
        case auto
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar

            switch currentMode {
            case .chat:
                ChatScreen(viewModel: viewModel)
            case .dual:
                DualChatScreen(viewModel: viewModel)
            case .auto:
                AutoConversationScreen(viewModel: viewModel)
            }
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
            viewModel.applySharedText(appState.consumePendingText())
        }
        .onChange(of: appState.pendingSharedText) { _, _ in
            viewModel.applySharedText(appState.consumePendingText())
        }
    }

    private var workspaceBackground: Color {
        Color(uiColor: .systemGroupedBackground)
    }

    private var currentMode: WorkspaceMode {
        if viewModel.settings.isDualModeEnabled {
            return .dual
        }
        if viewModel.settings.isAutoConversationEnabled {
            return .auto
        }
        return .chat
    }

    private var modelPresetLabel: String {
        let model = viewModel.settings.currentModel().trimmingCharacters(in: .whitespacesAndNewlines)
        return model.isEmpty ? "Chat" : model
    }

    private var currentProvider: String {
        viewModel.settings.apiProvider.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    private var currentModel: String {
        viewModel.settings.currentModel().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func isActiveChatPreset(_ preset: ModelPreset) -> Bool {
        let presetProvider = preset.apiProvider.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let presetModel = preset.model.trimmingCharacters(in: .whitespacesAndNewlines)
        return presetProvider == currentProvider && presetModel == currentModel
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
            .accessibilityLabel("チャット履歴")

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
                HStack(spacing: 4) {
                    Text(modelPresetLabel)
                        .font(.system(size: 19, weight: .semibold))
                        .lineLimit(1)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

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

                Button(viewModel.settings.isDualModeEnabled ? "デュアルをOFF" : "デュアルをON") {
                    viewModel.toggleDualMode()
                }

                Button(viewModel.settings.isAutoConversationEnabled ? "自動会話をOFF" : "自動会話をON") {
                    viewModel.toggleAutoConversation()
                }

                if viewModel.isAutoConversationRunning {
                    Button("自動会話を停止") {
                        viewModel.stopAutoConversation()
                    }
                }

                Divider()
                Button("Prompt: Custom") {
                    viewModel.applySystemPromptPreset(name: nil)
                }
                ForEach(viewModel.availableSystemPromptPresets()) { preset in
                    Button("Prompt: \(preset.name)") {
                        viewModel.applySystemPromptPreset(name: preset.name)
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

    private func toggleSidebar() {
        UIApplication.shared.sendAction(
            #selector(UISplitViewController.toggleSidebar(_:)),
            to: nil,
            from: nil,
            for: nil
        )
    }

    private func openConversationHistory() {
        if horizontalSizeClass == .compact {
            appState.isConversationHistoryPresented = true
        } else {
            toggleSidebar()
        }
    }
}

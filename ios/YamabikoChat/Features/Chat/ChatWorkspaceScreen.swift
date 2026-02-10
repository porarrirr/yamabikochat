import SwiftUI
import UIKit

struct ChatWorkspaceScreen: View {
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var appState: AppState
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @ObservedObject var viewModel: ChatViewModel
    @State private var selectedSegment: Segment = .chat

    enum Segment: String, CaseIterable, Identifiable {
        case chat = "チャット"
        case dual = "デュアル"
        case auto = "自動会話"

        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar

            switch selectedSegment {
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

    private var titleLabel: String {
        switch selectedSegment {
        case .chat:
            let model = viewModel.settings.currentModel().trimmingCharacters(in: .whitespacesAndNewlines)
            return model.isEmpty ? "Chat" : model
        case .dual:
            return "Dual Chat"
        case .auto:
            return "Auto Conversation"
        }
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
                Section("モード") {
                    ForEach(Segment.allCases) { item in
                        Button {
                            selectedSegment = item
                        } label: {
                            if selectedSegment == item {
                                Label(item.rawValue, systemImage: "checkmark")
                            } else {
                                Text(item.rawValue)
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(titleLabel)
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
                    viewModel.regenerateLastAssistantMessage()
                }

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

                let chatPresets = viewModel.availableChatPresets()
                if !chatPresets.isEmpty {
                    Divider()
                    ForEach(chatPresets) { preset in
                        Button("Chat Preset: \(preset.name)") {
                            viewModel.applyChatPreset(preset)
                        }
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
            appState.selectedConversationID = conversationID
            selectedSegment = .chat
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

import SwiftUI

struct RootView: View {
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var appState: AppState

    @StateObject private var listViewModel = ConversationListViewModel()
    @StateObject private var settingsViewModel = SettingsViewModel()
    @State private var isSettingsPresented = false
    @State private var dynamicColorEnabled = true
    @State private var themeColor = "BLUE_PURPLE"
    @State private var themeMode = "SYSTEM"

    var body: some View {
        NavigationSplitView {
            ConversationListScreen(
                viewModel: listViewModel,
                selection: $appState.selectedConversationID,
                onSelect: { id in
                    selectConversation(id: id)
                },
                onOpenSettings: {
                    isSettingsPresented = true
                }
            )
            .navigationTitle("会話")
        } detail: {
            if let conversationID = appState.selectedConversationID {
                ConversationDetailHost(
                    conversationID: conversationID,
                    onSelectConversation: { id in
                        selectConversation(id: id)
                    }
                )
                .id(conversationID)
            } else {
                ContentUnavailableView(
                    "会話がありません",
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text("新規作成するか既存の会話を選択してください。")
                )
            }
        }
        .task {
            listViewModel.bind(repository: container.chatRepository)
            if appState.selectedConversationID == nil {
                appState.selectedConversationID = listViewModel.conversations.first?.id
            }
            if let settings = try? container.chatRepository.loadSettings() {
                applyAppearance(settings)
            }
        }
        .onReceive(container.chatRepository.settingsPublisher()) { settings in
            applyAppearance(settings)
        }
        .onChange(of: listViewModel.conversations.map(\.id)) { _, ids in
            guard !ids.isEmpty else {
                appState.selectedConversationID = nil
                return
            }
            if let selected = appState.selectedConversationID, ids.contains(selected) {
                return
            }
            appState.selectedConversationID = ids.first
        }
        .sheet(isPresented: $isSettingsPresented) {
            SettingsScreen(viewModel: settingsViewModel)
                .environmentObject(container)
        }
        .sheet(isPresented: $appState.isConversationHistoryPresented) {
            ConversationHistorySheet(
                viewModel: listViewModel,
                selection: $appState.selectedConversationID,
                onSelect: { id in
                    selectConversation(id: id, closeHistory: true)
                }
            )
            .environmentObject(container)
        }
        .preferredColorScheme(resolvedColorScheme)
        .tint(resolvedTintColor)
    }

    private var resolvedColorScheme: ColorScheme? {
        switch themeMode.uppercased() {
        case "LIGHT":
            return .light
        case "DARK":
            return .dark
        default:
            return nil
        }
    }

    private var resolvedTintColor: Color {
        if dynamicColorEnabled {
            return Color(uiColor: .systemBlue)
        }

        switch themeColor.uppercased() {
        case "BLUE":
            return Color(uiColor: .systemBlue)
        case "GREEN":
            return Color(uiColor: .systemGreen)
        case "YELLOW":
            return Color(uiColor: .systemYellow)
        case "PINK":
            return Color(uiColor: .systemPink)
        case "ORANGE":
            return Color(uiColor: .systemOrange)
        case "BLACK":
            return Color(uiColor: .black)
        default:
            return Color(uiColor: .systemIndigo)
        }
    }

    private func applyAppearance(_ settings: AppSettings) {
        dynamicColorEnabled = settings.dynamicColorEnabled
        themeColor = settings.themeColor
        themeMode = settings.themeMode
    }

    private func selectConversation(id: Int64, closeHistory: Bool = false) {
        appState.selectedConversationID = id
        if closeHistory {
            appState.isConversationHistoryPresented = false
        }
    }
}

private struct ConversationDetailHost: View {
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var appState: AppState

    let conversationID: Int64
    let onSelectConversation: (Int64) -> Void
    @StateObject private var viewModel: ChatViewModel

    init(
        conversationID: Int64,
        onSelectConversation: @escaping (Int64) -> Void
    ) {
        self.conversationID = conversationID
        self.onSelectConversation = onSelectConversation
        _viewModel = StateObject(wrappedValue: ChatViewModel(conversationID: conversationID))
    }

    var body: some View {
        ChatWorkspaceScreen(
            viewModel: viewModel,
            onSelectConversation: onSelectConversation
        )
            .environmentObject(container)
            .environmentObject(appState)
    }
}

private struct ConversationHistorySheet: View {
    @EnvironmentObject private var container: AppContainer
    @Environment(\.dismiss) private var dismiss

    @ObservedObject var viewModel: ConversationListViewModel
    @StateObject private var settingsViewModel = SettingsViewModel()
    @Binding var selection: Int64?

    let onSelect: (Int64) -> Void
    @State private var isSettingsPresented = false

    var body: some View {
        NavigationStack {
            ConversationListScreen(
                viewModel: viewModel,
                selection: $selection,
                onSelect: { id in
                    onSelect(id)
                },
                onOpenSettings: {
                    isSettingsPresented = true
                }
            )
            .navigationTitle("チャット履歴")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
        .sheet(isPresented: $isSettingsPresented) {
            SettingsScreen(viewModel: settingsViewModel)
                .environmentObject(container)
        }
    }
}

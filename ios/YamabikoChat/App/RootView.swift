import SwiftUI

struct RootView: View {
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var appState: AppState
    @Environment(\.scenePhase) private var scenePhase

    @StateObject private var listViewModel = ConversationListViewModel()
    @StateObject private var settingsViewModel = SettingsViewModel()
    @State private var isSettingsPresented = false
    @State private var screenshotSettingsTab: SettingsScreen.SettingsTab?
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic
    @State private var preferredCompactColumn: NavigationSplitViewColumn = .sidebar
    @State private var dynamicColorEnabled = true
    @State private var themeColor = "BLUE_PURPLE"
    @State private var themeMode = "SYSTEM"

    var body: some View {
        NavigationSplitView(
            columnVisibility: $columnVisibility,
            preferredCompactColumn: $preferredCompactColumn
        ) {
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
            if let settings = try? container.chatRepository.loadSettings() {
                applyAppearance(settings)
            }
            importSharePayloadIfNeeded()
            await applyScreenshotRoutingIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: AppConstants.sharePayloadDidChangeNotification)) { _ in
            importSharePayloadIfNeeded()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                importSharePayloadIfNeeded()
            }
        }
        .onReceive(container.chatRepository.settingsPublisher()) { settings in
            applyAppearance(settings)
        }
        .onChange(of: appState.conversationSidebarRevealGeneration) { _, _ in
            columnVisibility = .all
            preferredCompactColumn = .sidebar
        }
        .onChange(of: listViewModel.conversations.map(\.id)) { _, ids in
            guard !AppStoreScreenshotRouting.isEnabled else { return }
            if let draft = appState.shareImportDraft, ids.contains(draft.conversationID) {
                appState.selectedConversationID = draft.conversationID
                preferredCompactColumn = .detail
                return
            }
            guard !ids.isEmpty else {
                appState.selectedConversationID = nil
                preferredCompactColumn = .sidebar
                return
            }
            if let selected = appState.selectedConversationID, ids.contains(selected) {
                return
            }
            appState.selectedConversationID = ids.first
            if appState.selectedConversationID != nil {
                preferredCompactColumn = .detail
            }
        }
        .sheet(isPresented: $isSettingsPresented) {
            SettingsScreen(viewModel: settingsViewModel, initialTab: screenshotSettingsTab)
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

    @MainActor
    private func applyScreenshotRoutingIfNeeded() async {
        guard let launch = AppStoreScreenshotRouting.launchConfiguration() else {
            if appState.selectedConversationID == nil {
                appState.selectedConversationID = listViewModel.conversations.first?.id
                if appState.selectedConversationID != nil {
                    preferredCompactColumn = .detail
                }
            }
            return
        }

        try? await Task.sleep(nanoseconds: 300_000_000)

        switch launch.scene {
        case .list:
            appState.selectedConversationID = nil
            preferredCompactColumn = .sidebar
        case .chat:
            if let conversationID = launch.conversationID ?? listViewModel.conversations.first?.id {
                selectConversation(id: conversationID)
            }
        case .settingsAPI:
            screenshotSettingsTab = .api
            isSettingsPresented = true
        case .settingsAppearance:
            screenshotSettingsTab = .appearance
            isSettingsPresented = true
        case .settingsDual:
            screenshotSettingsTab = .dual
            isSettingsPresented = true
        case .settingsAuto:
            screenshotSettingsTab = .auto
            isSettingsPresented = true
        case .project:
            if let projectID = launch.projectID {
                listViewModel.selectProject(projectID)
            }
            appState.selectedConversationID = nil
            preferredCompactColumn = .sidebar
        }

        try? await Task.sleep(nanoseconds: 500_000_000)
    }

    private func selectConversation(id: Int64, closeHistory: Bool = false) {
        listViewModel.resetProjectFilterForNonProjectConversation(conversationId: id)
        appState.selectedConversationID = id
        preferredCompactColumn = .detail
        if closeHistory {
            appState.isConversationHistoryPresented = false
        }
    }

    private func importSharePayloadIfNeeded() {
        guard appState.importSharePayload(
            from: container.sharePayloadStore,
            repository: container.chatRepository
        ) else {
            return
        }
        preferredCompactColumn = .detail
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
            conversationID: conversationID,
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
                },
                onClose: {
                    dismiss()
                }
            )
        }
        .sheet(isPresented: $isSettingsPresented) {
            SettingsScreen(viewModel: settingsViewModel)
                .environmentObject(container)
        }
    }
}

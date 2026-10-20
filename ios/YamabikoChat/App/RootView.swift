import SwiftUI

enum ConversationListSelectionResolution: Equatable {
    case keepCurrentSelection
    case clearSelection
    case select(Int64)
}

enum ConversationListSelectionResolver {
    static func resolve(
        visibleConversationIDs ids: [Int64],
        selectedConversationID: Int64?,
        selectedConversationExists: Bool,
        keepSidebarAfterSecretDiscard: Bool
    ) -> ConversationListSelectionResolution {
        if selectedConversationID != nil {
            if selectedConversationExists {
                return .keepCurrentSelection
            }
        } else if keepSidebarAfterSecretDiscard {
            return .keepCurrentSelection
        }

        guard !ids.isEmpty else {
            return .clearSelection
        }

        return .select(ids[0])
    }
}

enum RootNavigationPresentationPolicy {
    static func usesCompactColumnNavigation(horizontalSizeClass: UserInterfaceSizeClass?) -> Bool {
        horizontalSizeClass == .compact
    }
}

struct RootView: View {
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var appState: AppState
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @StateObject private var listViewModel = ConversationListViewModel()
    @StateObject private var settingsStore = SettingsViewModelStore()
    @StateObject private var chatViewModelStore = ChatViewModelStore()
    @State private var isSettingsPresented = false
    @State private var screenshotSettingsTab: SettingsScreen.SettingsTab?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var preferredCompactColumn: NavigationSplitViewColumn = .sidebar
    @State private var isCompactDrawerOpen = false
    @State private var dynamicColorEnabled = true
    @State private var themeColor = "BLUE_PURPLE"
    @State private var themeMode = "SYSTEM"
    @State private var keepSidebarAfterSecretDiscard = false
    @State private var privacyCoverVisible = false

    private var settingsViewModel: SettingsViewModel { settingsStore.viewModel }

    var body: some View {
        navigationContent
        .task {
            listViewModel.bind(repository: container.chatRepository)
            if let settings = try? container.chatRepository.loadSettings() {
                applyAppearance(settings)
            }
            importSharePayloadIfNeeded()
            applySiriNavigation()
            await applyScreenshotRoutingIfNeeded()
        }
        .onReceive(SiriNavigation.shared.$pendingRequest) { request in
            guard request != nil else { return }
            Task { @MainActor in applySiriNavigation() }
        }
        .onReceive(NotificationCenter.default.publisher(for: AppConstants.sharePayloadDidChangeNotification)) { _ in
            importSharePayloadIfNeeded()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                privacyCoverVisible = isSelectedConversationSecret && UIScreen.main.isCaptured
                importSharePayloadIfNeeded()
                Task {
                    do {
                        try await PiAgentRuntime.shared.prepareForForeground()
                    } catch {
                        DiagnosticsLogger.log(
                            "Pi runtime foreground synchronization failed",
                            category: .network,
                            error: error
                        )
                    }
                }
            } else {
                if isSelectedConversationSecret {
                    privacyCoverVisible = true
                }
                if phase == .background {
                    discardSelectedSecretConversationIfNeeded()
                    SecretConversationVault.shared.destroyAll()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIScreen.capturedDidChangeNotification)) { _ in
            privacyCoverVisible = isSelectedConversationSecret && UIScreen.main.isCaptured
        }
        .onReceive(container.chatRepository.settingsPublisher()) { settings in
            applyAppearance(settings)
        }
        .onChange(of: appState.conversationSidebarRevealGeneration) { _, _ in
            let revealSidebar = {
                columnVisibility = .all
                setPreferredCompactColumn(.sidebar)
            }
            if reduceMotion {
                revealSidebar()
            } else {
                withAnimation(.easeOut(duration: 0.25), revealSidebar)
            }
        }
        .onChange(of: listViewModel.conversations.map(\.id)) { previousIDs, ids in
            chatViewModelStore.removeConversations(ids: Set(previousIDs).subtracting(ids))
        }
        .onChange(of: listViewModel.filteredConversations.map(\.id)) { _, ids in
            guard !AppStoreScreenshotRouting.isEnabled else { return }
            if let draft = appState.shareImportDraft, ids.contains(draft.conversationID) {
                appState.selectedConversationID = draft.conversationID
                setPreferredCompactColumn(.detail)
                return
            }

            let selectedConversationExists = appState.selectedConversationID.map { id in
                (try? container.chatRepository.conversation(id: id)) != nil
            } ?? false
            let resolution = ConversationListSelectionResolver.resolve(
                visibleConversationIDs: ids,
                selectedConversationID: appState.selectedConversationID,
                selectedConversationExists: selectedConversationExists,
                keepSidebarAfterSecretDiscard: keepSidebarAfterSecretDiscard
            )

            switch resolution {
            case .keepCurrentSelection:
                if keepSidebarAfterSecretDiscard, appState.selectedConversationID == nil {
                    keepSidebarAfterSecretDiscard = false
                    setPreferredCompactColumn(.sidebar)
                }
            case .clearSelection:
                appState.selectedConversationID = nil
                keepSidebarAfterSecretDiscard = false
                setPreferredCompactColumn(.sidebar)
            case let .select(id):
                appState.selectedConversationID = id
                keepSidebarAfterSecretDiscard = false
                setPreferredCompactColumn(.detail)
            }
        }
        .sheet(isPresented: $isSettingsPresented) {
            SettingsScreen(viewModel: settingsViewModel, initialTab: screenshotSettingsTab)
                .environmentObject(container)
        }
        .sheet(isPresented: $appState.isConversationHistoryPresented) {
            ConversationHistorySheet(
                viewModel: listViewModel,
                settingsViewModel: settingsViewModel,
                selection: $appState.selectedConversationID,
                onSelect: { id in
                    selectConversation(id: id, closeHistory: true)
                }
            )
            .environmentObject(container)
            .environmentObject(appState)
        }
        .amoledPresentation()
        .preferredColorScheme(resolvedColorScheme)
        .tint(resolvedTintColor)
        .overlay {
            if privacyCoverVisible {
                ZStack {
                    Color(uiColor: .amoledSystemBackground).ignoresSafeArea()
                    VStack(spacing: 12) {
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 44))
                        Text(L10n.text("シークレットチャットを保護中"))
                            .font(.headline)
                    }
                }
                .accessibilityHidden(true)
                .zIndex(10_000)
            }
        }
    }

    @ViewBuilder
    private var navigationContent: some View {
        if horizontalSizeClass == .compact {
            ConversationDrawer(
                isOpen: $isCompactDrawerOpen,
                hasConversation: appState.selectedConversationID != nil,
                reduceMotion: reduceMotion
            ) {
                NavigationStack { conversationSidebar }
                    .environmentObject(container)
                    .environmentObject(appState)
                    .tint(resolvedTintColor)
            } detail: {
                conversationDetail
                    .environmentObject(container)
                    .environmentObject(appState)
                    .tint(resolvedTintColor)
            }
            .ignoresSafeArea()
        } else {
            NavigationSplitView(
                columnVisibility: $columnVisibility,
                preferredCompactColumn: $preferredCompactColumn
            ) {
                conversationSidebar
                    .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 360)
            } detail: {
                conversationDetail
            }
        }
    }

    private var conversationSidebar: some View {
        ConversationListScreen(
            viewModel: listViewModel,
            selection: $appState.selectedConversationID,
            onSelect: { id in selectConversation(id: id) },
            onOpenSettings: { isSettingsPresented = true },
            allowsRowSwipeActions: horizontalSizeClass != .compact || appState.selectedConversationID == nil
        )
    }

    private var conversationDetail: some View {
        ZStack {
            if let conversationID = appState.selectedConversationID {
                ConversationDetailHost(
                    conversationID: conversationID,
                    viewModelStore: chatViewModelStore,
                    onSelectConversation: { id in selectConversation(id: id) }
                )
                .id(conversationID)
                .transition(horizontalSizeClass == .compact ? .identity : .asymmetric(
                    insertion: .offset(x: 28).combined(with: .opacity),
                    removal: .opacity
                ))
            } else {
                ContentUnavailableView {
                    Label(L10n.text("会話を始めましょう"), systemImage: "bubble.left.and.bubble.right")
                } actions: {
                    Button {
                        createConversationFromEmptyDetail()
                    } label: {
                        Label(L10n.text("新しいチャット"), systemImage: "square.and.pencil")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .accessibilityIdentifier("empty-detail-new-chat")
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    private var isSelectedConversationSecret: Bool {
        guard let id = appState.selectedConversationID else { return false }
        return (try? container.chatRepository.conversation(id: id)?.isSecret) == true
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
        case "WHITE":
            return Color(uiColor: .white)
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
            do {
                if try appState.initializeConversationSelectionIfNeeded(repository: container.chatRepository) {
                    setPreferredCompactColumn(.detail)
                }
            } catch {
                DiagnosticsLogger.log("Initialize launch conversation failed", category: .chat, error: error)
            }
            return
        }

        try? await Task.sleep(nanoseconds: 300_000_000)

        // The list observation can arrive after the launch animation. Wait for
        // actual data when routing directly to a conversation in UI fixtures.
        var screenshotConversations = listViewModel.conversations
        if screenshotConversations.isEmpty, launch.scene == .chat || launch.scene == .performance {
            guard let entries = await listViewModel.$conversations.values.first(where: { !$0.isEmpty }),
                  !Task.isCancelled else { return }
            screenshotConversations = entries
        }

        switch launch.scene {
        case .list:
            appState.selectedConversationID = nil
            setPreferredCompactColumn(.sidebar)
        case .chat:
            let genUITitle = ProcessInfo.processInfo.arguments.contains("-GenUIRichFixture")
                ? GenUIRichDemoFixture.title : GenUIDemoFixture.title
            let genUIFixtureID = ProcessInfo.processInfo.arguments.contains("-GenUIFixture") || ProcessInfo.processInfo.arguments.contains("-GenUIRichFixture")
                ? screenshotConversations.first(where: { $0.title == genUITitle })?.id : nil
            if let conversationID = launch.conversationID ?? genUIFixtureID ?? screenshotConversations.first?.id {
                selectConversation(id: conversationID)
            }
        case .temporaryChat:
            if let conversationID = try? container.chatRepository.createConversation(
                title: "Temporary Chat Screenshot Fixture"
            ) {
                selectConversation(id: conversationID)
            }
        case .performance:
            if let conversationID = screenshotConversations.first(where: {
                $0.title == "Timeline Performance Fixture"
            })?.id {
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
            setPreferredCompactColumn(.sidebar)
        }

        try? await Task.sleep(nanoseconds: 500_000_000)
    }

    private func applySiriNavigation() {
        guard let request = SiriNavigation.shared.consume() else { return }
        switch request {
        case .conversation(let id):
            do {
                _ = try SiriConversationService.resolve(id: id, repository: container.conversationRepository)
                listViewModel.selectedProjectId = nil
                listViewModel.searchQuery = ""
                selectConversation(id: id, closeHistory: true)
            } catch {
                DiagnosticsLogger.log("Siri navigation rejected unavailable conversation", category: .app, error: error)
            }
        case .search(let term):
            listViewModel.selectedProjectId = nil
            listViewModel.searchFromSiri(term: term, conversations: container.conversationRepository)
            appState.requestConversationSidebarReveal()
            setPreferredCompactColumn(.sidebar)
        }
    }

    private func selectConversation(id: Int64, closeHistory: Bool = false) {
        let shouldAnimate = !reduceMotion && !isSelectedConversationSecret
        if appState.selectedConversationID != id {
            discardSelectedSecretConversationIfNeeded(keepSidebar: false)
        }
        listViewModel.resetProjectFilterForNonProjectConversation(conversationId: id)
        let showConversation = {
            appState.selectedConversationID = id
            keepSidebarAfterSecretDiscard = false
            setPreferredCompactColumn(.detail)
        }
        if shouldAnimate {
            withAnimation(.easeOut(duration: 0.25), showConversation)
        } else {
            showConversation()
        }
        if closeHistory {
            appState.isConversationHistoryPresented = false
        }
    }

    private func importSharePayloadIfNeeded() {
        var importedAny = false
        while appState.importSharePayload(
            from: container.sharePayloadStore,
            repository: container.chatRepository
        ) {
            importedAny = true
        }
        if importedAny {
            setPreferredCompactColumn(.detail)
        }
    }

    private func discardSelectedSecretConversationIfNeeded(keepSidebar: Bool = true) {
        guard let id = appState.selectedConversationID else { return }
        discardSecretConversationIfNeeded(id: id, keepSidebar: keepSidebar)
    }

    private func discardSecretConversationIfNeeded(id: Int64, keepSidebar: Bool) {
        do {
            let deleted = try container.chatRepository.deleteSecretConversationIfNeeded(id: id)
            if deleted, appState.selectedConversationID == id {
                appState.selectedConversationID = nil
                keepSidebarAfterSecretDiscard = keepSidebar
                setPreferredCompactColumn(.sidebar)
            }
        } catch {
            DiagnosticsLogger.log(
                "Discard secret conversation failed conversation=\(id)",
                category: .chat,
                error: error
            )
        }
    }

    private func setPreferredCompactColumn(_ column: NavigationSplitViewColumn) {
        guard RootNavigationPresentationPolicy.usesCompactColumnNavigation(
            horizontalSizeClass: horizontalSizeClass
        ) else {
            return
        }
        preferredCompactColumn = column
        isCompactDrawerOpen = column == .sidebar
    }

    private func createConversationFromEmptyDetail() {
        do {
            let id = try container.chatRepository.createConversation()
            selectConversation(id: id)
        } catch {
            DiagnosticsLogger.log(
                "Create conversation from empty detail failed",
                category: .chat,
                error: error
            )
        }
    }
}

private struct ConversationDetailHost: View {
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var appState: AppState
    @Environment(\.scenePhase) private var scenePhase

    let conversationID: Int64
    let onSelectConversation: (Int64) -> Void
    @StateObject private var viewModel: ChatViewModel

    init(
        conversationID: Int64,
        viewModelStore: ChatViewModelStore,
        onSelectConversation: @escaping (Int64) -> Void
    ) {
        self.conversationID = conversationID
        self.onSelectConversation = onSelectConversation
        _viewModel = StateObject(wrappedValue: viewModelStore.viewModel(conversationID: conversationID))
    }

    var body: some View {
        ChatWorkspaceScreen(
            conversationID: conversationID,
            viewModel: viewModel,
            onSelectConversation: onSelectConversation
            )
            .environmentObject(container)
            .environmentObject(appState)
            .onChange(of: scenePhase) { _, phase in
                if phase == .background {
                    viewModel.discardSecretDataFromMemory()
                }
            }
            .onDisappear {
                viewModel.handleWorkspaceDisappearance()
            }
    }
}

private struct ConversationHistorySheet: View {
    @EnvironmentObject private var container: AppContainer
    @Environment(\.dismiss) private var dismiss

    @ObservedObject var viewModel: ConversationListViewModel
    let settingsViewModel: SettingsViewModel
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

// Preserve one settings model without forwarding its publications to the chat tree.
@MainActor
private final class SettingsViewModelStore: ObservableObject {
    let viewModel = SettingsViewModel()
}

import SwiftUI

struct OnboardingScreen: View {
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var appState: AppState
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var viewModel: OnboardingViewModel
    @ObservedObject var settings: SettingsViewModel
    @State private var hasPrefetchedCatalogs = false
    @State private var connectionDrafts: [String: String] = [:]
    @State private var isFinishing = false

    private var connectionStep: OnboardingConnectionStep? {
        switch viewModel.progress.step {
        case .credentials: .credentials
        case .model: .model
        default: nil
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.progress.step == .provider {
                    CatalogProviderListView(
                        selectedProviderID: settings.settings.apiProvider,
                        catalogProviders: settings.modelsDevCatalogState.providers.map(CatalogProviderOption.init),
                        excludedProviderIDs: OnboardingProgress.apiExcludedProviderIDs,
                        dismissOnSelection: false,
                        title: "プロバイダーを選ぶ",
                        onSelect: { provider in
                            settings.setProvider(provider)
                            viewModel.advance(connectionDrafts: connectionDrafts)
                        }
                    )
                    .navigationBarTitleDisplayMode(.inline)
                } else if let connectionStep {
                    SettingsDetailScreen(
                        viewModel: settings,
                        category: .connection,
                        onboardingStep: connectionStep,
                        onOnboardingContinue: {
                            if viewModel.advance(connectionDrafts: connectionDrafts) { finish() }
                        },
                        isOnboardingFinishing: isFinishing,
                        hasPrefetchedConnectionCatalogs: $hasPrefetchedCatalogs,
                        modelsDevFieldDrafts: $connectionDrafts
                    )
                } else {
                    connectionChoices
                }
            }
            .toolbar {
                if viewModel.progress.step == .provider || connectionStep != nil {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { viewModel.goBack() } label: {
                            Label("戻る", systemImage: "chevron.backward")
                        }
                        .disabled(isFinishing)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(viewModel.progress.step == .model ? "あとで" : "あとで設定する") { finish(skip: true) }
                        .font(.subheadline)
                        .disabled(isFinishing)
                        .accessibilityIdentifier("onboarding-skip")
                }
            }
            .safeAreaInset(edge: .bottom) {
                // Background credential reads do not interrupt the connection chooser.
                if let error = viewModel.presentedError {
                    Text(error).font(.callout).foregroundStyle(.red).padding()
                }
            }
        }
        .task {
            settings.bind(
                repository: container.chatRepository,
                credentialStore: container.credentialStore,
                modelsDevCatalogRepository: container.modelsDevCatalogRepository,
                skillRepository: container.skillRepository,
                automaticallyRefreshCodexAuth: false
            )
            await viewModel.refreshPCC()
        }
        .task(id: viewModel.progress.step) {
            if viewModel.progress.step == .provider, !hasPrefetchedCatalogs {
                hasPrefetchedCatalogs = true
                await settings.prefetchLatestModelCatalogs()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await viewModel.refreshPCC() } }
            else { settings.flushPendingSettingsSave() }
        }
        .onDisappear {
            viewModel.cancelChatGPTSignIn()
            settings.flushPendingSettingsSave()
        }
        .tint(.primary)
        .amoledPresentation()
    }

    private var connectionChoices: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Text("AIを接続")
                    .font(.largeTitle.bold())
                    .accessibilityAddTraits(.isHeader)
                VStack(spacing: 14) {
                    connectionCard("ChatGPTでサインイン", icon: "", connection: .chatGPT)
                    if viewModel.pccAvailable {
                        connectionCard("AppleのAIを使う（PCC）", icon: "apple.logo", connection: .pcc)
                    }
                    connectionCard("APIキーで接続", icon: "key", connection: .apiKey)
                    if viewModel.isSigningInWithChatGPT {
                        Button("サインインをキャンセル") { viewModel.cancelChatGPTSignIn() }
                            .accessibilityIdentifier("onboarding-cancel-sign-in")
                    }
                }
            }
            .frame(maxWidth: 560, alignment: .leading)
            .padding(28)
            .frame(maxWidth: .infinity)
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    private func connectionCard(_ title: String, icon: String, connection: OnboardingProgress.Connection) -> some View {
        Button {
            if connection == .chatGPT {
                Task { await viewModel.signInWithChatGPT() }
            } else {
                viewModel.select(connection)
                if connection == .pcc, viewModel.progress.connection == .pcc { finish() }
            }
        } label: {
            HStack(spacing: 16) {
                if connection == .chatGPT {
                    if viewModel.isSigningInWithChatGPT {
                        ProgressView().tint(Color(uiColor: .amoledSystemBackground)).frame(width: 24, height: 24)
                    } else {
                        ChatGPTBrandIcon(inverse: true).frame(width: 24, height: 24)
                    }
                } else {
                    Image(systemName: icon).font(.title2).frame(width: 24)
                }
                Text(title).font(.headline)
                Spacer(minLength: 0)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(connection == .chatGPT ? Color(uiColor: .amoledSystemBackground) : Color.primary)
            .background {
                RoundedRectangle(cornerRadius: 20)
                    .fill(connection == .chatGPT ? AnyShapeStyle(Color.primary) : AnyShapeStyle(.quaternary))
            }
            .contentShape(RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain)
        .disabled(isFinishing)
        .accessibilityIdentifier("onboarding-connect-\(connection.rawValue)")
    }

    private func finish(skip: Bool = false) {
        guard !isFinishing else { return }
        isFinishing = true
        Task {
            await viewModel.finish(repository: container.chatRepository, appState: appState, skip: skip)
            isFinishing = false
        }
    }
}

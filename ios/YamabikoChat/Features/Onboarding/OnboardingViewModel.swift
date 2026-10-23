import Foundation
import Combine

enum OnboardingConnectionStep {
    case credentials, model

    var title: String {
        switch self {
        case .credentials: "APIキーで接続"
        case .model: "モデルを選ぶ"
        }
    }

}

struct OnboardingProgress: Codable, Equatable {
    enum Step: String, Codable {
        case choice, provider, credentials, chatGPT, model, completed
    }
    enum Connection: String, Codable { case chatGPT, pcc, apiKey }

    static let apiExcludedProviderIDs: Set<String> = ["CODEX_AUTH", "SUPERGROK", "APPLE_INTELLIGENCE"]
    var step: Step = .choice
    var connection: Connection?

    mutating func goBack() {
        switch step {
        case .choice, .completed: break
        case .provider, .chatGPT: step = .choice
        case .credentials: step = .provider
        case .model: step = connection == .chatGPT ? .choice : .credentials
        }
    }
}

/// Stores only navigation progress. Credentials stay in the existing Keychain path.
final class OnboardingStateStore {
    private static let key = "onboarding.progress.v1"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard, hasExistingInstallation: Bool) {
        self.defaults = defaults
        if defaults.data(forKey: Self.key) == nil {
            save(OnboardingProgress(step: hasExistingInstallation ? .completed : .choice))
        }
    }

    func load() -> OnboardingProgress {
        guard let data = defaults.data(forKey: Self.key),
              let progress = try? JSONDecoder().decode(OnboardingProgress.self, from: data) else {
            return OnboardingProgress()
        }
        return progress
    }

    func save(_ progress: OnboardingProgress) {
        defaults.set(try? JSONEncoder().encode(progress), forKey: Self.key)
    }
}

@MainActor
final class OnboardingViewModel: ObservableObject {
    @Published private(set) var progress: OnboardingProgress {
        didSet { store.save(progress) }
    }
    @Published private(set) var pccAvailable = false
    @Published private(set) var isCheckingPCC = false
    @Published private(set) var isSigningInWithChatGPT = false
    @Published var errorMessage: String?
    let settings = SettingsViewModel()
    private var chatGPTSignInTask: Task<Void, Never>?
    private var chatGPTSignInID: UUID?
    private let store: OnboardingStateStore
    private let pccCapability: () async -> PCCCapability
    private let chatGPTSignIn: (SettingsViewModel) async -> Void

    init(
        store: OnboardingStateStore,
        pccCapability: @escaping () async -> PCCCapability = PCCProviderClient.capability,
        chatGPTSignIn: @escaping (SettingsViewModel) async -> Void = { await $0.loginCodexAuth() }
    ) {
        self.pccCapability = pccCapability
        self.chatGPTSignIn = chatGPTSignIn
        self.store = store
        var restored = store.load()
        // An interrupted browser handoff must wait for a new user tap.
        if restored.step == .chatGPT { restored.step = .choice }
        progress = restored
    }

    var isCompleted: Bool { progress.step == .completed }
    var presentedError: String? {
        errorMessage ?? (progress.step == .choice ? nil : settings.visibleErrorMessage)
    }

    func goBack() { cancelChatGPTSignIn(); errorMessage = nil; progress.goBack() }

    func select(_ connection: OnboardingProgress.Connection) {
        cancelChatGPTSignIn()
        errorMessage = nil
        settings.errorMessage = nil
        switch connection {
        case .chatGPT:
            settings.setProvider("CODEX_AUTH")
            progress = OnboardingProgress(step: .chatGPT, connection: connection)
        case .pcc:
            guard pccAvailable else { return }
            settings.setProvider("APPLE_INTELLIGENCE")
            settings.setDefaultModel(AppleIntelligenceModelCatalog.pccModel)
            progress = OnboardingProgress(step: .choice, connection: connection)
        case .apiKey:
            if OnboardingProgress.apiExcludedProviderIDs.contains(settings.settings.apiProvider.uppercased()) {
                settings.setProvider("GEMINI")
            }
            progress = OnboardingProgress(step: .provider, connection: connection)
        }
    }

    func cancelChatGPTSignIn() {
        guard chatGPTSignInID != nil else { return }
        chatGPTSignInID = nil
        chatGPTSignInTask?.cancel()
        isSigningInWithChatGPT = false
        if progress.step == .chatGPT { progress.step = .choice }
        settings.errorMessage = nil
        errorMessage = nil
        DiagnosticsLogger.log("Onboarding ChatGPT authorization cancelled", category: .auth)
    }

    func signInWithChatGPT() async {
        select(.chatGPT)
        let previousTask = chatGPTSignInTask
        let id = UUID()
        chatGPTSignInID = id
        isSigningInWithChatGPT = true
        let task = Task { @MainActor in
            // Let the previous Pi connection close before starting another login.
            await previousTask?.value
            guard !Task.isCancelled else { return }
            await chatGPTSignIn(settings)
        }
        chatGPTSignInTask = task
        await task.value
        // A cancelled attempt must not change a newer selection or login.
        guard chatGPTSignInID == id else { return }
        chatGPTSignInID = nil
        chatGPTSignInTask = nil
        isSigningInWithChatGPT = false
        guard settings.codexAuthState.planUsageEnabled else {
            progress.step = .choice
            errorMessage = settings.visibleErrorMessage ?? "ChatGPTプランの利用が許可されませんでした。"
            return
        }
        progress.step = .model
    }

    func refreshPCC() async {
        guard !isCheckingPCC else { return }
        isCheckingPCC = true
        defer { isCheckingPCC = false }
        pccAvailable = await pccCapability().available
    }

    @discardableResult
    func advance(connectionDrafts: [String: String]) -> Bool {
        errorMessage = nil
        switch progress.step {
        case .provider:
            guard !OnboardingProgress.apiExcludedProviderIDs.contains(settings.settings.apiProvider.uppercased()) else { return false }
            progress.step = .credentials
        case .chatGPT:
            guard settings.codexAuthState.planUsageEnabled else { return false }
            progress.step = .model
        case .credentials:
            settings.errorMessage = nil
            let reference = ProviderReference(persistedID: settings.settings.apiProvider)
            if let id = reference.modelsDevID,
               let provider = settings.modelsDevCatalogState.providers.first(where: { $0.id == id }) {
                let fields = Dictionary(uniqueKeysWithValues: provider.connectionFields.map { field in
                    let key = "\(id)\u{0}\(field)"
                    return (field, connectionDrafts[key] ?? settings.modelsDevField(providerID: id, fieldName: field))
                })
                if !fields.isEmpty && fields.values.allSatisfy({ $0.trimmedNonEmpty == nil }) {
                    errorMessage = "接続情報を入力してください。"
                    return false
                }
                settings.saveModelsDevFields(providerID: id, fields: fields)
            } else if settings.settings.apiProvider != "OPENAI_COMPAT", settings.apiKeyDraft.trimmedNonEmpty == nil {
                errorMessage = "APIキーを入力してください。"
                return false
            }
            settings.flushPendingSettingsSave()
            guard settings.errorMessage == nil else { return false }
            progress.step = .model
        case .model:
            guard settings.settings.defaultModel.trimmedNonEmpty != nil else {
                errorMessage = "モデルを選んでください。"
                return false
            }
            if progress.connection == .chatGPT {
                guard settings.codexAuthState.planUsageEnabled,
                      CodexModelCatalog.visiblePresets(from: settings.codexModels).contains(where: {
                          $0.model == settings.settings.defaultModel && $0.isSupported
                      }) else {
                    errorMessage = "利用可能なChatGPTモデルを選んでください。"
                    return false
                }
            }
            settings.flushPendingSettingsSave()
            guard settings.errorMessage == nil else { return false }
            return true
        default: break
        }
        return false
    }

    func finish(repository: ChatRepository, appState: AppState, skip: Bool = false) async {
        cancelChatGPTSignIn()
        errorMessage = nil
        if !skip, progress.connection == .pcc {
            await refreshPCC()
            guard pccAvailable else {
                progress.step = .choice
                return
            }
        }
        settings.errorMessage = nil
        settings.flushPendingSettingsSave()
        if settings.errorMessage != nil {
            errorMessage = settings.visibleErrorMessage
            return
        }
        do {
            // External share imports / Siri links retain their selected destination.
            if !skip, appState.selectedConversationID == nil {
                let id = try repository.createConversation()
                _ = try repository.syncNewChatWithSettingsIfEmpty(
                    conversationId: id, settings: settings.settings, previousSettings: nil
                )
                appState.selectedConversationID = id
            }
            progress.step = .completed
        } catch {
            DiagnosticsLogger.log("Onboarding completion failed", category: .app, error: error)
        }
    }
}

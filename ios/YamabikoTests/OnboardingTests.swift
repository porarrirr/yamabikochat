import XCTest
import GRDB
@testable import YamabikoChat

private final class OnboardingCredentials: SecureCredentialStore {
    var secrets: [String: String] = [:]
    func saveSecret(_ value: String?, key: String) throws { secrets[key] = value }
    func readSecret(key: String) throws -> String? { secrets[key] }
    func deleteSecret(key: String) throws { secrets.removeValue(forKey: key) }
}

final class OnboardingTests: XCTestCase {
    private func withStore(_ body: (OnboardingStateStore, UserDefaults) throws -> Void) throws {
        let suite = "OnboardingTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(OnboardingStateStore(defaults: defaults, hasExistingInstallation: false), defaults)
    }

    func testNewInstallationStartsAtConnectionChoiceAndExistingInstallationSkips() throws {
        try withStore { store, defaults in
            XCTAssertEqual(store.load().step, .choice)
            defaults.removeObject(forKey: "onboarding.progress.v1")
            let existing = OnboardingStateStore(defaults: defaults, hasExistingInstallation: true)
            XCTAssertEqual(existing.load().step, .completed)
        }
    }

    func testFreshDatabaseWithSeededSettingsStillNeedsOnboarding() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("onboarding-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        let hadDatabase = FileManager.default.fileExists(atPath: url.path)
        let database = try DatabaseQueue(path: url.path)
        try AppDatabase.migrator.migrate(database)
        XCTAssertNotNil(try database.read { try AppSettings.fetchOne($0, key: 1) })
        try withStore { _, defaults in
            defaults.removeObject(forKey: "onboarding.progress.v1")
            let store = OnboardingStateStore(defaults: defaults, hasExistingInstallation: hadDatabase)
            XCTAssertEqual(store.load().step, .choice)
        }
    }

    func testInterruptedSetupResumesEvenAfterSettingsHaveBeenCreated() throws {
        try withStore { store, defaults in
            let progress = OnboardingProgress(step: .credentials, connection: .apiKey)
            store.save(progress)
            let reopened = OnboardingStateStore(defaults: defaults, hasExistingInstallation: true)
            XCTAssertEqual(reopened.load(), progress)
            store.save(OnboardingProgress(step: .completed))
            XCTAssertEqual(reopened.load().step, .completed)
        }
    }

    func testBackNavigationFollowsSelectedConnection() {
        for (connection, expected): (OnboardingProgress.Connection, OnboardingProgress.Step) in [
            (.chatGPT, .choice), (.apiKey, .credentials)
        ] {
            var progress = OnboardingProgress(step: .model, connection: connection)
            progress.goBack()
            XCTAssertEqual(progress.step, expected)
        }
    }

    @MainActor
    func testPCCChoiceRequiresSuccessfulCapabilityCheck() async throws {
        let suite = "OnboardingTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = OnboardingStateStore(defaults: defaults, hasExistingInstallation: false)
        for reason in ["pcc_os_unsupported", "pcc_device_not_eligible", "pcc_system_not_ready", "pcc_quota_limit_reached", "pcc_context_unavailable"] {
            let model = OnboardingViewModel(store: store, pccCapability: { PCCCapability(available: false, reason: reason) })
            await model.refreshPCC()
            XCTAssertFalse(model.pccAvailable)
            model.select(.pcc)
            XCTAssertEqual(model.progress.step, .choice)
        }
        let model = OnboardingViewModel(store: store, pccCapability: { PCCCapability(available: true, contextSize: 32_768) })
        await model.refreshPCC()
        model.select(.pcc)
        XCTAssertEqual(model.progress.step, .choice)
        XCTAssertEqual(model.settings.settings.apiProvider, "APPLE_INTELLIGENCE")
        XCTAssertEqual(model.settings.settings.defaultModel, AppleIntelligenceModelCatalog.pccModel)
    }

    @MainActor
    func testChatGPTCannotAdvanceWithoutPlanAuthorization() throws {
        try withStore { store, _ in
            let model = OnboardingViewModel(store: store)
            model.select(.chatGPT)
            model.advance(connectionDrafts: [:])
            XCTAssertEqual(model.progress.step, .chatGPT)
            model.select(.apiKey)
            XCTAssertEqual(model.progress.step, .provider)
            XCTAssertFalse(OnboardingProgress.apiExcludedProviderIDs.contains(model.settings.settings.apiProvider))
            model.advance(connectionDrafts: [:])
            model.advance(connectionDrafts: [:])
            XCTAssertEqual(model.progress.step, .credentials)
            XCTAssertNotNil(model.errorMessage)
        }
    }

    @MainActor
    func testBackgroundCredentialFailureDoesNotInterruptConnectionChoice() throws {
        try withStore { store, _ in
            let model = OnboardingViewModel(store: store)
            model.settings.errorMessage = KeychainStoreError.unexpectedStatus(-34018).localizedDescription
            XCTAssertNil(model.presentedError)
            model.select(.chatGPT)
            model.settings.errorMessage = "サインインに失敗しました。"
            XCTAssertEqual(model.presentedError, "サインインに失敗しました。")
            model.goBack()
            XCTAssertNil(model.presentedError)
        }
    }

    func testKeychainErrorDoesNotExposeInternalTypeName() {
        let description = KeychainStoreError.unexpectedStatus(-34018).localizedDescription
        XCTAssertFalse(description.contains("KeychainStoreError"))
        XCTAssertTrue(description.contains("認証情報"))
    }

    @MainActor
    func testChatGPTChoiceStartsSignInAndAdvancesDirectlyToModels() async throws {
        let suite = "OnboardingTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var signInCount = 0
        let model = OnboardingViewModel(
            store: OnboardingStateStore(defaults: defaults, hasExistingInstallation: false),
            chatGPTSignIn: { settings in
                signInCount += 1
                XCTAssertEqual(settings.settings.apiProvider, "CODEX_AUTH")
                settings.codexAuthState = CodexAuthState(isLoggedIn: true, planUsageEnabled: true)
            }
        )
        await model.signInWithChatGPT()
        XCTAssertEqual(signInCount, 1)
        XCTAssertEqual(model.progress.step, .model)
        XCTAssertFalse(model.isSigningInWithChatGPT)
        model.goBack()
        XCTAssertEqual(model.progress.step, .choice)
    }

    @MainActor
    func testFailedChatGPTSignInReturnsToChoicesWithoutOpeningModels() async throws {
        let suite = "OnboardingTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = OnboardingViewModel(
            store: OnboardingStateStore(defaults: defaults, hasExistingInstallation: false),
            chatGPTSignIn: { $0.errorMessage = "接続がキャンセルされました。" }
        )
        await model.signInWithChatGPT()
        XCTAssertEqual(model.progress.step, .choice)
        XCTAssertEqual(model.presentedError, "接続がキャンセルされました。")
        XCTAssertFalse(model.isSigningInWithChatGPT)
    }

    @MainActor
    func testInterruptedBrowserHandoffReturnsToChoicesOnRelaunch() throws {
        try withStore { store, _ in
            store.save(OnboardingProgress(step: .chatGPT, connection: .chatGPT))
            let model = OnboardingViewModel(store: store)
            XCTAssertEqual(model.progress.step, .choice)
            XCTAssertFalse(model.isSigningInWithChatGPT)
        }
    }

    @MainActor
    func testCompletionOpensEmptyChatWithChosenModel() async throws {
        let suite = "OnboardingTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let database = try DatabaseQueue()
        try AppDatabase.migrator.migrate(database)
        let settings = SettingsRepository(dbQueue: database)
        let conversations = ConversationRepository(dbQueue: database)
        let credentials = OnboardingCredentials()
        let repository = ChatRepositoryTestSupport.makeRepository(
            dbQueue: database, settings: settings, conversations: conversations, credentials: credentials
        )
        let model = OnboardingViewModel(store: OnboardingStateStore(defaults: defaults, hasExistingInstallation: false))
        model.settings.bind(repository: repository, credentialStore: credentials)
        model.settings.setProvider("SARASHINA")
        model.settings.setDefaultModel("sarashina3-nano")
        model.settings.apiKeyDraft = "test-key"
        let state = AppState()
        await model.finish(repository: repository, appState: state)
        XCTAssertTrue(model.isCompleted)
        let id = try XCTUnwrap(state.selectedConversationID)
        XCTAssertEqual(try repository.conversation(id: id)?.model, "sarashina3-nano")
        XCTAssertTrue(try conversations.isConversationEmpty(conversationId: id))
        model.settings.errorMessage = "previous login failure"
        await model.finish(repository: repository, appState: state, skip: true)
        XCTAssertTrue(model.isCompleted)
    }
}

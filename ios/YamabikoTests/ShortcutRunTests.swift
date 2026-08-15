import XCTest
import GRDB
@testable import YamabikoChat

private final class TestCredentialStore: SecureCredentialStore {
    private var storage: [String: String] = [:]

    func saveSecret(_ value: String?, key: String) throws {
        if let value {
            storage[key] = value
        } else {
            storage.removeValue(forKey: key)
        }
    }

    func readSecret(key: String) throws -> String? {
        storage[key]
    }

    func deleteSecret(key: String) throws {
        storage.removeValue(forKey: key)
    }
}

private struct NoopPricingRepository: LiteLlmPricingEstimating {
    func estimateCostUsd(
        provider: String,
        model: String,
        inputTokens: Int,
        outputTokens: Int,
        cachedInputTokens: Int?,
        cacheCreationInputTokens: Int?,
        reasoningTokens: Int?
    ) async -> Double? {
        nil
    }

    func modelSupportsVision(provider: String, model: String) async -> Bool {
        false
    }
}

final class ShortcutRunTests: XCTestCase {
    func testRunShortcutAskOnlyReturnsTextWithoutPersistingConversation() async throws {
        let runtime = successRuntime()
        let fixture = try makeFixture(runtime: runtime) { settings in
            settings.apiProvider = "OPENROUTER"
            settings.defaultModel = "openai/gpt-4o-mini"
            settings.isStreamingEnabled = true
        }
        try fixture.credentials.setCredential("openrouter-key", for: .openRouter)

        let conversationCountBefore = try await fixture.dbQueue.read { db in
            try Conversation.fetchCount(db)
        }

        let result = try await fixture.repository.runShortcut(
            prompt: "hello shortcut",
            provider: "OPENROUTER",
            model: "openai/gpt-4o-mini",
            systemPromptOverride: "system from shortcut",
            saveToNewConversation: false
        )

        XCTAssertEqual(result.text, "shortcut answer")
        XCTAssertNil(result.conversationId)
        XCTAssertNil(result.userMessageId)
        XCTAssertNil(result.assistantMessageId)

        let conversationCountAfter = try await fixture.dbQueue.read { db in
            try Conversation.fetchCount(db)
        }
        XCTAssertEqual(conversationCountAfter, conversationCountBefore)

        let request = try XCTUnwrap(runtime.calls.last?.request)
        XCTAssertFalse(request.stream)
        XCTAssertEqual(request.model, "openai/gpt-4o-mini")
        XCTAssertEqual(request.messages.last?.content, "hello shortcut")
    }

    func testRunShortcutSaveCreatesConversationMessagesThinkingAndTokenUsage() async throws {
        let fixture = try makeFixture(runtime: successRuntime()) { settings in
            settings.apiProvider = "OPENROUTER"
            settings.defaultModel = "openai/gpt-4o-mini"
            settings.isStreamingEnabled = false
        }
        try fixture.credentials.setCredential("openrouter-key", for: .openRouter)

        let result = try await fixture.repository.runShortcut(
            prompt: "save this",
            provider: "OPENROUTER",
            model: "openai/gpt-4o-mini",
            systemPromptOverride: "saved system prompt",
            saveToNewConversation: true
        )

        XCTAssertEqual(result.text, "shortcut answer")
        let conversationID = try XCTUnwrap(result.conversationId)
        let assistantMessageID = try XCTUnwrap(result.assistantMessageId)

        let conversation = try fixture.repository.conversation(id: conversationID)
        XCTAssertEqual(conversation?.apiProvider, "OPENROUTER")
        XCTAssertEqual(conversation?.model, "openai/gpt-4o-mini")
        XCTAssertEqual(conversation?.systemPrompt, "saved system prompt")
        XCTAssertEqual(conversation?.title, "save this")

        let messages = try fixture.conversations.fetchMessages(conversationId: conversationID)
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages[0].role, "user")
        XCTAssertEqual(messages[0].text, "save this")
        XCTAssertEqual(messages[1].role, "model")
        XCTAssertEqual(messages[1].text, "shortcut answer")

        let assistant = try XCTUnwrap(fixture.conversations.fetchFullMessage(id: assistantMessageID))
        XCTAssertEqual(assistant.thinkingStream, "shortcut thinking")

        let usageRecord = try await fixture.dbQueue.read { db in
            try TokenUsageRecord.fetchOne(db)
        }
        XCTAssertEqual(usageRecord?.requestType, "shortcut")
        XCTAssertEqual(usageRecord?.conversationId, conversationID)
        XCTAssertEqual(usageRecord?.inputTokens, 10)
        XCTAssertEqual(usageRecord?.outputTokens, 5)
    }

    func testRunShortcutAcceptsCustomModelIDOutsideCatalog() async throws {
        let runtime = successRuntime()
        let fixture = try makeFixture(runtime: runtime) { settings in
            settings.apiProvider = "OPENROUTER"
            settings.defaultModel = "openai/gpt-4o-mini"
            settings.isStreamingEnabled = false
        }
        try fixture.credentials.setCredential("openrouter-key", for: .openRouter)

        let result = try await fixture.repository.runShortcut(
            prompt: "custom model",
            provider: "OPENROUTER",
            model: "vendor/custom-model-id",
            saveToNewConversation: false
        )

        XCTAssertEqual(result.text, "shortcut answer")
        XCTAssertEqual(runtime.calls.last?.request.model, "vendor/custom-model-id")
    }

    func testRunShortcutRejectsEmptyPrompt() async throws {
        let fixture = try makeFixture()
        do {
            _ = try await fixture.repository.runShortcut(
                prompt: "   ",
                provider: "OPENROUTER",
                model: "openai/gpt-4o-mini",
                saveToNewConversation: false
            )
            XCTFail("Expected empty prompt to throw")
        } catch let error as ProviderClientError {
            if case let .parseFailure(message) = error {
                XCTAssertEqual(message, L10n.text("Shortcuts: プロンプトを入力してください。"))
            } else {
                XCTFail("Unexpected ProviderClientError: \(error)")
            }
        }
    }

    func testRunShortcutRejectsEmptyModel() async throws {
        let fixture = try makeFixture()
        do {
            _ = try await fixture.repository.runShortcut(
                prompt: "hello",
                provider: "OPENROUTER",
                model: "  ",
                saveToNewConversation: false
            )
            XCTFail("Expected empty model to throw")
        } catch let error as ProviderClientError {
            if case let .parseFailure(message) = error {
                XCTAssertEqual(message, L10n.text("Shortcuts: モデル ID を入力してください。"))
            } else {
                XCTFail("Unexpected ProviderClientError: \(error)")
            }
        }
    }

    func testRunShortcutRejectsUnknownProvider() async throws {
        let fixture = try makeFixture()
        do {
            _ = try await fixture.repository.runShortcut(
                prompt: "hello",
                provider: "NOT_A_PROVIDER",
                model: "openai/gpt-4o-mini",
                saveToNewConversation: false
            )
            XCTFail("Expected unknown provider to throw")
        } catch let error as ProviderClientError {
            if case let .parseFailure(message) = error {
                XCTAssertEqual(message, L10n.text("Shortcuts: 不明なプロバイダです。"))
            } else {
                XCTFail("Unexpected ProviderClientError: \(error)")
            }
        }
    }

    func testRunShortcutPropagatesProviderHTTPError() async throws {
        let runtime = PiStreamSpy { _, _ in
            throw ProviderClientError.httpStatus(500, "provider failed")
        }
        let fixture = try makeFixture(runtime: runtime) { settings in
            settings.apiProvider = "OPENROUTER"
            settings.defaultModel = "openai/gpt-4o-mini"
            settings.isStreamingEnabled = false
        }
        try fixture.credentials.setCredential("openrouter-key", for: .openRouter)

        do {
            _ = try await fixture.repository.runShortcut(
                prompt: "hello",
                provider: "OPENROUTER",
                model: "openai/gpt-4o-mini",
                saveToNewConversation: false
            )
            XCTFail("Expected provider HTTP error to throw")
        } catch {
            XCTAssertTrue(error is ProviderClientError)
        }
    }

    private func makeFixture(
        runtime: PiStreamSpy = PiStreamSpy(),
        configureSettings: ((inout AppSettings) -> Void)? = nil
    ) throws -> (
        repository: ChatRepository,
        conversations: ConversationRepository,
        credentials: TestCredentialStore,
        dbQueue: DatabaseQueue
    ) {
        let dbQueue = try DatabaseQueue()
        try AppDatabase.migrator.migrate(dbQueue)

        let settings = SettingsRepository(dbQueue: dbQueue)
        let conversations = ConversationRepository(dbQueue: dbQueue)
        let credentials = TestCredentialStore()
        if configureSettings != nil {
            var current = try settings.load()
            configureSettings?(&current)
            try settings.save(current)
        }

        let repository = ChatRepositoryTestSupport.makeRepository(
            dbQueue: dbQueue,
            settings: settings,
            conversations: conversations,
            credentials: credentials,
            piStream: runtime.stream,
            pricingRepository: NoopPricingRepository()
        )
        return (repository, conversations, credentials, dbQueue)
    }

    private func successRuntime() -> PiStreamSpy {
        PiStreamSpy { _, _ in
            [.completed(ProviderResponse(
                text: "shortcut answer",
                reasoningSummary: "shortcut thinking",
                usage: ProviderUsage(inputTokens: 10, outputTokens: 5, totalTokens: 15)
            ))]
        }
    }
}

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

private actor PricingSpyRepository: LiteLlmPricingEstimating {
    struct Call: Equatable {
        var provider: String
        var model: String
        var inputTokens: Int
        var outputTokens: Int
        var cachedInputTokens: Int?
        var cacheCreationInputTokens: Int?
        var reasoningTokens: Int?
    }

    private(set) var calls: [Call] = []
    private let returnValue: Double?

    init(returnValue: Double?) {
        self.returnValue = returnValue
    }

    func estimateCostUsd(
        provider: String,
        model: String,
        inputTokens: Int,
        outputTokens: Int,
        cachedInputTokens: Int?,
        cacheCreationInputTokens: Int?,
        reasoningTokens: Int?
    ) async -> Double? {
        calls.append(
            Call(
                provider: provider,
                model: model,
                inputTokens: inputTokens,
                outputTokens: outputTokens,
                cachedInputTokens: cachedInputTokens,
                cacheCreationInputTokens: cacheCreationInputTokens,
                reasoningTokens: reasoningTokens
            )
        )
        return returnValue
    }

    func modelSupportsVision(provider: String, model: String) async -> Bool {
        false
    }

    func lastCall() -> Call? {
        calls.last
    }
}

final class ChatRepositorySyncTests: XCTestCase {
    func testCreateConversationReusesExistingEmptyNewChat() throws {
        let fixture = try makeFixture()

        let firstID = try fixture.repository.createConversation(title: "New Chat")
        let secondID = try fixture.repository.createConversation(title: "New Chat")

        XCTAssertEqual(secondID, firstID)
    }

    func testGeneratedAttachmentsAreDeduplicatedForMessagesAndVariants() throws {
        let fixture = try makeFixture()
        let conversationID = try fixture.repository.createConversation(title: "Attachment Test")
        let messageID = try fixture.conversations.insertMessage(
            ChatMessage(conversationId: conversationID, role: "model", text: "answer")
        )
        let variant = try fixture.conversations.insertMessageVariant(
            baseMessageId: messageID,
            text: "variant"
        )
        let variantID = try XCTUnwrap(variant.id)

        try fixture.conversations.appendAttachments(messageId: messageID, paths: ["/tmp/a.txt", "/tmp/a.txt"])
        try fixture.conversations.appendAttachments(messageId: messageID, paths: ["/tmp/a.txt", "/tmp/b.txt"])
        try fixture.conversations.appendAttachments(variantId: variantID, paths: ["/tmp/v.txt", "/tmp/v.txt"])

        let full = try XCTUnwrap(fixture.conversations.fetchFullMessage(id: messageID))
        XCTAssertEqual(Self.decodeAttachments(full.message.attachmentsJSON), ["/tmp/a.txt", "/tmp/b.txt"])
        XCTAssertEqual(Self.decodeAttachments(full.variants.first?.attachmentsJSON ?? "[]"), ["/tmp/v.txt"])
    }

    func testSendMessageRenamesDefaultConversationToFirstPrompt() async throws {
        let fixture = try makeFixture()
        let conversationID = try fixture.repository.createConversation(title: "New Chat")

        let firstPrompt = "  First   line\nsecond line " + String(repeating: "x", count: 80)
        do {
            _ = try await fixture.repository.sendMessage(
                conversationId: conversationID,
                text: firstPrompt,
                attachments: []
            )
            XCTFail("Expected sendMessage to fail without credentials in test fixture.")
        } catch {}

        let normalized = firstPrompt
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let expected = String(normalized.prefix(50))

        let updated = try fixture.repository.conversation(id: conversationID)
        XCTAssertEqual(updated?.title, expected)
    }

    func testSendMessageDoesNotOverwriteConversationTitleAfterFirstPrompt() async throws {
        let fixture = try makeFixture()
        let conversationID = try fixture.repository.createConversation(title: "Secret Chat")

        do {
            _ = try await fixture.repository.sendMessage(
                conversationId: conversationID,
                text: "first prompt",
                attachments: []
            )
            XCTFail("Expected sendMessage to fail without credentials in test fixture.")
        } catch {}

        do {
            _ = try await fixture.repository.sendMessage(
                conversationId: conversationID,
                text: "second prompt should not replace title",
                attachments: []
            )
            XCTFail("Expected sendMessage to fail without credentials in test fixture.")
        } catch {}

        let updated = try fixture.repository.conversation(id: conversationID)
        XCTAssertEqual(updated?.title, "first prompt")
    }

    func testUpdateConversationModelAndProviderUpdatesConversation() throws {
        let fixture = try makeFixture()
        let conversationID = try fixture.repository.ensureInitialConversation()

        try fixture.repository.updateConversationModelAndProvider(
            conversationId: conversationID,
            model: "openai/gpt-4o-mini",
            provider: "OPENROUTER"
        )

        let updated = try fixture.repository.conversation(id: conversationID)
        XCTAssertEqual(updated?.model, "openai/gpt-4o-mini")
        XCTAssertEqual(updated?.apiProvider, "OPENROUTER")
    }

    func testSyncNewChatWithSettingsIfEmptyUpdatesConversationProviderAndModel() throws {
        let fixture = try makeFixture()
        let conversationID = try fixture.repository.ensureInitialConversation()
        let previous = try fixture.repository.loadSettings()

        var next = previous
        next.apiProvider = "OPENROUTER"
        next.defaultModel = "openai/gpt-4o-mini"
        next.providerDefaultModelsJSON = #"{"GEMINI":"gemini-2.5-flash","OPENROUTER":"openai/gpt-4o-mini"}"#
        next.systemPrompt = "updated prompt"

        let synced = try fixture.repository.syncNewChatWithSettingsIfEmpty(
            conversationId: conversationID,
            settings: next,
            previousSettings: previous
        )

        XCTAssertEqual(synced?.apiProvider, "OPENROUTER")
        XCTAssertEqual(synced?.model, "openai/gpt-4o-mini")
        XCTAssertEqual(synced?.systemPrompt, "updated prompt")
    }

    func testSyncNewChatWithSettingsIfEmptySkipsConversationWithMessages() throws {
        let fixture = try makeFixture()
        let conversationID = try fixture.repository.ensureInitialConversation()
        let previous = try fixture.repository.loadSettings()
        let originalConversation = try fixture.repository.conversation(id: conversationID)

        _ = try fixture.conversations.insertMessage(
            ChatMessage(
                conversationId: conversationID,
                role: "user",
                text: "hello"
            )
        )

        var next = previous
        next.apiProvider = "OPENROUTER"
        next.defaultModel = "openai/gpt-4o-mini"
        next.providerDefaultModelsJSON = #"{"GEMINI":"gemini-2.5-flash","OPENROUTER":"openai/gpt-4o-mini"}"#

        let synced = try fixture.repository.syncNewChatWithSettingsIfEmpty(
            conversationId: conversationID,
            settings: next,
            previousSettings: previous
        )

        XCTAssertEqual(synced?.apiProvider, originalConversation?.apiProvider)
        XCTAssertEqual(synced?.model, originalConversation?.model)
    }

    func testSendMessageRecordsTokenUsageFromUsagePayload() async throws {
        let runtime = PiStreamSpy { _, _ in
            [.completed(ProviderResponse(
                text: "ok",
                usage: ProviderUsage(
                    inputTokens: 60,
                    outputTokens: 30,
                    totalTokens: 150,
                    reasoningTokens: 9,
                    cachedInputTokens: 48,
                    cacheCreationInputTokens: 12
                )
            ))]
        }
        let fixture = try makeFixture(runtime: runtime) { settings in
            settings.apiProvider = "OPENROUTER"
            settings.defaultModel = "openai/gpt-4o-mini"
            settings.providerDefaultModelsJSON = #"{"OPENROUTER":"openai/gpt-4o-mini"}"#
            settings.isStreamingEnabled = false
        }
        try fixture.credentials.setCredential("openrouter-key", for: .openRouter)

        let conversationID = try fixture.repository.createConversation(title: "New Chat")
        _ = try await fixture.repository.sendMessage(
            conversationId: conversationID,
            text: "hello",
            attachments: []
        )

        let totals = try fixture.conversations.fetchTokenUsageTotals(sinceEpochMs: 0)
        XCTAssertEqual(totals.requestCount, 1)
        XCTAssertEqual(totals.inputTokens, 60)
        XCTAssertEqual(totals.outputTokens, 30)
        XCTAssertEqual(totals.cachedInputTokens, 48)
        XCTAssertEqual(totals.cacheCreationInputTokens, 12)
        XCTAssertEqual(totals.reasoningTokens, 9)
        XCTAssertEqual(totals.totalTokens, 150)
    }

    func testSendMessageRecordsPiAssistantUsageSamplesAsSeparateRequests() async throws {
        let runtime = PiStreamSpy { _, _ in
            [.completed(ProviderResponse(
                text: "ok",
                usage: ProviderUsage(inputTokens: 150, outputTokens: 30, totalTokens: 180),
                usageSamples: [
                    ProviderUsage(inputTokens: 100, outputTokens: 20, totalTokens: 120),
                    ProviderUsage(inputTokens: 50, outputTokens: 10, totalTokens: 60)
                ]
            ))]
        }
        let fixture = try makeFixture(runtime: runtime) { settings in
            settings.apiProvider = "OPENROUTER"
            settings.defaultModel = "openai/gpt-4o-mini"
            settings.providerDefaultModelsJSON = #"{"OPENROUTER":"openai/gpt-4o-mini"}"#
            settings.isStreamingEnabled = false
        }
        try fixture.credentials.setCredential("openrouter-key", for: .openRouter)

        let conversationID = try fixture.repository.createConversation(title: "New Chat")
        _ = try await fixture.repository.sendMessage(
            conversationId: conversationID,
            text: "hello",
            attachments: []
        )

        let totals = try fixture.conversations.fetchTokenUsageTotals(sinceEpochMs: 0)
        XCTAssertEqual(totals.requestCount, 2)
        XCTAssertEqual(totals.inputTokens, 150)
        XCTAssertEqual(totals.outputTokens, 30)
        XCTAssertEqual(totals.totalTokens, 180)
    }

    func testSendMessagePassesCacheAndReasoningUsageToPricingEstimator() async throws {
        let runtime = PiStreamSpy { _, _ in
            [.completed(ProviderResponse(
                text: "ok",
                usage: ProviderUsage(
                    inputTokens: 45,
                    outputTokens: 20,
                    totalTokens: 100,
                    reasoningTokens: 7,
                    cachedInputTokens: 30,
                    cacheCreationInputTokens: 5
                )
            ))]
        }
        let pricingSpy = PricingSpyRepository(returnValue: 0.42)
        let fixture = try makeFixture(
            runtime: runtime,
            pricingRepository: pricingSpy
        ) { settings in
            settings.apiProvider = "OPENROUTER"
            settings.defaultModel = "openai/gpt-4o-mini"
            settings.providerDefaultModelsJSON = #"{"OPENROUTER":"openai/gpt-4o-mini"}"#
            settings.isStreamingEnabled = false
        }
        try fixture.credentials.setCredential("openrouter-key", for: .openRouter)

        let conversationID = try fixture.repository.createConversation(title: "New Chat")
        _ = try await fixture.repository.sendMessage(
            conversationId: conversationID,
            text: "hello",
            attachments: []
        )

        let lastCall = await pricingSpy.lastCall()
        let call = try XCTUnwrap(lastCall)
        XCTAssertEqual(call.provider, "OPENROUTER")
        XCTAssertEqual(call.model, "openai/gpt-4o-mini")
        XCTAssertEqual(call.inputTokens, 45)
        XCTAssertEqual(call.outputTokens, 20)
        XCTAssertEqual(call.cachedInputTokens, 30)
        XCTAssertEqual(call.cacheCreationInputTokens, 5)
        XCTAssertEqual(call.reasoningTokens, 7)

        let totals = try fixture.conversations.fetchTokenUsageTotals(sinceEpochMs: 0)
        XCTAssertEqual(totals.totalCostUsd, 0.42, accuracy: 0.000_001)
    }

    func testOpenCodeGoNormalStreamUsesSinglePiRun() async throws {
        let runtime = PiStreamSpy { _, _ in
            [
                .textDelta("normal stream text"),
                .completed(ProviderResponse(text: "normal stream text"))
            ]
        }
        let fixture = try makeFixture(runtime: runtime) { settings in
            settings.apiProvider = "OPENCODE_GO"
            settings.defaultModel = "deepseek-v4-flash"
            settings.providerDefaultModelsJSON = #"{"OPENCODE_GO":"deepseek-v4-flash"}"#
            settings.isStreamingEnabled = true
        }
        try fixture.credentials.setCredential("opencode-go-key", for: .openCodeGo)

        let conversationID = try fixture.repository.createConversation(title: "New Chat")
        let result = try await fixture.repository.sendMessage(
            conversationId: conversationID,
            text: "hello",
            attachments: []
        )

        XCTAssertEqual(result.response.text, "normal stream text")
        XCTAssertEqual(runtime.calls.count, 1)

        let saved = try fixture.conversations.fetchFullMessage(id: result.assistantMessageId)
        XCTAssertEqual(saved?.displayText, "normal stream text")
    }

    func testOtherProviderEmptyStreamUsesSinglePiRun() async throws {
        let runtime = PiStreamSpy { _, _ in
            [.completed(ProviderResponse(text: ""))]
        }
        let fixture = try makeFixture(runtime: runtime) { settings in
            settings.apiProvider = "OPENROUTER"
            settings.defaultModel = "openai/gpt-4o-mini"
            settings.providerDefaultModelsJSON = #"{"OPENROUTER":"openai/gpt-4o-mini"}"#
            settings.isStreamingEnabled = true
        }
        try fixture.credentials.setCredential("openrouter-key", for: .openRouter)

        let conversationID = try fixture.repository.createConversation(title: "New Chat")
        let result = try await fixture.repository.sendMessage(
            conversationId: conversationID,
            text: "hello",
            attachments: []
        )

        XCTAssertEqual(result.response.text, "")
        XCTAssertEqual(runtime.calls.count, 1)
    }

    private func makeFixture(
        runtime: PiStreamSpy = PiStreamSpy(),
        pricingRepository: any LiteLlmPricingEstimating = NoopPricingRepository(),
        configureSettings: ((inout AppSettings) -> Void)? = nil
    ) throws -> (repository: ChatRepository, conversations: ConversationRepository, credentials: TestCredentialStore) {
        let dbQueue = try DatabaseQueue()
        try AppDatabase.migrator.migrate(dbQueue)

        let settings = SettingsRepository(dbQueue: dbQueue)
        let conversations = ConversationRepository(dbQueue: dbQueue)
        let credentials = TestCredentialStore()
        let modelService = OpenRouterModelService(credentialStore: credentials)

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
            pricingRepository: pricingRepository
        )
        return (repository, conversations, credentials)
    }

    private static func decodeAttachments(_ rawValue: String) -> [String] {
        guard let data = rawValue.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }
}

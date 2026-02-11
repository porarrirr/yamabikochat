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

private final class GeminiStreamFallbackHTTPClient: HTTPClientProtocol {
    private let streamLines: [String]
    private let nonStreamingBody: String
    private(set) var streamCallCount: Int = 0
    private(set) var sendCallCount: Int = 0

    init(streamLines: [String], nonStreamingBody: String) {
        self.streamLines = streamLines
        self.nonStreamingBody = nonStreamingBody
    }

    func send(_ request: HTTPRequest) async throws -> (Data, HTTPURLResponse) {
        sendCallCount += 1
        let response = HTTPURLResponse(
            url: request.url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        return (nonStreamingBody.data(using: .utf8) ?? Data(), response)
    }

    func stream(_ request: HTTPRequest) async throws -> (AsyncThrowingStream<String, Error>, HTTPURLResponse) {
        streamCallCount += 1
        let response = HTTPURLResponse(
            url: request.url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        let stream = AsyncThrowingStream<String, Error> { continuation in
            for line in streamLines {
                continuation.yield(line)
            }
            continuation.finish()
        }
        return (stream, response)
    }
}

final class ChatRepositorySyncTests: XCTestCase {
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

    func testSendMessageFallsBackToNonStreamingWhenGeminiAuthStreamIsEmpty() async throws {
        let httpClient = GeminiStreamFallbackHTTPClient(
            streamLines: [
                #"data: {"event":"keepalive"}"#,
                "",
                "data: [DONE]",
                ""
            ],
            nonStreamingBody: #"{"response":{"candidates":[{"content":{"parts":[{"text":"fallback answer"}]}}]}}"#
        )
        let fixture = try makeFixture(httpClient: httpClient) { settings in
            settings.apiProvider = "GEMINI_AUTH"
            settings.defaultModel = "gemini-2.5-flash"
            settings.providerDefaultModelsJSON = #"{"GEMINI_AUTH":"gemini-2.5-flash"}"#
        }
        try fixture.credentials.setGeminiAccessToken("gemini-access-token")
        try fixture.credentials.saveSecret("project-1", key: "gemini_project_id")

        let conversationID = try fixture.repository.createConversation(title: "New Chat")
        let result = try await fixture.repository.sendMessage(
            conversationId: conversationID,
            text: "hello",
            attachments: []
        )

        XCTAssertEqual(result.response.text, "fallback answer")
        let assistant = try fixture.conversations.fetchLastAssistantMessage(conversationId: conversationID)
        XCTAssertEqual(assistant?.text, "fallback answer")
        XCTAssertEqual(httpClient.streamCallCount, 1)
        XCTAssertEqual(httpClient.sendCallCount, 1)
    }

    func testRegenerateFallsBackToNonStreamingWhenGeminiAuthStreamIsEmpty() async throws {
        let httpClient = GeminiStreamFallbackHTTPClient(
            streamLines: [
                #"data: {"event":"keepalive"}"#,
                "",
                "data: [DONE]",
                ""
            ],
            nonStreamingBody: #"{"response":{"candidates":[{"content":{"parts":[{"text":"fallback answer"}]}}]}}"#
        )
        let fixture = try makeFixture(httpClient: httpClient) { settings in
            settings.apiProvider = "GEMINI_AUTH"
            settings.defaultModel = "gemini-2.5-flash"
            settings.providerDefaultModelsJSON = #"{"GEMINI_AUTH":"gemini-2.5-flash"}"#
        }
        try fixture.credentials.setGeminiAccessToken("gemini-access-token")
        try fixture.credentials.saveSecret("project-1", key: "gemini_project_id")

        let conversationID = try fixture.repository.createConversation(title: "New Chat")
        _ = try await fixture.repository.sendMessage(
            conversationId: conversationID,
            text: "initial",
            attachments: []
        )

        let targetMessageID = try await fixture.repository.regenerateLastAssistantVariant(conversationId: conversationID)
        let full = try fixture.conversations.fetchFullMessage(id: targetMessageID)
        XCTAssertEqual(full?.variants.last?.text, "fallback answer")
        XCTAssertEqual(httpClient.streamCallCount, 2)
        XCTAssertEqual(httpClient.sendCallCount, 2)
    }

    private func makeFixture(
        httpClient: HTTPClientProtocol = URLSessionHTTPClient(),
        configureSettings: ((inout AppSettings) -> Void)? = nil
    ) throws -> (repository: ChatRepository, conversations: ConversationRepository, credentials: TestCredentialStore) {
        let dbQueue = try DatabaseQueue()
        try AppDatabase.migrator.migrate(dbQueue)

        let settings = SettingsRepository(dbQueue: dbQueue)
        let conversations = ConversationRepository(dbQueue: dbQueue)
        let credentials = TestCredentialStore()
        let providers = ProviderGateway(
            settingsRepository: settings,
            credentialStore: credentials,
            httpClient: httpClient
        )
        let modelService = OpenRouterModelService(credentialStore: credentials)
        let codexAuth = CodexAuthRepository(credentialStore: credentials)
        let geminiAuth = GeminiAuthRepository(credentialStore: credentials)

        if configureSettings != nil {
            var current = try settings.load()
            configureSettings?(&current)
            try settings.save(current)
        }

        let repository = ChatRepository(
            conversations: conversations,
            settings: settings,
            providers: providers,
            credentialStore: credentials,
            modelService: modelService,
            codexAuthRepository: codexAuth,
            geminiAuthRepository: geminiAuth
        )
        return (repository, conversations, credentials)
    }
}

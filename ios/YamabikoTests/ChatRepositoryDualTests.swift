import XCTest
import GRDB
@testable import YamabikoChat

private final class DualTestCredentialStore: SecureCredentialStore {
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

private final class DualChatHTTPClient: HTTPClientProtocol {
    private let lock = NSLock()
    private var bodies: [[String: Any]] = []
    var failModels: Set<String> = []

    func send(_ request: HTTPRequest) async throws -> (Data, HTTPURLResponse) {
        let payload = parseBody(request.body)
        lock.lock()
        bodies.append(payload)
        lock.unlock()

        let model = payload["model"] as? String ?? ""
        if failModels.contains(model) {
            return (
                Data(#"{"error":"forced failure"}"#.utf8),
                HTTPURLResponse(url: request.url, statusCode: 500, httpVersion: nil, headerFields: nil)!
            )
        }

        let text = "response-\(model)"
        let responseBody = #"{"choices":[{"message":{"content":"\#(text)"}}]}"#
        return (
            Data(responseBody.utf8),
            HTTPURLResponse(url: request.url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        )
    }

    func stream(_ request: HTTPRequest) async throws -> (AsyncThrowingStream<String, Error>, HTTPURLResponse) {
        let stream = AsyncThrowingStream<String, Error> { continuation in
            continuation.finish()
        }
        return (
            stream,
            HTTPURLResponse(url: request.url, statusCode: 500, httpVersion: nil, headerFields: nil)!
        )
    }

    func payloads(forModel model: String) -> [[String: Any]] {
        lock.lock()
        defer { lock.unlock() }
        return bodies.filter { ($0["model"] as? String) == model }
    }

    private func parseBody(_ data: Data?) -> [String: Any] {
        guard
            let data,
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return [:]
        }
        return object
    }
}

final class ChatRepositoryDualTests: XCTestCase {
    func testSendDualMessageStoresUserAndModelRowsSeparately() async throws {
        let httpClient = DualChatHTTPClient()
        let fixture = try makeFixture(httpClient: httpClient) { settings in
            settings.dualProviderA = "OPENAI"
            settings.dualProviderB = "OPENAI"
            settings.dualModelA = "model-a"
            settings.dualModelB = "model-b"
            settings.isDualModeEnabled = true
            settings.isStreamingEnabled = false
        }
        try fixture.credentials.setCredential("test-api-key", for: .openAI)

        let conversationID = try fixture.repository.createConversation(title: "New Chat")
        let result = try await fixture.repository.sendDualMessage(
            conversationId: conversationID,
            text: "hello dual",
            attachments: ["file:///tmp/sample.txt"]
        )

        let rows = try fixture.conversations.fetchDualMessages(conversationId: conversationID)
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].parsedRole, .user)
        XCTAssertEqual(rows[0].userText, "hello dual")
        XCTAssertEqual(rows[0].attachments, ["file:///tmp/sample.txt"])
        XCTAssertEqual(rows[1].parsedRole, .dualModel)
        XCTAssertEqual(rows[1].modelAText, "response-model-a")
        XCTAssertEqual(rows[1].modelBText, "response-model-b")
        XCTAssertEqual(result.parsedRole, .dualModel)
    }

    func testSendDualMessageBuildsIndependentHistoryPerSide() async throws {
        let httpClient = DualChatHTTPClient()
        let fixture = try makeFixture(httpClient: httpClient) { settings in
            settings.dualProviderA = "OPENAI"
            settings.dualProviderB = "OPENAI"
            settings.dualModelA = "model-a"
            settings.dualModelB = "model-b"
            settings.isDualModeEnabled = true
            settings.isStreamingEnabled = false
        }
        try fixture.credentials.setCredential("test-api-key", for: .openAI)

        let conversationID = try fixture.repository.createConversation(title: "New Chat")
        _ = try await fixture.repository.sendDualMessage(conversationId: conversationID, text: "first")
        _ = try await fixture.repository.sendDualMessage(conversationId: conversationID, text: "second")

        let modelARequests = httpClient.payloads(forModel: "model-a")
        let modelBRequests = httpClient.payloads(forModel: "model-b")
        XCTAssertGreaterThanOrEqual(modelARequests.count, 2)
        XCTAssertGreaterThanOrEqual(modelBRequests.count, 2)

        let modelALastMessages = modelARequests.last?["messages"] as? [[String: Any]] ?? []
        let modelAJoined = modelALastMessages.compactMap { $0["content"] as? String }.joined(separator: "\n")
        XCTAssertTrue(modelAJoined.contains("response-model-a"))
        XCTAssertFalse(modelAJoined.contains("response-model-b"))

        let modelBLastMessages = modelBRequests.last?["messages"] as? [[String: Any]] ?? []
        let modelBJoined = modelBLastMessages.compactMap { $0["content"] as? String }.joined(separator: "\n")
        XCTAssertTrue(modelBJoined.contains("response-model-b"))
        XCTAssertFalse(modelBJoined.contains("response-model-a"))
    }

    func testSendDualMessageKeepsPartialSuccessWhenOneSideFails() async throws {
        let httpClient = DualChatHTTPClient()
        httpClient.failModels = ["model-b"]
        let fixture = try makeFixture(httpClient: httpClient) { settings in
            settings.dualProviderA = "OPENAI"
            settings.dualProviderB = "OPENAI"
            settings.dualModelA = "model-a"
            settings.dualModelB = "model-b"
            settings.isDualModeEnabled = true
            settings.isStreamingEnabled = false
        }
        try fixture.credentials.setCredential("test-api-key", for: .openAI)

        let conversationID = try fixture.repository.createConversation(title: "New Chat")
        let result = try await fixture.repository.sendDualMessage(conversationId: conversationID, text: "hello")

        XCTAssertEqual(result.modelAText, "response-model-a")
        XCTAssertTrue(result.modelBText.hasPrefix("エラー:"))
        let rows = try fixture.conversations.fetchDualMessages(conversationId: conversationID)
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows.last?.parsedRole, .dualModel)
    }

    private func makeFixture(
        httpClient: HTTPClientProtocol,
        configureSettings: ((inout AppSettings) -> Void)? = nil
    ) throws -> (
        repository: ChatRepository,
        conversations: ConversationRepository,
        credentials: DualTestCredentialStore
    ) {
        let dbQueue = try DatabaseQueue()
        try AppDatabase.migrator.migrate(dbQueue)

        let settings = SettingsRepository(dbQueue: dbQueue)
        let conversations = ConversationRepository(dbQueue: dbQueue)
        let credentials = DualTestCredentialStore()
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

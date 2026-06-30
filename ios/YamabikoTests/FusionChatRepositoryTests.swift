import XCTest
import GRDB
@testable import YamabikoChat

private let fusionJudgeJSON = """
{
  "consensus": ["both agree"],
  "contradictions": [],
  "unique_insights": [],
  "coverage_gaps": [],
  "suspected_errors": [],
  "strongest_answer_parts": [{"model": "gemini-2.5-flash", "part": "ok", "reason": "clear"}],
  "recommended_final_position": "Merged",
  "confidence": "high"
}
"""

private final class FusionTestCredentialStore: SecureCredentialStore {
    private var storage: [String: String] = [:]

    func saveSecret(_ value: String?, key: String) throws {
        if let value { storage[key] = value } else { storage.removeValue(forKey: key) }
    }

    func readSecret(key: String) throws -> String? { storage[key] }
    func deleteSecret(key: String) throws { storage.removeValue(forKey: key) }
}

private final class FusionChatHTTPClient: HTTPClientProtocol {
    private let counterLock = NSLock()
    private(set) var generateCallCount = 0
    private(set) var streamCallCount = 0

    func send(_ request: HTTPRequest) async throws -> (Data, HTTPURLResponse) {
        counterLock.withLock { generateCallCount += 1 }

        let bodyText = requestBodyText(request.body)
        let content = responseContent(for: bodyText)
        let data: Data
        if bodyText.contains("contents") || request.url.absoluteString.contains("generativelanguage") {
            data = Data(#"{"candidates":[{"content":{"parts":[{"text":"\#(content)"}]}}]}"#.utf8)
        } else {
            data = Data(#"{"choices":[{"message":{"content":"\#(content)"}}]}"#.utf8)
        }
        return (
            data,
            HTTPURLResponse(url: request.url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        )
    }

    func stream(_ request: HTTPRequest) async throws -> (AsyncThrowingStream<String, Error>, HTTPURLResponse) {
        counterLock.withLock { streamCallCount += 1 }

        let stream = AsyncThrowingStream<String, Error> { continuation in
            let isGemini = request.url.absoluteString.contains("generativelanguage")
            if isGemini {
                continuation.yield(#"data: {"candidates":[{"content":{"parts":[{"text":"Fused "}]}}]}"#)
                continuation.yield("")
                continuation.yield(#"data: {"candidates":[{"content":{"parts":[{"text":"answer"}]}}]}"#)
                continuation.yield("")
            } else {
                continuation.yield(#"data: {"choices":[{"delta":{"content":"Fused "}}]}"#)
                continuation.yield("")
                continuation.yield(#"data: {"choices":[{"delta":{"content":"answer"}}]}"#)
                continuation.yield("")
            }
            continuation.yield("data: [DONE]")
            continuation.yield("")
            continuation.finish()
        }
        return (
            stream,
            HTTPURLResponse(url: request.url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        )
    }

    private func requestBodyText(_ data: Data?) -> String {
        guard let data, let text = String(data: data, encoding: .utf8) else { return "" }
        return text
    }

    private func responseContent(for bodyText: String) -> String {
        if bodyText.contains("judge comparing") || bodyText.contains("Compare these answers") {
            return fusionJudgeJSON
        }
        if bodyText.contains("analysis panel") {
            return "panel-answer"
        }
        return "fallback"
    }
}

private final class FusionFailingPanelHTTPClient: HTTPClientProtocol {
    private let counterLock = NSLock()
    private(set) var generateCallCount = 0
    private let failingPanelCount = 2

    func send(_ request: HTTPRequest) async throws -> (Data, HTTPURLResponse) {
        let callIndex = counterLock.withLock {
            generateCallCount += 1
            return generateCallCount
        }
        if callIndex <= failingPanelCount {
            throw ProviderClientError.httpStatus(503, "panel failed")
        }

        let isGemini = request.url.absoluteString.contains("generativelanguage")
        let data: Data
        if isGemini {
            data = Data(#"{"candidates":[{"content":{"parts":[{"text":"fallback answer"}]}}]}"#.utf8)
        } else {
            data = Data(#"{"choices":[{"message":{"content":"fallback answer"}}]}"#.utf8)
        }
        return (
            data,
            HTTPURLResponse(url: request.url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        )
    }

    func stream(_ request: HTTPRequest) async throws -> (AsyncThrowingStream<String, Error>, HTTPURLResponse) {
        throw ProviderClientError.parseFailure("stream not expected")
    }
}

final class FusionChatRepositoryTests: XCTestCase {
    func testSendFusionMessageStoresMessagesTraceAndStreamsSynthesis() async throws {
        let httpClient = FusionChatHTTPClient()
        let fixture = try makeFixture(httpClient: httpClient) { settings in
            settings.isFusionModeEnabled = true
            settings.fusionPresetName = "fast"
            settings.isStreamingEnabled = true
            settings.fusionDebugModeEnabled = true
        }
        try fixture.credentials.setCredential("test-gemini-key", for: .gemini)
        try fixture.credentials.setCredential("test-openrouter-key", for: .openRouter)

        let conversationID = try fixture.repository.createConversation(title: "Fusion Test")
        let result = try await fixture.repository.sendFusionMessage(
            conversationId: conversationID,
            text: "What is fusion?"
        )

        XCTAssertGreaterThan(httpClient.generateCallCount, 0)
        XCTAssertEqual(httpClient.streamCallCount, 1)

        let messages = try fixture.conversations.fetchMessages(conversationId: conversationID)
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages[0].role, "user")
        XCTAssertEqual(messages[0].text, "What is fusion?")
        XCTAssertEqual(messages[1].role, "model")
        XCTAssertTrue(messages[1].text.contains("Fused"))
        XCTAssertNotNil(messages[1].fusionTraceId)

        if let traceId = messages[1].fusionTraceId {
            let trace = try fixture.repository.fetchFusionTrace(id: traceId)
            XCTAssertNotNil(trace)
            XCTAssertEqual(trace?.status, "completed")
            XCTAssertFalse(trace?.panelResults.isEmpty ?? true)
            XCTAssertEqual(trace?.preset, "fast")
        }

        XCTAssertEqual(result.assistantMessageId, messages[1].id)
    }

    func testSendFusionMessageFallsBackWhenAllPanelsFail() async throws {
        let httpClient = FusionFailingPanelHTTPClient()
        let fixture = try makeFixture(httpClient: httpClient) { settings in
            settings.isFusionModeEnabled = true
            settings.fusionPresetName = "fast"
            settings.isStreamingEnabled = false
        }
        try fixture.credentials.setCredential("test-gemini-key", for: .gemini)
        try fixture.credentials.setCredential("test-openrouter-key", for: .openRouter)

        let conversationID = try fixture.repository.createConversation(title: "Fusion Fallback")
        let result = try await fixture.repository.sendFusionMessage(
            conversationId: conversationID,
            text: "Need fallback"
        )

        XCTAssertGreaterThan(httpClient.generateCallCount, 2)

        let messages = try fixture.conversations.fetchMessages(conversationId: conversationID)
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages[1].role, "model")
        XCTAssertFalse(messages[1].text.isEmpty)
        XCTAssertNotNil(messages[1].fusionTraceId)

        if let traceId = messages[1].fusionTraceId {
            let trace = try fixture.repository.fetchFusionTrace(id: traceId)
            XCTAssertEqual(trace?.status, "all_panels_failed")
            XCTAssertTrue(trace?.panelResults.allSatisfy { !$0.success } ?? false)
        }

        XCTAssertEqual(result.assistantMessageId, messages[1].id)
    }

    func testSendFusionMessageRequiresFusionModeEnabled() async throws {
        let fixture = try makeFixture(httpClient: FusionChatHTTPClient())
        let conversationID = try fixture.repository.createConversation(title: "Fusion Disabled")

        do {
            _ = try await fixture.repository.sendFusionMessage(
                conversationId: conversationID,
                text: "Should fail"
            )
            XCTFail("Expected fusion mode guard")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("Fusion"))
        }
    }

    private func makeFixture(
        httpClient: HTTPClientProtocol,
        configureSettings: ((inout AppSettings) -> Void)? = nil
    ) throws -> (
        repository: ChatRepository,
        conversations: ConversationRepository,
        credentials: FusionTestCredentialStore
    ) {
        let dbQueue = try DatabaseQueue()
        try AppDatabase.migrator.migrate(dbQueue)

        let settings = SettingsRepository(dbQueue: dbQueue)
        let conversations = ConversationRepository(dbQueue: dbQueue)
        let credentials = FusionTestCredentialStore()

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
            httpClient: httpClient,
            pricingRepository: FusionNoopPricingRepository()
        )
        return (repository, conversations, credentials)
    }
}
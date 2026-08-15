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

final class FusionChatRepositoryTests: XCTestCase {
    func testSendFusionMessageStoresMessagesTraceAndStreamsSynthesis() async throws {
        let runtime = PiStreamSpy { request, _ in
            switch request.metadata["fusionPhase"] {
            case "judge":
                return [.completed(ProviderResponse(text: fusionJudgeJSON))]
            case "synthesizer":
                return [
                    .textDelta("Fused "),
                    .textDelta("answer"),
                    .completed(ProviderResponse(text: "Fused answer"))
                ]
            default:
                return [.completed(ProviderResponse(text: "panel-answer"))]
            }
        }
        let fixture = try makeFixture(runtime: runtime) { settings in
            settings.isFusionModeEnabled = true
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

        XCTAssertEqual(runtime.calls.filter { $0.request.metadata["fusionPhase"] == "synthesizer" }.count, 1)

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
            XCTAssertEqual(trace?.preset, FusionPresetLoader.presetLabel)
        }

        XCTAssertEqual(result.assistantMessageId, messages[1].id)
    }

    func testSendFusionMessagePropagatesWhenAllPanelsFail() async throws {
        let runtime = PiStreamSpy { _, _ in
            throw ProviderClientError.httpStatus(503, "panel failed")
        }
        let fixture = try makeFixture(runtime: runtime) { settings in
            settings.isFusionModeEnabled = true
            settings.isStreamingEnabled = false
            var preset = AppSettings.defaultFusionCustomPreset()
            preset.panelModels = Array(preset.panelModels.prefix(2))
            settings.fusionCustomPresetJSON = settings.encodeFusionCustomPreset(preset)
        }
        try fixture.credentials.setCredential("test-gemini-key", for: .gemini)
        try fixture.credentials.setCredential("test-openrouter-key", for: .openRouter)

        let conversationID = try fixture.repository.createConversation(title: "Fusion Failure")
        do {
            _ = try await fixture.repository.sendFusionMessage(
                conversationId: conversationID,
                text: "Fail directly"
            )
            XCTFail("Expected all panels to fail")
        } catch FusionError.allPanelsFailed {
            // Expected: there is no alternate execution path.
        }

        let messages = try fixture.conversations.fetchMessages(conversationId: conversationID)
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(runtime.calls.count, 2)
    }

    func testSendFusionMessageRequiresFusionModeEnabled() async throws {
        let fixture = try makeFixture(runtime: PiStreamSpy())
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
        runtime: PiStreamSpy,
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
            piStream: runtime.stream,
            pricingRepository: FusionNoopPricingRepository()
        )
        return (repository, conversations, credentials)
    }
}

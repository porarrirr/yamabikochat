import XCTest
import FoundationModels
@testable import YamabikoChat

@MainActor
final class PCCSessionStoreTests: XCTestCase {
    func testCanonicalHistoryTreatsExplicitFalseCompactionAsOmitted() {
        let omitted = PCCNativeRequest.Message(
            role: "assistant",
            content: .string("Answer"),
            pccTranscript: "{\"entries\":[]}"
        )
        let explicitFalse = PCCNativeRequest.Message(
            role: "assistant",
            content: .array([.object(["type": .string("text"), "text": .string("Answer")])]),
            pccTranscript: "{\"entries\":[]}",
            pccContextCompacted: false
        )

        XCTAssertEqual(omitted.canonical, explicitFalse.canonical)
    }

    func testSameChatPreservesSDKSessionAndPrefixWithPerTurnUsage() async throws {
        guard #available(iOS 27.0, *) else { throw XCTSkip("Requires iOS 27") }
        let store = PCCSessionStore()
        let model = PCCCacheTestModel()
        var request = makeRequest(key: "conversation-1")
        let first = try await run(request, model: model, store: store)
        XCTAssertEqual(first.sessionReused, false)
        request.context.messages += [assistant(first), .init(role: "user", content: .string("Next"))]
        let second = try await run(request, model: model, store: store)
        XCTAssertEqual(second.sessionReused, true)
        XCTAssertEqual(second.usage?.cachedInputTokens, 60)
        XCTAssertEqual(second.usage?.inputTokens, 100)
        XCTAssertEqual(second.usage?.outputTokens, 2)
        XCTAssertEqual(second.usage?.totalTokens, 102)
        let archived = try JSONDecoder().decode(Transcript.self, from: Data(try XCTUnwrap(second.transcript).utf8))
        XCTAssertEqual(archived.count, 1, "Only this turn is archived, not all earlier turns")
    }

    func testChangedHistorySettingsAndDifferentChatsDoNotReuseSession() async throws {
        guard #available(iOS 27.0, *) else { throw XCTSkip("Requires iOS 27") }
        for change in ["chat", "edit", "regenerate", "reasoning", "instructions", "temperature", "limit", "tools"] {
            let store = PCCSessionStore()
            let model = PCCCacheTestModel()
            var request = makeRequest(key: "conversation-1")
            let first = try await run(request, model: model, store: store)
            request.context.messages += [assistant(first), .init(role: "user", content: .string("Next"))]
            switch change {
            case "chat": request.sessionID = "conversation-2"
            case "edit": request.context.messages[0].content = .string("Edited")
            case "regenerate": request.context.messages = [request.context.messages[0]]
            case "reasoning": request.reasoningLevel = "deep"
            case "instructions": request.context.systemPrompt = "New instructions"
            case "temperature": request.temperature = 0.5
            case "limit": request.maximumResponseTokens = 100
            default: request.context.tools = [definition("lookup")]
            }
            let next = try await run(request, model: model, store: store)
            XCTAssertEqual(next.sessionReused, false, change)
        }
    }

    func testReusedToolsUseCurrentRunCallbacksAndStableDefinitionOrdering() async throws {
        guard #available(iOS 27.0, *) else { throw XCTSkip("Requires iOS 27") }
        let store = PCCSessionStore()
        let model = PCCCacheTestModel(wantsTools: true)
        var request = makeRequest(key: "conversation-tools")
        request.context.tools = [definition("lookup"), definition("unused")]
        let first = try await run(request, model: model, store: store, runID: "first", result: "first-result")
        request.context.messages += [assistant(first), .init(role: "user", content: .string("Again"))]
        request.context.tools?.reverse()
        let second = try await run(request, model: model, store: store, runID: "second", result: "second-result")
        XCTAssertEqual(second.sessionReused, true)
        XCTAssertEqual(second.text, "second-result")
        XCTAssertEqual(second.usage?.inputTokens, 200, "Do not count the first run again")
    }

    func testEvictionDeletionAndMemoryPressureRebuildSafely() async throws {
        guard #available(iOS 27.0, *) else { throw XCTSkip("Requires iOS 27") }
        for operation in ["evict", "delete", "memory", "expire"] {
            let store = PCCSessionStore(capacity: 1, idleLifetime: operation == "expire" ? 0 : 900)
            let model = PCCCacheTestModel()
            var request = makeRequest(key: "conversation-1")
            let first = try await run(request, model: model, store: store)
            switch operation {
            case "evict": _ = try await run(makeRequest(key: "conversation-2"), model: model, store: store)
            case "delete": store.removeConversations([1])
            case "memory": store.removeAll()
            default: break
            }
            request.context.messages += [assistant(first), .init(role: "user", content: .string("Next"))]
            let next = try await run(request, model: model, store: store)
            XCTAssertEqual(next.sessionReused, false, operation)
        }
    }

    func testConcurrentSameChatIsRejectedAndFailedSessionIsNotRetained() async throws {
        guard #available(iOS 27.0, *) else { throw XCTSkip("Requires iOS 27") }
        let store = PCCSessionStore()
        let signature = PCCSessionStore.Signature(modelType: "test", modelConfiguration: AnyHashable(0), instructions: "", tools: [], reasoning: "light", temperature: nil, maximumResponseTokens: nil)
        let lease = try store.acquire(key: "conversation-1", signature: signature, history: []) {
            PCCSessionStore.Entry(session: LanguageModelSession(model: PCCCacheTestModel()), router: PCCToolRouter(), signature: signature)
        }
        XCTAssertThrowsError(try store.acquire(key: "conversation-1", signature: signature, history: []) { lease.entry }) {
            XCTAssertEqual(($0 as? PCCFailure)?.code, "pcc_session_busy")
        }
        store.release(lease, completedHistory: nil)
        let next = try store.acquire(key: "conversation-1", signature: signature, history: []) { lease.entry }
        XCTAssertFalse(next.reused)
        store.removeAll()
        store.release(next, completedHistory: [])
        let cleared = try store.acquire(key: "conversation-1", signature: signature, history: []) { lease.entry }
        XCTAssertFalse(cleared.reused, "An in-flight lease must not repopulate cleared state")
        store.release(cleared, completedHistory: nil)
    }

    private func makeRequest(key: String) -> PCCNativeRequest {
        .init(context: .init(systemPrompt: "Stable instructions", messages: [.init(role: "user", content: .string("Hello"))]), reasoningLevel: "light", sessionID: key, contextSize: 32_768)
    }

    private func definition(_ name: String) -> PCCNativeRequest.ToolDefinition {
        .init(name: name, description: name, parameters: .object(["type": .string("object"), "properties": .object([:])]))
    }

    private func assistant(_ event: PCCNativeEvent) -> PCCNativeRequest.Message {
        .init(role: "assistant", content: .array([.object(["type": .string("text"), "text": .string(event.text ?? "")])]), pccTranscript: event.transcript)
    }

    @available(iOS 27.0, *)
    private func run(_ request: PCCNativeRequest, model: PCCCacheTestModel, store: PCCSessionStore, runID: String = "run", result: String = "result") async throws -> PCCNativeEvent {
        let collector = PCCCacheEventCollector()
        try await PCCSDK.execute(request, runID: runID, requestID: UUID().uuidString, using: model, store: store, executeTool: { call in
            ToolResult(callId: call.id, name: call.name, content: result)
        }, send: { event in
            XCTAssertEqual(event.runId, runID, "Retained tools must route events to the current run")
            await collector.append(event)
        })
        let last = await collector.last()
        return try XCTUnwrap(last)
    }
}

private actor PCCCacheEventCollector {
    var events: [PCCNativeEvent] = []
    func append(_ event: PCCNativeEvent) { events.append(event) }
    func last() -> PCCNativeEvent? { events.last }
}

/// Deterministic simulated cache; verifies unchanged transcript prefixes and
/// executor state retention. Actual PCC hit rate still requires a physical device.
@available(iOS 27.0, *)
private struct PCCCacheTestModel: LanguageModel {
    struct Configuration: Hashable, Sendable {
        let id = UUID()
        var wantsTools = false
    }
    let executorConfiguration: Configuration
    init(wantsTools: Bool = false) { executorConfiguration = .init(wantsTools: wantsTools) }
    var capabilities: LanguageModelCapabilities { .init([.reasoning, .toolCalling, .guidedGeneration]) }

    actor State {
        var previous: [Transcript.Entry] = []
        func cachedTokens(_ transcript: Transcript) -> Int {
            let current = Array(transcript)
            let preserved = !previous.isEmpty && Array(current.prefix(previous.count)) == previous
            previous = current
            return preserved ? 60 : 0
        }
    }

    struct Executor: LanguageModelExecutor {
        typealias Model = PCCCacheTestModel
        let state = State()
        init(configuration: Configuration) {}
        func respond(to request: LanguageModelExecutorGenerationRequest, model: PCCCacheTestModel, streamingInto channel: LanguageModelExecutorGenerationChannel) async throws {
            let cached = await state.cachedTokens(request.transcript)
            let promptIndex = request.transcript.lastIndex { if case .prompt = $0 { return true }; return false } ?? 0
            let result = request.transcript.suffix(from: promptIndex).compactMap { entry -> Transcript.ToolOutput? in
                if case .toolOutput(let output) = entry { return output }; return nil
            }.last
            if model.executorConfiguration.wantsTools, result == nil {
                await channel.send(.toolCalls(action: .toolCall(id: UUID().uuidString, name: "lookup", action: .appendArguments("{}", tokenCount: 2))))
                await channel.send(.toolCalls(action: .updateUsage(input: .init(totalTokenCount: 100, cachedTokenCount: cached), output: .init(totalTokenCount: 2, reasoningTokenCount: 0))))
            } else {
                let text = result?.segments.compactMap { if case .text(let value) = $0 { return value.content }; return nil }.joined() ?? "Answer"
                await channel.send(.response(action: .appendText(text, tokenCount: 2)))
                await channel.send(.response(action: .updateUsage(input: .init(totalTokenCount: 100, cachedTokenCount: cached), output: .init(totalTokenCount: 2, reasoningTokenCount: 0))))
            }
        }
    }
}

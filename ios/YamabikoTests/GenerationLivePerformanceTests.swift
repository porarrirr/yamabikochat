import XCTest
@testable import YamabikoChat

/// Opt in with YAMABIKO_LIVE_CONFIG_URL in the test runner environment.
/// The loopback endpoint supplies credentials in memory; never put keys in
/// fixtures, test arguments, xcresult attachments, or persisted app settings.
final class GenerationLivePerformanceTests: XCTestCase {
    private struct Configuration: Decodable {
        var provider: String
        var model: String
        var apiKey: String
    }

    private func configuration() async throws -> Configuration {
        guard let address = ProcessInfo.processInfo.environment["YAMABIKO_LIVE_CONFIG_URL"],
              let url = URL(string: address), url.host == "127.0.0.1" else {
            throw XCTSkip("Requires an explicit in-memory free-model configuration endpoint")
        }
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode(Configuration.self, from: data)
    }

    @MainActor
    func testFreeModelTextStreaming() async throws {
        let config = try await configuration()
        var history: [ProviderRequestMessage] = []
        let prompts = [
            "Pythonで表データの合計を求め、Webで出典を確認し、結果を図で表示する手順を、日本語の箇条書き5項目、400文字程度で説明してください。各項目に [資料](https://example.com) というリンクを含めてください。このURLは例示用です。ツールは実行不要です。",
            "今の説明を初心者向けの3項目に要約してください。資料へのリンクを1つ残してください。"
        ]
        for (index, prompt) in prompts.enumerated() {
            history.append(ProviderRequestMessage(role: "user", content: prompt))
            let start = ContinuousClock.now
            let presentation = PresentationProbe()
            let stream = try await PiAgentRuntime.shared.stream(
                request: ProviderRequest(model: config.model, messages: history,
                    provider: config.provider == "openrouter" ? ProviderRoutingConfig(allowFallbacks: false,
                        maxPrice: ProviderMaxPriceConfig(prompt: 0, completion: 0)) : nil,
                    metadata: ["max_output_tokens": "512"], timeoutInterval: 120),
                configuration: PiAgentConfiguration(provider: config.provider, model: config.model, apiKey: config.apiKey),
                tools: LocalToolRegistry(executors: []))
            var deltas = 0
            var firstDeltaMs: Double?
            var completed = false
            for try await event in stream {
                presentation.consume(event)
                let duration = start.duration(to: .now).components
                let elapsed = Double(duration.seconds) * 1000 + Double(duration.attoseconds) / 1e15
                switch event {
                case .textDelta(let text):
                    if !text.isEmpty { deltas += 1; if firstDeltaMs == nil { firstDeltaMs = elapsed } }
                case .completed(let response):
                    completed = true
                    XCTAssertFalse(response.text.isEmpty)
                    history.append(ProviderRequestMessage(role: "assistant", content: response.text))
                    print("LIVE_TEXT provider=\(config.provider) model=\(config.model) turn=\(index + 1) total_ms=\(elapsed) first_delta_ms=\(firstDeltaMs ?? -1) deltas=\(deltas)")
                default: break
                }
            }
            XCTAssertTrue(completed)
            XCTAssertGreaterThan(deltas, 0)
            presentation.report(provider: config.provider, scenario: "text-turn-\(index + 1)")
        }
    }

    @MainActor
    func testFreeModelToolsAndStreaming() async throws {
        let config = try await configuration()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("live-generation-\(UUID().uuidString)")
        // A provider can fail before Python creates its workspace. Do not let a
        // missing-directory cleanup error obscure the original provider error.
        defer {
            if FileManager.default.fileExists(atPath: root.path) {
                try? FileManager.default.removeItem(at: root)
            }
        }
        let sessions = PythonSessionStore(rootOverride: root)
        let worker = PythonWorker(sessions: sessions)
        let executors: [any LocalToolExecutor] = [
            PythonExecuteTool(worker: worker, sessions: sessions,
                attachments: AttachmentRepository(generatedFilesRootOverride: root.appendingPathComponent("exports"))),
            WebSearchTool(), FetchUrlTool(), GenUITool()
        ]
        let registry = LocalToolRegistry(executors: executors.map { TimedExecutor(base: $0) })
        let request = ProviderRequest(model: config.model, messages: [ProviderRequestMessage(role: "user", content: """
            次の3つのツールを各1回使ってください。
            1. python_execute で sum([12, 18, 30]) を計算。
            2. fetch_url で https://example.com を読み、goal は "Example Domain"。
            3. genui で title:"計算結果", code:"return DIL.h('col', {}, [DIL.h('text', {}, '合計60')]);" を作成。ui や components は指定不要です。
            最後に日本語で計算結果と参照URLを短く説明してください。追加の検索やツール再実行は不要です。
            """)], tools: registry.definitions.map(\.providerTool),
            provider: config.provider == "openrouter" ? ProviderRoutingConfig(allowFallbacks: false,
                maxPrice: ProviderMaxPriceConfig(prompt: 0, completion: 0)) : nil,
            metadata: ["pythonSessionId": "live-performance"], timeoutInterval: 120)
        let start = ContinuousClock.now
        let stream = try await PiAgentRuntime.shared.stream(request: request,
            configuration: PiAgentConfiguration(provider: config.provider, model: config.model, apiKey: config.apiKey), tools: registry)
        var firstDeltaMs: Double?
        var previews = 0
        var completedTools: [String] = []
        let presentation = PresentationProbe()
        var completed = false
        for try await event in stream {
            presentation.consume(event)
            let duration = start.duration(to: .now).components
            let elapsed = Double(duration.seconds) * 1000 + Double(duration.attoseconds) / 1e15
            switch event {
            case .textDelta, .reasoningDelta:
                if firstDeltaMs == nil { firstDeltaMs = elapsed }
            case .toolActivity(let activity):
                if activity.phase == .generating { previews += 1 }
                if activity.phase == .finished {
                    XCTAssertFalse(activity.result?.isError ?? true, "Tool failed: \(activity.call.name)")
                    if activity.call.name == PythonExecuteTool.name, let result = activity.result {
                        let fields = try JSONSerialization.jsonObject(with: Data(result.content.utf8)) as? [String: Any]
                        XCTAssertEqual(fields?["result_repr"] as? String, "60")
                    }
                    completedTools.append(activity.call.name)
                    print("LIVE_TOOL \(activity.call.name) elapsed_ms=\(elapsed)")
                }
            case .completed(let response):
                completed = true
                // A rendered GenUI document is also a complete visible answer.
                XCTAssertTrue(!response.text.isEmpty || presentation.toolActivity.steps.contains { $0.genUIDocument != nil })
                print("LIVE_RESULT provider=\(config.provider) model=\(config.model) total_ms=\(elapsed) first_delta_ms=\(firstDeltaMs ?? -1) text_characters=\(response.text.count) previews=\(previews) tools=\(completedTools)")
            default: break
            }
        }
        XCTAssertTrue(completed)
        XCTAssertEqual(Set(completedTools), Set([PythonExecuteTool.name, FetchUrlTool.name, GenUITool.name]))
        XCTAssertNotNil(presentation.toolActivity.steps.first { $0.toolName == GenUITool.name }?.genUIDocument?.code)
        presentation.report(provider: config.provider, scenario: "tools")
        await worker.resetSession(sessionID: "live-performance")
    }

    private struct TimedExecutor: LocalToolExecutor {
        let base: any LocalToolExecutor
        var definition: ToolDefinition { base.definition }

        func execute(call: ToolCall) async throws -> ToolResult {
            let start = ContinuousClock.now
            defer {
                let duration = start.duration(to: .now).components
                let ms = Double(duration.seconds) * 1000 + Double(duration.attoseconds) / 1e15
                print("LIVE_EXECUTOR tool=\(call.name) duration_ms=\(ms)")
            }
            return try await base.execute(call: call)
        }
    }

    /// Times the real main-actor timeline preparation for incoming Pi events.
    /// Excludes network/actor wait and does not claim to measure UIKit/GPU frames.
    @MainActor
    private final class PresentationProbe {
        private let row = ChatTimelineRowStore(item: .message(FullChatMessage(
            id: 1, message: ChatMessage(id: 1, conversationId: 1, role: "model", text: ""),
            thinkingStream: nil, variants: [])))
        private var text = ""
        private var thinking = ""
        private var samples: [Double] = []
        private(set) var toolActivity = ToolActivityPayload()

        func consume(_ event: ProviderStreamEvent) {
            let start = ContinuousClock.now
            var isFinal = false
            switch event {
            case .answerStart: text = ""
            case .textDelta(let delta): text += delta
            case .textSnapshot(let value): text = value
            case .reasoningDelta(let delta): thinking += delta
            case .toolActivity(let activity): toolActivity.apply(activity)
            case .completed(let response):
                text = response.text
                if let reasoning = response.reasoningSummary { thinking = reasoning }
                isFinal = true
            default: return
            }
            row.apply(snapshot: ChatStreamingSnapshot(targetId: 1, text: text, thinking: thinking,
                toolActivity: toolActivity, isFinal: isFinal))
            let duration = start.duration(to: .now).components
            samples.append(Double(duration.seconds) * 1000 + Double(duration.attoseconds) / 1e15)
        }

        func report(provider: String, scenario: String) {
            let sorted = samples.sorted()
            let p95 = sorted.isEmpty ? 0 : sorted[min(sorted.count - 1, Int(ceil(Double(sorted.count) * 0.95)) - 1)]
            print("LIVE_PRESENTATION provider=\(provider) scenario=\(scenario) updates=\(samples.count) total_ms=\(samples.reduce(0, +)) p95_ms=\(p95) max_ms=\(sorted.last ?? 0)")
        }
    }
}

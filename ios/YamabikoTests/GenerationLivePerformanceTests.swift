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

    func testFreeModelTextStreaming() async throws {
        let config = try await configuration()
        let start = ContinuousClock.now
        let stream = try await PiAgentRuntime.shared.stream(
            request: ProviderRequest(model: config.model, messages: [ProviderRequestMessage(role: "user",
                content: "Pythonで表データの合計を求め、Webで出典を確認し、結果を図で表示する手順を、日本語の箇条書き5項目、200文字程度で説明してください。ツールは実行不要です。")],
                provider: config.provider == "openrouter" ? ProviderRoutingConfig(allowFallbacks: false,
                    maxPrice: ProviderMaxPriceConfig(prompt: 0, completion: 0)) : nil,
                metadata: ["max_output_tokens": "512"], timeoutInterval: 120),
            configuration: PiAgentConfiguration(provider: config.provider, model: config.model, apiKey: config.apiKey),
            tools: LocalToolRegistry(executors: []))
        var deltas = 0
        var firstDeltaMs: Double?
        var completed = false
        for try await event in stream {
            let duration = start.duration(to: .now).components
            let elapsed = Double(duration.seconds) * 1000 + Double(duration.attoseconds) / 1e15
            switch event {
            case .textDelta(let text):
                if !text.isEmpty { deltas += 1; if firstDeltaMs == nil { firstDeltaMs = elapsed } }
            case .completed(let response):
                completed = true
                XCTAssertFalse(response.text.isEmpty)
                print("LIVE_TEXT provider=\(config.provider) model=\(config.model) total_ms=\(elapsed) first_delta_ms=\(firstDeltaMs ?? -1) deltas=\(deltas)")
            default: break
            }
        }
        XCTAssertTrue(completed)
        XCTAssertGreaterThan(deltas, 0)
    }

    func testFreeModelToolsAndStreaming() async throws {
        let config = try await configuration()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("live-generation-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let sessions = PythonSessionStore(rootOverride: root)
        let worker = PythonWorker(sessions: sessions, memoryLimitBytes: 4_000_000_000)
        let registry = LocalToolRegistry(executors: [
            PythonExecuteTool(worker: worker, sessions: sessions,
                attachments: AttachmentRepository(generatedFilesRootOverride: root.appendingPathComponent("exports"))),
            WebSearchTool(), FetchUrlTool(), GenUITool()
        ])
        let request = ProviderRequest(model: config.model, messages: [ProviderRequestMessage(role: "user", content: """
            次の3つのツールを各1回使ってください。
            1. python_execute で sum([12, 18, 30]) を計算。
            2. fetch_url で https://example.com を読み、goal は "Example Domain"。
            3. genui で title:"計算結果", ui:{type:"col",children:[{type:"text",children:["合計60"]}]} を作成。
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
        var payload = ToolActivityPayload()
        var completed = false
        for try await event in stream {
            let duration = start.duration(to: .now).components
            let elapsed = Double(duration.seconds) * 1000 + Double(duration.attoseconds) / 1e15
            switch event {
            case .textDelta, .reasoningDelta:
                if firstDeltaMs == nil { firstDeltaMs = elapsed }
            case .toolActivity(let activity):
                payload.apply(activity)
                if activity.phase == .generating { previews += 1 }
                if activity.phase == .finished {
                    XCTAssertFalse(activity.result?.isError ?? true, "Tool failed: \(activity.call.name)")
                    completedTools.append(activity.call.name)
                    print("LIVE_TOOL \(activity.call.name) elapsed_ms=\(elapsed)")
                }
            case .completed(let response):
                completed = true
                // A rendered GenUI document is also a complete visible answer.
                XCTAssertTrue(!response.text.isEmpty || payload.steps.contains { $0.genUIDocument != nil })
                print("LIVE_RESULT provider=\(config.provider) model=\(config.model) total_ms=\(elapsed) first_delta_ms=\(firstDeltaMs ?? -1) text_characters=\(response.text.count) previews=\(previews) tools=\(completedTools)")
            default: break
            }
        }
        XCTAssertTrue(completed)
        XCTAssertEqual(Set(completedTools), Set([PythonExecuteTool.name, FetchUrlTool.name, GenUITool.name]))
        XCTAssertNotNil(payload.steps.first { $0.toolName == GenUITool.name }?.genUIDocument)
        await worker.resetSession(sessionID: "live-performance")
    }
}

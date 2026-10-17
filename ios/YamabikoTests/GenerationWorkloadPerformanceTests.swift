import XCTest
@testable import YamabikoChat

/// Offline replay isolates app work from provider queue time and network variance.
/// Keep the same fixtures and optimization level for both measurements.
final class GenerationWorkloadPerformanceTests: XCTestCase {
    @MainActor
    func testListAnswerStreamingPerformance() {
        let source = (1...32).map { index in
            "\(index). 日本語の **手順\(index)** と `code` を確認します。[資料](https://example.com/\(index)) を参照してください。\n"
        }.joined()
        let characters = Array(source)
        let frames = (1...180).map { String(characters.prefix((characters.count * $0 + 179) / 180)) }
        let item = ChatTimelineItem.message(FullChatMessage(id: 1,
            message: ChatMessage(id: 1, conversationId: 1, role: "model", text: ""), thinkingStream: nil, variants: []))
        measure {
            let row = ChatTimelineRowStore(item: item)
            for frame in frames {
                row.apply(snapshot: ChatStreamingSnapshot(targetId: 1, text: frame, thinking: "", isFinal: false))
            }
            XCTAssertEqual(row.streamingMarkdownBlocks, NativeMarkdownParser.parse(source, rendersMath: false))
        }
    }

    @MainActor
    func testChatWithGeneratedCodePreviewPerformance() throws {
        // Already-coalesced native events, at the production 10 Hz preview rate.
        // Text, thinking, Python/Web status and growing GenUI code share one row.
        let answer = (1...12).map { "## 結果\($0)\n\n日本語の **説明** と [資料](https://example.com)。\n\n" }.joined()
        let code = "const values = [12, 18, 30];\nreturn DIL.h('col', {}, [" +
            (1...24).map { "DIL.h('text', {}, '項目\($0)：合計60')" }.joined(separator: ",\n") + "]);"
        let textCharacters = Array(answer), codeCharacters = Array(code)
        let frames = try (1...180).map { index -> (String, ToolActivityEvent?) in
            let text = String(textCharacters.prefix((textCharacters.count * index + 179) / 180))
            guard index.isMultiple(of: 3) || index == 1 else { return (text, nil) }
            let partial = String(codeCharacters.prefix((codeCharacters.count * index + 179) / 180))
            let data = try JSONSerialization.data(withJSONObject: ["title": "計算結果", "code": partial])
            return (text, ToolActivityEvent(phase: .generating,
                call: ToolCall(id: "genui", name: GenUITool.name, argumentsJSON: String(decoding: data, as: UTF8.self)),
                createdAtMs: Int64(index * 33)))
        }
        let statuses = [
            ToolActivityEvent(phase: .finished, call: ToolCall(id: "python", name: PythonExecuteTool.name,
                argumentsJSON: #"{"code":"sum([12,18,30])"}"#),
                result: ToolResult(callId: "python", name: PythonExecuteTool.name,
                    content: #"{"status":"ok","result_repr":"60","duration_ms":12}"#), createdAtMs: 0),
            ToolActivityEvent(phase: .finished, call: ToolCall(id: "web", name: FetchUrlTool.name,
                argumentsJSON: #"{"url":"https://example.com","goal":"資料"}"#),
                result: ToolResult(callId: "web", name: FetchUrlTool.name,
                    content: #"{"results":[{"text":"Example Domain"}]}"#), createdAtMs: 1)
        ]
        var samples: [Double] = []
        for _ in 0..<10 {
            let row = ChatTimelineRowStore(item: .message(FullChatMessage(id: 1,
                message: ChatMessage(id: 1, conversationId: 1, role: "model", text: ""), thinkingStream: nil, variants: [])))
            var activity = ToolActivityPayload()
            let start = ContinuousClock.now
            for status in statuses { activity.apply(status) }
            for frame in frames {
                autoreleasepool {
                    if let event = frame.1 { activity.apply(event) }
                    row.apply(snapshot: ChatStreamingSnapshot(targetId: 1, text: frame.0,
                        thinking: "計算と出典を確認しています。", toolActivity: activity, isFinal: false))
                }
                XCTAssertEqual(row.streamingSnapshot?.targetId, 1)
            }
            let duration = start.duration(to: .now).components
            samples.append(Double(duration.seconds) * 1000 + Double(duration.attoseconds) / 1e15)
            XCTAssertEqual(row.streamingMarkdownBlocks, NativeMarkdownParser.parse(answer, rendersMath: false))
            XCTAssertEqual(activity.steps.last?.genUIDocument?.code, code)
            XCTAssertEqual(activity.steps.prefix(2).map(\.status), [.completed, .completed])
        }
        print("WORKLOAD chat_generated_code_preview_ms \(samples)")
    }

    @MainActor
    func testLinkedChatAnswerStreamingPerformance() {
        // A typical sourced answer: short sections, inline citations and a code
        // example, arriving in 180 presentation frames (about 6 seconds at 30Hz).
        let source = (1...16).map { index in
            "## 手順\(index)\n\n日本語の **説明** と [出典\(index)](https://example.com/docs/\(index))。計算結果を確認してから次に進みます。\n\n"
        }.joined() + "```python\nvalues = [12, 18, 30]\nprint(sum(values))\n```\n\n合計は **60** です。"
        let characters = Array(source)
        let frames = (1...180).map { String(characters.prefix((characters.count * $0 + 179) / 180)) }
        let item = ChatTimelineItem.message(FullChatMessage(
            id: 1, message: ChatMessage(id: 1, conversationId: 1, role: "model", text: ""),
            thinkingStream: nil, variants: []))
        measure {
            let row = ChatTimelineRowStore(item: item)
            for frame in frames {
                row.apply(snapshot: ChatStreamingSnapshot(targetId: 1, text: frame, thinking: "", isFinal: false))
            }
            XCTAssertEqual(row.streamingMarkdownBlocks, NativeMarkdownParser.parse(source, rendersMath: false))
        }
    }

    @MainActor
    func testCachedAnswerRefreshesForCompletionReplacementAndNextStream() {
        let row = ChatTimelineRowStore(item: .message(FullChatMessage(
            id: 1, message: ChatMessage(id: 1, conversationId: 1, role: "model", text: ""),
            thinkingStream: nil, variants: [])))
        let answer = "本文\n\n```html\n<div>preview</div>\n```"
        row.apply(snapshot: ChatStreamingSnapshot(targetId: 1, text: answer, thinking: "", isFinal: false))
        let streaming = row.streamingMarkdownBlocks
        row.apply(snapshot: ChatStreamingSnapshot(targetId: 1, text: answer, thinking: "思考", isFinal: false))
        XCTAssertEqual(row.streamingMarkdownBlocks, streaming)
        row.apply(snapshot: ChatStreamingSnapshot(targetId: 1, text: answer, thinking: "思考", isFinal: true))
        XCTAssertEqual(row.streamingMarkdownBlocks?.count, 1, "Completed HTML fences move into the artifact card")
        row.apply(snapshot: ChatStreamingSnapshot(targetId: 1, text: "# 新しい回答", thinking: "", isFinal: false))
        XCTAssertEqual(row.streamingMarkdownBlocks, NativeMarkdownParser.parse("# 新しい回答", rendersMath: false))
        row.apply(snapshot: nil)
        row.apply(snapshot: ChatStreamingSnapshot(targetId: 1, text: answer, thinking: "", isFinal: false))
        XCTAssertEqual(row.streamingMarkdownBlocks, streaming)
    }

    func testEntityDecodingPreservesUnicodeAndUnknownEntities() {
        XCTAssertEqual(HTMLTextExtractor.decodeEntities("👨‍👩‍👧‍👦 e\u{301} &AMP; &#x6771;&#20140; &#128512; &unknown; &#x110000;"),
                       "👨‍👩‍👧‍👦 e\u{301} & 東京 😀 &unknown; &#x110000;")
        XCTAssertEqual(HTMLTextExtractor.decodeEntities("&amp;#65; &quot;引用&quot; &nbsp;&apos;"), "A \"引用\"  '")
    }

    func testWebArticleExtractionPerformance() {
        let html = "<html><main><h1>調査資料</h1>" + (0..<160).map { index in
            "<h2>Section \(index)</h2><p>日本語の資料 &#x6771;京 &amp; 大阪。<strong>検証済み</strong>の価格は \(index) 円です。 Details &quot;source&quot; and &#65;.</p>"
        }.joined() + "</main></html>"
        measure {
            let paragraphs = PageParagraphExtractor.extractHTML(html)
            XCTAssertEqual(paragraphs.count, 160)
            XCTAssertTrue(paragraphs[0].text.contains("東京 & 大阪"))
        }
    }

    @MainActor
    func testThinkingAndToolUpdatesWithLongAnswerPerformance() {
        let answer = String(repeating: "## 分析結果\n\n日本語の **説明** と `code` を表示します。\n\n", count: 150)
            + "```html\n<div>preview</div>\n```\n"
        let item = ChatTimelineItem.message(FullChatMessage(
            id: 1, message: ChatMessage(id: 1, conversationId: 1, role: "model", text: ""),
            thinkingStream: nil, variants: []
        ))
        measure {
            let row = ChatTimelineRowStore(item: item)
            for frame in 1...120 {
                row.apply(snapshot: ChatStreamingSnapshot(targetId: 1, text: answer,
                    thinking: String(repeating: "考察。", count: frame), isFinal: false))
            }
            XCTAssertFalse(row.streamingMarkdownBlocks?.isEmpty ?? true)
        }
    }

    func testPythonWorkspaceCellsPerformance() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("python-perf-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let sessions = PythonSessionStore(rootOverride: root)
        let paths = try sessions.prepare(sessionID: "performance")
        for index in 0..<300 {
            try Data("value,amount\n\(index),42\n".utf8)
                .write(to: paths.workspace.appendingPathComponent("input-\(index).csv"))
        }
        let worker = PythonWorker(sessions: sessions, memoryLimitBytes: 4_000_000_000)
        // Interpreter startup is measured by live tests, not repeated warm cells.
        let warmup = try await worker.execute(sessionID: "performance", code: "sum(range(1000))", reset: true, attachmentPaths: [])
        XCTAssertEqual(warmup.status, "ok", warmup.error?.traceback ?? "")
        var samples: [Double] = []
        for _ in 0..<10 {
            let start = ContinuousClock.now
            let response = try await worker.execute(sessionID: "performance",
                code: "sum(range(1000))", reset: false, attachmentPaths: [])
            let duration = start.duration(to: .now).components
            samples.append(Double(duration.seconds) * 1000 + Double(duration.attoseconds) / 1e15)
            XCTAssertEqual(response.resultRepr, "499500")
            XCTAssertTrue(response.artifacts.isEmpty)
        }
        print("WORKLOAD python_workspace_cells_ms \(samples)")
        await worker.resetSession(sessionID: "performance")
    }

    func testGenUIPreviewValidationReplayPerformance() throws {
        // Same 50 delta/s cadence as benchmark-genui-preview.mjs. Pi's repaired
        // arguments can contain syntactically incomplete code until the final delta.
        let code = "return DIL.h('text',{},'" + String(repeating: "日本語の分析結果。", count: 40) + "');"
        let characters = Array(code)
        let frames = try (0..<400).map { index -> ToolActivityEvent in
            let partial = String(characters.prefix((characters.count * (index + 1) + 399) / 400))
            let data = try JSONSerialization.data(withJSONObject: ["title": "分析結果", "code": partial])
            return ToolActivityEvent(phase: .generating, call: ToolCall(id: "preview", name: GenUITool.name,
                argumentsJSON: String(decoding: data, as: UTF8.self)), createdAtMs: Int64(index * 20))
        }
        func replay(coalesced: Bool) -> Double {
            var payload = ToolActivityPayload()
            let start = ContinuousClock.now
            for (index, frame) in frames.enumerated() where !coalesced || index.isMultiple(of: 5) || index == 399 {
                autoreleasepool { payload.apply(frame) }
            }
            let duration = start.duration(to: .now).components
            XCTAssertEqual(payload.steps.first?.genUIDocument?.code, code)
            return Double(duration.seconds) * 1000 + Double(duration.attoseconds) / 1e15
        }
        _ = replay(coalesced: false)
        _ = replay(coalesced: true)
        var before: [Double] = [], after: [Double] = []
        for _ in 0..<5 { before.append(replay(coalesced: false)); after.append(replay(coalesced: true)) }
        print("WORKLOAD genui_validation_uncoalesced_ms \(before)")
        print("WORKLOAD genui_validation_coalesced_ms \(after)")
    }
}

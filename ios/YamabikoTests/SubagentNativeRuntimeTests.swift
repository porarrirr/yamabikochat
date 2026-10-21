import XCTest
import Network
@testable import YamabikoChat

/// Runs the shipped JS bundle on NodeMobile, including the plugin's workflow workers.
final class SubagentNativeRuntimeTests: XCTestCase {
    func testBundledPluginRunsThreeChildrenOnNodeMobile() async throws {
        let server = try SubagentMockHTTPServer()
        let port = try await server.start()
        defer { server.stop() }
        var endpoint = OpenAICompatPreset(name: "Native subagent test", baseURL: "http://127.0.0.1:\(port)/v1")
        endpoint.apiProtocol = "openai-completions"
        endpoint.modelId = "native-subagent-model"
        endpoint.toolCall = true
        let config = PiAgentConfiguration(provider: "yamabiko-custom", model: endpoint.modelId, apiKey: "fixture-key",
            customEndpoint: endpoint, thinkingLevel: "off", subagents: PiSubagentOptions(enabled: true, models: []))
        let request = ProviderRequest(model: endpoint.modelId,
            messages: [.init(role: "user", content: "native-parent-test")], timeoutInterval: 20)
        let stream = try await PiAgentRuntime.shared.stream(request: request, configuration: config, tools: LocalToolRegistry(executors: []))
        var response: ProviderResponse?
        var runningIDs: Set<String> = []
        for try await event in stream {
            if case let .toolActivity(activity) = event, let run = activity.subagent, run.status == .running { runningIDs.insert(run.id) }
            if case let .completed(value) = event { response = value }
        }
        XCTAssertEqual(response?.text, "Native children completed")
        XCTAssertEqual(response?.subagents?.count, 3, response?.providerTranscript?.filter { $0.role == "tool" }.map(\.content).joined(separator: "\n") ?? "No transcript")
        XCTAssertEqual(runningIDs.count, 3)
        XCTAssertTrue(response?.subagents?.allSatisfy { $0.status == .completed && $0.output.contains("Child native result") && $0.model == endpoint.modelId && $0.effort == "off" } == true)
        XCTAssertEqual(server.requestCount, 5)
    }
}

private final class SubagentMockHTTPServer: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "subagent-native-http-test")
    private let lock = NSLock()
    private var count = 0
    var requestCount: Int { lock.withLock { count } }

    init() throws { listener = try NWListener(using: .tcp, on: .any) }

    func start() async throws -> UInt16 {
        try await withCheckedThrowingContinuation { continuation in
            listener.stateUpdateHandler = { [listener] state in
                switch state {
                case .ready: continuation.resume(returning: listener.port!.rawValue)
                case let .failed(error): continuation.resume(throwing: error)
                default: break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                guard let self else { return }
                let handler = SubagentMockHTTPConnection(connection: connection) { [weak self] data in self?.response(data) ?? Data() }
                connection.start(queue: self.queue)
                handler.receive()
            }
            listener.start(queue: queue)
        }
    }

    func stop() { listener.cancel() }

    private func response(_ data: Data) -> Data {
        lock.withLock { count += 1 }
        let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        let messages = body["messages"] as? [[String: Any]] ?? []
        let isParent = messages.contains { String(describing: $0["content"] ?? "").contains("native-parent-test") }
        let delta: [String: Any]
        let stop: String
        if isParent, messages.last?["role"] as? String != "tool" {
            let params: [String: Any] = ["tasks": (1...3).map { ["agent": "delegate", "task": "Reply as child \($0)"] }, "async": false]
            let arguments = String(decoding: try! JSONSerialization.data(withJSONObject: params), as: UTF8.self)
            delta = ["role": "assistant", "tool_calls": [["index": 0, "id": "native-delegate", "type": "function", "function": ["name": "subagent", "arguments": arguments]]]]
            stop = "tool_calls"
        } else {
            delta = ["role": "assistant", "content": isParent ? "Native children completed" : "Child native result"]
            stop = "stop"
        }
        let event: [String: Any] = ["id": "native-test", "object": "chat.completion.chunk", "model": "native-subagent-model",
            "choices": [["index": 0, "delta": delta, "finish_reason": stop]]]
        return Data("data: \(String(decoding: try! JSONSerialization.data(withJSONObject: event), as: UTF8.self))\n\ndata: [DONE]\n\n".utf8)
    }
}

private final class SubagentMockHTTPConnection: @unchecked Sendable {
    let connection: NWConnection
    let respond: @Sendable (Data) -> Data
    var bytes = Data()
    init(connection: NWConnection, respond: @escaping @Sendable (Data) -> Data) { self.connection = connection; self.respond = respond }

    func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1_048_576) { [self] data, _, complete, error in
            if let data { bytes.append(data) }
            if let range = bytes.range(of: Data("\r\n\r\n".utf8)),
               let header = String(data: bytes[..<range.lowerBound], encoding: .utf8),
               let field = header.components(separatedBy: "\r\n").first(where: { $0.lowercased().hasPrefix("content-length:") }),
               let length = Int(field.split(separator: ":", maxSplits: 1)[1].trimmingCharacters(in: .whitespaces)),
               bytes.count >= range.upperBound + length {
                let output = respond(bytes.subdata(in: range.upperBound..<(range.upperBound + length)))
                var response = Data("HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nContent-Length: \(output.count)\r\nConnection: close\r\n\r\n".utf8)
                response.append(output)
                connection.send(content: response, completion: .contentProcessed { [connection] _ in connection.cancel() })
            } else if complete || error != nil { connection.cancel() }
            else { receive() }
        }
    }
}

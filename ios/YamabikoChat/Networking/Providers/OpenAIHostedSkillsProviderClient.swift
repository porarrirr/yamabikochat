import Foundation
import CryptoKit
import ZIPFoundation

enum OpenAIHostedSkillsPolicy {
    private static let supportedModelPatterns = [
        #"^gpt-5\.4(?:-(?:mini|nano))?(?:-\d{4}-\d{2}-\d{2})?$"#,
        #"^gpt-5\.5(?:-\d{4}-\d{2}-\d{2})?$"#,
        #"^gpt-5\.6$"#,
        #"^gpt-5\.6-(?:sol|terra|luna)(?:-\d{4}-\d{2}-\d{2})?$"#,
    ]

    static func validate(request: ProviderRequest, settings: AppSettings) throws {
        guard request.skillContext?.hostedExecutionEnabled == true,
              request.skillContext?.catalog.isEmpty == false else { return }
        guard isOfficialBaseURL(settings.resolvedOpenAIBaseURL()) else {
            throw ProviderClientError.parseFailure(
                "OpenAI hosted Skill実行には公式エンドポイント https://api.openai.com/v1/ が必要です。"
            )
        }
        guard supportsModel(request.model) else {
            throw ProviderClientError.parseFailure(
                "モデル '\(request.model)' はOpenAI hosted shell/Skillsに対応していません。対応モデルを選択してください。"
            )
        }
    }

    static func supportsModel(_ model: String) -> Bool {
        let normalized = model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let range = NSRange(normalized.startIndex..., in: normalized)
        return supportedModelPatterns.contains { pattern in
            (try? NSRegularExpression(pattern: pattern))?.firstMatch(
                in: normalized,
                range: range
            ) != nil
        }
    }

    static func isOfficialBaseURL(_ rawValue: String) -> Bool {
        guard let components = URLComponents(string: rawValue.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return false
        }
        let validPaths: Set<String> = ["", "/", "/v1", "/v1/"]
        return components.scheme?.lowercased() == "https"
            && components.host?.lowercased() == "api.openai.com"
            && components.port == nil
            && components.user == nil
            && components.password == nil
            && components.query == nil
            && components.fragment == nil
            && validPaths.contains(components.path)
    }

    static func cacheKey(context: SkillRequestContext, token: String) -> String {
        let conversation = context.conversationID ?? UUID().uuidString
        let digest = SHA256.hash(data: Data(token.utf8))
            .prefix(16)
            .map { String(format: "%02x", $0) }
            .joined()
        return "\(conversation):\(context.enabledSkillSetHash):\(digest)"
    }
}

actor OpenAISkillContainerManager {
    private struct Cached { var key: String; var id: String; var lastActive: Date }
    private var cached: [String: Cached] = [:]
    private let skillRepository: AgentSkillRepository

    init(skillRepository: AgentSkillRepository) { self.skillRepository = skillRepository }

    func containerID(context: SkillRequestContext, token: String, httpClient: HTTPClientProtocol) async throws -> String {
        let key = OpenAIHostedSkillsPolicy.cacheKey(context: context, token: token)
        if var existing = cached[key], Date().timeIntervalSince(existing.lastActive) < 19 * 60 {
            existing.lastActive = Date()
            cached[key] = existing
            return existing.id
        }
        let skills = try skillRepository.enabledSkills.map { skill -> [String: Any] in
            let zip = try zipSkill(name: skill.manifest.name)
            return [
                "type": "inline",
                "name": skill.manifest.name,
                "description": skill.manifest.description,
                "source": ["type": "base64", "media_type": "application/zip", "data": zip.base64EncodedString()]
            ]
        }
        let body: [String: Any] = [
            "name": "YamabikoChat Agent Skills",
            "expires_after": ["anchor": "last_active_at", "minutes": 20],
            "skills": skills
        ]
        let data = try JSONSerialization.data(withJSONObject: body)
        let request = HTTPRequest(
            url: URL(string: "https://api.openai.com/v1/containers")!,
            headers: Self.headers(token),
            body: data
        )
        let (responseData, response) = try await httpClient.send(request)
        guard (200...299).contains(response.statusCode) else {
            throw ProviderClientError.httpStatus(response.statusCode, String(decoding: responseData, as: UTF8.self))
        }
        guard let object = try JSONSerialization.jsonObject(with: responseData) as? [String: Any], let id = object["id"] as? String else {
            throw ProviderClientError.parseFailure("OpenAI container response did not include an id")
        }
        cached = cached.filter { Date().timeIntervalSince($0.value.lastActive) < 20 * 60 }
        cached[key] = Cached(key: key, id: id, lastActive: Date())
        DiagnosticsLogger.log("OpenAI temporary Skill container created", category: .network, metadata: ["container": id, "skills": String(skills.count), "expires_minutes": "20"])
        return id
    }

    private func zipSkill(name: String) throws -> Data {
        let root = try skillRepository.rootForEnabledSkill(name: name)
        let target = FileManager.default.temporaryDirectory.appendingPathComponent("skill-\(UUID().uuidString).zip")
        defer { try? FileManager.default.removeItem(at: target) }
        let archive = try Archive(url: target, accessMode: .create)
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else {
            throw AgentSkillError.invalidArchive("SkillをZIP化できません: \(name)")
        }
        while let url = enumerator.nextObject() as? URL {
            guard (try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
            let relative = String(url.path.dropFirst(root.path.count + 1))
            guard relative != "state.json" else { continue }
            try archive.addEntry(with: "\(name)/\(relative)", fileURL: url)
        }
        return try Data(contentsOf: target)
    }

    static func headers(_ token: String) -> [String: String] {
        ["Authorization": "Bearer \(token)", "Content-Type": "application/json"]
    }
}

struct OpenAIHostedSkillsProviderClient: ProviderClient {
    let provider: LLMProvider = .openAI
    let manager: OpenAISkillContainerManager
    let attachmentRepository: AttachmentRepository

    func generate(request: ProviderRequest, settings: AppSettings, credentialStore: SecureCredentialStore, httpClient: HTTPClientProtocol) async throws -> ProviderResponse {
        try OpenAIHostedSkillsPolicy.validate(request: request, settings: settings)
        guard let context = request.skillContext, context.hostedExecutionEnabled, !context.catalog.isEmpty else {
            throw ProviderClientError.parseFailure("OpenAI hosted Skill execution requires enabled skills")
        }
        let token = try credentialStore.credential(for: .openAI)?.trimmedNonEmpty
        guard let token else { throw ProviderClientError.missingCredential("OPENAI") }
        let container = try await manager.containerID(context: context, token: token, httpClient: httpClient)
        let payload = try buildPayload(request: request, containerID: container, stream: false)
        let httpRequest = HTTPRequest(url: URL(string: "https://api.openai.com/v1/responses")!, headers: OpenAISkillContainerManager.headers(token), body: payload, timeoutInterval: request.timeoutInterval)
        let (data, response) = try await httpClient.send(httpRequest)
        guard (200...299).contains(response.statusCode) else { throw ProviderClientError.httpStatus(response.statusCode, String(decoding: data, as: UTF8.self)) }
        return try await parseFinal(data: data, token: token, httpClient: httpClient)
    }

    func stream(request: ProviderRequest, settings: AppSettings, credentialStore: SecureCredentialStore, httpClient: HTTPClientProtocol) -> AsyncThrowingStream<ProviderStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try OpenAIHostedSkillsPolicy.validate(request: request, settings: settings)
                    guard let context = request.skillContext, context.hostedExecutionEnabled, !context.catalog.isEmpty else { throw ProviderClientError.parseFailure("OpenAI hosted Skill execution requires enabled skills") }
                    guard let token = try credentialStore.credential(for: .openAI)?.trimmedNonEmpty else { throw ProviderClientError.missingCredential("OPENAI") }
                    let container = try await manager.containerID(context: context, token: token, httpClient: httpClient)
                    let payload = try buildPayload(request: request, containerID: container, stream: true)
                    let httpRequest = HTTPRequest(url: URL(string: "https://api.openai.com/v1/responses")!, headers: OpenAISkillContainerManager.headers(token), body: payload, timeoutInterval: request.timeoutInterval)
                    let (lines, response) = try await httpClient.stream(httpRequest)
                    guard (200...299).contains(response.statusCode) else { throw ProviderClientError.httpStatus(response.statusCode, "OpenAI Responses streaming failed") }
                    var fullText = ""
                    var fullReasoning = ""
                    var finalObject: [String: Any]?
                    var activities: [ProviderServerActivity] = []
                    for try await line in lines {
                        try Task.checkCancellation()
                        guard line.hasPrefix("data:") else { continue }
                        let raw = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        guard raw != "[DONE]", let data = raw.data(using: .utf8), let event = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                        let type = event["type"] as? String ?? ""
                        if type == "response.output_text.delta", let delta = event["delta"] as? String { fullText += delta; continuation.yield(.textDelta(delta)) }
                        else if type.contains("reasoning_summary_text.delta"), let delta = event["delta"] as? String { fullReasoning += delta; continuation.yield(.reasoningDelta(delta)) }
                        else if type == "response.output_item.done", let item = event["item"] as? [String: Any], let activity = Self.activity(from: item) { activities.append(activity); continuation.yield(.serverActivity(activity)) }
                        else if type == "response.completed", let responseObject = event["response"] as? [String: Any] { finalObject = responseObject }
                        else if type == "error" { throw ProviderClientError.parseFailure((event["message"] as? String) ?? "OpenAI Responses stream failed") }
                    }
                    guard let finalObject else { throw ProviderClientError.parseFailure("OpenAI Responses stream ended without response.completed") }
                    let finalData = try JSONSerialization.data(withJSONObject: finalObject)
                    var final = try await parseFinal(data: finalData, token: token, httpClient: httpClient)
                    final.text = fullText.isEmpty ? final.text : fullText
                    final.reasoningSummary = fullReasoning.trimmedNonEmpty ?? final.reasoningSummary
                    final.serverActivities = activities + final.serverActivities.filter { candidate in !activities.contains(where: { $0.id == candidate.id }) }
                    continuation.yield(.completed(final)); continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func buildPayload(request: ProviderRequest, containerID: String, stream: Bool) throws -> Data {
        var input: [[String: Any]] = []
        for message in request.messages {
            if message.role == "tool", let callID = message.toolCallId?.trimmedNonEmpty {
                input.append(["type": "function_call_output", "call_id": callID, "output": message.content])
                continue
            }
            guard ["user", "assistant", "system"].contains(message.role) else { continue }
            var content: [[String: Any]] = []
            if !message.content.isEmpty {
                content.append([
                    "type": message.role == "assistant" ? "output_text" : "input_text",
                    "text": message.content,
                ])
            }
            if message.role != "assistant" {
                for rawAttachment in message.attachments {
                    guard let payload = ProviderAttachmentEncoder.loadInlinePayload(from: rawAttachment) else { continue }
                    if payload.isImage {
                        content.append(["type": "input_image", "image_url": payload.dataURL])
                    } else {
                        let filename = ProviderAttachmentEncoder.resolveFileURL(from: rawAttachment)?.lastPathComponent
                            .trimmedNonEmpty ?? "attachment"
                        content.append([
                            "type": "input_file",
                            "filename": filename,
                            "file_data": payload.dataURL,
                        ])
                    }
                }
            }
            if !content.isEmpty {
                input.append(["role": message.role, "content": content])
            }
            for call in message.toolCalls ?? [] {
                input.append([
                    "type": "function_call",
                    "call_id": call.id,
                    "name": call.name,
                    "arguments": call.argumentsJSON,
                ])
            }
        }
        var tools: [[String: Any]] = request.tools.compactMap { tool in
            guard tool.type == "function", let name = tool.payload["name"] else { return nil }
            let parameters = tool.payload["parameters"]?.data(using: .utf8).flatMap { try? JSONSerialization.jsonObject(with: $0) } ?? ["type": "object"]
            return ["type": "function", "name": name, "description": tool.payload["description"] ?? "", "parameters": parameters]
        }
        tools.append(["type": "shell", "environment": ["type": "container_reference", "container_id": containerID]])
        var body: [String: Any] = ["model": request.model, "input": input, "tools": tools, "stream": stream]
        if let prompt = request.systemPrompt?.trimmedNonEmpty { body["instructions"] = prompt }
        if let promptCacheKey = request.metadata["promptCacheKey"]?.trimmedNonEmpty {
            body["prompt_cache_key"] = promptCacheKey
        }
        if let thinking = request.thinking, thinking.enabled != false {
            var reasoning: [String: Any] = [:]
            if let effort = thinking.effort { reasoning["effort"] = effort }
            reasoning["summary"] = "auto"
            body["reasoning"] = reasoning
        }
        return try JSONSerialization.data(withJSONObject: body)
    }

    private func parseFinal(data: Data, token: String, httpClient: HTTPClientProtocol) async throws -> ProviderResponse {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw ProviderClientError.invalidResponse }
        var text = ""; var reasoning = ""; var calls: [ToolCall] = []; var activities: [ProviderServerActivity] = []
        for item in root["output"] as? [[String: Any]] ?? [] {
            let type = item["type"] as? String ?? ""
            if type == "message" {
                for content in item["content"] as? [[String: Any]] ?? [] { if content["type"] as? String == "output_text" { text += content["text"] as? String ?? "" } }
            } else if type == "reasoning" {
                for summary in item["summary"] as? [[String: Any]] ?? [] { reasoning += summary["text"] as? String ?? "" }
            } else if type == "function_call", let name = item["name"] as? String {
                calls.append(ToolCall(id: item["call_id"] as? String ?? item["id"] as? String ?? UUID().uuidString, name: name, argumentsJSON: item["arguments"] as? String ?? "{}"))
            }
            if let activity = Self.activity(from: item) { activities.append(activity) }
        }
        let usageObject = root["usage"] as? [String: Any]
        let inputDetails = usageObject?["input_tokens_details"] as? [String: Any]
        let outputDetails = usageObject?["output_tokens_details"] as? [String: Any]
        let usage = ProviderUsage(
            inputTokens: Self.intValue(in: usageObject, keys: ["input_tokens", "inputTokens"]),
            outputTokens: Self.intValue(in: usageObject, keys: ["output_tokens", "outputTokens"]),
            totalTokens: Self.intValue(in: usageObject, keys: ["total_tokens", "totalTokens"]),
            reasoningTokens: Self.intValue(in: outputDetails, keys: ["reasoning_tokens", "reasoningTokens"]),
            cachedInputTokens: Self.intValue(in: inputDetails, keys: ["cached_tokens", "cachedTokens"]),
            cacheCreationInputTokens: Self.intValue(
                in: inputDetails,
                keys: ["cache_write_tokens", "cacheWriteTokens", "cache_creation_input_tokens"]
            )
        )
        var generated = Self.fileReferences(in: root)
        for index in generated.indices {
            do {
                let url = URL(string: "https://api.openai.com/v1/containers/\(generated[index].containerID)/files/\(generated[index].fileID)/content")!
                let (fileData, response) = try await httpClient.send(HTTPRequest(url: url, method: "GET", headers: ["Authorization": "Bearer \(token)"]))
                guard (200...299).contains(response.statusCode) else { throw ProviderClientError.httpStatus(response.statusCode, String(decoding: fileData, as: UTF8.self)) }
                generated[index].localPath = try attachmentRepository.persistGeneratedFile(data: fileData, filename: generated[index].filename).path
                activities.append(ProviderServerActivity(id: "file:\(generated[index].fileID)", kind: .file, title: "生成ファイルを保存", detail: generated[index].filename, isError: false))
            } catch {
                activities.append(ProviderServerActivity(id: "file:\(generated[index].fileID)", kind: .file, title: "生成ファイルの取得に失敗", detail: error.localizedDescription, isError: true))
                DiagnosticsLogger.log("OpenAI generated file download failed", category: .network, metadata: ["file": generated[index].fileID], error: error)
            }
        }
        return ProviderResponse(text: text, reasoningSummary: reasoning.trimmedNonEmpty, raw: nil, usage: usage.normalizedNonEmpty(), toolCalls: calls, generatedFiles: generated, serverActivities: activities)
    }

    private static func intValue(in object: [String: Any]?, keys: [String]) -> Int? {
        guard let object else { return nil }
        for key in keys {
            if let value = object[key] as? Int { return value }
            if let value = object[key] as? NSNumber { return value.intValue }
            if let value = object[key] as? String, let parsed = Int(value) { return parsed }
        }
        return nil
    }

    private static func activity(from item: [String: Any]) -> ProviderServerActivity? {
        let type = item["type"] as? String ?? ""
        guard type == "shell_call" || type == "shell_call_output" else { return nil }
        let callID = item["call_id"] as? String ?? item["id"] as? String ?? UUID().uuidString
        var exit: Int?
        var timedOut: Bool?
        let detail: String
        if type == "shell_call" {
            let action = item["action"] as? [String: Any]
            let commands = action?["commands"] as? [String] ?? []
            let timeout = action?["timeout_ms"] as? Int
            detail = (commands.isEmpty ? "hosted shell" : commands.joined(separator: "\n"))
                + (timeout.map { "\ntimeout_ms=\($0)" } ?? "")
        } else {
            var lines: [String] = []
            for output in item["output"] as? [[String: Any]] ?? [] {
                if let stdout = (output["stdout"] as? String)?.trimmedNonEmpty { lines.append("stdout:\n\(stdout)") }
                if let stderr = (output["stderr"] as? String)?.trimmedNonEmpty { lines.append("stderr:\n\(stderr)") }
                let outcome = output["outcome"] as? [String: Any]
                if outcome?["type"] as? String == "timeout" { timedOut = true }
                if let code = outcome?["exit_code"] as? Int {
                    if exit == nil || code != 0 { exit = code }
                }
            }
            detail = String(lines.joined(separator: "\n\n").prefix(4_000))
        }
        let isError = (exit ?? 0) != 0 || timedOut == true
        let activity = ProviderServerActivity(id: "\(type):\(callID)", kind: .shell, title: type == "shell_call" ? "OpenAI hosted shell" : "hosted shell結果", detail: detail, exitCode: exit, timedOut: timedOut, isError: isError)
        DiagnosticsLogger.log("OpenAI hosted shell activity", level: isError ? .error : .info, category: .network, metadata: ["type": type, "exit_code": exit.map(String.init) ?? "-", "timed_out": String(timedOut ?? false)])
        return activity
    }

    private static func fileReferences(in root: Any) -> [ProviderGeneratedFile] {
        var result: [ProviderGeneratedFile] = []
        func walk(_ value: Any) {
            if let object = value as? [String: Any] {
                if object["type"] as? String == "container_file_citation", let container = object["container_id"] as? String, let file = object["file_id"] as? String {
                    result.append(ProviderGeneratedFile(containerID: container, fileID: file, filename: object["filename"] as? String ?? "generated-file"))
                }
                object.values.forEach(walk)
            } else if let array = value as? [Any] { array.forEach(walk) }
        }
        walk(root)
        var seen = Set<String>()
        return result.filter { seen.insert($0.id).inserted }
    }
}

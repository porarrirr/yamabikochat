import Foundation

struct PythonExecuteTool: LocalToolExecutor {
    static let name = "python_execute"

    let definition = ToolDefinition(
        name: Self.name,
        description: """
        Execute Python 3.14 locally in a stateful namespace scoped to this chat. The current working directory is the same persistent workspace exposed by str_replace_editor as /workspace; use relative paths such as src/main.js from Python. NumPy, Matplotlib, and Pillow are bundled for local data analysis and image generation. Matplotlib includes Noto fonts for Japanese, Simplified Chinese, Hindi, Arabic, Bengali, Urdu, Latin, and Cyrillic text; use native-language labels directly without probing system fonts. Japanese is the default CJK style. For localized Han or Urdu forms, set `fontfamily="Noto Sans SC"` or `fontfamily="Noto Nastaliq Urdu"` on that text. Files created or updated in the workspace or ./outputs/ are automatically returned to the user as visible artifacts; open Matplotlib figures are automatically saved as PNG. Network, subprocess, and shell access are disabled. Files attached to the chat are copied into the current workspace.
        """,
        parametersJSON: #"{"type":"object","properties":{"code":{"type":"string","description":"Python source code to execute"},"reset":{"type":"boolean","description":"Reset this chat's Python namespace before executing; workspace files are preserved"}},"required":["code"],"additionalProperties":false}"#
    )

    private let worker: PythonWorker
    private let sessions: PythonSessionStore
    private let attachments: AttachmentRepository

    init(
        worker: PythonWorker = .shared,
        sessions: PythonSessionStore = .shared,
        attachments: AttachmentRepository = AttachmentRepository()
    ) {
        self.worker = worker
        self.sessions = sessions
        self.attachments = attachments
    }

    func execute(call: ToolCall) async throws -> ToolResult {
        guard let data = call.argumentsJSON.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let code = object["code"] as? String,
              !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return ToolResult(
                callId: call.id,
                name: call.name,
                content: LocalToolRegistry.errorContent("python_execute requires non-empty code"),
                isError: true
            )
        }
        guard let sessionID = call.providerMetadata?["pythonSessionId"]?.trimmedNonEmpty else {
            throw PythonToolError.missingSession
        }
        let sourceAttachments: [String]
        if let json = call.providerMetadata?["pythonAttachmentsJSON"],
           let data = json.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            sourceAttachments = decoded
        } else {
            sourceAttachments = []
        }
        let response = try await worker.execute(
            sessionID: sessionID,
            code: code,
            reset: object["reset"] as? Bool ?? false,
            attachmentPaths: sourceAttachments
        )
        var generated: [ToolArtifact] = []
        for artifact in response.artifacts {
            let source = try sessions.artifactURL(
                sessionID: sessionID,
                root: artifact.root ?? "outputs",
                relativePath: artifact.relpath
            )
            let data = try Data(contentsOf: source, options: .mappedIfSafe)
            let persisted = try attachments.persistGeneratedFile(
                data: data,
                filename: artifact.name,
                collection: "Chat \(sessionID)"
            )
            generated.append(ToolArtifact(path: persisted.path, name: artifact.name, mime: artifact.mime, size: artifact.size))
        }
        let resultData = try JSONEncoder().encode(response)
        return ToolResult(
            callId: call.id,
            name: call.name,
            content: String(decoding: resultData, as: UTF8.self),
            status: response.status == "ok" ? .complete : .failure,
            artifacts: generated
        )
    }
}

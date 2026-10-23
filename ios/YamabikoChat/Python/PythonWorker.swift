import Foundation

struct PythonArtifactDescriptor: Codable, Sendable, Equatable {
    var name: String
    var root: String?
    var relpath: String
    var mime: String
    var size: Int64
}

struct PythonExecutionFailure: Codable, Sendable, Equatable {
    var type: String
    var message: String
    var traceback: String
}

struct PythonExecutionResponse: Codable, Sendable, Equatable {
    var status: String
    var stdout: String
    var stderr: String
    var resultRepr: String?
    var artifacts: [PythonArtifactDescriptor]
    var durationMs: Int64
    var error: PythonExecutionFailure?

    enum CodingKeys: String, CodingKey {
        case status, stdout, stderr, artifacts, error
        case resultRepr = "result_repr"
        case durationMs = "duration_ms"
    }
}

enum PythonToolError: LocalizedError, Equatable {
    case runtimeResourcesMissing
    case missingSession
    case invalidArtifactPath
    case invalidResponse
    case poisoned
    case attachmentMissing(String)
    case attachmentIdentityCollision(String)
    case resourceLimitExceeded(String)

    var errorDescription: String? {
        switch self {
        case .runtimeResourcesMissing:
            return "Embedded Python resources are missing. Run ios/scripts/bootstrap-python.sh and rebuild the app."
        case .missingSession:
            return "python_execute requires a valid conversation session."
        case .invalidArtifactPath:
            return "Python returned an artifact outside the active session directory."
        case .invalidResponse:
            return "Embedded Python returned an invalid result envelope."
        case .poisoned:
            return "The Python execution queue is unavailable."
        case let .attachmentMissing(path):
            return "A Python attachment no longer exists: \(path)"
        case let .attachmentIdentityCollision(identifier):
            return "Python attachment identity invariant failed for \(identifier)."
        case let .resourceLimitExceeded(reason):
            return "Python workspace resource limit exceeded: \(reason)"
        }
    }
}

actor PythonJobQueue {
    static let shared = PythonJobQueue()
    private var active: UUID?
    private var unavailable = false
    private var waiting: [(UUID, CheckedContinuation<Void, Error>)] = []

    func acquire(_ id: UUID) async throws {
        guard !unavailable else { throw PythonToolError.poisoned }
        try Task.checkCancellation()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                if active == nil {
                    active = id
                    continuation.resume()
                } else {
                    waiting.append((id, continuation))
                }
            }
        } onCancel: {
            Task { await self.cancel(id) }
        }
        if Task.isCancelled {
            release(id)
            throw CancellationError()
        }
    }

    func poison() {
        unavailable = true
        let pending = waiting
        waiting = []
        pending.forEach { $0.1.resume(throwing: PythonToolError.poisoned) }
    }

    private func cancel(_ id: UUID) {
        guard let index = waiting.firstIndex(where: { $0.0 == id }) else { return }
        waiting.remove(at: index).1.resume(throwing: CancellationError())
    }

    func release(_ id: UUID) {
        guard active == id else { return }
        active = nil
        if !waiting.isEmpty {
            let next = waiting.removeFirst()
            active = next.0
            next.1.resume()
        }
    }
}

actor PythonWorker {
    static let shared = PythonWorker()
    private let sessions: PythonSessionStore
    private let timeoutSeconds: TimeInterval
    private let files: PythonSandboxFiles
    private let maximumRetainedSessions: Int
    private var sandboxes: [String: PythonWebSandbox] = [:]
    private var recentSessions: [String] = []

    deinit {
        let remaining = Array(sandboxes.values)
        Task { @MainActor in remaining.forEach { $0.dispose() } }
    }

    init(
        sessions: PythonSessionStore = .shared,
        timeoutSeconds: TimeInterval = 120,
        maximumRetainedSessions: Int = 2,
        maximumWorkspaceFiles: Int = 1_024,
        maximumWorkspaceBytes: Int64 = 100 * 1_024 * 1_024,
        maximumFileBytes: Int64 = 25 * 1_024 * 1_024,
        maximumPathDepth: Int = 16
    ) {
        self.sessions = sessions
        self.timeoutSeconds = timeoutSeconds
        self.maximumRetainedSessions = max(1, maximumRetainedSessions)
        // The bundled WASM declares a hard 512 MiB maximum, enforced by WebKit.
        self.files = PythonSandboxFiles(maximumFiles: maximumWorkspaceFiles,
            maximumBytes: maximumWorkspaceBytes, maximumFileBytes: maximumFileBytes,
            maximumDepth: maximumPathDepth)
    }

    func execute(sessionID: String, code: String, reset: Bool, attachmentPaths: [String]) async throws -> PythonExecutionResponse {
        let job = UUID()
        try await PythonJobQueue.shared.acquire(job)
        do {
            let result = try await executeAcquired(sessionID: sessionID, code: code, reset: reset, attachmentPaths: attachmentPaths)
            await PythonJobQueue.shared.release(job)
            return result
        } catch {
            await PythonJobQueue.shared.release(job)
            throw error
        }
    }

    private func executeAcquired(sessionID: String, code: String, reset: Bool, attachmentPaths: [String]) async throws -> PythonExecutionResponse {
        try Task.checkCancellation()
        let paths = try sessions.prepare(sessionID: sessionID)
        _ = try sessions.stageAttachments(attachmentPaths, in: paths)
        let baseline = try files.read(workspace: paths.workspace)
        // A reset discards the entire worker, including mutated JS/Python modules.
        if reset { await discard(sessionID) }
        let sandbox: PythonWebSandbox
        if let existing = sandboxes[sessionID] { sandbox = existing }
        else {
            while sandboxes.count >= maximumRetainedSessions, let oldest = recentSessions.first {
                await discard(oldest)
            }
            sandbox = await PythonWebSandbox()
            sandboxes[sessionID] = sandbox
        }
        recentSessions.removeAll { $0 == sessionID }
        recentSessions.append(sessionID)
        do {
            let envelope = try await sandbox.execute(code: code, reset: reset, files: baseline, timeout: timeoutSeconds)
            try Task.checkCancellation()
            let validated = try files.validate(envelope.files)
            for artifact in envelope.result.artifacts {
                guard ["workspace", "outputs"].contains(artifact.root ?? ""),
                      !artifact.relpath.hasPrefix("/"), !artifact.relpath.split(separator: "/", omittingEmptySubsequences: false).contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }),
                      !artifact.relpath.contains("\\"), !artifact.relpath.contains("\0") else { throw PythonToolError.invalidArtifactPath }
                let path = artifact.root == "outputs" ? "outputs/" + artifact.relpath : artifact.relpath
                guard let value = validated[path], let data = value, Int64(data.count) == artifact.size else { throw PythonToolError.invalidArtifactPath }
            }
            try files.commit(envelope.files, workspace: paths.workspace, baseline: baseline)
            return envelope.result
        } catch is PythonSandboxTimeout {
            await discard(sessionID)
            return Self.failure("TimeoutError", "Python execution exceeded its time limit. Its namespace was reset; workspace files were preserved.")
        } catch is CancellationError {
            await discard(sessionID)
            throw CancellationError()
        } catch let error as PythonToolError {
            await discard(sessionID)
            if case let .resourceLimitExceeded(message) = error { return Self.failure("ResourceLimitExceeded", message) }
            throw error
        } catch {
            await discard(sessionID)
            DiagnosticsLogger.log("Isolated Python execution failed", category: .network)
            throw PythonToolError.invalidResponse
        }
    }

    func resetSession(sessionID: String) async {
        let job = UUID()
        do { try await PythonJobQueue.shared.acquire(job) } catch { return }
        await discard(sessionID)
        await PythonJobQueue.shared.release(job)
    }

    private func discard(_ sessionID: String) async {
        recentSessions.removeAll { $0 == sessionID }
        if let sandbox = sandboxes.removeValue(forKey: sessionID) { await sandbox.dispose() }
    }

    private static func failure(_ type: String, _ message: String) -> PythonExecutionResponse {
        PythonExecutionResponse(status: "error", stdout: "", stderr: "", resultRepr: nil,
            artifacts: [], durationMs: 0, error: PythonExecutionFailure(type: type, message: message, traceback: ""))
    }
}

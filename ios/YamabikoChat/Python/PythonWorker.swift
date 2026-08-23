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
            return "Embedded Python did not stop inside a native extension. Restart YamabikoChat before using python_execute again."
        }
    }
}

private final class PythonExecutionGate: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<String, Never>?
    private var finished = false
    private var interruptStarted = false

    init(continuation: CheckedContinuation<String, Never>) {
        self.continuation = continuation
    }

    var isFinished: Bool {
        lock.lock()
        defer { lock.unlock() }
        return finished
    }

    func beginInterrupt() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !finished, !interruptStarted else { return false }
        interruptStarted = true
        return true
    }

    func finish(_ value: String) {
        lock.lock()
        guard !finished else {
            lock.unlock()
            return
        }
        finished = true
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(returning: value)
    }
}

private final class PythonRuntimeBridgeStore: @unchecked Sendable {
    static let shared = PythonRuntimeBridgeStore()

    private let lock = NSLock()
    private var bridge: PythonRuntimeBridge?

    func resolve(
        pythonHome: String,
        harnessPath: String,
        sitePackagesPath: String?
    ) -> PythonRuntimeBridge {
        lock.lock()
        defer { lock.unlock() }
        if let bridge { return bridge }
        let runtime = PythonRuntimeBridge(
            pythonHome: pythonHome,
            harnessPath: harnessPath,
            sitePackagesPath: sitePackagesPath
        )
        bridge = runtime
        return runtime
    }
}

actor PythonWorker {
    static let shared = PythonWorker()

    private let sessions: PythonSessionStore
    private let timeoutSeconds: TimeInterval
    private let memoryLimitBytes: UInt64
    private var bridge: PythonRuntimeBridge?
    private var poisoned = false

    init(
        sessions: PythonSessionStore = .shared,
        timeoutSeconds: TimeInterval = 120,
        memoryLimitBytes: UInt64 = 1_200_000_000
    ) {
        self.sessions = sessions
        self.timeoutSeconds = timeoutSeconds
        self.memoryLimitBytes = memoryLimitBytes
    }

    func execute(
        sessionID: String,
        code: String,
        reset: Bool,
        attachmentPaths: [String]
    ) async throws -> PythonExecutionResponse {
        guard !poisoned else { throw PythonToolError.poisoned }
        let bridge = try runtimeBridge()
        let paths = try sessions.prepare(sessionID: sessionID, reset: reset)
        _ = try sessions.stageAttachments(attachmentPaths, in: paths)
        let readRoots = [
            Bundle.main.resourceURL?.appendingPathComponent("python").path,
            Bundle.main.resourceURL?.path,
        ].compactMap { $0 }
        let options: [String: Any] = [
            "workspace": paths.workspace.path,
            "outputs": paths.outputs.path,
            "read_roots": readRoots,
            "reset": reset,
        ]
        let data = try JSONSerialization.data(withJSONObject: options)
        let optionsJSON = String(decoding: data, as: UTF8.self)
        let resultJSON = await executeWithWatchdog(
            bridge: bridge,
            sessionID: sessionID,
            code: code,
            optionsJSON: optionsJSON
        )
        guard let resultData = resultJSON.data(using: .utf8),
              let result = try? JSONDecoder().decode(PythonExecutionResponse.self, from: resultData)
        else {
            throw PythonToolError.invalidResponse
        }
        return result
    }

    func discard(sessionID: String) async {
        if let bridge {
            let paths = try? sessions.prepare(sessionID: sessionID, reset: false)
            if let paths,
               let data = try? JSONSerialization.data(withJSONObject: [
                   "workspace": paths.workspace.path,
                   "outputs": paths.outputs.path,
                   "read_roots": [Bundle.main.resourceURL?.path].compactMap { $0 },
                   "reset": true,
               ]) {
                _ = await bridge.executeSession(
                    sessionID,
                    code: "",
                    optionsJSON: String(decoding: data, as: UTF8.self)
                )
            }
        }
        try? sessions.delete(sessionID: sessionID)
    }

    private func runtimeBridge() throws -> PythonRuntimeBridge {
        if let bridge { return bridge }
        guard let resourceRoot = Bundle.main.resourceURL,
              let harness = Bundle.main.url(forResource: "yamabiko_runtime", withExtension: "py")
        else { throw PythonToolError.runtimeResourcesMissing }
        let pythonHome = resourceRoot.appendingPathComponent("python", isDirectory: true)
        guard FileManager.default.fileExists(atPath: pythonHome.path) else {
            throw PythonToolError.runtimeResourcesMissing
        }
        let sitePackages = resourceRoot.appendingPathComponent("PythonSitePackages", isDirectory: true)
        let runtime = PythonRuntimeBridgeStore.shared.resolve(
            pythonHome: pythonHome.path,
            harnessPath: harness.path,
            sitePackagesPath: FileManager.default.fileExists(atPath: sitePackages.path) ? sitePackages.path : nil
        )
        bridge = runtime
        return runtime
    }

    private func executeWithWatchdog(
        bridge: PythonRuntimeBridge,
        sessionID: String,
        code: String,
        optionsJSON: String
    ) async -> String {
        let configuredMemoryLimit = memoryLimitBytes
        let configuredTimeout = timeoutSeconds
        return await withCheckedContinuation { continuation in
            let gate = PythonExecutionGate(continuation: continuation)
            bridge.executeSession(sessionID, code: code, optionsJSON: optionsJSON) { result in
                gate.finish(result)
            }
            Task { [weak self] in
                guard let self else { return }
                let started = ContinuousClock.now
                while !gate.isFinished {
                    try? await Task.sleep(for: .milliseconds(250))
                    guard !gate.isFinished else { return }
                    let footprint = bridge.physicalFootprintBytes()
                    if footprint > configuredMemoryLimit {
                        await self.interrupt(
                            bridge: bridge,
                            gate: gate,
                            exceptionName: "MemoryError",
                            errorType: "MemoryLimitExceeded",
                            message: "Python exceeded the 1.2 GB process memory soft limit."
                        )
                        return
                    }
                    if started.duration(to: .now) >= .seconds(configuredTimeout) {
                        await self.interrupt(
                            bridge: bridge,
                            gate: gate,
                            exceptionName: "TimeoutError",
                            errorType: "TimeoutError",
                            message: "Python execution exceeded the 120 second limit."
                        )
                        return
                    }
                }
            }
        }
    }

    private func interrupt(
        bridge: PythonRuntimeBridge,
        gate: PythonExecutionGate,
        exceptionName: String,
        errorType: String,
        message: String
    ) async {
        guard gate.beginInterrupt() else { return }
        bridge.requestInterrupt(withExceptionName: exceptionName)
        try? await Task.sleep(for: .seconds(5))
        guard !gate.isFinished else { return }
        poisoned = true
        gate.finish(Self.errorJSON(type: errorType, message: message + " The interpreter is now unavailable until app restart."))
    }

    private static func errorJSON(type: String, message: String) -> String {
        let object: [String: Any] = [
            "status": "error", "stdout": "", "stderr": "", "result_repr": NSNull(),
            "artifacts": [], "duration_ms": 0,
            "error": ["type": type, "message": message, "traceback": ""],
        ]
        let data = try? JSONSerialization.data(withJSONObject: object)
        return data.map { String(decoding: $0, as: UTF8.self) } ?? #"{"status":"error"}"#
    }
}

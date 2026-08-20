import Foundation

struct PythonSessionPaths: Sendable, Equatable {
    let root: URL
    let workspace: URL
    let outputs: URL
}

final class PythonSessionStore: @unchecked Sendable {
    static let shared = PythonSessionStore()

    private let fileManager: FileManager
    private let rootOverride: URL?
    private let lock = NSLock()

    init(fileManager: FileManager = .default, rootOverride: URL? = nil) {
        self.fileManager = fileManager
        self.rootOverride = rootOverride
    }

    func prepare(sessionID: String, reset: Bool) throws -> PythonSessionPaths {
        try lock.withLock {
            let paths = try paths(sessionID: sessionID)
            if reset, fileManager.fileExists(atPath: paths.root.path) {
                try fileManager.removeItem(at: paths.root)
            }
            try fileManager.createDirectory(at: paths.workspace, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: paths.outputs, withIntermediateDirectories: true)
            return paths
        }
    }

    func stageAttachments(_ sourcePaths: [String], in paths: PythonSessionPaths) throws -> [String] {
        try lock.withLock {
            var staged: [String] = []
            for sourcePath in sourcePaths {
                let source = URL(fileURLWithPath: sourcePath).standardizedFileURL
                guard fileManager.fileExists(atPath: source.path) else { continue }
                let safeName = source.lastPathComponent.replacingOccurrences(
                    of: #"[^A-Za-z0-9._-]+"#,
                    with: "_",
                    options: .regularExpression
                )
                let destination = paths.workspace.appendingPathComponent(safeName.isEmpty ? "attachment" : safeName)
                if !fileManager.fileExists(atPath: destination.path) {
                    try fileManager.copyItem(at: source, to: destination)
                }
                staged.append(destination.lastPathComponent)
            }
            return staged
        }
    }

    func delete(sessionID: String) throws {
        try lock.withLock {
            let directory = try paths(sessionID: sessionID).root
            if fileManager.fileExists(atPath: directory.path) {
                try fileManager.removeItem(at: directory)
            }
        }
    }

    func purgeAll() throws {
        try lock.withLock {
            let root = try sessionsRoot()
            if fileManager.fileExists(atPath: root.path) {
                try fileManager.removeItem(at: root)
            }
        }
    }

    func outputURL(sessionID: String, relativePath: String) throws -> URL {
        let paths = try paths(sessionID: sessionID)
        let candidate = paths.outputs.appendingPathComponent(relativePath).standardizedFileURL
        let outputRoot = paths.outputs.standardizedFileURL.path + "/"
        guard candidate.path.hasPrefix(outputRoot) else {
            throw PythonToolError.invalidArtifactPath
        }
        return candidate
    }

    private func paths(sessionID: String) throws -> PythonSessionPaths {
        let safeID = sessionID.replacingOccurrences(
            of: #"[^A-Za-z0-9._-]+"#,
            with: "_",
            options: .regularExpression
        )
        guard !safeID.isEmpty else { throw PythonToolError.missingSession }
        let root = try sessionsRoot().appendingPathComponent(safeID, isDirectory: true)
        return PythonSessionPaths(
            root: root,
            workspace: root.appendingPathComponent("workspace", isDirectory: true),
            outputs: root.appendingPathComponent("outputs", isDirectory: true)
        )
    }

    private func sessionsRoot() throws -> URL {
        if let rootOverride { return rootOverride }
        let support = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return support.appendingPathComponent("YamabikoChat/PythonSessions", isDirectory: true)
    }
}

private extension NSLock {
    func withLock<T>(_ operation: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try operation()
    }
}

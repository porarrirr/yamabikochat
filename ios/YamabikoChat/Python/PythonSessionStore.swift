import Foundation
import CryptoKit

struct PythonSessionPaths: Sendable, Equatable {
    let root: URL
    let workspace: URL
    let outputs: URL
}

struct PythonWorkspaceUsage: Sendable, Equatable {
    let fileCount: Int
    let totalBytes: Int64
    let largestFileBytes: Int64
    let maximumDepth: Int
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
            var manifest: [[String: String]] = []
            let attachmentsDirectory = paths.workspace.appendingPathComponent("attachments", isDirectory: true)
            try fileManager.createDirectory(at: attachmentsDirectory, withIntermediateDirectories: true)
            for sourcePath in sourcePaths {
                let source = URL(fileURLWithPath: sourcePath).standardizedFileURL
                guard fileManager.fileExists(atPath: source.path) else {
                    throw PythonToolError.attachmentMissing(source.path)
                }
                let sourceData = try Data(contentsOf: source, options: .mappedIfSafe)
                let attachmentID = SHA256.hash(data: sourceData).map { String(format: "%02x", $0) }.joined()
                let safeName = source.lastPathComponent.replacingOccurrences(
                    of: #"[^A-Za-z0-9._-]+"#,
                    with: "_",
                    options: .regularExpression
                )
                let displayName = safeName.isEmpty ? "attachment" : safeName
                let identityDirectory = attachmentsDirectory.appendingPathComponent(attachmentID, isDirectory: true)
                try fileManager.createDirectory(at: identityDirectory, withIntermediateDirectories: true)
                let destination = identityDirectory.appendingPathComponent(displayName)
                if fileManager.fileExists(atPath: destination.path) {
                    let existingData = try Data(contentsOf: destination, options: .mappedIfSafe)
                    guard existingData == sourceData else {
                        throw PythonToolError.attachmentIdentityCollision(attachmentID)
                    }
                } else {
                    try fileManager.copyItem(at: source, to: destination)
                }
                let relativePath = "attachments/\(attachmentID)/\(displayName)"
                staged.append(relativePath)
                manifest.append([
                    "id": attachmentID,
                    "name": source.lastPathComponent,
                    "path": relativePath,
                ])
            }
            let manifestData = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
            try manifestData.write(to: attachmentsDirectory.appendingPathComponent("manifest.json"), options: .atomic)
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
        try artifactURL(sessionID: sessionID, root: "outputs", relativePath: relativePath)
    }

    func artifactURL(sessionID: String, root: String, relativePath: String) throws -> URL {
        let paths = try paths(sessionID: sessionID)
        let allowedRoot: URL
        switch root {
        case "outputs":
            allowedRoot = paths.outputs
        case "workspace":
            allowedRoot = paths.workspace
        default:
            throw PythonToolError.invalidArtifactPath
        }
        let candidate = allowedRoot.appendingPathComponent(relativePath).standardizedFileURL
        let normalizedRoot = allowedRoot.standardizedFileURL.path + "/"
        guard candidate.path.hasPrefix(normalizedRoot) else {
            throw PythonToolError.invalidArtifactPath
        }
        return candidate
    }

    func workspaceUsage(in paths: PythonSessionPaths) throws -> PythonWorkspaceUsage {
        guard let enumerator = fileManager.enumerator(
            at: paths.workspace,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [],
            errorHandler: { _, _ in false }
        ) else {
            return PythonWorkspaceUsage(fileCount: 0, totalBytes: 0, largestFileBytes: 0, maximumDepth: 0)
        }
        var fileCount = 0
        var totalBytes: Int64 = 0
        var largestFileBytes: Int64 = 0
        var maximumDepth = 0
        for case let url as URL in enumerator {
            let relative = url.path.replacingOccurrences(of: paths.workspace.path + "/", with: "")
            maximumDepth = max(maximumDepth, relative.split(separator: "/").count)
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values.isRegularFile == true else { continue }
            let size = Int64(values.fileSize ?? 0)
            fileCount += 1
            totalBytes += size
            largestFileBytes = max(largestFileBytes, size)
        }
        return PythonWorkspaceUsage(
            fileCount: fileCount,
            totalBytes: totalBytes,
            largestFileBytes: largestFileBytes,
            maximumDepth: maximumDepth
        )
    }

    private func paths(sessionID: String) throws -> PythonSessionPaths {
        let safeID = sessionID.replacingOccurrences(
            of: #"[^A-Za-z0-9._-]+"#,
            with: "_",
            options: .regularExpression
        )
        guard !safeID.isEmpty else { throw PythonToolError.missingSession }
        let root = try sessionsRoot().appendingPathComponent(safeID, isDirectory: true)
        let workspace = root.appendingPathComponent("workspace", isDirectory: true)
        return PythonSessionPaths(
            root: root,
            workspace: workspace,
            outputs: workspace.appendingPathComponent("outputs", isDirectory: true)
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

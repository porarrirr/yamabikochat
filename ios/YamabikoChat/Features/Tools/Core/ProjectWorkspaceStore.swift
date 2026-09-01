import Foundation

struct ProjectWorkspaceFile: Identifiable, Equatable, Sendable {
    var relativePath: String
    var name: String
    var sizeBytes: Int64
    var modifiedAt: Date?

    var id: String { relativePath }
}

enum ProjectWorkspaceError: LocalizedError, Equatable {
    case invalidFile(String)
    case fileTooLarge(String)
    case workspaceLimitExceeded
    case fileNotFound

    var errorDescription: String? {
        switch self {
        case let .invalidFile(name):
            return L10n.format("ファイルを読み込めませんでした: %@", name)
        case let .fileTooLarge(name):
            return L10n.format("ファイルサイズが上限を超えています: %@", name)
        case .workspaceLimitExceeded:
            return L10n.text("ワークスペースの容量またはファイル数の上限を超えています。")
        case .fileNotFound:
            return L10n.text("ファイルが見つかりません。")
        }
    }
}

final class ProjectWorkspaceStore: @unchecked Sendable {
    static let shared = ProjectWorkspaceStore()

    private struct StagedFile {
        var url: URL
        var name: String
        var sizeBytes: Int64
    }

    private let workspaces: EditorWorkspaceStore
    private let fileManager: FileManager
    private let sourcesRootOverride: URL?
    private let lock = NSLock()

    init(
        workspaces: EditorWorkspaceStore = .shared,
        fileManager: FileManager = .default,
        sourcesRootOverride: URL? = nil
    ) {
        self.workspaces = workspaces
        self.fileManager = fileManager
        self.sourcesRootOverride = sourcesRootOverride
    }

    func files(projectID: Int64) throws -> [ProjectWorkspaceFile] {
        try withProjectSources(projectID: projectID) { root in
            try listFiles(in: root)
        }
    }

    @discardableResult
    func importFiles(from sourceURLs: [URL], projectID: Int64) throws -> [ProjectWorkspaceFile] {
        guard !sourceURLs.isEmpty else { return try files(projectID: projectID) }
        var staged: [StagedFile] = []
        do {
            for sourceURL in sourceURLs {
                staged.append(try stageFile(sourceURL))
            }
        } catch {
            for file in staged {
                try? fileManager.removeItem(at: file.url)
            }
            throw error
        }
        defer {
            for file in staged {
                try? fileManager.removeItem(at: file.url)
            }
        }

        return try withProjectSources(projectID: projectID) { root in
            let usage = try workspaceUsage(in: root)
            let importedBytes = staged.reduce(Int64(0)) { $0 + $1.sizeBytes }
            guard usage.fileCount + staged.count <= StrReplaceEditorTool.maximumWorkspaceFiles,
                  usage.totalBytes + importedBytes <= StrReplaceEditorTool.maximumWorkspaceBytes else {
                throw ProjectWorkspaceError.workspaceLimitExceeded
            }

            var reservedNames = Set(
                try fileManager.contentsOfDirectory(atPath: root.path)
                    .map { $0.precomposedStringWithCanonicalMapping.lowercased() }
            )
            var destinations: [URL] = []
            do {
                for file in staged {
                    let name = uniqueName(for: file.name, reservedNames: &reservedNames)
                    let destination = root.appendingPathComponent(name, isDirectory: false)
                    try fileManager.copyItem(at: file.url, to: destination)
                    destinations.append(destination)
                }
            } catch {
                for destination in destinations {
                    try? fileManager.removeItem(at: destination)
                }
                throw error
            }
            return try listFiles(in: root)
        }
    }

    @discardableResult
    func removeFile(relativePath: String, projectID: Int64) throws -> [ProjectWorkspaceFile] {
        try withProjectSources(projectID: projectID) { root in
            let target = try resolve(relativePath: relativePath, in: root)
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: target.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
                throw ProjectWorkspaceError.fileNotFound
            }
            try fileManager.removeItem(at: target)
            try pruneEmptyParentDirectories(startingAt: target.deletingLastPathComponent(), root: root)
            return try listFiles(in: root)
        }
    }

    func delete(projectID: Int64) throws {
        lock.lock()
        defer { lock.unlock() }
        let root = try projectSourcesURL(projectID: projectID)
        if fileManager.fileExists(atPath: root.path) {
            try fileManager.removeItem(at: root)
        }
    }

    /// Creates a new, isolated tool workspace for one provider execution and
    /// copies the project's user-managed source files into it.
    func prepareExecutionWorkspace(projectID: Int64) throws -> String {
        let sessionID = ConversationWorkspacePath.executionSessionID(projectID: projectID)
        do {
            try withProjectSources(projectID: projectID) { sources in
                try workspaces.withWorkspace(sessionID: sessionID) { workspace in
                    let existing = try fileManager.contentsOfDirectory(atPath: workspace.path)
                    guard existing.isEmpty else {
                        throw ProjectWorkspaceError.workspaceLimitExceeded
                    }
                    for source in try fileManager.contentsOfDirectory(
                        at: sources,
                        includingPropertiesForKeys: [.isSymbolicLinkKey],
                        options: []
                    ) {
                        let values = try source.resourceValues(forKeys: [.isSymbolicLinkKey])
                        guard values.isSymbolicLink != true else { continue }
                        try fileManager.copyItem(
                            at: source,
                            to: workspace.appendingPathComponent(source.lastPathComponent)
                        )
                    }
                }
            }
        } catch {
            try? workspaces.delete(sessionID: sessionID)
            throw error
        }
        return sessionID
    }

    private func withProjectSources<T>(
        projectID: Int64,
        _ operation: (URL) throws -> T
    ) throws -> T {
        lock.lock()
        defer { lock.unlock() }
        let root = try projectSourcesURL(projectID: projectID)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        return try operation(root)
    }

    private func projectSourcesURL(projectID: Int64) throws -> URL {
        let root: URL
        if let sourcesRootOverride {
            root = sourcesRootOverride
        } else {
            let support = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            root = support.appendingPathComponent("YamabikoChat/ProjectSources", isDirectory: true)
        }
        return root.appendingPathComponent(
            ConversationWorkspacePath.directoryName(for: "project-\(projectID)"),
            isDirectory: true
        )
    }

    private func stageFile(_ sourceURL: URL) throws -> StagedFile {
        let secured = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if secured { sourceURL.stopAccessingSecurityScopedResource() }
        }

        let safeName = sanitizedFilename(sourceURL.lastPathComponent)
        guard !safeName.isEmpty else {
            throw ProjectWorkspaceError.invalidFile(sourceURL.lastPathComponent)
        }
        let temporary = fileManager.temporaryDirectory
            .appendingPathComponent("yamabiko-project-file-\(UUID().uuidString)", isDirectory: false)
        var coordinationError: NSError?
        var copyError: Error?
        let coordinator = NSFileCoordinator()
        coordinator.coordinate(readingItemAt: sourceURL, options: [.withoutChanges], error: &coordinationError) { coordinatedURL in
            do {
                let values = try coordinatedURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                guard values.isRegularFile == true, values.isSymbolicLink != true else {
                    throw ProjectWorkspaceError.invalidFile(sourceURL.lastPathComponent)
                }
                try self.fileManager.copyItem(at: coordinatedURL, to: temporary)
            } catch {
                copyError = error
            }
        }
        if let coordinationError { throw coordinationError }
        if let copyError { throw copyError }

        do {
            let size = Int64(try temporary.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
            guard size <= StrReplaceEditorTool.maximumFileBytes else {
                throw ProjectWorkspaceError.fileTooLarge(safeName)
            }
            return StagedFile(url: temporary, name: safeName, sizeBytes: size)
        } catch {
            try? fileManager.removeItem(at: temporary)
            throw error
        }
    }

    private func sanitizedFilename(_ value: String) -> String {
        let name = URL(fileURLWithPath: value).lastPathComponent
            .replacingOccurrences(of: #"[\x00-\x1F/:]+"#, with: "_", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return name == "." || name == ".." ? "" : name
    }

    private func uniqueName(for filename: String, reservedNames: inout Set<String>) -> String {
        let source = URL(fileURLWithPath: filename)
        let ext = source.pathExtension
        let stem = source.deletingPathExtension().lastPathComponent
        var candidate = filename
        var index = 2
        while reservedNames.contains(candidate.precomposedStringWithCanonicalMapping.lowercased()) {
            candidate = ext.isEmpty ? "\(stem) (\(index))" : "\(stem) (\(index)).\(ext)"
            index += 1
        }
        reservedNames.insert(candidate.precomposedStringWithCanonicalMapping.lowercased())
        return candidate
    }

    private func listFiles(in root: URL) throws -> [ProjectWorkspaceFile] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey]
        let canonicalRootComponents = root.resolvingSymlinksInPath().standardizedFileURL.pathComponents
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: []
        ) else { return [] }

        var files: [ProjectWorkspaceFile] = []
        while let url = enumerator.nextObject() as? URL {
            let values = try url.resourceValues(forKeys: Set(keys))
            guard values.isRegularFile == true, values.isSymbolicLink != true else { continue }
            let canonicalFileComponents = url.resolvingSymlinksInPath().standardizedFileURL.pathComponents
            guard canonicalFileComponents.starts(with: canonicalRootComponents),
                  canonicalFileComponents.count > canonicalRootComponents.count else {
                throw ProjectWorkspaceError.fileNotFound
            }
            let relativePath = canonicalFileComponents
                .dropFirst(canonicalRootComponents.count)
                .joined(separator: "/")
            files.append(ProjectWorkspaceFile(
                relativePath: relativePath,
                name: url.lastPathComponent,
                sizeBytes: Int64(values.fileSize ?? 0),
                modifiedAt: values.contentModificationDate
            ))
        }
        return files.sorted {
            $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending
        }
    }

    private func workspaceUsage(in root: URL) throws -> (fileCount: Int, totalBytes: Int64) {
        let files = try listFiles(in: root)
        return (files.count, files.reduce(Int64(0)) { $0 + $1.sizeBytes })
    }

    private func resolve(relativePath: String, in root: URL) throws -> URL {
        let components = relativePath.replacingOccurrences(of: "\\", with: "/").split(separator: "/")
        guard !components.isEmpty, components.allSatisfy({ $0 != "." && $0 != ".." }) else {
            throw ProjectWorkspaceError.fileNotFound
        }
        let target = components.reduce(root) { $0.appendingPathComponent(String($1)) }.standardizedFileURL
        let standardizedRoot = root.standardizedFileURL
        guard target.path.hasPrefix(standardizedRoot.path + "/") else {
            throw ProjectWorkspaceError.fileNotFound
        }
        return target
    }

    private func pruneEmptyParentDirectories(startingAt directory: URL, root: URL) throws {
        var current = directory.standardizedFileURL
        let standardizedRoot = root.standardizedFileURL
        while current != standardizedRoot, current.path.hasPrefix(standardizedRoot.path + "/") {
            guard try fileManager.contentsOfDirectory(atPath: current.path).isEmpty else { return }
            try fileManager.removeItem(at: current)
            current.deleteLastPathComponent()
        }
    }
}

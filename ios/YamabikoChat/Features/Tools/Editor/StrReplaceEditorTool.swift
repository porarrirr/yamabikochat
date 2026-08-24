import CryptoKit
import Foundation
import UniformTypeIdentifiers

private enum StrReplaceEditorError: LocalizedError {
    case invalid(String)

    var errorDescription: String? {
        switch self {
        case let .invalid(message): message
        }
    }
}

final class EditorWorkspaceStore: @unchecked Sendable {
    static let shared = EditorWorkspaceStore()

    private let fileManager: FileManager
    private let rootOverride: URL?
    private let lock = NSLock()

    init(fileManager: FileManager = .default, rootOverride: URL? = nil) {
        self.fileManager = fileManager
        self.rootOverride = rootOverride
    }

    func withWorkspace<T>(sessionID: String, _ operation: (URL) throws -> T) throws -> T {
        lock.lock()
        defer { lock.unlock() }
        let root = try workspaceURL(sessionID: sessionID)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        return try operation(root)
    }

    func delete(sessionID: String) throws {
        lock.lock()
        defer { lock.unlock() }
        let root = try workspaceURL(sessionID: sessionID)
        if fileManager.fileExists(atPath: root.path) {
            try fileManager.removeItem(at: root)
        }
    }

    func deleteOrphans(validSessionIDs: [String]) throws {
        lock.lock()
        defer { lock.unlock() }
        let base = try baseURL()
        guard fileManager.fileExists(atPath: base.path) else { return }
        let validNames = Set(validSessionIDs.map(ConversationWorkspacePath.directoryName))
        for entry in try fileManager.contentsOfDirectory(at: base, includingPropertiesForKeys: [.isDirectoryKey], options: []) {
            if !validNames.contains(entry.lastPathComponent) {
                try fileManager.removeItem(at: entry)
            }
        }
    }

    private func workspaceURL(sessionID: String) throws -> URL {
        guard !sessionID.isEmpty else { throw StrReplaceEditorError.invalid("str_replace_editor requires a valid conversation session.") }
        return try ConversationWorkspacePath.workspace(
            sessionID: sessionID,
            fileManager: fileManager,
            rootOverride: rootOverride
        )
    }

    private func baseURL() throws -> URL {
        try ConversationWorkspacePath.sessionsRoot(fileManager: fileManager, override: rootOverride)
    }
}

struct StrReplaceEditorTool: LocalToolExecutor, @unchecked Sendable {
    static let name = "str_replace_editor"
    static let maximumOutputCharacters = 16_000
    static let maximumFileBytes: Int64 = 25 * 1_024 * 1_024
    static let maximumWorkspaceBytes: Int64 = 100 * 1_024 * 1_024
    static let maximumWorkspaceFiles = 1_024
    static let maximumPathDepth = 16

    let definition = ToolDefinition(
        name: Self.name,
        description: """
        Custom editing tool for viewing, creating and editing files in the persistent conversation workspace at /workspace, shared with python_execute. If path is a file, view displays numbered lines; if it is a directory, view lists visible entries up to 2 levels deep. create creates missing parent directories but never overwrites an existing path. str_replace requires old_str to occur exactly once and replaces it literally. Long view output is clipped and marked with <response clipped>.
        """,
        parametersJSON: #"{"type":"object","properties":{"command":{"type":"string","description":"The command to run.","enum":["view","create","str_replace","insert"]},"path":{"type":"string","description":"Absolute virtual path under /workspace."},"file_text":{"type":"string","description":"Required content for create."},"insert_line":{"type":"integer","description":"Required for insert; new_str is inserted after this line (0 inserts before line 1)."},"new_str":{"type":"string","description":"Replacement or insertion text. Omission deletes old_str for str_replace."},"old_str":{"type":"string","description":"Required unique literal text for str_replace."},"view_range":{"type":"array","items":{"type":"integer"},"description":"Optional inclusive 1-based [start,end] range; end -1 means EOF."}},"required":["command","path"]}"#
    )

    private let workspaces: EditorWorkspaceStore
    private let attachments: AttachmentRepository
    private let fileManager: FileManager

    init(
        workspaces: EditorWorkspaceStore = .shared,
        attachments: AttachmentRepository = AttachmentRepository(),
        fileManager: FileManager = .default
    ) {
        self.workspaces = workspaces
        self.attachments = attachments
        self.fileManager = fileManager
    }

    func execute(call: ToolCall) async throws -> ToolResult {
        guard let sessionID = call.providerMetadata?["editorSessionId"]?.trimmedNonEmpty else {
            throw StrReplaceEditorError.invalid("str_replace_editor requires a valid conversation session.")
        }
        let arguments = try decodeArguments(call.argumentsJSON)
        return try workspaces.withWorkspace(sessionID: sessionID) { workspace in
            try stageAttachments(call.providerMetadata?["editorAttachmentsJSON"], in: workspace)
            let target = try resolve(arguments.path, in: workspace)
            let execution = try execute(arguments, target: target, workspace: workspace, sessionID: sessionID)
            return ToolResult(
                callId: call.id,
                name: call.name,
                content: execution.content,
                artifacts: execution.artifact.map { [$0] } ?? []
            )
        }
    }

    private struct Arguments {
        let command: String
        let path: String
        let fileText: String?
        let oldString: String?
        let newString: String?
        let insertLine: Int?
        let viewRange: [Int]?
    }

    private struct Execution {
        let content: String
        let artifact: ToolArtifact?
    }

    private func decodeArguments(_ json: String) throws -> Arguments {
        guard let data = json.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let command = object["command"] as? String,
              let path = object["path"] as? String else {
            throw StrReplaceEditorError.invalid("Parameters `command` and `path` are required.")
        }
        let insertLine: Int?
        if let number = object["insert_line"] as? NSNumber {
            guard CFGetTypeID(number) != CFBooleanGetTypeID(),
                  number.doubleValue.rounded() == number.doubleValue else {
                throw StrReplaceEditorError.invalid("Parameter `insert_line` must be an integer.")
            }
            insertLine = number.intValue
        } else {
            insertLine = nil
        }
        let viewRange: [Int]?
        if let values = object["view_range"] as? [NSNumber] {
            guard values.allSatisfy({
                CFGetTypeID($0) != CFBooleanGetTypeID() && $0.doubleValue.rounded() == $0.doubleValue
            }) else {
                throw StrReplaceEditorError.invalid("Invalid `view_range`. It should be a list of two integers.")
            }
            viewRange = values.map(\.intValue)
        } else {
            viewRange = nil
        }
        return Arguments(
            command: command,
            path: path,
            fileText: object["file_text"] as? String,
            oldString: object["old_str"] as? String,
            newString: object["new_str"] as? String,
            insertLine: insertLine,
            viewRange: viewRange
        )
    }

    private func execute(
        _ arguments: Arguments,
        target: URL,
        workspace: URL,
        sessionID: String
    ) throws -> Execution {
        switch arguments.command {
        case "view":
            return Execution(content: try view(target, virtualPath: arguments.path, range: arguments.viewRange), artifact: nil)
        case "create":
            guard let text = arguments.fileText else {
                throw StrReplaceEditorError.invalid("Parameter `file_text` is required for command: create")
            }
            guard !fileManager.fileExists(atPath: target.path) else {
                throw StrReplaceEditorError.invalid("File already exists at: \(arguments.path). Cannot overwrite files using command `create`.")
            }
            try createParentDirectories(for: target, workspace: workspace)
            return try mutate(target, virtualPath: arguments.path, workspace: workspace, content: text, create: true, sessionID: sessionID)
        case "str_replace":
            let old = try required(arguments.oldString, name: "old_str", command: "str_replace", allowEmpty: false)
            let before = try readRegularFile(target, virtualPath: arguments.path)
            let matches = literalOffsets(of: old, in: before)
            guard let offset = matches.first else {
                throw StrReplaceEditorError.invalid("No replacement was performed, old_str `\(old)` did not appear verbatim in \(arguments.path).")
            }
            guard matches.count == 1 else {
                let lines = matches.map { lineNumber(at: $0, in: before) }
                throw StrReplaceEditorError.invalid("No replacement was performed. Multiple occurrences of old_str `\(old)` in lines [\(lines.map(String.init).joined(separator: ", "))]. Please ensure it is unique")
            }
            let start = before.index(before.startIndex, offsetBy: offset)
            let end = before.index(start, offsetBy: old.count)
            let after = before[..<start] + (arguments.newString ?? "") + before[end...]
            return try mutate(target, virtualPath: arguments.path, workspace: workspace, content: String(after), create: false, sessionID: sessionID)
        case "insert":
            guard let line = arguments.insertLine else {
                throw StrReplaceEditorError.invalid("Parameter `insert_line` is required for command: insert")
            }
            let value = try required(arguments.newString, name: "new_str", command: "insert")
            let before = try readRegularFile(target, virtualPath: arguments.path)
            let separator = before.contains("\r\n") ? "\r\n" : "\n"
            let lines = before.isEmpty ? [] : before.components(separatedBy: separator)
            guard line >= 0, line <= lines.count else {
                throw StrReplaceEditorError.invalid("Invalid `insert_line` parameter: \(line). It should be within the range of lines of the file: [0, \(lines.count)]")
            }
            let insertedLines = value.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
            let after = (Array(lines[..<line]) + insertedLines + Array(lines[line...])).joined(separator: separator)
            return try mutate(target, virtualPath: arguments.path, workspace: workspace, content: after, create: false, sessionID: sessionID)
        default:
            throw StrReplaceEditorError.invalid("Unsupported command: \(arguments.command)")
        }
    }

    private func resolve(_ virtualPath: String, in workspace: URL) throws -> URL {
        guard virtualPath == "/workspace" || virtualPath.hasPrefix("/workspace/") else {
            throw StrReplaceEditorError.invalid("The path \(virtualPath) must be an absolute virtual path under `/workspace`.")
        }
        let relative = String(virtualPath.dropFirst("/workspace".count))
        let components = relative.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard components.count <= Self.maximumPathDepth,
              !components.contains(where: { $0 == "." || $0 == ".." }) else {
            throw StrReplaceEditorError.invalid("The path \(virtualPath) is outside the allowed workspace.")
        }
        var current = workspace.standardizedFileURL
        for component in components {
            current.appendPathComponent(component)
            if fileManager.fileExists(atPath: current.path) {
                let values = try current.resourceValues(forKeys: [.isSymbolicLinkKey])
                if values.isSymbolicLink == true {
                    throw StrReplaceEditorError.invalid("Symbolic links are not allowed in the editor workspace: \(virtualPath)")
                }
            }
        }
        return current.standardizedFileURL
    }

    private func createParentDirectories(for target: URL, workspace: URL) throws {
        let parent = target.deletingLastPathComponent()
        guard parent != workspace else { return }
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
    }

    private func view(_ target: URL, virtualPath: String, range: [Int]?) throws -> String {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: target.path, isDirectory: &isDirectory) else {
            throw StrReplaceEditorError.invalid("The path \(virtualPath) does not exist. Please provide a valid path.")
        }
        if isDirectory.boolValue {
            guard range == nil else {
                throw StrReplaceEditorError.invalid("The `view_range` parameter is not allowed when `path` points to a directory.")
            }
            return try listDirectory(target, virtualPath: virtualPath)
        }
        let content = try readRegularFile(target, virtualPath: virtualPath)
        let allLines = content.components(separatedBy: "\n")
        var start = 1
        var end = allLines.count
        var suffix = ""
        if let range {
            guard range.count == 2 else {
                throw StrReplaceEditorError.invalid("Invalid `view_range`. It should be a list of two integers.")
            }
            start = range[0]
            end = range[1] == -1 ? allLines.count : range[1]
            guard start >= 1, start <= allLines.count, end >= start, end <= allLines.count else {
                throw StrReplaceEditorError.invalid("Invalid `view_range`: [\(range.map(String.init).joined(separator: ", "))] for a file with \(allLines.count) lines.")
            }
            suffix = " with view_range=[\(range[0]), \(range[1])]"
        }
        let numbered = allLines[(start - 1)..<end].enumerated().map {
            String(format: "%6d  %@", start + $0.offset, $0.element)
        }.joined(separator: "\n")
        return clip("Here's the content of \(virtualPath) with line numbers (which has a total of \(allLines.count) lines)\(suffix):\n\(numbered)\n")
    }

    private func listDirectory(_ directory: URL, virtualPath: String) throws -> String {
        var rows = ["d\t\(virtualPath)"]
        func visit(_ url: URL, virtual: String, depth: Int) throws {
            let entries = try fileManager.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey],
                options: []
            ).filter { !$0.lastPathComponent.hasPrefix(".") && $0.lastPathComponent != "node_modules" && $0.lastPathComponent != "__pycache__" }
            for entry in entries {
                let values = try entry.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey])
                guard values.isSymbolicLink != true else { continue }
                let childVirtual = virtual + "/" + entry.lastPathComponent
                rows.append("\(values.isDirectory == true ? "d" : values.isRegularFile == true ? "f" : "?")\t\(childVirtual)")
                if values.isDirectory == true, depth < 2 { try visit(entry, virtual: childVirtual, depth: depth + 1) }
            }
        }
        try visit(directory, virtual: virtualPath, depth: 1)
        rows.sort { $0.split(separator: "\t", maxSplits: 1).last! < $1.split(separator: "\t", maxSplits: 1).last! }
        return clip("Here're the files and directories up to 2 levels deep in \(virtualPath), excluding hidden items, node_modules, and Python cache directories:\n\(rows.joined(separator: "\n"))\n")
    }

    private func readRegularFile(_ target: URL, virtualPath: String) throws -> String {
        let values = try target.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true else {
            throw StrReplaceEditorError.invalid("The path \(virtualPath) is not a regular file.")
        }
        guard Int64(values.fileSize ?? 0) <= Self.maximumFileBytes else {
            throw StrReplaceEditorError.invalid("The file exceeds the \(Self.maximumFileBytes)-byte limit.")
        }
        let data = try Data(contentsOf: target, options: .mappedIfSafe)
        guard let content = String(data: data, encoding: .utf8) else {
            throw StrReplaceEditorError.invalid("The file is not valid UTF-8 text: \(virtualPath)")
        }
        return content
    }

    private func mutate(
        _ target: URL,
        virtualPath: String,
        workspace: URL,
        content: String,
        create: Bool,
        sessionID: String
    ) throws -> Execution {
        let data = Data(content.utf8)
        try validateQuota(workspace: workspace, target: target, newSize: Int64(data.count), create: create)
        let mime = UTType(filenameExtension: target.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        let temporary = target.deletingLastPathComponent().appendingPathComponent(".yamabiko-editor-\(UUID().uuidString)")
        do {
            try data.write(to: temporary, options: .withoutOverwriting)
            if create {
                try fileManager.moveItem(at: temporary, to: target)
            } else {
                _ = try fileManager.replaceItemAt(target, withItemAt: temporary)
            }
        } catch {
            try? fileManager.removeItem(at: temporary)
            throw error
        }
        let snapshot = try attachments.persistGeneratedFileReplacingExisting(
            data: data,
            filename: target.lastPathComponent,
            collection: "Editor \(sessionID)"
        )
        return Execution(
            content: create ? "New file created successfully at: \(virtualPath)" : "The file \(virtualPath) has been edited successfully.",
            artifact: ToolArtifact(path: snapshot.path, name: target.lastPathComponent, mime: mime, size: Int64(data.count))
        )
    }

    private func validateQuota(workspace: URL, target: URL, newSize: Int64, create: Bool) throws {
        guard newSize <= Self.maximumFileBytes else {
            throw StrReplaceEditorError.invalid("The file exceeds the \(Self.maximumFileBytes)-byte limit.")
        }
        let enumerator = fileManager.enumerator(at: workspace, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey])
        var count = 0
        var bytes: Int64 = 0
        while let url = enumerator?.nextObject() as? URL {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values.isRegularFile == true else { continue }
            count += 1
            if url.standardizedFileURL != target.standardizedFileURL { bytes += Int64(values.fileSize ?? 0) }
        }
        let proposedCount = create ? count + 1 : count
        guard proposedCount <= Self.maximumWorkspaceFiles, bytes + newSize <= Self.maximumWorkspaceBytes else {
            throw StrReplaceEditorError.invalid("The editor workspace resource limit would be exceeded.")
        }
    }

    private func stageAttachments(_ json: String?, in workspace: URL) throws {
        guard let json, let data = json.data(using: .utf8),
              let paths = try? JSONDecoder().decode([String].self, from: data), !paths.isEmpty else { return }
        let root = workspace.appendingPathComponent("attachments", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        for path in paths {
            let source = URL(fileURLWithPath: path).standardizedFileURL
            guard fileManager.fileExists(atPath: source.path) else { continue }
            let sourceData = try Data(contentsOf: source, options: .mappedIfSafe)
            guard Int64(sourceData.count) <= Self.maximumFileBytes else {
                throw StrReplaceEditorError.invalid("An attachment exceeds the editor file limit: \(source.lastPathComponent)")
            }
            let digest = SHA256.hash(data: sourceData).map { String(format: "%02x", $0) }.joined()
            let directory = root.appendingPathComponent(digest, isDirectory: true)
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let safeName = source.lastPathComponent.replacingOccurrences(of: #"[^A-Za-z0-9._-]+"#, with: "_", options: .regularExpression)
            let destination = directory.appendingPathComponent(safeName.isEmpty ? "attachment" : safeName)
            if !fileManager.fileExists(atPath: destination.path) {
                try validateQuota(workspace: workspace, target: destination, newSize: Int64(sourceData.count), create: true)
                let temporary = directory.appendingPathComponent(".yamabiko-editor-\(UUID().uuidString)")
                do {
                    try sourceData.write(to: temporary, options: .withoutOverwriting)
                    try fileManager.moveItem(at: temporary, to: destination)
                } catch {
                    try? fileManager.removeItem(at: temporary)
                    throw error
                }
            }
        }
    }

    private func required(_ value: String?, name: String, command: String, allowEmpty: Bool = true) throws -> String {
        guard let value else { throw StrReplaceEditorError.invalid("Parameter `\(name)` is required for command: \(command)") }
        guard allowEmpty || !value.isEmpty else { throw StrReplaceEditorError.invalid("Parameter `\(name)` is empty for command: \(command)") }
        return value
    }

    private func literalOffsets(of needle: String, in haystack: String) -> [Int] {
        var offsets: [Int] = []
        var searchStart = haystack.startIndex
        while searchStart <= haystack.endIndex, let range = haystack.range(of: needle, options: .literal, range: searchStart..<haystack.endIndex) {
            offsets.append(haystack.distance(from: haystack.startIndex, to: range.lowerBound))
            searchStart = range.upperBound
        }
        return offsets
    }

    private func lineNumber(at offset: Int, in content: String) -> Int {
        let index = content.index(content.startIndex, offsetBy: offset)
        return content[..<index].reduce(1) { $1 == "\n" ? $0 + 1 : $0 }
    }

    private func clip(_ value: String) -> String {
        guard value.count > Self.maximumOutputCharacters else { return value }
        let end = value.index(value.startIndex, offsetBy: Self.maximumOutputCharacters)
        return String(value[..<end]) + "<response clipped><NOTE>To save on context only part of this output has been shown.</NOTE>"
    }
}

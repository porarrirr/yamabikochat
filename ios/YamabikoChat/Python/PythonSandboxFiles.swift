import Foundation

struct PythonSandboxFile: Codable, Equatable, Sendable {
    var path: String
    /// nil is an empty directory, otherwise base64 file bytes.
    var data: String?
}

/// The only filesystem broker. It never accepts absolute host paths from Python.
struct PythonSandboxFiles: Sendable {
    var maximumFiles: Int = 1_024
    var maximumBytes: Int64 = 100 * 1_024 * 1_024
    var maximumFileBytes: Int64 = 25 * 1_024 * 1_024
    var maximumDepth: Int = 16

    func validate(_ files: [PythonSandboxFile]) throws -> [String: Data?] {
        var values: [String: Data?] = [:]
        var seen = Set<String>()
        var total: Int64 = 0
        var count = 0
        guard files.count <= maximumFiles * 4 else { throw PythonToolError.resourceLimitExceeded("Too many workspace entries.") }
        for file in files {
            let parts = file.path.split(separator: "/", omittingEmptySubsequences: false)
            guard !file.path.contains("\\"), !file.path.contains("\0"), file.path.utf8.count <= 4096,
                  !parts.isEmpty, parts.count <= maximumDepth,
                  parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && $0.utf8.count <= 255 }),
                  seen.insert(file.path).inserted else { throw PythonToolError.invalidArtifactPath }
            if let encoded = file.data {
                guard encoded.utf8.count <= ((maximumFileBytes + 2) / 3) * 4,
                      let data = Data(base64Encoded: encoded) else { throw PythonToolError.resourceLimitExceeded("Invalid or oversized workspace file.") }
                count += 1
                total += Int64(data.count)
                guard count <= maximumFiles, Int64(data.count) <= maximumFileBytes, total <= maximumBytes else { throw PythonToolError.resourceLimitExceeded("Python workspace quota exceeded.") }
                values.updateValue(data, forKey: file.path)
            } else { values.updateValue(nil, forKey: file.path) }
        }
        // Reject a file used as another entry's parent before touching disk.
        for path in values.keys {
            var parent = (path as NSString).deletingLastPathComponent
            while !parent.isEmpty {
                if let entry = values[parent], entry != nil { throw PythonToolError.invalidArtifactPath }
                parent = (parent as NSString).deletingLastPathComponent
            }
        }
        return values
    }

    func read(workspace: URL) throws -> [PythonSandboxFile] {
        let manager = FileManager.default
        // Enumeration resolves aliases such as /var -> /private/var on iOS.
        // Normalize both root and entries before stripping the workspace prefix.
        let workspace = workspace.resolvingSymlinksInPath().standardizedFileURL
        let prefix = workspace.path + "/"
        guard let enumerator = manager.enumerator(at: workspace, includingPropertiesForKeys: [.isSymbolicLinkKey, .isRegularFileKey, .isDirectoryKey, .fileSizeKey]) else { throw PythonToolError.invalidArtifactPath }
        var files: [PythonSandboxFile] = []
        var total: Int64 = 0
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey, .isDirectoryKey, .fileSizeKey])
            guard values.isSymbolicLink != true else { throw PythonToolError.invalidArtifactPath }
            let path = url.resolvingSymlinksInPath().standardizedFileURL.path
            guard path.hasPrefix(prefix) else { throw PythonToolError.invalidArtifactPath }
            let relative = String(path.dropFirst(prefix.count))
            if values.isDirectory == true { files.append(PythonSandboxFile(path: relative, data: nil)); continue }
            guard values.isRegularFile == true, Int64(values.fileSize ?? 0) <= maximumFileBytes else { throw PythonToolError.resourceLimitExceeded("Invalid or oversized workspace file.") }
            total += Int64(values.fileSize ?? 0)
            guard total <= maximumBytes, files.count <= maximumFiles * 4 else { throw PythonToolError.resourceLimitExceeded("Python workspace quota exceeded.") }
            files.append(PythonSandboxFile(path: relative, data: try Data(contentsOf: url).base64EncodedString()))
        }
        _ = try validate(files)
        return files.sorted { $0.path < $1.path }
    }

    func commit(_ files: [PythonSandboxFile], workspace: URL, baseline: [PythonSandboxFile]) throws {
        let values = try validate(files)
        // A parallel editor must not have its changes overwritten by an old copy.
        guard try read(workspace: workspace) == baseline else { throw PythonToolError.resourceLimitExceeded("Workspace changed during Python execution; run the cell again.") }
        let manager = FileManager.default
        let staging = workspace.deletingLastPathComponent().appendingPathComponent(".python-result-\(UUID().uuidString)", isDirectory: true)
        try manager.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: staging) }
        for (path, bytes) in values.sorted(by: { $0.key < $1.key }) {
            let target = staging.appendingPathComponent(path)
            if let bytes {
                try manager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try bytes.write(to: target, options: [.atomic, .completeFileProtection])
            } else { try manager.createDirectory(at: target, withIntermediateDirectories: true) }
        }
        try manager.createDirectory(at: staging.appendingPathComponent("outputs"), withIntermediateDirectories: true)
        _ = try manager.replaceItemAt(workspace, withItemAt: staging)
    }
}

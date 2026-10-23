import Foundation

/// iOS encrypts these files with Complete Protection; they are unavailable while locked.
/// Keep internal files out of backups and create public copies only on an explicit share.
enum ProtectedFileStorage {
    static func createDirectory(_ url: URL, fileManager: FileManager = .default) throws {
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true,
                                        attributes: [.protectionKey: FileProtectionType.complete])
        try protect(url, fileManager: fileManager)
    }

    static func write(_ data: Data, to url: URL, fileManager: FileManager = .default) throws {
        try createDirectory(url.deletingLastPathComponent(), fileManager: fileManager)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        try protect(url, fileManager: fileManager)
    }

    static func protect(_ url: URL, fileManager: FileManager = .default) throws {
        guard try url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else {
            throw CocoaError(.fileReadNoPermission)
        }
        try fileManager.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: url.path)
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        var target = url
        try target.setResourceValues(resourceValues)
    }

    /// Upgrade existing data too, including files copied with weaker source attributes.
    static func protectExistingTree(_ root: URL, fileManager: FileManager = .default) throws {
        guard fileManager.fileExists(atPath: root.path) else { return }
        try protect(root, fileManager: fileManager)
        var enumerationError: Error?
        guard let entries = fileManager.enumerator(at: root, includingPropertiesForKeys: [.isSymbolicLinkKey],
                                                   errorHandler: { _, error in enumerationError = error; return false }) else {
            throw CocoaError(.fileReadUnknown)
        }
        for case let url as URL in entries {
            try protect(url, fileManager: fileManager)
        }
        if let enumerationError { throw enumerationError }
    }
}

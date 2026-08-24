import Foundation
import UniformTypeIdentifiers

enum AttachmentValidationResult: Equatable {
    case valid
    case tooLarge(sizeBytes: Int)
    case unsupportedType
    case dangerousFile
    case unreadable
}

final class AttachmentRepository: @unchecked Sendable {
    private let fileManager: FileManager
    private let generatedFilesRootOverride: URL?
    private let generatedFilesLock = NSLock()

    init(fileManager: FileManager = .default, generatedFilesRootOverride: URL? = nil) {
        self.fileManager = fileManager
        self.generatedFilesRootOverride = generatedFilesRootOverride
    }

    func requiresVision(url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension.lowercased()) else {
            return false
        }
        return type.conforms(to: .image)
    }

    func validate(url: URL) -> AttachmentValidationResult {
        guard url.isFileURL else { return .unreadable }
        let secured = url.startAccessingSecurityScopedResource()
        defer {
            if secured {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentTypeKey])
            let size = values.fileSize ?? 0
            if size > AppConstants.maxAttachmentSizeBytes {
                return .tooLarge(sizeBytes: size)
            }

            if isDangerous(url: url) {
                return .dangerousFile
            }

            if let type = values.contentType {
                if !isSupported(type: type) {
                    return .unsupportedType
                }
            }
            return .valid
        } catch {
            return .unreadable
        }
    }

    func persistAttachment(url: URL) throws -> URL {
        let supportURL = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = supportURL.appendingPathComponent("YamabikoChat/Attachments", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let destination = directory.appendingPathComponent(UUID().uuidString + "_" + url.lastPathComponent)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        let stagedURL = try coordinateAndCopyToTemporary(url: url)
        defer { try? fileManager.removeItem(at: stagedURL) }

        do {
            try fileManager.moveItem(at: stagedURL, to: destination)
        } catch {
            try fileManager.copyItem(at: stagedURL, to: destination)
        }
        return destination
    }

    func persistGeneratedFile(data: Data, filename: String, collection: String? = nil) throws -> URL {
        try generatedFilesLock.withLock {
            let safeName = safeGeneratedName(filename, fallback: "generated-file")
            var directory = try generatedFilesRoot()
            if let collection, !collection.isEmpty {
                directory.appendPathComponent(
                    safeGeneratedName(collection, fallback: "Chat"),
                    isDirectory: true
                )
            }
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let destination = uniqueDestination(directory: directory, filename: safeName)
            try data.write(to: destination, options: [.atomic])
            return destination
        }
    }

    func persistGeneratedFileReplacingExisting(data: Data, filename: String, collection: String? = nil) throws -> URL {
        try persistGeneratedFileReplacingExisting(
            data: data,
            relativePath: filename,
            collection: collection
        )
    }

    func persistGeneratedFileReplacingExisting(data: Data, relativePath: String, collection: String? = nil) throws -> URL {
        try generatedFilesLock.withLock {
            var directory = try generatedFilesRoot()
            if let collection, !collection.isEmpty {
                directory.appendPathComponent(
                    safeGeneratedName(collection, fallback: "Chat"),
                    isDirectory: true
                )
            }
            let components = relativePath
                .replacingOccurrences(of: "\\", with: "/")
                .split(separator: "/", omittingEmptySubsequences: true)
                .map(String.init)
            let safeComponents = components
                .filter { $0 != "." && $0 != ".." }
                .map { safeGeneratedName($0, fallback: "generated-file") }
            guard !safeComponents.isEmpty, safeComponents.count == components.count else {
                throw CocoaError(.fileWriteInvalidFileName)
            }
            let destination = safeComponents.reduce(directory) { partial, component in
                partial.appendingPathComponent(component)
            }
            try fileManager.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: destination, options: [.atomic])
            return destination
        }
    }

    private func generatedFilesRoot() throws -> URL {
        if let generatedFilesRootOverride { return generatedFilesRootOverride }
        let documents = try fileManager.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return documents.appendingPathComponent("Generated Files", isDirectory: true)
    }

    private func safeGeneratedName(_ value: String, fallback: String) -> String {
        let component = URL(fileURLWithPath: value).lastPathComponent
            .replacingOccurrences(of: #"[\x00-\x1F/:]+"#, with: "_", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return component.isEmpty || component == "." ? fallback : component
    }

    private func uniqueDestination(directory: URL, filename: String) -> URL {
        let initial = directory.appendingPathComponent(filename)
        guard fileManager.fileExists(atPath: initial.path) else { return initial }
        let source = URL(fileURLWithPath: filename)
        let ext = source.pathExtension
        let stem = source.deletingPathExtension().lastPathComponent
        var index = 2
        while true {
            let candidateName = ext.isEmpty ? "\(stem) (\(index))" : "\(stem) (\(index)).\(ext)"
            let candidate = directory.appendingPathComponent(candidateName)
            if !fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
            index += 1
        }
    }

    private func coordinateAndCopyToTemporary(url: URL) throws -> URL {
        let secured = url.startAccessingSecurityScopedResource()
        defer {
            if secured {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let ext = url.pathExtension.isEmpty ? "tmp" : url.pathExtension
        let temporaryURL = fileManager.temporaryDirectory
            .appendingPathComponent("yamabiko-attachment-\(UUID().uuidString)")
            .appendingPathExtension(ext)

        var coordinationError: NSError?
        var copyError: Error?
        let coordinator = NSFileCoordinator()
        coordinator.coordinate(readingItemAt: url, options: [.withoutChanges], error: &coordinationError) { coordinatedURL in
            do {
                if self.fileManager.fileExists(atPath: temporaryURL.path) {
                    try self.fileManager.removeItem(at: temporaryURL)
                }
                try self.fileManager.copyItem(at: coordinatedURL, to: temporaryURL)
            } catch {
                copyError = error
            }
        }

        if let coordinationError {
            throw coordinationError
        }
        if let copyError {
            throw copyError
        }
        guard fileManager.fileExists(atPath: temporaryURL.path) else {
            throw CocoaError(.fileReadUnknown)
        }
        return temporaryURL
    }

    private func isSupported(type: UTType) -> Bool {
        type.conforms(to: .image) ||
            type.conforms(to: .pdf) ||
            type.conforms(to: .plainText) ||
            type.conforms(to: .utf8PlainText)
    }

    private func isDangerous(url: URL) -> Bool {
        let blocked = ["exe", "bat", "cmd", "com", "sh", "js", "dll", "msi", "apk", "ipa"]
        return blocked.contains(url.pathExtension.lowercased())
    }
}

private extension NSLock {
    func withLock<T>(_ operation: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try operation()
    }
}

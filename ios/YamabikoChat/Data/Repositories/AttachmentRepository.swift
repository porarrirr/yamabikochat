import Foundation
import UniformTypeIdentifiers

enum AttachmentValidationResult: Equatable {
    case valid
    case tooLarge(sizeBytes: Int)
    case unsupportedType
    case dangerousFile
    case unreadable
}

final class AttachmentRepository {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func validate(url: URL) -> AttachmentValidationResult {
        guard url.isFileURL else { return .unreadable }

        do {
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentTypeKey])
            let size = values.fileSize ?? 0
            if size > AppConstants.maxAttachmentSizeBytes {
                return .tooLarge(sizeBytes: size)
            }

            if let type = values.contentType {
                if !isSupported(type: type) {
                    return .unsupportedType
                }
            }

            if isDangerous(url: url) {
                return .dangerousFile
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
        try fileManager.copyItem(at: url, to: destination)
        return destination
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
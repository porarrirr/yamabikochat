import CryptoKit
import Foundation

enum ConversationWorkspaceError: LocalizedError {
    case missingSession

    var errorDescription: String? {
        "A conversation workspace requires a valid session identifier."
    }
}

enum ConversationWorkspacePath {
    static func sessionsRoot(fileManager: FileManager = .default, override: URL? = nil) throws -> URL {
        if let override { return override }
        let support = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        // Keep the existing editor location as the canonical store so persistent
        // conversation files survive this shared-workspace migration.
        return support.appendingPathComponent("YamabikoChat/EditorWorkspaces", isDirectory: true)
    }

    static func workspace(
        sessionID: String,
        fileManager: FileManager = .default,
        rootOverride: URL? = nil
    ) throws -> URL {
        guard !sessionID.isEmpty else { throw ConversationWorkspaceError.missingSession }
        return try sessionsRoot(fileManager: fileManager, override: rootOverride)
            .appendingPathComponent(directoryName(for: sessionID), isDirectory: true)
    }

    static func directoryName(for sessionID: String) -> String {
        SHA256.hash(data: Data(sessionID.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

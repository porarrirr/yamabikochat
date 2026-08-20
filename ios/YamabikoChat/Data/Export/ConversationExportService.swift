import Foundation
import ZIPFoundation

struct ConversationMessageDebugExport: Codable, Equatable {
    var message: ChatMessage
    var thinkingStream: String?
    var attachments: [String]
    var toolActivity: ToolActivityPayload?
    var variants: [ConversationVariantDebugExport]
}

struct ConversationVariantDebugExport: Codable, Equatable {
    var variant: ChatMessageVariant
    var attachments: [String]
    var toolActivity: ToolActivityPayload?
}

struct DualMessageDebugExport: Codable, Equatable {
    var message: DualChatMessage
    var attachments: [String]
    var modelAToolActivity: ToolActivityPayload?
    var modelBToolActivity: ToolActivityPayload?
}

struct AutoConversationDebugExport: Codable, Equatable {
    var conversation: AutoConversation
    var messages: [AutoConversationMessageDebugExport]
}

struct AutoConversationMessageDebugExport: Codable, Equatable {
    var message: AutoConversationMessage
    var piExecution: JSONValue?
}

struct ConversationExportFileRecord: Codable, Equatable {
    enum Status: String, Codable {
        case included
        case missing
        case unreadable
    }

    var originalPath: String
    var archivePath: String?
    var status: Status
    var size: Int64?
    var error: String?
}

struct ConversationDebugExport: Codable, Equatable {
    struct ApplicationInfo: Codable, Equatable {
        var name: String
        var version: String
        var build: String
        var platform: String
    }

    var format: String = "yamabiko-chat-debug-export"
    var schemaVersion: Int = 1
    var exportedAtMs: Int64
    var application: ApplicationInfo
    var securityNotice: String
    var conversation: Conversation
    var messages: [ConversationMessageDebugExport]
    var dualMessages: [DualMessageDebugExport]
    var autoConversations: [AutoConversationDebugExport]
    var fusionTraces: [FusionTraceRecord]
    var tokenUsageRecords: [TokenUsageRecord]
    var executionMetrics: [ConversationExecutionMetric]
    var files: [ConversationExportFileRecord]

    var referencedFilePaths: [String] {
        let messageFiles = messages.flatMap { message in
            message.attachments
                + (message.toolActivity?.attachmentPaths ?? [])
                + message.variants.flatMap { variant in
                    variant.attachments + (variant.toolActivity?.attachmentPaths ?? [])
                }
        }
        let dualFiles = dualMessages.flatMap { dualMessage in
            dualMessage.attachments
                + (dualMessage.modelAToolActivity?.attachmentPaths ?? [])
                + (dualMessage.modelBToolActivity?.attachmentPaths ?? [])
        }
        let fusionFiles = fusionTraces
            .compactMap { try? $0.fusionTrace() }
            .flatMap { trace in
                trace.panelResults.flatMap { $0.toolActivity?.attachmentPaths ?? [] }
            }
        return messageFiles + dualFiles + fusionFiles
    }
}

enum ConversationExportError: LocalizedError {
    case conversationNotFound
    case archiveCreationFailed

    var errorDescription: String? {
        switch self {
        case .conversationNotFound:
            return L10n.text("チャットが見つかりません。")
        case .archiveCreationFailed:
            return L10n.text("チャットの書き出しファイルを作成できませんでした。")
        }
    }
}

enum ConversationExportService {
    static func createArchive(
        snapshot: ConversationDebugExport,
        fileManager: FileManager = .default
    ) throws -> URL {
        let exportRoot = fileManager.temporaryDirectory
            .appendingPathComponent("YamabikoChatExports", isDirectory: true)
        try fileManager.createDirectory(at: exportRoot, withIntermediateDirectories: true)

        let identifier = UUID().uuidString
        let stagingURL = exportRoot.appendingPathComponent(identifier, isDirectory: true)
        try fileManager.createDirectory(at: stagingURL, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: stagingURL) }

        let filesURL = stagingURL.appendingPathComponent("files", isDirectory: true)
        try fileManager.createDirectory(at: filesURL, withIntermediateDirectories: true)

        var export = snapshot
        export.files = includeFiles(snapshot.referencedFilePaths, at: filesURL, fileManager: fileManager)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let exportData = try encoder.encode(export)
        try exportData.write(to: stagingURL.appendingPathComponent("conversation.json"), options: .atomic)

        let readme = """
        YamabikoChat complete debug export

        conversation.json contains the stored conversation, every variant, thinking text,
        tool calls and results, token usage, execution timing, and Pi Agent execution snapshots.
        Pi snapshots include Agent.state.messages and the provider request payload captured for
        every LLM step. API keys, authorization values, credentials, access tokens, and abort
        signals are deliberately excluded.

        files/ contains readable chat attachments and generated artifacts. Missing or unreadable
        files remain listed in conversation.json with an explicit status and error.
        """
        try Data(readme.utf8).write(to: stagingURL.appendingPathComponent("README.txt"), options: .atomic)

        let filename = safeFilename(snapshot.conversation.title)
        let archiveURL = exportRoot.appendingPathComponent("\(filename)-\(identifier.prefix(8)).zip")
        try fileManager.zipItem(
            at: stagingURL,
            to: archiveURL,
            shouldKeepParent: false,
            compressionMethod: .deflate
        )
        guard fileManager.fileExists(atPath: archiveURL.path) else {
            throw ConversationExportError.archiveCreationFailed
        }
        return archiveURL
    }

    private static func includeFiles(
        _ paths: [String],
        at filesURL: URL,
        fileManager: FileManager
    ) -> [ConversationExportFileRecord] {
        var seen = Set<String>()
        let uniquePaths = paths.filter { seen.insert($0).inserted }

        return uniquePaths.enumerated().map { offset, originalPath in
            let sourceURL = PiAgentRuntime.attachmentFileURL(from: originalPath)
            guard fileManager.fileExists(atPath: sourceURL.path) else {
                return ConversationExportFileRecord(
                    originalPath: originalPath,
                    archivePath: nil,
                    status: .missing,
                    size: nil,
                    error: "File does not exist at export time"
                )
            }

            let archiveName = String(format: "%04d-%@", offset + 1, safeFilename(sourceURL.lastPathComponent))
            let destinationURL = filesURL.appendingPathComponent(archiveName)
            do {
                try fileManager.copyItem(at: sourceURL, to: destinationURL)
                let size = try destinationURL.resourceValues(forKeys: [.fileSizeKey]).fileSize
                return ConversationExportFileRecord(
                    originalPath: originalPath,
                    archivePath: "files/\(archiveName)",
                    status: .included,
                    size: size.map(Int64.init),
                    error: nil
                )
            } catch {
                DiagnosticsLogger.log(
                    "Conversation export could not include file",
                    level: .warning,
                    category: .chat,
                    metadata: ["path": originalPath],
                    error: error
                )
                return ConversationExportFileRecord(
                    originalPath: originalPath,
                    archivePath: nil,
                    status: .unreadable,
                    size: nil,
                    error: error.localizedDescription
                )
            }
        }
    }

    private static func safeFilename(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        let sanitized = value.unicodeScalars.map { allowed.contains($0) ? Character(String($0)) : "_" }
        let result = String(sanitized).trimmingCharacters(in: CharacterSet(charactersIn: "._"))
        return result.isEmpty ? "YamabikoChat" : String(result.prefix(80))
    }
}

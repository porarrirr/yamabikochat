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

struct ConversationPiExecutionExport: Codable, Equatable {
    var source: String
    var sourceId: String
    var execution: JSONValue
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
    var schemaVersion: Int = 2
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
    var piExecutions: [ConversationPiExecutionExport]
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
    case referencedFileUnavailable(String)
    case invalidStoredRecord(String)

    var errorDescription: String? {
        switch self {
        case .conversationNotFound:
            return L10n.text("チャットが見つかりません。")
        case .archiveCreationFailed:
            return L10n.text("チャットの書き出しファイルを作成できませんでした。")
        case let .referencedFileUnavailable(path):
            return L10n.format("参照ファイルを完全に書き出せませんでした: %@", path)
        case let .invalidStoredRecord(record):
            return L10n.format("書き出し対象の保存データが壊れています: %@", record)
        }
    }
}

enum ConversationExportMode: Sendable, Equatable {
    case standard
    case fullDiagnostics
}

enum ConversationExportService {
    static func createArchive(
        snapshot: ConversationDebugExport,
        mode: ConversationExportMode = .standard,
        fileManager: FileManager = .default
    ) throws -> URL {
        let exportRoot = fileManager.temporaryDirectory
            .appendingPathComponent("YamabikoChatExports", isDirectory: true)
        try fileManager.createDirectory(at: exportRoot, withIntermediateDirectories: true)
        purgeExpiredArchives(in: exportRoot, fileManager: fileManager)

        let identifier = UUID().uuidString
        let stagingURL = exportRoot.appendingPathComponent(identifier, isDirectory: true)
        try fileManager.createDirectory(at: stagingURL, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: stagingURL) }

        let filesURL = stagingURL.appendingPathComponent("files", isDirectory: true)
        try fileManager.createDirectory(at: filesURL, withIntermediateDirectories: true)

        for trace in snapshot.fusionTraces {
            _ = try trace.fusionTrace()
        }
        let piExecutions = snapshot.piExecutions
        var export = preparedExport(snapshot, mode: mode)
        export.files = try includeFiles(snapshot.referencedFilePaths, at: filesURL, fileManager: fileManager)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let exportData = try encoder.encode(export)
        try exportData.write(to: stagingURL.appendingPathComponent("conversation.json"), options: .atomic)
        if mode == .fullDiagnostics {
            try writePiSessions(piExecutions, at: stagingURL, encoder: encoder, fileManager: fileManager)
        }

        let readme = mode == .fullDiagnostics ? """
        YamabikoChat complete diagnostic export

        conversation.json contains the stored conversation, variants, thinking text, tool activity,
        token usage, and execution timing. sessions/manifest.json indexes every Pi execution, and
        each execution is stored once in its session directory as execution.json. API keys,
        authorization values, credentials, access tokens, and abort signals are excluded.

        files/ contains every referenced chat attachment and generated artifact. Archive creation
        fails if any referenced file cannot be read, so a successful export is never incomplete.
        """ : """
        YamabikoChat conversation export

        conversation.json contains the conversation and its variants. Runtime transcripts,
        reasoning, token metrics, and complete Pi diagnostics are excluded. files/ contains every
        referenced chat attachment and generated artifact.
        """
        try Data(readme.utf8).write(to: stagingURL.appendingPathComponent("README.txt"), options: .atomic)

        let filename = safeFilename(snapshot.conversation.title)
        let suffix = mode == .fullDiagnostics ? "-diagnostics" : ""
        let archiveURL = exportRoot.appendingPathComponent("\(filename)\(suffix)-\(identifier.prefix(8)).zip")
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

    private static func purgeExpiredArchives(in directory: URL, fileManager: FileManager) {
        guard let files = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        let cutoff = Date().addingTimeInterval(-24 * 60 * 60)
        for file in files where file.pathExtension.lowercased() == "zip" {
            guard let values = try? file.resourceValues(forKeys: [.contentModificationDateKey]),
                  let modified = values.contentModificationDate,
                  modified < cutoff else { continue }
            try? fileManager.removeItem(at: file)
        }
    }

    private static func preparedExport(
        _ snapshot: ConversationDebugExport,
        mode: ConversationExportMode
    ) -> ConversationDebugExport {
        var export = snapshot
        export.schemaVersion = 3
        export.piExecutions = []

        for messageIndex in export.messages.indices {
            export.messages[messageIndex].toolActivity?.piExecution = nil
            for variantIndex in export.messages[messageIndex].variants.indices {
                export.messages[messageIndex].variants[variantIndex].toolActivity?.piExecution = nil
            }
        }
        for dualIndex in export.dualMessages.indices {
            export.dualMessages[dualIndex].modelAToolActivity?.piExecution = nil
            export.dualMessages[dualIndex].modelBToolActivity?.piExecution = nil
        }
        for conversationIndex in export.autoConversations.indices {
            for messageIndex in export.autoConversations[conversationIndex].messages.indices {
                export.autoConversations[conversationIndex].messages[messageIndex].piExecution = nil
            }
        }

        guard mode == .standard else { return export }
        export.format = "yamabiko-chat-export"
        export.messages = export.messages.map { message in
            var value = message
            value.thinkingStream = nil
            value.toolActivity = nil
            value.variants = value.variants.map { variant in
                var variantValue = variant
                variantValue.toolActivity = nil
                return variantValue
            }
            return value
        }
        export.dualMessages = export.dualMessages.map { message in
            var value = message
            value.modelAToolActivity = nil
            value.modelBToolActivity = nil
            return value
        }
        export.fusionTraces = []
        export.tokenUsageRecords = []
        export.executionMetrics = []
        return export
    }

    private static func includeFiles(
        _ paths: [String],
        at filesURL: URL,
        fileManager: FileManager
    ) throws -> [ConversationExportFileRecord] {
        var seen = Set<String>()
        let uniquePaths = paths.filter { seen.insert($0).inserted }
        var records: [ConversationExportFileRecord] = []

        for (offset, originalPath) in uniquePaths.enumerated() {
            let sourceURL = PiAgentRuntime.attachmentFileURL(from: originalPath)
            guard fileManager.fileExists(atPath: sourceURL.path) else {
                throw ConversationExportError.referencedFileUnavailable(originalPath)
            }

            let archiveName = String(format: "%04d-%@", offset + 1, safeFilename(sourceURL.lastPathComponent))
            let destinationURL = filesURL.appendingPathComponent(archiveName)
            do {
                try fileManager.copyItem(at: sourceURL, to: destinationURL)
                let size = try destinationURL.resourceValues(forKeys: [.fileSizeKey]).fileSize
                records.append(ConversationExportFileRecord(
                    originalPath: originalPath,
                    archivePath: "files/\(archiveName)",
                    status: .included,
                    size: size.map(Int64.init),
                    error: nil
                ))
            } catch {
                DiagnosticsLogger.log(
                    "Conversation export could not include file",
                    level: .warning,
                    category: .chat,
                    metadata: ["path": originalPath],
                    error: error
                )
                throw ConversationExportError.referencedFileUnavailable(originalPath)
            }
        }
        return records
    }

    private struct PiSessionManifestRecord: Codable {
        var source: String
        var sourceId: String
        var archivePath: String
        var eventCount: Int
    }

    private static func writePiSessions(
        _ executions: [ConversationPiExecutionExport],
        at stagingURL: URL,
        encoder: JSONEncoder,
        fileManager: FileManager
    ) throws {
        let sessionsURL = stagingURL.appendingPathComponent("sessions", isDirectory: true)
        try fileManager.createDirectory(at: sessionsURL, withIntermediateDirectories: true)
        var manifest: [PiSessionManifestRecord] = []

        for (offset, record) in executions.enumerated() {
            let directoryName = String(
                format: "%04d-%@-%@",
                offset + 1,
                safeFilename(record.source),
                safeFilename(record.sourceId)
            )
            let directoryURL = sessionsURL.appendingPathComponent(directoryName, isDirectory: true)
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            try encoder.encode(record.execution).write(
                to: directoryURL.appendingPathComponent("execution.json"),
                options: .atomic
            )

            let events = executionEvents(record.execution)
            manifest.append(
                PiSessionManifestRecord(
                    source: record.source,
                    sourceId: record.sourceId,
                    archivePath: "sessions/\(directoryName)/execution.json",
                    eventCount: events.count
                )
            )
        }

        try encoder.encode(manifest).write(
            to: sessionsURL.appendingPathComponent("manifest.json"),
            options: .atomic
        )
    }

    private static func executionEvents(_ execution: JSONValue) -> [JSONValue] {
        guard case let .object(root) = execution,
              case let .array(events)? = root["events"]
        else { return [] }
        return events
    }

    private static func safeFilename(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        let sanitized = value.unicodeScalars.map { allowed.contains($0) ? Character(String($0)) : "_" }
        let result = String(sanitized).trimmingCharacters(in: CharacterSet(charactersIn: "._"))
        return result.isEmpty ? "YamabikoChat" : String(result.prefix(80))
    }
}

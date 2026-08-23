import XCTest
import GRDB
import ZIPFoundation
@testable import YamabikoChat

final class ConversationExportTests: XCTestCase {
    func testDebugExportIncludesPiHistoryToolTranscriptMetricsAndFiles() throws {
        let dbQueue = try DatabaseQueue()
        try AppDatabase.migrator.migrate(dbQueue)
        let repository = ConversationRepository(dbQueue: dbQueue)
        let conversationID = try repository.createConversation(
            title: "Debug / Chat",
            model: "test-model",
            provider: "TEST",
            systemPrompt: "system instructions"
        )

        let sourceDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: sourceDirectory) }
        let attachmentURL = sourceDirectory.appendingPathComponent("input.txt")
        try Data("attachment body".utf8).write(to: attachmentURL)
        let toolOutputURL = sourceDirectory.appendingPathComponent("chart.svg")
        try Data("<svg>chart</svg>".utf8).write(to: toolOutputURL)
        let attachmentJSON = String(
            decoding: try JSONEncoder().encode([attachmentURL.path]),
            as: UTF8.self
        )

        _ = try repository.insertMessage(
            ChatMessage(
                conversationId: conversationID,
                role: "user",
                text: "question",
                attachmentsJSON: attachmentJSON,
                createdAtMs: 1
            )
        )
        let assistantID = try repository.insertMessage(
            ChatMessage(conversationId: conversationID, role: "model", text: "answer", createdAtMs: 2)
        )
        try repository.saveThinking(messageId: assistantID, stream: "reasoning")

        let call = ToolCall(id: "call-1", name: PythonExecuteTool.name, argumentsJSON: #"{"code":"print(42)"}"#)
        let execution: JSONValue = .object([
            "format": .string("yamabiko.pi-agent-execution"),
            "state": .object([
                "messages": .array([
                    .object(["role": .string("user"), "content": .string("question")]),
                    .object(["role": .string("assistant"), "content": .string("answer")])
                ])
            ]),
            "providerRequests": .array([
                .object(["step": .number(1), "payload": .object(["model": .string("test-model")])])
            ]),
            "events": .array([
                .object([
                    "seq": .number(0),
                    "time": .number(11),
                    "event": .object(["type": .string("turn_start")])
                ]),
                .object([
                    "seq": .number(1),
                    "time": .number(19),
                    "event": .object(["type": .string("turn_end")])
                ])
            ])
        ])
        try repository.saveToolActivity(
            messageId: assistantID,
            variantId: nil,
            payload: ToolActivityPayload(
                steps: [],
                providerTranscript: [
                    ProviderRequestMessage(role: "assistant", content: "", toolCalls: [call]),
                    ProviderRequestMessage(
                        role: "tool",
                        content: #"{"stdout":"42"}"#,
                        toolCallId: call.id,
                        toolName: call.name,
                        toolResultIsError: false
                    )
                ],
                attachmentPaths: [toolOutputURL.path],
                piExecution: execution
            )
        )
        try repository.appendAttachments(messageId: assistantID, paths: [toolOutputURL.path])
        try repository.insertTokenUsage(
            TokenUsageRecord(
                provider: "TEST",
                model: "test-model",
                conversationId: conversationID,
                inputTokens: 10,
                outputTokens: 4,
                totalTokens: 14
            )
        )
        try repository.insertExecutionMetric(
            ConversationExecutionMetric(
                conversationId: conversationID,
                turnId: "turn-1",
                kind: .llm,
                startedAtMs: 10,
                firstTokenAtMs: 12,
                completedAtMs: 20,
                succeeded: true,
                inputTokens: 10,
                outputTokens: 4,
                cachedInputTokens: 0,
                cacheCreationInputTokens: 0
            )
        )

        let snapshot = try repository.fetchDebugExport(conversationId: conversationID)
        XCTAssertEqual(snapshot.messages.count, 2)
        XCTAssertEqual(snapshot.messages[1].thinkingStream, "reasoning")
        XCTAssertEqual(snapshot.messages[1].toolActivity?.providerTranscript.count, 2)
        XCTAssertEqual(snapshot.messages[1].toolActivity?.attachmentPaths, [toolOutputURL.path])
        XCTAssertEqual(snapshot.messages[1].toolActivity?.piExecution, execution)
        XCTAssertEqual(snapshot.tokenUsageRecords.first?.totalTokens, 14)
        XCTAssertEqual(snapshot.executionMetrics.first?.turnId, "turn-1")

        let archiveURL = try ConversationExportService.createArchive(snapshot: snapshot)
        defer { try? FileManager.default.removeItem(at: archiveURL) }
        XCTAssertEqual(archiveURL.pathExtension, "zip")

        let extractedURL = sourceDirectory.appendingPathComponent("extracted", isDirectory: true)
        try FileManager.default.unzipItem(at: archiveURL, to: extractedURL)
        let data = try Data(contentsOf: extractedURL.appendingPathComponent("conversation.json"))
        let decoded = try JSONDecoder().decode(ConversationDebugExport.self, from: data)
        XCTAssertEqual(decoded.messages[1].toolActivity?.piExecution, execution)
        XCTAssertEqual(decoded.piExecutions.count, 1)
        XCTAssertEqual(decoded.piExecutions.first?.source, "message")
        XCTAssertEqual(decoded.files.count, 2)
        XCTAssertTrue(decoded.files.allSatisfy { $0.status == .included })
        let attachmentRecord = try XCTUnwrap(
            decoded.files.first { $0.originalPath == attachmentURL.path }
        )
        let archivedPath = try XCTUnwrap(attachmentRecord.archivePath)
        XCTAssertEqual(
            try String(contentsOf: extractedURL.appendingPathComponent(archivedPath), encoding: .utf8),
            "attachment body"
        )
        let toolOutputRecord = try XCTUnwrap(
            decoded.files.first { $0.originalPath == toolOutputURL.path }
        )
        let toolOutputArchivePath = try XCTUnwrap(toolOutputRecord.archivePath)
        XCTAssertEqual(
            try String(contentsOf: extractedURL.appendingPathComponent(toolOutputArchivePath), encoding: .utf8),
            "<svg>chart</svg>"
        )
        let manifestData = try Data(
            contentsOf: extractedURL.appendingPathComponent("sessions/manifest.json")
        )
        let manifest = try JSONSerialization.jsonObject(with: manifestData) as? [[String: Any]]
        XCTAssertEqual(manifest?.count, 1)
        XCTAssertEqual(manifest?.first?["eventCount"] as? Int, 2)
        let sessionPath = try XCTUnwrap(manifest?.first?["archivePath"] as? String)
        let sessionLog = try String(
            contentsOf: extractedURL.appendingPathComponent(sessionPath),
            encoding: .utf8
        )
        XCTAssertEqual(sessionLog.split(separator: "\n").count, 3)
        XCTAssertTrue(sessionLog.contains(#""format":"yamabiko.pi-agent-session""#))
        XCTAssertTrue(sessionLog.contains(#""type":"turn_start""#))
    }

    func testExportFailsWhenAReferencedFileIsMissing() throws {
        let dbQueue = try DatabaseQueue()
        try AppDatabase.migrator.migrate(dbQueue)
        let repository = ConversationRepository(dbQueue: dbQueue)
        let conversationID = try repository.createConversation(
            title: "Missing attachment",
            model: "test-model",
            provider: "TEST",
            systemPrompt: ""
        )
        let missingPath = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .path
        let attachmentsJSON = String(
            decoding: try JSONEncoder().encode([missingPath]),
            as: UTF8.self
        )
        _ = try repository.insertMessage(
            ChatMessage(
                conversationId: conversationID,
                role: "user",
                text: "question",
                attachmentsJSON: attachmentsJSON
            )
        )

        let snapshot = try repository.fetchDebugExport(conversationId: conversationID)
        XCTAssertThrowsError(try ConversationExportService.createArchive(snapshot: snapshot)) { error in
            guard case let ConversationExportError.referencedFileUnavailable(path) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(path, missingPath)
        }
    }

    func testMigrationAddsPiExecutionAndToolAttachmentColumns() throws {
        let dbQueue = try DatabaseQueue()
        try AppDatabase.migrator.migrate(dbQueue)

        try dbQueue.read { db in
            let toolColumns = try String.fetchAll(
                db,
                sql: "SELECT name FROM pragma_table_info('chat_message_tool_activity')"
            )
            let autoColumns = try String.fetchAll(
                db,
                sql: "SELECT name FROM pragma_table_info('auto_conversation_messages')"
            )
            XCTAssertTrue(toolColumns.contains("piExecutionJSON"))
            XCTAssertTrue(toolColumns.contains("attachmentPathsJSON"))
            XCTAssertTrue(autoColumns.contains("piExecutionJSON"))
        }
    }
}

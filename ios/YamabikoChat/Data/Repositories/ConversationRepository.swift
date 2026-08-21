import Foundation
import Combine
import GRDB

// DatabaseQueue serializes database access and is safe to share across tasks.
final class ConversationRepository: @unchecked Sendable {
    private let dbQueue: DatabaseQueue

    init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    func createConversation(
        title: String,
        model: String,
        provider: String,
        systemPrompt: String? = nil,
        isSecret: Bool = false,
        projectId: Int64? = nil
    ) throws -> Int64 {
        try dbQueue.write { db in
            var conversation = Conversation(
                title: title,
                systemPrompt: systemPrompt,
                model: model,
                apiProvider: provider,
                isSecret: isSecret,
                projectId: projectId
            )
            try conversation.insert(db)
            return conversation.id ?? 0
        }
    }

    func createProject(
        title: String,
        instructions: String?,
        iconName: String = "folder.fill",
        colorHex: String = "#3A7AFE"
    ) throws -> Int64 {
        try dbQueue.write { db in
            var project = ChatProject(
                title: title,
                iconName: iconName,
                colorHex: colorHex,
                instructions: instructions?.trimmedNonEmpty
            )
            try project.insert(db)
            return project.id ?? 0
        }
    }

    func fetchProject(id: Int64) throws -> ChatProject? {
        try dbQueue.read { db in
            try ChatProject.fetchOne(db, key: id)
        }
    }

    func observeProjects() -> AnyPublisher<[ProjectListEntry], Never> {
        ValueObservation.tracking { db -> [ProjectListEntry] in
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT id, title, iconName, colorHex, instructions, updatedAtMs
                FROM projects
                ORDER BY updatedAtMs DESC, createdAtMs DESC
                """
            )
            return rows.compactMap { row in
                guard let id: Int64 = row["id"] else { return nil }
                return ProjectListEntry(
                    id: id,
                    title: row["title"] ?? "Project",
                    iconName: row["iconName"] ?? "folder.fill",
                    colorHex: row["colorHex"] ?? "#3A7AFE",
                    instructions: row["instructions"],
                    updatedAtMs: row["updatedAtMs"] ?? 0
                )
            }
        }
        .publisher(in: dbQueue)
        .replaceError(with: [])
        .eraseToAnyPublisher()
    }

    func countConversations(projectId: Int64) throws -> Int {
        try dbQueue.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM conversations WHERE projectId = ?",
                arguments: [projectId]
            ) ?? 0
        }
    }

    func conversationIDs(projectId: Int64) throws -> [Int64] {
        try dbQueue.read { db in
            try Int64.fetchAll(
                db,
                sql: "SELECT id FROM conversations WHERE projectId = ?",
                arguments: [projectId]
            )
        }
    }

    func deleteProject(id: Int64) throws {
        try dbQueue.write { db in
            let deleted = try ChatProject.deleteOne(db, key: id)
            guard deleted else {
                throw ProviderClientError.parseFailure("Project not found")
            }
        }
    }

    func deleteProjectWithConversations(id: Int64) throws {
        try dbQueue.write { db in
            let project = try ChatProject.fetchOne(db, key: id)
            guard project != nil else {
                throw ProviderClientError.parseFailure("Project not found")
            }

            try db.execute(
                sql: """
                DELETE FROM token_usage_records
                WHERE conversationId IN (SELECT id FROM conversations WHERE projectId = ?)
                """,
                arguments: [id]
            )
            try db.execute(
                sql: "DELETE FROM conversations WHERE projectId = ?",
                arguments: [id]
            )
            _ = try ChatProject.deleteOne(db, key: id)
        }
    }

    func upsertConversation(_ conversation: Conversation) throws -> Int64 {
        try dbQueue.write { db in
            var updated = conversation
            updated.updatedAtMs = Int64(Date().timeIntervalSince1970 * 1000)
            try updated.save(db)
            return updated.id ?? 0
        }
    }

    func deleteConversation(id: Int64) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "DELETE FROM token_usage_records WHERE conversationId = ?",
                arguments: [id]
            )
            try deleteAutoConversationsBoundToConversations(db, idsSQL: "?", arguments: StatementArguments([id]))
            _ = try Conversation.deleteOne(db, key: id)
        }
    }

    func deleteConversations(ids: Set<Int64>) throws {
        guard !ids.isEmpty else { return }
        try dbQueue.write { db in
            let idArray = Array(ids)
            try TokenUsageRecord
                .filter(idArray.contains(Column("conversationId")))
                .deleteAll(db)
            try deleteAutoConversationsBoundToConversations(
                db,
                idsSQL: idArray.map { _ in "?" }.joined(separator: ","),
                arguments: StatementArguments(idArray)
            )
            try Conversation
                .filter(idArray.contains(Column("id")))
                .deleteAll(db)
        }
    }

    func deleteSecretConversationIfNeeded(id: Int64) throws -> Bool {
        try dbQueue.write { db in
            guard let isSecret = try Bool.fetchOne(
                db,
                sql: "SELECT isSecret FROM conversations WHERE id = ?",
                arguments: [id]
            ), isSecret else {
                return false
            }

            try db.execute(
                sql: "DELETE FROM token_usage_records WHERE conversationId = ?",
                arguments: [id]
            )
            try deleteAutoConversationsBoundToConversations(db, idsSQL: "?", arguments: StatementArguments([id]))
            _ = try Conversation.deleteOne(db, key: id)
            return true
        }
    }

    func purgeSecretConversations() throws {
        try dbQueue.write { db in
            try db.execute(
                sql: """
                DELETE FROM token_usage_records
                WHERE conversationId IN (SELECT id FROM conversations WHERE isSecret = 1)
                """
            )
            try db.execute(
                sql: """
                DELETE FROM auto_conversation_messages
                WHERE autoConversationId IN (
                    SELECT id FROM auto_conversations
                    WHERE boundChatConversationId IN (SELECT id FROM conversations WHERE isSecret = 1)
                       OR boundConversationId IN (SELECT id FROM conversations WHERE isSecret = 1)
                )
                """
            )
            try db.execute(
                sql: """
                DELETE FROM auto_conversations
                WHERE boundChatConversationId IN (SELECT id FROM conversations WHERE isSecret = 1)
                   OR boundConversationId IN (SELECT id FROM conversations WHERE isSecret = 1)
                """
            )
            try Conversation
                .filter(Column("isSecret") == true)
                .deleteAll(db)
        }
    }

    func fetchConversation(id: Int64) throws -> Conversation? {
        try dbQueue.read { db in
            try Conversation.fetchOne(db, key: id)
        }
    }

    func getOrCreateCodexSessionId(conversationId: Int64) throws -> String {
        try dbQueue.write { db in
            guard var conversation = try Conversation.fetchOne(db, key: conversationId) else {
                throw ProviderClientError.parseFailure("Conversation not found")
            }
            let existing = conversation.codexSessionId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !existing.isEmpty { return existing }

            let created = UUID().uuidString
            conversation.codexSessionId = created
            try conversation.update(db)
            return created
        }
    }

    func fetchLatestEmptyConversation(title: String, projectId: Int64? = nil) throws -> Conversation? {
        try dbQueue.read { db in
            try Conversation
                .filter(Column("title") == title)
                .order(Column("updatedAtMs").desc)
                .fetchAll(db)
                .first { conversation in
                    guard conversation.projectId == projectId else { return false }
                    let chatCount = try? Int.fetchOne(
                        db,
                        sql: "SELECT COUNT(*) FROM chat_messages WHERE conversationId = ?",
                        arguments: [conversation.id ?? 0]
                    )
                    if (chatCount ?? 0) > 0 {
                        return false
                    }
                    let dualCount = try? Int.fetchOne(
                        db,
                        sql: "SELECT COUNT(*) FROM dual_chat_messages WHERE conversationId = ?",
                        arguments: [conversation.id ?? 0]
                    )
                    return (dualCount ?? 0) == 0
                }
        }
    }

    func observeConversationList() -> AnyPublisher<[ConversationListEntry], Never> {
        ValueObservation.tracking { db -> [ConversationListEntry] in
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT c.id, c.title, c.updatedAtMs, c.isSecret, c.projectId, p.title AS projectTitle,
                       (
                           SELECT merged.preview
                           FROM (
                               SELECT
                                   m.createdAtMs AS ts,
                                   CASE
                                       WHEN m.role = 'model' AND m.selectedVariantIndex > 0 THEN COALESCE(
                                           (SELECT v.text
                                            FROM chat_message_variants v
                                            WHERE v.baseMessageId = m.id AND v.variantIndex = m.selectedVariantIndex
                                            LIMIT 1),
                                           m.text
                                       )
                                       ELSE m.text
                                   END AS preview
                               FROM chat_messages m
                               WHERE m.conversationId = c.id

                               UNION ALL

                               SELECT
                                   d.createdAtMs AS ts,
                                   CASE
                                       WHEN d.role = 'dual_model' AND LENGTH(TRIM(d.modelAText)) > 0 THEN d.modelAText
                                       WHEN d.role = 'dual_model' AND LENGTH(TRIM(d.modelBText)) > 0 THEN d.modelBText
                                       WHEN d.role = 'user' AND LENGTH(TRIM(d.userText)) > 0 THEN d.userText
                                       WHEN LENGTH(TRIM(d.modelAText)) > 0 THEN d.modelAText
                                       WHEN LENGTH(TRIM(d.modelBText)) > 0 THEN d.modelBText
                                       ELSE d.userText
                                   END AS preview
                               FROM dual_chat_messages d
                               WHERE d.conversationId = c.id
                           ) AS merged
                           ORDER BY merged.ts DESC
                           LIMIT 1
                       ) AS lastMessagePreview
                FROM conversations c
                LEFT JOIN projects p ON p.id = c.projectId
                WHERE EXISTS (
                    SELECT 1
                    FROM chat_messages m
                    WHERE m.conversationId = c.id
                )
                OR EXISTS (
                    SELECT 1
                    FROM dual_chat_messages d
                    WHERE d.conversationId = c.id
                )
                ORDER BY c.updatedAtMs DESC
                """
            )

            return rows.compactMap { row in
                guard let id: Int64 = row["id"] else { return nil }
                return ConversationListEntry(
                    id: id,
                    title: row["title"] ?? "New Chat",
                    updatedAtMs: row["updatedAtMs"] ?? 0,
                    lastMessagePreview: row["lastMessagePreview"],
                    isSecret: row["isSecret"] ?? false,
                    projectId: row["projectId"],
                    projectTitle: row["projectTitle"]
                )
            }
        }
        .publisher(in: dbQueue)
        .replaceError(with: [])
        .eraseToAnyPublisher()
    }

    func observeMessages(conversationId: Int64) -> AnyPublisher<[ChatMessageSummary], Never> {
        ValueObservation.tracking { db -> [ChatMessageSummary] in
            try self.fetchMessageSummaries(db: db, conversationId: conversationId)
        }
        .publisher(in: dbQueue)
        .replaceError(with: [])
        .eraseToAnyPublisher()
    }

    func observeFullMessages(conversationId: Int64) -> AnyPublisher<[FullChatMessage], Never> {
        ValueObservation.tracking { db -> [FullChatMessage] in
            let messages = try ChatMessage
                .filter(Column("conversationId") == conversationId)
                .order(Column("createdAtMs").asc)
                .fetchAll(db)

            let messageIds = messages.compactMap(\.id)
            let variantsByMessageID = try self.fetchVariantsByBaseMessageIDs(db: db, messageIds: messageIds)

            let thinkingRows: [ChatMessageThinking]
            if messageIds.isEmpty {
                thinkingRows = []
            } else {
                thinkingRows = try ChatMessageThinking
                    .filter(messageIds.contains(Column("messageId")))
                    .fetchAll(db)
            }
            let thinkingByMessageID = Dictionary(uniqueKeysWithValues: thinkingRows.map { ($0.messageId, $0.thinkingStream) })
            let variantIds = variantsByMessageID.values.flatMap { $0 }.compactMap(\.id)
            let activityRows: [ChatMessageToolActivity]
            if messageIds.isEmpty {
                activityRows = []
            } else {
                activityRows = try ChatMessageToolActivity
                    .filter(messageIds.contains(Column("messageId")))
                    .filter(Column("variantId") == nil)
                    .fetchAll(db)
            }
            let variantActivityRows: [ChatMessageToolActivity]
            if variantIds.isEmpty {
                variantActivityRows = []
            } else {
                variantActivityRows = try ChatMessageToolActivity
                    .filter(variantIds.contains(Column("variantId")))
                    .fetchAll(db)
            }
            let activityByMessageID = Dictionary(
                uniqueKeysWithValues: activityRows.compactMap { activity in
                    activity.messageId.map { ($0, activity) }
                }
            )
            let activityByVariantID = Dictionary(
                uniqueKeysWithValues: variantActivityRows.compactMap { activity in
                    activity.variantId.map { ($0, activity) }
                }
            )

            return messages.compactMap { message in
                guard let id = message.id else { return nil }
                let variants = variantsByMessageID[id] ?? []
                let variantActivities = Dictionary(
                    uniqueKeysWithValues: variants.compactMap { variant in
                        variant.id.flatMap { variantId in
                            activityByVariantID[variantId].map { (variantId, $0) }
                        }
                    }
                )
                return FullChatMessage(
                    id: id,
                    message: message,
                    thinkingStream: thinkingByMessageID[id],
                    variants: variants,
                    toolActivity: activityByMessageID[id],
                    variantToolActivities: variantActivities
                )
            }
        }
        .publisher(in: dbQueue)
        .replaceError(with: [])
        .eraseToAnyPublisher()
    }

    func fetchMessageSummaries(conversationId: Int64) throws -> [ChatMessageSummary] {
        try dbQueue.read { db in
            try fetchMessageSummaries(db: db, conversationId: conversationId)
        }
    }

    func isConversationEmpty(conversationId: Int64) throws -> Bool {
        try dbQueue.read { db in
            let chatCount = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM chat_messages WHERE conversationId = ?",
                arguments: [conversationId]
            ) ?? 0
            if chatCount > 0 { return false }

            let dualCount = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM dual_chat_messages WHERE conversationId = ?",
                arguments: [conversationId]
            ) ?? 0
            return dualCount == 0
        }
    }

    func fetchMessages(conversationId: Int64) throws -> [ChatMessage] {
        try dbQueue.read { db in
            try ChatMessage
                .filter(Column("conversationId") == conversationId)
                .order(Column("createdAtMs").asc)
                .fetchAll(db)
        }
    }

    func fetchMessage(id: Int64) throws -> ChatMessage? {
        try dbQueue.read { db in
            try ChatMessage.fetchOne(db, key: id)
        }
    }

    func fetchLastAssistantMessage(conversationId: Int64) throws -> ChatMessage? {
        try dbQueue.read { db in
            try ChatMessage
                .filter(Column("conversationId") == conversationId)
                .filter(Column("role") == "model")
                .order(Column("createdAtMs").desc)
                .fetchOne(db)
        }
    }

    func fetchFullMessage(id: Int64) throws -> FullChatMessage? {
        try dbQueue.read { db in
            guard let message = try ChatMessage.fetchOne(db, key: id), let messageId = message.id else { return nil }
            let thinking = try ChatMessageThinking
                .filter(Column("messageId") == messageId)
                .fetchOne(db)?.thinkingStream
            let variants = try ChatMessageVariant
                .filter(Column("baseMessageId") == messageId)
                .order(Column("variantIndex").asc)
                .fetchAll(db)
            let activity = try ChatMessageToolActivity
                .filter(Column("messageId") == messageId)
                .filter(Column("variantId") == nil)
                .fetchOne(db)
            let variantIds = variants.compactMap(\.id)
            let variantActivityRows: [ChatMessageToolActivity]
            if variantIds.isEmpty {
                variantActivityRows = []
            } else {
                variantActivityRows = try ChatMessageToolActivity
                    .filter(variantIds.contains(Column("variantId")))
                    .fetchAll(db)
            }
            let activityByVariantID = Dictionary(
                uniqueKeysWithValues: variantActivityRows.compactMap { activity in
                    activity.variantId.map { ($0, activity) }
                }
            )
            return FullChatMessage(
                id: messageId,
                message: message,
                thinkingStream: thinking,
                variants: variants,
                toolActivity: activity,
                variantToolActivities: activityByVariantID
            )
        }
    }

    func insertMessage(_ message: ChatMessage) throws -> Int64 {
        try dbQueue.write { db in
            var mutable = message
            try mutable.insert(db)

            let now = Int64(Date().timeIntervalSince1970 * 1000)
            try db.execute(
                sql: "UPDATE conversations SET updatedAtMs = ? WHERE id = ?",
                arguments: [now, mutable.conversationId]
            )

            return mutable.id ?? 0
        }
    }

    func updateMessage(_ message: ChatMessage) throws {
        try dbQueue.write { db in
            let mutable = message
            try mutable.update(db)
        }
    }

    func appendAttachments(messageId: Int64, paths: [String]) throws {
        let normalized = paths.filter { !$0.isEmpty }
        guard !normalized.isEmpty else { return }
        try dbQueue.write { db in
            guard var message = try ChatMessage.fetchOne(db, key: messageId) else { return }
            message.attachmentsJSON = mergeAttachmentJSON(message.attachmentsJSON, additions: normalized)
            try message.update(db)
        }
    }

    func appendAttachments(variantId: Int64, paths: [String]) throws {
        let normalized = paths.filter { !$0.isEmpty }
        guard !normalized.isEmpty else { return }
        try dbQueue.write { db in
            guard var variant = try ChatMessageVariant.fetchOne(db, key: variantId) else { return }
            variant.attachmentsJSON = mergeAttachmentJSON(variant.attachmentsJSON, additions: normalized)
            try variant.update(db)
        }
    }

    func updateMessageText(messageId: Int64, text: String) throws {
        try dbQueue.write { db in
            guard var mutable = try ChatMessage.fetchOne(db, key: messageId) else { return }
            mutable.text = text
            try mutable.update(db)
        }
    }

    func saveThinking(messageId: Int64, stream: String) throws {
        try dbQueue.write { db in
            if var existing = try ChatMessageThinking.filter(Column("messageId") == messageId).fetchOne(db) {
                existing.thinkingStream = stream
                try existing.update(db)
            } else {
                var thinking = ChatMessageThinking(messageId: messageId, thinkingStream: stream)
                try thinking.insert(db)
            }
        }
    }

    func insertMessageVariant(
        baseMessageId: Int64,
        text: String,
        attachmentsJSON: String = "[]",
        thinkingStream: String? = nil
    ) throws -> ChatMessageVariant {
        try dbQueue.write { db in
            guard let baseMessage = try ChatMessage.fetchOne(db, key: baseMessageId) else {
                throw ProviderClientError.parseFailure("Base message not found")
            }

            let maxIndex = try Int.fetchOne(
                db,
                sql: "SELECT MAX(variantIndex) FROM chat_message_variants WHERE baseMessageId = ?",
                arguments: [baseMessageId]
            ) ?? 0
            let nextIndex = max(1, maxIndex + 1)

            var variant = ChatMessageVariant(
                baseMessageId: baseMessageId,
                variantIndex: nextIndex,
                text: text,
                attachmentsJSON: attachmentsJSON,
                thinkingStream: thinkingStream
            )
            try variant.insert(db)

            try db.execute(
                sql: "UPDATE chat_messages SET selectedVariantIndex = ? WHERE id = ?",
                arguments: [nextIndex, baseMessageId]
            )
            try touchConversation(db: db, conversationId: baseMessage.conversationId)

            return variant
        }
    }

    func updateMessageSelectedVariantIndex(messageId: Int64, variantIndex: Int) throws {
        try dbQueue.write { db in
            guard (try ChatMessage.fetchOne(db, key: messageId)) != nil else { return }
            try db.execute(
                sql: "UPDATE chat_messages SET selectedVariantIndex = ? WHERE id = ?",
                arguments: [max(0, variantIndex), messageId]
            )
        }
    }

    func updateMessageVariantText(variantId: Int64, text: String) throws {
        try dbQueue.write { db in
            guard var variant = try ChatMessageVariant.fetchOne(db, key: variantId) else { return }
            variant.text = text
            try variant.update(db)
        }
    }

    func saveMessageVariantThinking(variantId: Int64, stream: String) throws {
        try dbQueue.write { db in
            guard var variant = try ChatMessageVariant.fetchOne(db, key: variantId) else { return }
            variant.thinkingStream = stream
            try variant.update(db)
        }
    }

    func saveToolActivity(
        messageId: Int64?,
        variantId: Int64?,
        payload: ToolActivityPayload
    ) throws {
        let stepsData = try JSONEncoder().encode(payload.steps)
        let transcriptData = try JSONEncoder().encode(payload.providerTranscript)
        let piExecutionData = try payload.piExecution.map { try JSONEncoder().encode($0) }
        var activity = ChatMessageToolActivity(
            messageId: messageId,
            variantId: variantId,
            stepsJSON: String(decoding: stepsData, as: UTF8.self),
            providerTranscriptJSON: String(decoding: transcriptData, as: UTF8.self),
            piExecutionJSON: piExecutionData.map { String(decoding: $0, as: UTF8.self) }
        )
        try dbQueue.write { db in
            if let messageId {
                try ChatMessageToolActivity.filter(Column("messageId") == messageId).deleteAll(db)
            } else if let variantId {
                try ChatMessageToolActivity.filter(Column("variantId") == variantId).deleteAll(db)
            }
            try activity.insert(db)
        }
    }

    func fetchDebugExport(conversationId: Int64) throws -> ConversationDebugExport {
        try dbQueue.read { db in
            guard let conversation = try Conversation.fetchOne(db, key: conversationId) else {
                throw ConversationExportError.conversationNotFound
            }

            let messages = try ChatMessage
                .filter(Column("conversationId") == conversationId)
                .order(Column("createdAtMs").asc, Column("id").asc)
                .fetchAll(db)
            let messageIDs = messages.compactMap(\.id)
            let variants = messageIDs.isEmpty ? [] : try ChatMessageVariant
                .filter(messageIDs.contains(Column("baseMessageId")))
                .order(Column("baseMessageId").asc, Column("variantIndex").asc)
                .fetchAll(db)
            let variantsByMessage = Dictionary(grouping: variants, by: \.baseMessageId)
            let variantIDs = variants.compactMap(\.id)

            let thinkingRows = messageIDs.isEmpty ? [] : try ChatMessageThinking
                .filter(messageIDs.contains(Column("messageId")))
                .fetchAll(db)
            let thinkingByMessage = Dictionary(uniqueKeysWithValues: thinkingRows.map { ($0.messageId, $0.thinkingStream) })

            let activityRows: [ChatMessageToolActivity]
            if messageIDs.isEmpty, variantIDs.isEmpty {
                activityRows = []
            } else if variantIDs.isEmpty {
                activityRows = try ChatMessageToolActivity
                    .filter(messageIDs.contains(Column("messageId")))
                    .fetchAll(db)
            } else if messageIDs.isEmpty {
                activityRows = try ChatMessageToolActivity
                    .filter(variantIDs.contains(Column("variantId")))
                    .fetchAll(db)
            } else {
                activityRows = try ChatMessageToolActivity
                    .filter(
                        messageIDs.contains(Column("messageId"))
                            || variantIDs.contains(Column("variantId"))
                    )
                    .fetchAll(db)
            }
            let activityByMessage = Dictionary(
                uniqueKeysWithValues: activityRows.compactMap { row in row.messageId.map { ($0, row.payload) } }
            )
            let activityByVariant = Dictionary(
                uniqueKeysWithValues: activityRows.compactMap { row in row.variantId.map { ($0, row.payload) } }
            )

            let messageExports = messages.map { message in
                let messageVariants = (message.id.flatMap { variantsByMessage[$0] } ?? []).map { variant in
                    ConversationVariantDebugExport(
                        variant: variant,
                        attachments: decodeArray(variant.attachmentsJSON),
                        toolActivity: variant.id.flatMap { activityByVariant[$0] }
                    )
                }
                return ConversationMessageDebugExport(
                    message: message,
                    thinkingStream: message.id.flatMap { thinkingByMessage[$0] },
                    attachments: decodeArray(message.attachmentsJSON),
                    toolActivity: message.id.flatMap { activityByMessage[$0] },
                    variants: messageVariants
                )
            }

            let dualRows = try DualChatMessage
                .filter(Column("conversationId") == conversationId)
                .order(Column("createdAtMs").asc, Column("id").asc)
                .fetchAll(db)
            let dualExports = dualRows.map {
                DualMessageDebugExport(
                    message: $0,
                    attachments: $0.attachments,
                    modelAToolActivity: $0.modelAToolActivity,
                    modelBToolActivity: $0.modelBToolActivity
                )
            }

            let autoRows = try AutoConversation
                .filter(Column("boundChatConversationId") == conversationId)
                .order(Column("createdAtMs").asc, Column("id").asc)
                .fetchAll(db)
            let autoIDs = autoRows.compactMap(\.id)
            let autoMessages = autoIDs.isEmpty ? [] : try AutoConversationMessage
                .filter(autoIDs.contains(Column("autoConversationId")))
                .order(Column("autoConversationId").asc, Column("turnIndex").asc, Column("id").asc)
                .fetchAll(db)
            let autoMessagesByConversation = Dictionary(grouping: autoMessages, by: \.autoConversationId)
            let autoExports = autoRows.map { autoConversation in
                AutoConversationDebugExport(
                    conversation: autoConversation,
                    messages: (autoConversation.id.flatMap { autoMessagesByConversation[$0] } ?? []).map {
                        AutoConversationMessageDebugExport(message: $0, piExecution: $0.piExecution)
                    }
                )
            }

            let fusionTraces = try FusionTraceRecord
                .filter(Column("conversationId") == conversationId)
                .order(Column("startedAtMs").asc)
                .fetchAll(db)
            let tokenUsage = try TokenUsageRecord
                .filter(Column("conversationId") == conversationId)
                .order(Column("timestamp").asc, Column("id").asc)
                .fetchAll(db)
            let metrics = try ConversationExecutionMetric
                .filter(Column("conversationId") == conversationId)
                .order(Column("startedAtMs").asc, Column("id").asc)
                .fetchAll(db)

            func requiredExportId(_ id: Int64?, source: String) throws -> String {
                guard let id else {
                    throw ConversationExportError.invalidStoredRecord("\(source).id")
                }
                return String(id)
            }

            var piExecutions: [ConversationPiExecutionExport] = []
            for message in messageExports {
                if let execution = message.toolActivity?.piExecution {
                    piExecutions.append(
                        ConversationPiExecutionExport(
                            source: "message",
                            sourceId: try requiredExportId(message.message.id, source: "message"),
                            execution: execution
                        )
                    )
                }
                for variant in message.variants {
                    if let execution = variant.toolActivity?.piExecution {
                        piExecutions.append(
                            ConversationPiExecutionExport(
                                source: "message-variant",
                                sourceId: try requiredExportId(variant.variant.id, source: "message-variant"),
                                execution: execution
                            )
                        )
                    }
                }
            }
            for dual in dualExports {
                if let execution = dual.modelAToolActivity?.piExecution {
                    piExecutions.append(
                        ConversationPiExecutionExport(
                            source: "dual-model-a",
                            sourceId: try requiredExportId(dual.message.id, source: "dual-message"),
                            execution: execution
                        )
                    )
                }
                if let execution = dual.modelBToolActivity?.piExecution {
                    piExecutions.append(
                        ConversationPiExecutionExport(
                            source: "dual-model-b",
                            sourceId: try requiredExportId(dual.message.id, source: "dual-message"),
                            execution: execution
                        )
                    )
                }
            }
            for auto in autoExports {
                for message in auto.messages {
                    if let execution = message.piExecution {
                        piExecutions.append(
                            ConversationPiExecutionExport(
                                source: "auto-conversation",
                                sourceId: try requiredExportId(message.message.id, source: "auto-conversation-message"),
                                execution: execution
                            )
                        )
                    }
                }
            }
            for record in fusionTraces {
                let trace = try record.fusionTrace()
                for (index, panel) in trace.panelResults.enumerated() {
                    if let execution = panel.piExecution {
                        piExecutions.append(
                            ConversationPiExecutionExport(
                                source: "fusion-panel",
                                sourceId: "\(record.id)-\(index)-\(panel.modelId)",
                                execution: execution
                            )
                        )
                    }
                }
                for (index, execution) in (trace.judgeResult?.piExecutions ?? []).enumerated() {
                    piExecutions.append(
                        ConversationPiExecutionExport(
                            source: "fusion-judge",
                            sourceId: "\(record.id)-\(index)",
                            execution: execution
                        )
                    )
                }
                if let execution = trace.synthesisResult?.piExecution {
                    piExecutions.append(
                        ConversationPiExecutionExport(
                            source: "fusion-synthesis",
                            sourceId: record.id,
                            execution: execution
                        )
                    )
                }
            }

            return ConversationDebugExport(
                exportedAtMs: Int64(Date().timeIntervalSince1970 * 1_000),
                application: ConversationDebugExport.ApplicationInfo(
                    name: Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "YamabikoChat",
                    version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
                    build: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
                    platform: "iOS"
                ),
                securityNotice: "API keys, authorization values, credentials, access tokens, and abort signals are excluded. All conversation content and available Pi execution history are included.",
                conversation: conversation,
                messages: messageExports,
                dualMessages: dualExports,
                autoConversations: autoExports,
                fusionTraces: fusionTraces,
                tokenUsageRecords: tokenUsage,
                executionMetrics: metrics,
                piExecutions: piExecutions,
                files: []
            )
        }
    }

    func fetchProviderHistory(conversationId: Int64) throws -> [ProviderHistoryMessage] {
        try dbQueue.read { db in
            let messages = try ChatMessage
                .filter(Column("conversationId") == conversationId)
                .order(Column("createdAtMs").asc)
                .fetchAll(db)
            let messageIds = messages.compactMap(\.id)
            let variantsByMessageID = try fetchVariantsByBaseMessageIDs(db: db, messageIds: messageIds)
            let thinkingRows: [ChatMessageThinking]
            if messageIds.isEmpty {
                thinkingRows = []
            } else {
                thinkingRows = try ChatMessageThinking
                    .filter(messageIds.contains(Column("messageId")))
                    .fetchAll(db)
            }
            let thinkingByMessageID = Dictionary(uniqueKeysWithValues: thinkingRows.map { ($0.messageId, $0.thinkingStream) })
            let variantIds = variantsByMessageID.values.flatMap { $0 }.compactMap(\.id)
            let activityRows = messageIds.isEmpty ? [] : try ChatMessageToolActivity
                .filter(messageIds.contains(Column("messageId")))
                .filter(Column("variantId") == nil)
                .fetchAll(db)
            let variantActivityRows = variantIds.isEmpty ? [] : try ChatMessageToolActivity
                .filter(variantIds.contains(Column("variantId")))
                .fetchAll(db)
            let activityByMessageID = Dictionary(
                uniqueKeysWithValues: activityRows.compactMap { activity in
                    activity.messageId.map { ($0, activity) }
                }
            )
            let activityByVariantID = Dictionary(
                uniqueKeysWithValues: variantActivityRows.compactMap { activity in
                    activity.variantId.map { ($0, activity) }
                }
            )

            return messages.compactMap { message in
                guard let messageId = message.id else { return nil }
                let resolved = resolveMessageContent(message: message, variantsByMessageID: variantsByMessageID)
                let selectedVariant = message.selectedVariantIndex > 0
                    ? variantsByMessageID[messageId]?.first(where: { $0.variantIndex == message.selectedVariantIndex })
                    : nil
                let activity = selectedVariant?.id.flatMap { activityByVariantID[$0] }
                    ?? activityByMessageID[messageId]
                let providerTranscript = activity?.providerTranscript
                if let activity, !activity.steps.isEmpty, providerTranscript == nil {
                    DiagnosticsLogger.log(
                        "Stored tool activity has no replayable provider transcript",
                        level: .warning,
                        category: .chat,
                        metadata: ["message": String(messageId)]
                    )
                }
                return ProviderHistoryMessage(
                    messageId: messageId,
                    role: message.role == "model" ? "assistant" : message.role,
                    text: resolved.text,
                    attachments: decodeArray(resolved.attachmentsJSON),
                    thinkingStream: resolved.thinkingStream ?? thinkingByMessageID[messageId],
                    toolTranscript: providerTranscript ?? []
                )
            }
        }
    }

    func insertDualMessage(_ message: DualChatMessage) throws -> Int64 {
        try dbQueue.write { db in
            var mutable = message
            try mutable.insert(db)
            let now = Int64(Date().timeIntervalSince1970 * 1000)
            try db.execute(
                sql: "UPDATE conversations SET updatedAtMs = ? WHERE id = ?",
                arguments: [now, mutable.conversationId]
            )
            return mutable.id ?? 0
        }
    }

    func updateDualMessage(_ message: DualChatMessage) throws {
        try dbQueue.write { db in
            let mutable = message
            try mutable.update(db)
            try touchConversation(db: db, conversationId: mutable.conversationId)
        }
    }

    func fetchDualMessages(conversationId: Int64) throws -> [DualChatMessage] {
        try dbQueue.read { db in
            try DualChatMessage
                .filter(Column("conversationId") == conversationId)
                .order(Column("createdAtMs").asc, Column("id").asc)
                .fetchAll(db)
        }
    }

    func observeDualMessages(conversationId: Int64) -> AnyPublisher<[DualChatMessage], Never> {
        ValueObservation.tracking { db in
            try DualChatMessage
                .filter(Column("conversationId") == conversationId)
                .order(Column("createdAtMs").asc, Column("id").asc)
                .fetchAll(db)
        }
        .publisher(in: dbQueue)
        .replaceError(with: [])
        .eraseToAnyPublisher()
    }

    func createAutoConversation(
        config: AutoConversationConfig,
        boundChatConversationId: Int64?
    ) throws -> Int64 {
        try dbQueue.write { db in
            let now = Int64(Date().timeIntervalSince1970 * 1000)
            var conversation = AutoConversation(
                title: config.title,
                modelA: config.modelA,
                modelB: config.modelB,
                providerA: config.providerA,
                providerB: config.providerB,
                systemPromptA: config.systemPromptA,
                systemPromptB: config.systemPromptB,
                status: .active,
                maxTurns: config.maxTurns,
                currentTurn: 0,
                createdAtMs: now,
                updatedAtMs: now,
                lastActiveAtMs: now,
                endReason: nil,
                endSignal: config.endSignal,
                boundChatConversationId: boundChatConversationId
            )
            try conversation.insert(db)
            return conversation.id ?? 0
        }
    }

    func updateAutoConversation(_ conversation: AutoConversation) throws {
        try dbQueue.write { db in
            var mutable = conversation
            let now = Int64(Date().timeIntervalSince1970 * 1000)
            mutable.updatedAtMs = now
            mutable.lastActiveAtMs = now
            try mutable.update(db)
        }
    }

    func fetchAutoConversation(id: Int64) throws -> AutoConversation? {
        try dbQueue.read { db in
            try AutoConversation.fetchOne(db, key: id)
        }
    }

    func fetchAutoConversationMessages(autoConversationId: Int64) throws -> [AutoConversationMessage] {
        try dbQueue.read { db in
            try AutoConversationMessage
                .filter(Column("autoConversationId") == autoConversationId)
                .order(Column("turnIndex").asc, Column("createdAtMs").asc, Column("id").asc)
                .fetchAll(db)
        }
    }

    func observeAutoConversationMessages(autoConversationId: Int64) -> AnyPublisher<[AutoConversationMessage], Never> {
        ValueObservation.tracking { db in
            try AutoConversationMessage
                .filter(Column("autoConversationId") == autoConversationId)
                .order(Column("turnIndex").asc, Column("createdAtMs").asc, Column("id").asc)
                .fetchAll(db)
        }
        .publisher(in: dbQueue)
        .replaceError(with: [])
        .eraseToAnyPublisher()
    }

    func insertTokenUsage(_ record: TokenUsageRecord) throws {
        try dbQueue.write { db in
            var mutable = record
            try mutable.insert(db)
        }
    }

    func insertExecutionMetric(_ metric: ConversationExecutionMetric) throws {
        try dbQueue.write { db in
            var mutable = metric
            try mutable.insert(db)
        }
    }

    func observeConversationStats(conversationId: Int64) -> AnyPublisher<ConversationStats, Never> {
        ValueObservation.tracking { db -> ConversationStats in
            let row = try Row.fetchOne(
                db,
                sql: """
                SELECT
                    COUNT(DISTINCT turnId) AS turns,
                    COALESCE(SUM(CASE WHEN kind = 'llm' THEN 1 ELSE 0 END), 0) AS steps,
                    COALESCE(SUM(CASE WHEN kind = 'llm' AND succeeded = 1
                        THEN MAX(0, completedAtMs - startedAtMs) ELSE 0 END), 0) AS llmDurationMs,
                    COALESCE(SUM(CASE WHEN kind = 'tool'
                        THEN MAX(0, completedAtMs - startedAtMs) ELSE 0 END), 0) AS toolDurationMs,
                    COALESCE(SUM(CASE WHEN kind = 'llm' AND succeeded = 1 AND firstTokenAtMs IS NOT NULL
                        THEN MAX(0, firstTokenAtMs - startedAtMs) ELSE 0 END), 0) AS ttftTotalMs,
                    COALESCE(SUM(CASE WHEN kind = 'llm' AND succeeded = 1 AND firstTokenAtMs IS NOT NULL
                        THEN 1 ELSE 0 END), 0) AS ttftSampleCount,
                    COALESCE(SUM(CASE WHEN kind = 'llm' AND succeeded = 1
                        AND firstTokenAtMs IS NOT NULL AND outputTokens IS NOT NULL
                        THEN MAX(0, completedAtMs - firstTokenAtMs) ELSE 0 END), 0) AS decodeDurationMs,
                    COALESCE(SUM(CASE WHEN kind = 'llm' AND succeeded = 1
                        AND firstTokenAtMs IS NOT NULL AND outputTokens IS NOT NULL
                        THEN outputTokens ELSE 0 END), 0) AS decodeOutputTokens,
                    COALESCE(SUM(CASE WHEN kind = 'llm' AND succeeded = 1 THEN inputTokens ELSE 0 END), 0) AS inputTokens,
                    COALESCE(SUM(CASE WHEN kind = 'llm' AND succeeded = 1 THEN outputTokens ELSE 0 END), 0) AS outputTokens,
                    COALESCE(SUM(CASE WHEN kind = 'llm' AND succeeded = 1 THEN cachedInputTokens ELSE 0 END), 0) AS cachedInputTokens,
                    COALESCE(SUM(CASE WHEN kind = 'llm' AND succeeded = 1 THEN cacheCreationInputTokens ELSE 0 END), 0) AS cacheCreationInputTokens
                FROM conversation_execution_metrics
                WHERE conversationId = ?
                """,
                arguments: [conversationId]
            )
            return ConversationStats(
                turns: row?["turns"] ?? 0,
                steps: row?["steps"] ?? 0,
                llmDurationMs: row?["llmDurationMs"] ?? 0,
                toolDurationMs: row?["toolDurationMs"] ?? 0,
                ttftTotalMs: row?["ttftTotalMs"] ?? 0,
                ttftSampleCount: row?["ttftSampleCount"] ?? 0,
                decodeDurationMs: row?["decodeDurationMs"] ?? 0,
                decodeOutputTokens: row?["decodeOutputTokens"] ?? 0,
                inputTokens: row?["inputTokens"] ?? 0,
                outputTokens: row?["outputTokens"] ?? 0,
                cachedInputTokens: row?["cachedInputTokens"] ?? 0,
                cacheCreationInputTokens: row?["cacheCreationInputTokens"] ?? 0
            )
        }
        .publisher(in: dbQueue)
        .replaceError(with: ConversationStats())
        .eraseToAnyPublisher()
    }

    func observeTokenUsageTotals(sinceEpochMs: Int64) -> AnyPublisher<TokenUsageTotals, Never> {
        ValueObservation.tracking { db -> TokenUsageTotals in
            let row = try Row.fetchOne(
                db,
                sql: """
                SELECT
                    COUNT(*) as requestCount,
                    COALESCE(SUM(inputTokens), 0) as inputTokens,
                    COALESCE(SUM(outputTokens), 0) as outputTokens,
                    COALESCE(SUM(cachedInputTokens), 0) as cachedInputTokens,
                    COALESCE(SUM(cacheCreationInputTokens), 0) as cacheCreationInputTokens,
                    COALESCE(SUM(reasoningTokens), 0) as reasoningTokens,
                    COALESCE(SUM(totalTokens), 0) as totalTokens,
                    COALESCE(SUM(costUsd), 0.0) as totalCostUsd
                FROM token_usage_records
                WHERE timestamp >= ?
                """,
                arguments: [sinceEpochMs]
            )
            return TokenUsageTotals(
                requestCount: row?["requestCount"] ?? 0,
                inputTokens: row?["inputTokens"] ?? 0,
                outputTokens: row?["outputTokens"] ?? 0,
                cachedInputTokens: row?["cachedInputTokens"] ?? 0,
                cacheCreationInputTokens: row?["cacheCreationInputTokens"] ?? 0,
                reasoningTokens: row?["reasoningTokens"] ?? 0,
                totalTokens: row?["totalTokens"] ?? 0,
                totalCostUsd: row?["totalCostUsd"] ?? 0
            )
        }
        .publisher(in: dbQueue)
        .replaceError(with: TokenUsageTotals())
        .eraseToAnyPublisher()
    }

    func observeLatestTokenUsage(conversationId: Int64) -> AnyPublisher<TokenUsageRecord?, Never> {
        ValueObservation.tracking { db -> TokenUsageRecord? in
            try TokenUsageRecord
                .filter(Column("conversationId") == conversationId)
                .order(Column("timestamp").desc, Column("id").desc)
                .fetchOne(db)
        }
        .publisher(in: dbQueue)
        .replaceError(with: nil)
        .eraseToAnyPublisher()
    }

    func fetchTokenUsageTotals(sinceEpochMs: Int64) throws -> TokenUsageTotals {
        try dbQueue.read { db in
            let row = try Row.fetchOne(
                db,
                sql: """
                SELECT
                    COUNT(*) as requestCount,
                    COALESCE(SUM(inputTokens), 0) as inputTokens,
                    COALESCE(SUM(outputTokens), 0) as outputTokens,
                    COALESCE(SUM(cachedInputTokens), 0) as cachedInputTokens,
                    COALESCE(SUM(cacheCreationInputTokens), 0) as cacheCreationInputTokens,
                    COALESCE(SUM(reasoningTokens), 0) as reasoningTokens,
                    COALESCE(SUM(totalTokens), 0) as totalTokens,
                    COALESCE(SUM(costUsd), 0.0) as totalCostUsd
                FROM token_usage_records
                WHERE timestamp >= ?
                """,
                arguments: [sinceEpochMs]
            )
            return TokenUsageTotals(
                requestCount: row?["requestCount"] ?? 0,
                inputTokens: row?["inputTokens"] ?? 0,
                outputTokens: row?["outputTokens"] ?? 0,
                cachedInputTokens: row?["cachedInputTokens"] ?? 0,
                cacheCreationInputTokens: row?["cacheCreationInputTokens"] ?? 0,
                reasoningTokens: row?["reasoningTokens"] ?? 0,
                totalTokens: row?["totalTokens"] ?? 0,
                totalCostUsd: row?["totalCostUsd"] ?? 0
            )
        }
    }

    func observeTokenUsageByModel(
        sinceEpochMs: Int64,
        limit: Int
    ) -> AnyPublisher<[TokenUsageByModel], Never> {
        ValueObservation.tracking { db -> [TokenUsageByModel] in
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT
                    model as model,
                    COUNT(*) as requestCount,
                    COALESCE(SUM(inputTokens), 0) as inputTokens,
                    COALESCE(SUM(outputTokens), 0) as outputTokens,
                    COALESCE(SUM(cachedInputTokens), 0) as cachedInputTokens,
                    COALESCE(SUM(cacheCreationInputTokens), 0) as cacheCreationInputTokens,
                    COALESCE(SUM(reasoningTokens), 0) as reasoningTokens,
                    COALESCE(SUM(totalTokens), 0) as totalTokens,
                    COALESCE(SUM(costUsd), 0.0) as totalCostUsd
                FROM token_usage_records
                WHERE timestamp >= ?
                GROUP BY model
                ORDER BY totalTokens DESC, requestCount DESC, model ASC
                LIMIT ?
                """,
                arguments: [sinceEpochMs, max(1, limit)]
            )
            return rows.map { row in
                TokenUsageByModel(
                    model: row["model"] ?? "unknown",
                    requestCount: row["requestCount"] ?? 0,
                    inputTokens: row["inputTokens"] ?? 0,
                    outputTokens: row["outputTokens"] ?? 0,
                    cachedInputTokens: row["cachedInputTokens"] ?? 0,
                    cacheCreationInputTokens: row["cacheCreationInputTokens"] ?? 0,
                    reasoningTokens: row["reasoningTokens"] ?? 0,
                    totalTokens: row["totalTokens"] ?? 0,
                    totalCostUsd: row["totalCostUsd"] ?? 0
                )
            }
        }
        .publisher(in: dbQueue)
        .replaceError(with: [])
        .eraseToAnyPublisher()
    }

    func observeTokenUsageDaily(sinceEpochMs: Int64) -> AnyPublisher<[TokenUsageDailyPoint], Never> {
        ValueObservation.tracking { db -> [TokenUsageDailyPoint] in
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT
                    ((timestamp / 86400000) * 86400000) as dayBucketStartMs,
                    COUNT(*) as requestCount,
                    COALESCE(SUM(totalTokens), 0) as totalTokens,
                    COALESCE(SUM(costUsd), 0.0) as totalCostUsd
                FROM token_usage_records
                WHERE timestamp >= ?
                GROUP BY dayBucketStartMs
                ORDER BY dayBucketStartMs ASC
                """,
                arguments: [sinceEpochMs]
            )
            return rows.map { row in
                TokenUsageDailyPoint(
                    dayBucketStartMs: row["dayBucketStartMs"] ?? 0,
                    requestCount: row["requestCount"] ?? 0,
                    totalTokens: row["totalTokens"] ?? 0,
                    totalCostUsd: row["totalCostUsd"] ?? 0
                )
            }
        }
        .publisher(in: dbQueue)
        .replaceError(with: [])
        .eraseToAnyPublisher()
    }

    func insertAutoConversationMessage(_ message: AutoConversationMessage) throws -> Int64 {
        try dbQueue.write { db in
            var mutable = message
            try mutable.insert(db)
            let now = Int64(Date().timeIntervalSince1970 * 1000)
            try db.execute(
                sql: "UPDATE auto_conversations SET updatedAtMs = ?, lastActiveAtMs = ? WHERE id = ?",
                arguments: [now, now, message.autoConversationId]
            )
            return mutable.id ?? 0
        }
    }

    func fetchLastAutoConversationMessage(autoConversationId: Int64) throws -> AutoConversationMessage? {
        try dbQueue.read { db in
            try AutoConversationMessage
                .filter(Column("autoConversationId") == autoConversationId)
                .order(Column("turnIndex").desc, Column("createdAtMs").desc, Column("id").desc)
                .fetchOne(db)
        }
    }

    func assignConversationToProject(conversationId: Int64, projectId: Int64?) throws {
        try dbQueue.write { db in
            guard var conversation = try Conversation.fetchOne(db, key: conversationId) else {
                throw ProviderClientError.parseFailure("Conversation not found")
            }

            conversation.projectId = projectId
            conversation.updatedAtMs = Int64(Date().timeIntervalSince1970 * 1000)
            try conversation.update(db)

            if let projectId, var project = try ChatProject.fetchOne(db, key: projectId) {
                project.updatedAtMs = Int64(Date().timeIntervalSince1970 * 1000)
                try project.update(db)
            }
        }
    }

    func searchConversations(query: String, limit: Int = 200) throws -> [ConversationListEntry] {
        let like = "%\(query)%"
        return try dbQueue.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT c.id, c.title, c.updatedAtMs, c.isSecret,
                    c.projectId, p.title AS projectTitle,
                    (
                        SELECT merged.preview
                        FROM (
                            SELECT
                                m2.createdAtMs AS ts,
                                CASE
                                    WHEN m2.role = 'model' AND m2.selectedVariantIndex > 0 THEN COALESCE(
                                        (SELECT v.text
                                         FROM chat_message_variants v
                                         WHERE v.baseMessageId = m2.id AND v.variantIndex = m2.selectedVariantIndex
                                         LIMIT 1),
                                        m2.text
                                    )
                                    ELSE m2.text
                                END AS preview
                            FROM chat_messages m2
                            WHERE m2.conversationId = c.id

                            UNION ALL

                            SELECT
                                d2.createdAtMs AS ts,
                                CASE
                                    WHEN d2.role = 'dual_model' AND LENGTH(TRIM(d2.modelAText)) > 0 THEN d2.modelAText
                                    WHEN d2.role = 'dual_model' AND LENGTH(TRIM(d2.modelBText)) > 0 THEN d2.modelBText
                                    WHEN d2.role = 'user' AND LENGTH(TRIM(d2.userText)) > 0 THEN d2.userText
                                    WHEN LENGTH(TRIM(d2.modelAText)) > 0 THEN d2.modelAText
                                    WHEN LENGTH(TRIM(d2.modelBText)) > 0 THEN d2.modelBText
                                    ELSE d2.userText
                                END AS preview
                            FROM dual_chat_messages d2
                            WHERE d2.conversationId = c.id
                        ) AS merged
                        ORDER BY merged.ts DESC
                        LIMIT 1
                    ) AS lastMessagePreview
                FROM conversations c
                LEFT JOIN projects p ON p.id = c.projectId
                WHERE (
                    EXISTS (
                        SELECT 1
                        FROM chat_messages message_presence
                        WHERE message_presence.conversationId = c.id
                    )
                    OR EXISTS (
                        SELECT 1
                        FROM dual_chat_messages dual_presence
                        WHERE dual_presence.conversationId = c.id
                    )
                )
                AND (
                    c.title LIKE ?
                    OR EXISTS (
                         SELECT 1
                         FROM chat_messages m
                         WHERE m.conversationId = c.id
                           AND m.text LIKE ?
                    )
                    OR EXISTS (
                         SELECT 1
                         FROM dual_chat_messages d
                         WHERE d.conversationId = c.id
                           AND (
                             d.userText LIKE ?
                             OR d.modelAText LIKE ?
                             OR d.modelBText LIKE ?
                           )
                    )
                )
                ORDER BY c.updatedAtMs DESC
                LIMIT ?
                """,
                arguments: [like, like, like, like, like, limit]
            )

            return rows.compactMap { row in
                guard let id: Int64 = row["id"] else { return nil }
                return ConversationListEntry(
                    id: id,
                    title: row["title"] ?? "New Chat",
                    updatedAtMs: row["updatedAtMs"] ?? 0,
                    lastMessagePreview: row["lastMessagePreview"],
                    isSecret: row["isSecret"] ?? false,
                    projectId: row["projectId"],
                    projectTitle: row["projectTitle"]
                )
            }
        }
    }

    private func deleteAutoConversationsBoundToConversations(
        _ db: Database,
        idsSQL: String,
        arguments: StatementArguments
    ) throws {
        guard !idsSQL.isEmpty else { return }
        try db.execute(
            sql: """
            DELETE FROM auto_conversation_messages
            WHERE autoConversationId IN (
                SELECT id FROM auto_conversations
                WHERE boundChatConversationId IN (\(idsSQL))
                   OR boundConversationId IN (\(idsSQL))
            )
            """,
            arguments: arguments + arguments
        )
        try db.execute(
            sql: """
            DELETE FROM auto_conversations
            WHERE boundChatConversationId IN (\(idsSQL))
               OR boundConversationId IN (\(idsSQL))
            """,
            arguments: arguments + arguments
        )
    }

    private func fetchMessageSummaries(db: Database, conversationId: Int64) throws -> [ChatMessageSummary] {
        let messages = try ChatMessage
            .filter(Column("conversationId") == conversationId)
            .order(Column("createdAtMs").asc)
            .fetchAll(db)

        let variantsByMessageID = try fetchVariantsByBaseMessageIDs(db: db, messageIds: messages.compactMap(\.id))
        return messages.compactMap { message in
            guard let id = message.id else { return nil }
            let resolved = resolveMessageContent(message: message, variantsByMessageID: variantsByMessageID)
            return ChatMessageSummary(
                id: id,
                role: message.role,
                textPreview: String(resolved.text.prefix(200)),
                createdAtMs: message.createdAtMs,
                hasAttachments: resolved.attachmentsJSON != "[]"
            )
        }
    }

    private func resolveMessageContent(
        message: ChatMessage,
        variantsByMessageID: [Int64: [ChatMessageVariant]]
    ) -> (text: String, attachmentsJSON: String, thinkingStream: String?) {
        guard message.role == "model",
              message.selectedVariantIndex > 0,
              let messageId = message.id,
              let selectedVariant = variantsByMessageID[messageId]?.first(where: { $0.variantIndex == message.selectedVariantIndex })
        else {
            return (message.text, message.attachmentsJSON, nil)
        }
        return (selectedVariant.text, selectedVariant.attachmentsJSON, selectedVariant.thinkingStream)
    }

    private func fetchVariantsByBaseMessageIDs(db: Database, messageIds: [Int64]) throws -> [Int64: [ChatMessageVariant]] {
        guard !messageIds.isEmpty else { return [:] }
        let variants = try ChatMessageVariant
            .filter(messageIds.contains(Column("baseMessageId")))
            .order(Column("baseMessageId").asc, Column("variantIndex").asc)
            .fetchAll(db)

        var grouped: [Int64: [ChatMessageVariant]] = [:]
        for variant in variants {
            grouped[variant.baseMessageId, default: []].append(variant)
        }
        return grouped
    }

    private func decodeArray(_ raw: String) -> [String] {
        guard let data = raw.data(using: .utf8), let decoded = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return decoded
    }

    private func mergeAttachmentJSON(_ raw: String, additions: [String]) -> String {
        var seen = Set<String>()
        let merged = (decodeArray(raw) + additions).filter { seen.insert($0).inserted }
        guard let data = try? JSONEncoder().encode(merged),
              let encoded = String(data: data, encoding: .utf8) else {
            return raw
        }
        return encoded
    }

    private func touchConversation(db: Database, conversationId: Int64) throws {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        try db.execute(
            sql: "UPDATE conversations SET updatedAtMs = ? WHERE id = ?",
            arguments: [now, conversationId]
        )
    }
}

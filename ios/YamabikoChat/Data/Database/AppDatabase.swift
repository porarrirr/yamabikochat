import Foundation
import GRDB

enum AppDatabase {
    static func makeDatabaseQueue() throws -> DatabaseQueue {
        let fileManager = FileManager.default
        let supportURL = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directoryURL = supportURL.appendingPathComponent("YamabikoChat", isDirectory: true)
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let dbURL = directoryURL.appendingPathComponent("yamabiko.sqlite")

        var configuration = Configuration()
        configuration.foreignKeysEnabled = true

        let queue = try DatabaseQueue(path: dbURL.path, configuration: configuration)
        try migrator.migrate(queue)
        return queue
    }

    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_base") { db in
            try db.create(table: "conversations") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("title", .text).notNull()
                t.column("systemPrompt", .text)
                t.column("model", .text).notNull()
                t.column("apiProvider", .text).notNull()
                t.column("createdAtMs", .integer).notNull()
                t.column("updatedAtMs", .integer).notNull()
                t.column("codexSessionId", .text)
                t.column("isSecret", .boolean).notNull().defaults(to: false)
            }

            try db.create(table: "chat_messages") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("conversationId", .integer).notNull().references("conversations", onDelete: .cascade)
                t.column("role", .text).notNull()
                t.column("text", .text).notNull()
                t.column("attachmentsJSON", .text).notNull().defaults(to: "[]")
                t.column("createdAtMs", .integer).notNull()
            }
            try db.create(index: "idx_messages_conversation_time", on: "chat_messages", columns: ["conversationId", "createdAtMs"])

            try db.create(table: "chat_message_thinking") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("messageId", .integer).notNull().unique().references("chat_messages", onDelete: .cascade)
                t.column("thinkingStream", .text).notNull()
            }

            try db.create(table: "dual_chat_messages") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("conversationId", .integer).notNull().references("conversations", onDelete: .cascade)
                t.column("role", .text).notNull().defaults(to: "legacy")
                t.column("userText", .text).notNull()
                t.column("modelAText", .text).notNull()
                t.column("modelBText", .text).notNull()
                t.column("modelAName", .text).notNull()
                t.column("modelBName", .text).notNull()
                t.column("providerA", .text).notNull()
                t.column("providerB", .text).notNull()
                t.column("modelAThinking", .text)
                t.column("modelBThinking", .text)
                t.column("attachmentsJSON", .text).notNull().defaults(to: "[]")
                t.column("createdAtMs", .integer).notNull()
            }
            try db.create(index: "idx_dual_conversation_time", on: "dual_chat_messages", columns: ["conversationId", "createdAtMs"])

            try db.create(table: "auto_conversations") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("title", .text).notNull()
                t.column("modelA", .text).notNull()
                t.column("modelB", .text).notNull()
                t.column("providerA", .text).notNull()
                t.column("providerB", .text).notNull()
                t.column("systemPromptA", .text).notNull()
                t.column("systemPromptB", .text).notNull()
                t.column("maxTurns", .integer).notNull()
                t.column("status", .text).notNull()
                t.column("boundConversationId", .integer).references("conversations", onDelete: .setNull)
                t.column("createdAtMs", .integer).notNull()
                t.column("updatedAtMs", .integer).notNull()
            }

            try db.create(table: "auto_conversation_messages") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("autoConversationId", .integer).notNull().references("auto_conversations", onDelete: .cascade)
                t.column("speaker", .text).notNull()
                t.column("content", .text).notNull()
                t.column("turnIndex", .integer).notNull()
                t.column("createdAtMs", .integer).notNull()
            }
            try db.create(index: "idx_auto_conversation_turn", on: "auto_conversation_messages", columns: ["autoConversationId", "turnIndex"])

            try db.create(table: "model_presets") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull()
                t.column("model", .text).notNull()
                t.column("apiProvider", .text).notNull()
                t.column("systemPrompt", .text)
                t.column("configJSON", .text).notNull().defaults(to: "{}")
                t.column("createdAtMs", .integer).notNull()
            }

            try db.create(table: "settings") { t in
                t.primaryKey("id", .integer)
                t.column("defaultModel", .text).notNull()
                t.column("apiProvider", .text).notNull()
                t.column("systemPrompt", .text)
                t.column("systemPromptPresetsJSON", .text).notNull().defaults(to: "[]")
                t.column("selectedSystemPromptPreset", .text)

                t.column("isStreamingEnabled", .boolean).notNull().defaults(to: true)
                t.column("mathRenderingEnabled", .boolean).notNull().defaults(to: true)
                t.column("clientWebSearchToolEnabled", .boolean).notNull().defaults(to: false)

                t.column("dynamicColorEnabled", .boolean).notNull().defaults(to: true)
                t.column("themeColor", .text).notNull().defaults(to: "BLUE_PURPLE")
                t.column("themeMode", .text).notNull().defaults(to: "SYSTEM")

                t.column("geminiThinkingEnabled", .boolean).notNull().defaults(to: false)
                t.column("geminiThinkingBudget", .integer).notNull().defaults(to: 0)
                t.column("geminiThinkingLevel", .text).notNull().defaults(to: "")
                t.column("geminiGoogleSearchEnabled", .boolean).notNull().defaults(to: false)
                t.column("geminiCodeExecutionEnabled", .boolean).notNull().defaults(to: false)
                t.column("geminiURLContextEnabled", .boolean).notNull().defaults(to: false)
                t.column("geminiGoogleMapsEnabled", .boolean).notNull().defaults(to: false)
                t.column("geminiComputerUseEnabled", .boolean).notNull().defaults(to: false)
                t.column("geminiResponseMimeType", .text).notNull().defaults(to: "")
                t.column("geminiResponseJSONSchema", .text).notNull().defaults(to: "")
                t.column("geminiFunctionDeclarations", .text).notNull().defaults(to: "")

                t.column("openRouterThinkingEnabled", .boolean).notNull().defaults(to: false)
                t.column("openRouterThinkingBudget", .integer).notNull().defaults(to: 0)
                t.column("openRouterReasoningMode", .text).notNull().defaults(to: "auto")
                t.column("openRouterReasoningEffort", .text).notNull().defaults(to: "")
                t.column("openRouterReasoningExclude", .boolean).notNull().defaults(to: false)
                t.column("openRouterGoogleSearchEnabled", .boolean).notNull().defaults(to: false)
                t.column("openRouterCodeExecutionEnabled", .boolean).notNull().defaults(to: false)

                t.column("isDualModeEnabled", .boolean).notNull().defaults(to: false)
                t.column("dualModelA", .text).notNull()
                t.column("dualModelB", .text).notNull()
                t.column("dualProviderA", .text).notNull()
                t.column("dualProviderB", .text).notNull()
                t.column("dualSystemPromptA", .text)
                t.column("dualSystemPromptB", .text)
                t.column("dualSplitLayout", .text).notNull().defaults(to: "VERTICAL")
                t.column("dualSplitRatio", .double).notNull().defaults(to: 0.5)
                t.column("dualOpenRouterThinkingEnabledA", .boolean)
                t.column("dualOpenRouterThinkingBudgetA", .integer)
                t.column("dualOpenRouterReasoningModeA", .text)
                t.column("dualOpenRouterReasoningEffortA", .text)
                t.column("dualOpenRouterReasoningExcludeA", .boolean)
                t.column("dualOpenRouterThinkingEnabledB", .boolean)
                t.column("dualOpenRouterThinkingBudgetB", .integer)
                t.column("dualOpenRouterReasoningModeB", .text)
                t.column("dualOpenRouterReasoningEffortB", .text)
                t.column("dualOpenRouterReasoningExcludeB", .boolean)
                t.column("dualGoogleSearchEnabledA", .boolean)
                t.column("dualCodeExecutionEnabledA", .boolean)
                t.column("dualURLContextEnabledA", .boolean)
                t.column("dualGoogleMapsEnabledA", .boolean)
                t.column("dualComputerUseEnabledA", .boolean)
                t.column("dualThinkingEnabledA", .boolean)
                t.column("dualThinkingBudgetA", .integer)
                t.column("dualThinkingLevelA", .text)
                t.column("dualCodexReasoningEffortA", .text)
                t.column("dualGoogleSearchEnabledB", .boolean)
                t.column("dualCodeExecutionEnabledB", .boolean)
                t.column("dualURLContextEnabledB", .boolean)
                t.column("dualGoogleMapsEnabledB", .boolean)
                t.column("dualComputerUseEnabledB", .boolean)
                t.column("dualThinkingEnabledB", .boolean)
                t.column("dualThinkingBudgetB", .integer)
                t.column("dualThinkingLevelB", .text)
                t.column("dualCodexReasoningEffortB", .text)

                t.column("isAutoConversationEnabled", .boolean).notNull().defaults(to: false)
                t.column("autoModelA", .text).notNull()
                t.column("autoModelB", .text).notNull()
                t.column("autoProviderA", .text).notNull()
                t.column("autoProviderB", .text).notNull()
                t.column("autoSystemPromptA", .text).notNull()
                t.column("autoSystemPromptB", .text).notNull()
                t.column("autoMaxTurns", .integer).notNull().defaults(to: 20)
                t.column("autoOpenRouterThinkingEnabledA", .boolean)
                t.column("autoOpenRouterThinkingBudgetA", .integer)
                t.column("autoOpenRouterReasoningModeA", .text)
                t.column("autoOpenRouterReasoningEffortA", .text)
                t.column("autoOpenRouterReasoningExcludeA", .boolean)
                t.column("autoOpenRouterThinkingEnabledB", .boolean)
                t.column("autoOpenRouterThinkingBudgetB", .integer)
                t.column("autoOpenRouterReasoningModeB", .text)
                t.column("autoOpenRouterReasoningEffortB", .text)
                t.column("autoOpenRouterReasoningExcludeB", .boolean)
                t.column("autoGoogleSearchEnabledA", .boolean)
                t.column("autoCodeExecutionEnabledA", .boolean)
                t.column("autoURLContextEnabledA", .boolean)
                t.column("autoGoogleMapsEnabledA", .boolean)
                t.column("autoComputerUseEnabledA", .boolean)
                t.column("autoThinkingEnabledA", .boolean)
                t.column("autoThinkingBudgetA", .integer)
                t.column("autoThinkingLevelA", .text)
                t.column("autoCodexReasoningEffortA", .text)
                t.column("autoGoogleSearchEnabledB", .boolean)
                t.column("autoCodeExecutionEnabledB", .boolean)
                t.column("autoURLContextEnabledB", .boolean)
                t.column("autoGoogleMapsEnabledB", .boolean)
                t.column("autoComputerUseEnabledB", .boolean)
                t.column("autoThinkingEnabledB", .boolean)
                t.column("autoThinkingBudgetB", .integer)
                t.column("autoThinkingLevelB", .text)
                t.column("autoCodexReasoningEffortB", .text)

                t.column("providerDefaultModelsJSON", .text).notNull().defaults(to: "{}")
                t.column("preferredProvidersJSON", .text).notNull().defaults(to: "[]")
                t.column("selectedQuantizationsJSON", .text).notNull().defaults(to: "[]")
                t.column("maxPricePerMillionTokens", .double).notNull().defaults(to: 0)
                t.column("allowFallbacks", .boolean).notNull().defaults(to: true)
                t.column("requireParameters", .boolean).notNull().defaults(to: false)
                t.column("providerSelectionMax", .integer).notNull().defaults(to: 12)
                t.column("providerSort", .text).notNull().defaults(to: "price")

                t.column("openAIBaseURL", .text).notNull()
                t.column("miniMaxBaseURL", .text).notNull()
                t.column("openAICompatPresetsJSON", .text).notNull().defaults(to: "[]")
                t.column("selectedOpenAICompatPreset", .text)
                t.column("alibabaMCPEnabled", .boolean).notNull().defaults(to: false)
                t.column("alibabaMCPServerURL", .text).notNull().defaults(to: "")
                t.column("alibabaMCPServerName", .text).notNull().defaults(to: "firecrawl")
                t.column("alibabaMCPAllowedToolsCSV", .text).notNull().defaults(to: "")

                t.column("codexUserAgentPreset", .text).notNull().defaults(to: "ANDROID")
                t.column("codexReasoningEnabled", .boolean).notNull().defaults(to: true)
                t.column("codexReasoningEffort", .text).notNull().defaults(to: "medium")
                t.column("codexReasoningSummary", .text).notNull().defaults(to: "auto")
                t.column("codexVerbosity", .text).notNull().defaults(to: "medium")
                t.column("codexSupportsReasoningSummaries", .boolean).notNull().defaults(to: false)
                t.column("codexShowReasoningSummary", .boolean).notNull().defaults(to: true)
                t.column("codexWebSearchEnabled", .boolean).notNull().defaults(to: false)
                t.column("codexWebSearchContextSize", .text).notNull().defaults(to: "medium")
                t.column("codexPromptCacheEnabled", .boolean).notNull().defaults(to: true)
                t.column("codexPromptCacheMinLength", .integer).notNull().defaults(to: 512)
                t.column("codexPromptCacheType", .text).notNull().defaults(to: "ephemeral")

                t.column("showGlobalProviderPresetsInChat", .boolean).notNull().defaults(to: true)
                t.column("showGlobalProviderPresetsInChatByProviderJSON", .text).notNull().defaults(to: "{}")

                t.column("extraJSON", .text).notNull().defaults(to: "{}")
            }

            var defaultSettings = AppSettings()
            try defaultSettings.insert(db)
        }

        migrator.registerMigration("v2_message_variants") { db in
            try db.alter(table: "chat_messages") { t in
                t.add(column: "selectedVariantIndex", .integer).notNull().defaults(to: 0)
            }

            try db.create(table: "chat_message_variants") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("baseMessageId", .integer).notNull().references("chat_messages", onDelete: .cascade)
                t.column("variantIndex", .integer).notNull()
                t.column("text", .text).notNull()
                t.column("attachmentsJSON", .text).notNull().defaults(to: "[]")
                t.column("thinkingStream", .text)
                t.column("createdAtMs", .integer).notNull()
            }
            try db.create(
                index: "idx_message_variants_base_order",
                on: "chat_message_variants",
                columns: ["baseMessageId", "variantIndex"],
                unique: true
            )
        }

        migrator.registerMigration("v3_projects") { db in
            try db.create(table: "projects") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("title", .text).notNull()
                t.column("iconName", .text).notNull().defaults(to: "folder.fill")
                t.column("colorHex", .text).notNull().defaults(to: "#3A7AFE")
                t.column("instructions", .text)
                t.column("createdAtMs", .integer).notNull()
                t.column("updatedAtMs", .integer).notNull()
            }

            try db.alter(table: "conversations") { t in
                t.add(column: "projectId", .integer).references("projects", onDelete: .setNull)
            }
            try db.create(index: "idx_conversations_project", on: "conversations", columns: ["projectId", "updatedAtMs"])
        }

        migrator.registerMigration("v4_dual_parity") { db in
            func existingColumns(in table: String) throws -> Set<String> {
                let rows = try Row.fetchAll(db, sql: "PRAGMA table_info(\(table))")
                return Set(rows.compactMap { ($0["name"] as String?)?.lowercased() })
            }

            func ensureDualMessageColumns() throws {
                var columns = try existingColumns(in: "dual_chat_messages")
                if !columns.contains("role") {
                    try db.alter(table: "dual_chat_messages") { t in
                        t.add(column: "role", .text).notNull().defaults(to: "legacy")
                    }
                    columns.insert("role")
                }
                if !columns.contains("modelathinking") {
                    try db.alter(table: "dual_chat_messages") { t in
                        t.add(column: "modelAThinking", .text)
                    }
                    columns.insert("modelathinking")
                }
                if !columns.contains("modelbthinking") {
                    try db.alter(table: "dual_chat_messages") { t in
                        t.add(column: "modelBThinking", .text)
                    }
                    columns.insert("modelbthinking")
                }
                if !columns.contains("attachmentsjson") {
                    try db.alter(table: "dual_chat_messages") { t in
                        t.add(column: "attachmentsJSON", .text).notNull().defaults(to: "[]")
                    }
                }
            }

            func ensureSettingsColumns() throws {
                let columns = try existingColumns(in: "settings")
                let nullableBooleanColumns = [
                    "dualOpenRouterThinkingEnabledA",
                    "dualOpenRouterReasoningExcludeA",
                    "dualOpenRouterThinkingEnabledB",
                    "dualOpenRouterReasoningExcludeB",
                    "dualGoogleSearchEnabledA",
                    "dualCodeExecutionEnabledA",
                    "dualURLContextEnabledA",
                    "dualGoogleMapsEnabledA",
                    "dualComputerUseEnabledA",
                    "dualThinkingEnabledA",
                    "dualGoogleSearchEnabledB",
                    "dualCodeExecutionEnabledB",
                    "dualURLContextEnabledB",
                    "dualGoogleMapsEnabledB",
                    "dualComputerUseEnabledB",
                    "dualThinkingEnabledB"
                ]
                let nullableIntColumns = [
                    "dualOpenRouterThinkingBudgetA",
                    "dualOpenRouterThinkingBudgetB",
                    "dualThinkingBudgetA",
                    "dualThinkingBudgetB"
                ]
                let nullableTextColumns = [
                    "dualOpenRouterReasoningModeA",
                    "dualOpenRouterReasoningEffortA",
                    "dualOpenRouterReasoningModeB",
                    "dualOpenRouterReasoningEffortB",
                    "dualThinkingLevelA",
                    "dualCodexReasoningEffortA",
                    "dualThinkingLevelB",
                    "dualCodexReasoningEffortB"
                ]

                for name in nullableBooleanColumns where !columns.contains(name.lowercased()) {
                    try db.alter(table: "settings") { t in
                        t.add(column: name, .boolean)
                    }
                }
                for name in nullableIntColumns where !columns.contains(name.lowercased()) {
                    try db.alter(table: "settings") { t in
                        t.add(column: name, .integer)
                    }
                }
                for name in nullableTextColumns where !columns.contains(name.lowercased()) {
                    try db.alter(table: "settings") { t in
                        t.add(column: name, .text)
                    }
                }
            }

            try ensureDualMessageColumns()
            try ensureSettingsColumns()
        }

        migrator.registerMigration("v5_auto_conversation_parity") { db in
            func existingColumns(in table: String) throws -> Set<String> {
                let rows = try Row.fetchAll(db, sql: "PRAGMA table_info(\(table))")
                return Set(rows.compactMap { ($0["name"] as String?)?.lowercased() })
            }

            func ensureAutoConversationColumns() throws {
                var columns = try existingColumns(in: "auto_conversations")
                if !columns.contains("currentturn") {
                    try db.alter(table: "auto_conversations") { t in
                        t.add(column: "currentTurn", .integer).notNull().defaults(to: 0)
                    }
                    columns.insert("currentturn")
                }
                if !columns.contains("lastactiveatms") {
                    try db.alter(table: "auto_conversations") { t in
                        t.add(column: "lastActiveAtMs", .integer).notNull().defaults(to: 0)
                    }
                    columns.insert("lastactiveatms")
                }
                if !columns.contains("endreason") {
                    try db.alter(table: "auto_conversations") { t in
                        t.add(column: "endReason", .text)
                    }
                    columns.insert("endreason")
                }
                if !columns.contains("endsignal") {
                    try db.alter(table: "auto_conversations") { t in
                        t.add(column: "endSignal", .text).notNull().defaults(to: "[END]")
                    }
                    columns.insert("endsignal")
                }
                if !columns.contains("boundchatconversationid") {
                    try db.alter(table: "auto_conversations") { t in
                        t.add(column: "boundChatConversationId", .integer)
                    }
                    columns.insert("boundchatconversationid")
                }

                try db.execute(
                    sql: """
                    UPDATE auto_conversations
                    SET lastActiveAtMs = CASE
                        WHEN lastActiveAtMs <= 0 THEN COALESCE(updatedAtMs, createdAtMs, 0)
                        ELSE lastActiveAtMs
                    END
                    """
                )
                if columns.contains("boundconversationid") {
                    try db.execute(
                        sql: """
                        UPDATE auto_conversations
                        SET boundChatConversationId = COALESCE(boundChatConversationId, boundConversationId)
                        WHERE boundChatConversationId IS NULL
                        """
                    )
                }
            }

            func ensureAutoConversationMessageColumns() throws {
                let columns = try existingColumns(in: "auto_conversation_messages")
                if !columns.contains("reasoning") {
                    try db.alter(table: "auto_conversation_messages") { t in
                        t.add(column: "reasoning", .text)
                    }
                }
                if !columns.contains("isendsignal") {
                    try db.alter(table: "auto_conversation_messages") { t in
                        t.add(column: "isEndSignal", .boolean).notNull().defaults(to: false)
                    }
                }
            }

            func ensureSettingsColumns() throws {
                let columns = try existingColumns(in: "settings")
                let nullableBooleanColumns = [
                    "autoOpenRouterThinkingEnabledA",
                    "autoOpenRouterReasoningExcludeA",
                    "autoOpenRouterThinkingEnabledB",
                    "autoOpenRouterReasoningExcludeB",
                    "autoGoogleSearchEnabledA",
                    "autoCodeExecutionEnabledA",
                    "autoURLContextEnabledA",
                    "autoGoogleMapsEnabledA",
                    "autoComputerUseEnabledA",
                    "autoThinkingEnabledA",
                    "autoGoogleSearchEnabledB",
                    "autoCodeExecutionEnabledB",
                    "autoURLContextEnabledB",
                    "autoGoogleMapsEnabledB",
                    "autoComputerUseEnabledB",
                    "autoThinkingEnabledB"
                ]
                let nullableIntColumns = [
                    "autoOpenRouterThinkingBudgetA",
                    "autoOpenRouterThinkingBudgetB",
                    "autoThinkingBudgetA",
                    "autoThinkingBudgetB"
                ]
                let nullableTextColumns = [
                    "autoOpenRouterReasoningModeA",
                    "autoOpenRouterReasoningEffortA",
                    "autoOpenRouterReasoningModeB",
                    "autoOpenRouterReasoningEffortB",
                    "autoThinkingLevelA",
                    "autoCodexReasoningEffortA",
                    "autoThinkingLevelB",
                    "autoCodexReasoningEffortB"
                ]

                for name in nullableBooleanColumns where !columns.contains(name.lowercased()) {
                    try db.alter(table: "settings") { t in
                        t.add(column: name, .boolean)
                    }
                }
                for name in nullableIntColumns where !columns.contains(name.lowercased()) {
                    try db.alter(table: "settings") { t in
                        t.add(column: name, .integer)
                    }
                }
                for name in nullableTextColumns where !columns.contains(name.lowercased()) {
                    try db.alter(table: "settings") { t in
                        t.add(column: name, .text)
                    }
                }
            }

            try ensureAutoConversationColumns()
            try ensureAutoConversationMessageColumns()
            try ensureSettingsColumns()
        }

        migrator.registerMigration("v6_token_usage_stats") { db in
            try db.create(table: "token_usage_records", ifNotExists: true) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("timestamp", .integer).notNull()
                t.column("provider", .text).notNull()
                t.column("model", .text).notNull()
                t.column("requestType", .text).notNull().defaults(to: "chat")
                t.column("conversationId", .integer).references("conversations", onDelete: .setNull)
                t.column("inputTokens", .integer).notNull().defaults(to: 0)
                t.column("outputTokens", .integer).notNull().defaults(to: 0)
                t.column("totalTokens", .integer).notNull().defaults(to: 0)
                t.column("reasoningTokens", .integer)
                t.column("cachedInputTokens", .integer)
                t.column("cacheCreationInputTokens", .integer)
                t.column("costUsd", .double)
            }
            try db.create(index: "idx_token_usage_timestamp", on: "token_usage_records", columns: ["timestamp"], ifNotExists: true)
            try db.create(index: "idx_token_usage_model_timestamp", on: "token_usage_records", columns: ["model", "timestamp"], ifNotExists: true)
            try db.create(index: "idx_token_usage_conversation", on: "token_usage_records", columns: ["conversationId"], ifNotExists: true)
        }

        migrator.registerMigration("v7_token_usage_cache_creation") { db in
            let rows = try Row.fetchAll(db, sql: "PRAGMA table_info(token_usage_records)")
            let columns = Set(rows.compactMap { ($0["name"] as String?)?.lowercased() })
            if !columns.contains("cachecreationinputtokens") {
                try db.alter(table: "token_usage_records") { t in
                    t.add(column: "cacheCreationInputTokens", .integer)
                }
            }
        }

        migrator.registerMigration("v8_alibaba_remote_mcp") { db in
            let rows = try Row.fetchAll(db, sql: "PRAGMA table_info(settings)")
            let columns = Set(rows.compactMap { ($0["name"] as String?)?.lowercased() })
            try db.alter(table: "settings") { t in
                if !columns.contains("alibabamcpenabled") {
                    t.add(column: "alibabaMCPEnabled", .boolean).notNull().defaults(to: false)
                }
                if !columns.contains("alibabamcpserverurl") {
                    t.add(column: "alibabaMCPServerURL", .text).notNull().defaults(to: "")
                }
                if !columns.contains("alibabamcpservername") {
                    t.add(column: "alibabaMCPServerName", .text).notNull().defaults(to: "firecrawl")
                }
                if !columns.contains("alibabamcpallowedtoolscsv") {
                    t.add(column: "alibabaMCPAllowedToolsCSV", .text).notNull().defaults(to: "")
                }
            }
        }

        migrator.registerMigration("v9_client_web_search_tool") { db in
            let settingsRows = try Row.fetchAll(db, sql: "PRAGMA table_info(settings)")
            let settingsColumns = Set(settingsRows.compactMap { ($0["name"] as String?)?.lowercased() })
            if !settingsColumns.contains("clientwebsearchtoolenabled") {
                try db.alter(table: "settings") { t in
                    t.add(column: "clientWebSearchToolEnabled", .boolean).notNull().defaults(to: false)
                }
            }

            try Self.createToolActivityTable(db)
        }

        migrator.registerMigration("v10_tool_activity_variants") { db in
            let rows = try Row.fetchAll(db, sql: "PRAGMA table_info(chat_message_tool_activity)")
            let columns = Set(rows.compactMap { ($0["name"] as String?)?.lowercased() })
            guard !columns.isEmpty else {
                try Self.createToolActivityTable(db)
                return
            }
            guard !columns.contains("variantid") else {
                try Self.createToolActivityIndexes(db)
                return
            }

            try db.execute(sql: "ALTER TABLE chat_message_tool_activity RENAME TO chat_message_tool_activity_legacy")
            try Self.createToolActivityTable(db)
            try db.execute(sql: """
                INSERT INTO chat_message_tool_activity (id, messageId, stepsJSON)
                SELECT id, messageId, stepsJSON
                FROM chat_message_tool_activity_legacy
                WHERE messageId IS NOT NULL
                """)
            try db.execute(sql: "DROP TABLE chat_message_tool_activity_legacy")
        }

        return migrator
    }

    private static func createToolActivityTable(_ db: Database) throws {
        try db.execute(sql: """
            CREATE TABLE IF NOT EXISTS chat_message_tool_activity (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                messageId INTEGER REFERENCES chat_messages(id) ON DELETE CASCADE,
                variantId INTEGER REFERENCES chat_message_variants(id) ON DELETE CASCADE,
                stepsJSON TEXT NOT NULL DEFAULT '[]',
                CHECK (
                    (messageId IS NOT NULL AND variantId IS NULL)
                    OR (messageId IS NULL AND variantId IS NOT NULL)
                )
            )
            """)
        try createToolActivityIndexes(db)
    }

    private static func createToolActivityIndexes(_ db: Database) throws {
        try db.execute(sql: """
            CREATE UNIQUE INDEX IF NOT EXISTS idx_tool_activity_message
            ON chat_message_tool_activity(messageId)
            WHERE messageId IS NOT NULL
            """)
        try db.execute(sql: """
            CREATE UNIQUE INDEX IF NOT EXISTS idx_tool_activity_variant
            ON chat_message_tool_activity(variantId)
            WHERE variantId IS NOT NULL
            """)
    }
}

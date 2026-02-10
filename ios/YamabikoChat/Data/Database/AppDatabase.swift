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
                t.column("userText", .text).notNull()
                t.column("modelAText", .text).notNull()
                t.column("modelBText", .text).notNull()
                t.column("modelAName", .text).notNull()
                t.column("modelBName", .text).notNull()
                t.column("providerA", .text).notNull()
                t.column("providerB", .text).notNull()
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

                t.column("isAutoConversationEnabled", .boolean).notNull().defaults(to: false)
                t.column("autoModelA", .text).notNull()
                t.column("autoModelB", .text).notNull()
                t.column("autoProviderA", .text).notNull()
                t.column("autoProviderB", .text).notNull()
                t.column("autoSystemPromptA", .text).notNull()
                t.column("autoSystemPromptB", .text).notNull()
                t.column("autoMaxTurns", .integer).notNull().defaults(to: 20)

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

        return migrator
    }
}

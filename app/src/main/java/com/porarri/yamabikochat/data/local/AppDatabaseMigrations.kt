package com.porarri.yamabikochat.data.local

import androidx.room.migration.Migration
import androidx.sqlite.db.SupportSQLiteDatabase

object AppDatabaseMigrations {
    private const val LEGACY_TARGET_VERSION = 27
    private const val LATEST_VERSION = 51

    private val legacyRebuildMigrations: List<Migration> = (1 until LEGACY_TARGET_VERSION).map { startVersion ->
        object : Migration(startVersion, LEGACY_TARGET_VERSION) {
            override fun migrate(db: SupportSQLiteDatabase) {
                rebuildSchema(db)
            }
        }
    }

    private val migration27To28 = object : Migration(LEGACY_TARGET_VERSION, 28) {
        override fun migrate(db: SupportSQLiteDatabase) {
            ensureColumn(db, "auto_conversations", Column("endSignal", "TEXT", notNull = true, defaultValue = "'[END]'"))
            ensureColumn(db, "auto_conversations", Column("boundChatConversationId", "INTEGER"))

            // 既存の会話の timestamp を最新のメッセージに合わせて更新
            db.execSQL(
                """
                UPDATE conversations
                SET timestamp = (
                    SELECT COALESCE(MAX(cm.timestamp), timestamp)
                    FROM chat_messages cm
                    WHERE cm.conversationId = conversations.id
                )
                """.trimIndent()
            )
        }
    }

    private val migration28To29 = object : Migration(28, 29) {
        override fun migrate(db: SupportSQLiteDatabase) {
            ensureColumn(db, "settings", Column("dualSystemPromptA", "TEXT"))
            ensureColumn(db, "settings", Column("dualSystemPromptB", "TEXT"))
        }
    }

    private val migration29To30 = object : Migration(29, 30) {
        override fun migrate(db: SupportSQLiteDatabase) {
            ensureColumn(
                db,
                "settings",
                Column("openAiBaseUrl", "TEXT", notNull = true, defaultValue = "'https://api.openai.com/v1/'")
            )
            ensureColumn(db, "settings", Column("openAiCompatPresets", "TEXT", notNull = true, defaultValue = "''"))
            ensureColumn(db, "settings", Column("providerDefaultModels", "TEXT", notNull = true, defaultValue = "''"))
            ensureColumn(db, "settings", Column("selectedOpenAiCompatPreset", "TEXT"))
        }
    }

    private val migration30To31 = object : Migration(30, 31) {
        override fun migrate(db: SupportSQLiteDatabase) {
            ensureColumn(db, "settings", Column("geminiThinkingLevel", "TEXT", notNull = true, defaultValue = "''"))
            ensureColumn(db, "model_presets", Column("thinkingLevel", "TEXT", notNull = true, defaultValue = "''"))
        }
    }

    private val migration31To32 = object : Migration(31, 32) {
        override fun migrate(db: SupportSQLiteDatabase) {
            ensureColumn(db, "settings", Column("geminiUrlContextEnabled", "INTEGER", notNull = true, defaultValue = "0"))
            ensureColumn(db, "settings", Column("geminiGoogleMapsEnabled", "INTEGER", notNull = true, defaultValue = "0"))
            ensureColumn(db, "settings", Column("geminiComputerUseEnabled", "INTEGER", notNull = true, defaultValue = "0"))
            ensureColumn(db, "settings", Column("geminiResponseMimeType", "TEXT", notNull = true, defaultValue = "''"))
            ensureColumn(db, "settings", Column("geminiResponseJsonSchema", "TEXT", notNull = true, defaultValue = "''"))
            ensureColumn(db, "settings", Column("geminiFunctionDeclarations", "TEXT", notNull = true, defaultValue = "''"))
        }
    }

    private val migration32To33 = object : Migration(32, 33) {
        override fun migrate(db: SupportSQLiteDatabase) {
            ensureColumn(db, "settings", Column("systemPromptPresets", "TEXT", notNull = true, defaultValue = "''"))
            ensureColumn(db, "settings", Column("selectedSystemPromptPreset", "TEXT"))
        }
    }

    private val migration33To34 = object : Migration(33, 34) {
        override fun migrate(db: SupportSQLiteDatabase) {
            ensureColumn(db, "settings", Column("showGlobalProviderPresetsInChat", "INTEGER", notNull = true, defaultValue = "1"))
        }
    }

    private val migration34To35 = object : Migration(34, 35) {
        override fun migrate(db: SupportSQLiteDatabase) {
            ensureColumn(db, "settings", Column("openRouterPinnedModels", "TEXT", notNull = true, defaultValue = "''"))
            ensureColumn(db, "settings", Column("openRouterRecentModels", "TEXT", notNull = true, defaultValue = "''"))
        }
    }

    private val migration35To36 = object : Migration(35, 36) {      
        override fun migrate(db: SupportSQLiteDatabase) {
            ensureColumn(
                db,
                "settings",
                Column(
                    "miniMaxBaseUrl",
                    "TEXT",
                    notNull = true,
                    defaultValue = "'https://api.minimax.io/v1/'"
                )
            )
        }
    }

    private val migration36To37 = object : Migration(36, 37) {
        override fun migrate(db: SupportSQLiteDatabase) {
            ensureColumn(
                db,
                "settings",
                Column(
                    "showGlobalProviderPresetsInChatByProvider",
                    "TEXT",
                    notNull = true,
                    defaultValue = "''"
                )
            )
        }
    }

    private val migration37To38 = object : Migration(37, 38) {
        override fun migrate(db: SupportSQLiteDatabase) {
            ensureColumn(
                db,
                "settings",
                Column("dynamicColorEnabled", "INTEGER", notNull = true, defaultValue = "1")
            )
            ensureColumn(
                db,
                "settings",
                Column("themeMode", "TEXT", notNull = true, defaultValue = "'SYSTEM'")
            )
        }
    }

    private val migration38To39 = object : Migration(38, 39) {
        override fun migrate(db: SupportSQLiteDatabase) {
            ensureColumn(
                db,
                "settings",
                Column("themeColor", "TEXT", notNull = true, defaultValue = "'BLUE_PURPLE'")
            )
        }
    }

    private val migration39To40 = object : Migration(39, 40) {
        override fun migrate(db: SupportSQLiteDatabase) {
            ensureColumn(
                db,
                "settings",
                Column("codexReasoningEnabled", "INTEGER", notNull = true, defaultValue = "1")
            )
            ensureColumn(
                db,
                "settings",
                Column("codexReasoningEffort", "TEXT", notNull = true, defaultValue = "'medium'")
            )
        }
    }

    private val migration40To41 = object : Migration(40, 41) {
        override fun migrate(db: SupportSQLiteDatabase) {
            ensureColumn(
                db,
                "settings",
                Column("codexUserAgentPreset", "TEXT", notNull = true, defaultValue = "'ANDROID'")
            )
        }
    }

    private val migration41To42 = object : Migration(41, 42) {
        override fun migrate(db: SupportSQLiteDatabase) {
            ensureColumn(db, "conversations", Column("codexSessionId", "TEXT"))
        }
    }

    private val migration42To43 = object : Migration(42, 43) {
        override fun migrate(db: SupportSQLiteDatabase) {
            ensureColumn(
                db,
                "settings",
                Column("codexReasoningSummary", "TEXT", notNull = true, defaultValue = "'auto'")
            )
            ensureColumn(
                db,
                "settings",
                Column("codexVerbosity", "TEXT", notNull = true, defaultValue = "'medium'")
            )
            ensureColumn(
                db,
                "settings",
                Column("codexSupportsReasoningSummaries", "INTEGER", notNull = true, defaultValue = "0")
            )
            ensureColumn(
                db,
                "settings",
                Column("codexShowReasoningSummary", "INTEGER", notNull = true, defaultValue = "1")
            )
        }
    }

    private val migration43To44 = object : Migration(43, 44) {
        override fun migrate(db: SupportSQLiteDatabase) {
            ensureColumn(
                db,
                "settings",
                Column("codexWebSearchEnabled", "INTEGER", notNull = true, defaultValue = "0")
            )
            ensureColumn(
                db,
                "settings",
                Column("codexWebSearchContextSize", "TEXT", notNull = true, defaultValue = "'medium'")
            )
        }
    }

    private val migration44To45 = object : Migration(44, 45) {
        override fun migrate(db: SupportSQLiteDatabase) {
            ensureColumn(
                db,
                "settings",
                Column("codexPromptCacheEnabled", "INTEGER", notNull = true, defaultValue = "1")
            )
            ensureColumn(
                db,
                "settings",
                Column("codexPromptCacheMinLength", "INTEGER", notNull = true, defaultValue = "512")
            )
            ensureColumn(
                db,
                "settings",
                Column("codexPromptCacheType", "TEXT", notNull = true, defaultValue = "'ephemeral'")
            )
        }
    }

    private val migration45To46 = object : Migration(45, 46) {
        override fun migrate(db: SupportSQLiteDatabase) {
            ensureColumn(db, "model_presets", Column("systemPromptPresetName", "TEXT"))
            ensureColumn(db, "model_presets", Column("googleSearchEnabled", "INTEGER", notNull = true, defaultValue = "0"))
            ensureColumn(db, "model_presets", Column("codeExecutionEnabled", "INTEGER", notNull = true, defaultValue = "0"))
            ensureColumn(db, "model_presets", Column("urlContextEnabled", "INTEGER", notNull = true, defaultValue = "0"))
            ensureColumn(db, "model_presets", Column("googleMapsEnabled", "INTEGER", notNull = true, defaultValue = "0"))
            ensureColumn(db, "model_presets", Column("computerUseEnabled", "INTEGER", notNull = true, defaultValue = "0"))
            ensureColumn(db, "model_presets", Column("responseMimeType", "TEXT", notNull = true, defaultValue = "''"))
            ensureColumn(db, "model_presets", Column("responseJsonSchema", "TEXT", notNull = true, defaultValue = "''"))
            ensureColumn(db, "model_presets", Column("functionDeclarations", "TEXT", notNull = true, defaultValue = "''"))
        }
    }

    private val migration46To47 = object : Migration(46, 47) {
        override fun migrate(db: SupportSQLiteDatabase) {
            ensureColumn(
                db,
                "model_presets",
                Column("codexReasoningSummary", "TEXT", notNull = true, defaultValue = "'auto'")
            )
            ensureColumn(
                db,
                "model_presets",
                Column("codexVerbosity", "TEXT", notNull = true, defaultValue = "'medium'")
            )
            ensureColumn(
                db,
                "model_presets",
                Column("codexWebSearchEnabled", "INTEGER", notNull = true, defaultValue = "0")
            )
            ensureColumn(
                db,
                "model_presets",
                Column("codexWebSearchContextSize", "TEXT", notNull = true, defaultValue = "'medium'")
            )
            ensureColumn(
                db,
                "model_presets",
                Column("codexPromptCacheEnabled", "INTEGER", notNull = true, defaultValue = "1")
            )
            ensureColumn(
                db,
                "model_presets",
                Column("codexPromptCacheMinLength", "INTEGER", notNull = true, defaultValue = "512")
            )
            ensureColumn(
                db,
                "model_presets",
                Column("codexPromptCacheType", "TEXT", notNull = true, defaultValue = "'ephemeral'")
            )
            ensureColumn(
                db,
                "model_presets",
                Column("codexShowReasoningSummary", "INTEGER", notNull = true, defaultValue = "1")
            )
            ensureColumn(
                db,
                "model_presets",
                Column("codexSupportsReasoningSummaries", "INTEGER", notNull = true, defaultValue = "0")
            )
            ensureColumn(db, "model_presets", Column("openAiCompatPresetName", "TEXT"))
        }
    }

    private val migration47To48 = object : Migration(47, 48) {
        override fun migrate(db: SupportSQLiteDatabase) {
            ensureColumn(db, "conversations", Column("isSecret", "INTEGER", notNull = true, defaultValue = "0"))
        }
    }

    private val migration48To49 = object : Migration(48, 49) {
        override fun migrate(db: SupportSQLiteDatabase) {
            ensureColumn(db, "settings", Column("dualGoogleSearchEnabledA", "INTEGER"))
            ensureColumn(db, "settings", Column("dualCodeExecutionEnabledA", "INTEGER"))
            ensureColumn(db, "settings", Column("dualUrlContextEnabledA", "INTEGER"))
            ensureColumn(db, "settings", Column("dualGoogleMapsEnabledA", "INTEGER"))
            ensureColumn(db, "settings", Column("dualComputerUseEnabledA", "INTEGER"))
            ensureColumn(db, "settings", Column("dualThinkingEnabledA", "INTEGER"))
            ensureColumn(db, "settings", Column("dualThinkingBudgetA", "INTEGER"))
            ensureColumn(db, "settings", Column("dualThinkingLevelA", "TEXT"))
            ensureColumn(db, "settings", Column("dualCodexReasoningEffortA", "TEXT"))
            ensureColumn(db, "settings", Column("dualGoogleSearchEnabledB", "INTEGER"))
            ensureColumn(db, "settings", Column("dualCodeExecutionEnabledB", "INTEGER"))
            ensureColumn(db, "settings", Column("dualUrlContextEnabledB", "INTEGER"))
            ensureColumn(db, "settings", Column("dualGoogleMapsEnabledB", "INTEGER"))
            ensureColumn(db, "settings", Column("dualComputerUseEnabledB", "INTEGER"))
            ensureColumn(db, "settings", Column("dualThinkingEnabledB", "INTEGER"))
            ensureColumn(db, "settings", Column("dualThinkingBudgetB", "INTEGER"))
            ensureColumn(db, "settings", Column("dualThinkingLevelB", "TEXT"))
            ensureColumn(db, "settings", Column("dualCodexReasoningEffortB", "TEXT"))
            ensureColumn(db, "settings", Column("autoGoogleSearchEnabledA", "INTEGER"))
            ensureColumn(db, "settings", Column("autoCodeExecutionEnabledA", "INTEGER"))
            ensureColumn(db, "settings", Column("autoUrlContextEnabledA", "INTEGER"))
            ensureColumn(db, "settings", Column("autoGoogleMapsEnabledA", "INTEGER"))
            ensureColumn(db, "settings", Column("autoComputerUseEnabledA", "INTEGER"))
            ensureColumn(db, "settings", Column("autoThinkingEnabledA", "INTEGER"))
            ensureColumn(db, "settings", Column("autoThinkingBudgetA", "INTEGER"))
            ensureColumn(db, "settings", Column("autoThinkingLevelA", "TEXT"))
            ensureColumn(db, "settings", Column("autoCodexReasoningEffortA", "TEXT"))
            ensureColumn(db, "settings", Column("autoGoogleSearchEnabledB", "INTEGER"))
            ensureColumn(db, "settings", Column("autoCodeExecutionEnabledB", "INTEGER"))
            ensureColumn(db, "settings", Column("autoUrlContextEnabledB", "INTEGER"))
            ensureColumn(db, "settings", Column("autoGoogleMapsEnabledB", "INTEGER"))
            ensureColumn(db, "settings", Column("autoComputerUseEnabledB", "INTEGER"))
            ensureColumn(db, "settings", Column("autoThinkingEnabledB", "INTEGER"))
            ensureColumn(db, "settings", Column("autoThinkingBudgetB", "INTEGER"))
            ensureColumn(db, "settings", Column("autoThinkingLevelB", "TEXT"))
            ensureColumn(db, "settings", Column("autoCodexReasoningEffortB", "TEXT"))
        }
    }

    private val migration49To50 = object : Migration(49, 50) {
        override fun migrate(db: SupportSQLiteDatabase) {
            createTokenUsageRecords(db)
        }
    }

    private val migration50To51 = object : Migration(50, 51) {
        override fun migrate(db: SupportSQLiteDatabase) {
            createProjects(db)
            ensureColumn(db, "conversations", Column("projectId", "INTEGER"))
            ensureColumn(db, "chat_messages", Column("selectedVariantIndex", "INTEGER", notNull = true, defaultValue = "0"))
            createChatMessageVariants(db)
            db.execSQL("CREATE INDEX IF NOT EXISTS `index_conversations_projectId_timestamp` ON `conversations`(`projectId`, `timestamp`)")
        }
    }

    val ALL_MIGRATIONS: Array<Migration> =
        (legacyRebuildMigrations + listOf(
            migration27To28,
            migration28To29,
            migration29To30,
            migration30To31,
            migration31To32,
            migration32To33,
            migration33To34,
            migration34To35,
            migration35To36,
            migration36To37,
            migration37To38,
            migration38To39,
            migration39To40,
            migration40To41,
            migration41To42,
            migration42To43,
            migration43To44,
            migration44To45,
            migration45To46,
            migration46To47,
            migration47To48,
            migration48To49,
            migration49To50,
            migration50To51
        )).toTypedArray()

    private fun rebuildSchema(db: SupportSQLiteDatabase) {
        db.execSQL("PRAGMA foreign_keys=ON")
        createProjects(db)
        createConversations(db)
        createChatMessages(db)
        createChatMessageVariants(db)
        createSettings(db)
        createChatMessageThinking(db)
        createModelPresets(db)
        createDualChatMessages(db)
        createAutoConversations(db)
        createAutoConversationMessages(db)
        createTokenUsageRecords(db)
    }

    private fun createConversations(db: SupportSQLiteDatabase) {
        db.execSQL(
            """
            CREATE TABLE IF NOT EXISTS `conversations` (
                `id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
                `title` TEXT NOT NULL,
                `systemPrompt` TEXT,
                `model` TEXT NOT NULL,
                `apiProvider` TEXT NOT NULL DEFAULT 'GEMINI',
                `timestamp` INTEGER NOT NULL DEFAULT 0,
                `isSecret` INTEGER NOT NULL DEFAULT 0,
                `projectId` INTEGER
            )
            """.trimIndent()
        )
        ensureColumn(db, "conversations", Column("apiProvider", "TEXT", notNull = true, defaultValue = "'GEMINI'"))
        ensureColumn(db, "conversations", Column("timestamp", "INTEGER", notNull = true, defaultValue = "0"))
        ensureColumn(db, "conversations", Column("isSecret", "INTEGER", notNull = true, defaultValue = "0"))
        ensureColumn(db, "conversations", Column("projectId", "INTEGER"))
        db.execSQL("CREATE INDEX IF NOT EXISTS `index_conversations_projectId_timestamp` ON `conversations`(`projectId`, `timestamp`)")
    }

    private fun createProjects(db: SupportSQLiteDatabase) {
        db.execSQL(
            """
            CREATE TABLE IF NOT EXISTS `projects` (
                `id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
                `title` TEXT NOT NULL,
                `iconName` TEXT NOT NULL DEFAULT 'folder.fill',
                `colorHex` TEXT NOT NULL DEFAULT '#3A7AFE',
                `instructions` TEXT,
                `createdAtMs` INTEGER NOT NULL DEFAULT 0,
                `updatedAtMs` INTEGER NOT NULL DEFAULT 0
            )
            """.trimIndent()
        )
        db.execSQL("CREATE INDEX IF NOT EXISTS `index_projects_updatedAtMs` ON `projects`(`updatedAtMs`)")
    }

    private fun createChatMessages(db: SupportSQLiteDatabase) {
        db.execSQL(
            """
            CREATE TABLE IF NOT EXISTS `chat_messages` (
                `id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
                `conversationId` INTEGER NOT NULL,
                `role` TEXT NOT NULL,
                `text` TEXT NOT NULL,
                `attachments` TEXT NOT NULL DEFAULT '[]',
                `timestamp` INTEGER NOT NULL DEFAULT 0,
                `thinkingSummary` TEXT,
                `selectedVariantIndex` INTEGER NOT NULL DEFAULT 0
            )
            """.trimIndent()
        )
        ensureColumn(db, "chat_messages", Column("attachments", "TEXT", notNull = true, defaultValue = "'[]'"))
        ensureColumn(db, "chat_messages", Column("timestamp", "INTEGER", notNull = true, defaultValue = "0"))
        ensureColumn(db, "chat_messages", Column("thinkingSummary", "TEXT"))
        ensureColumn(db, "chat_messages", Column("selectedVariantIndex", "INTEGER", notNull = true, defaultValue = "0"))
    }

    private fun createChatMessageVariants(db: SupportSQLiteDatabase) {
        db.execSQL(
            """
            CREATE TABLE IF NOT EXISTS `chat_message_variants` (
                `id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
                `baseMessageId` INTEGER NOT NULL,
                `variantIndex` INTEGER NOT NULL,
                `text` TEXT NOT NULL,
                `attachments` TEXT NOT NULL DEFAULT '[]',
                `thinkingStream` TEXT,
                `createdAtMs` INTEGER NOT NULL DEFAULT 0,
                FOREIGN KEY(`baseMessageId`) REFERENCES `chat_messages`(`id`) ON DELETE CASCADE
            )
            """.trimIndent()
        )
        db.execSQL("CREATE UNIQUE INDEX IF NOT EXISTS `index_chat_message_variants_baseMessageId_variantIndex` ON `chat_message_variants`(`baseMessageId`, `variantIndex`)")
    }

    private fun createSettings(db: SupportSQLiteDatabase) {
        db.execSQL(
            """
            CREATE TABLE IF NOT EXISTS `settings` (
                `id` INTEGER NOT NULL PRIMARY KEY,
                `defaultModel` TEXT NOT NULL DEFAULT 'gemini-2.5-flash',
                `googleSearchEnabled` INTEGER NOT NULL DEFAULT 0,
                `codeExecutionEnabled` INTEGER NOT NULL DEFAULT 0,
                `thinkingEnabled` INTEGER NOT NULL DEFAULT 0,
                `thinkingBudget` INTEGER NOT NULL DEFAULT 0,
                `systemPrompt` TEXT,
                `systemPromptPresets` TEXT NOT NULL DEFAULT '',
                `selectedSystemPromptPreset` TEXT,
                `isStreamingEnabled` INTEGER NOT NULL DEFAULT 1,
                `apiProvider` TEXT NOT NULL DEFAULT 'GEMINI',
                `geminiGoogleSearchEnabled` INTEGER NOT NULL DEFAULT 0,
                `geminiCodeExecutionEnabled` INTEGER NOT NULL DEFAULT 0,
                `geminiUrlContextEnabled` INTEGER NOT NULL DEFAULT 0,
                `geminiGoogleMapsEnabled` INTEGER NOT NULL DEFAULT 0,
                `geminiComputerUseEnabled` INTEGER NOT NULL DEFAULT 0,
                `geminiThinkingEnabled` INTEGER NOT NULL DEFAULT 0,
                `geminiThinkingBudget` INTEGER NOT NULL DEFAULT 0,
                `geminiThinkingLevel` TEXT NOT NULL DEFAULT '',
                `geminiStreamingEnabled` INTEGER NOT NULL DEFAULT 1,
                `geminiResponseMimeType` TEXT NOT NULL DEFAULT '',
                `geminiResponseJsonSchema` TEXT NOT NULL DEFAULT '',
                `geminiFunctionDeclarations` TEXT NOT NULL DEFAULT '',
                `openRouterGoogleSearchEnabled` INTEGER NOT NULL DEFAULT 0,
                `openRouterCodeExecutionEnabled` INTEGER NOT NULL DEFAULT 0,
                `openRouterThinkingEnabled` INTEGER NOT NULL DEFAULT 0,
                `openRouterThinkingBudget` INTEGER NOT NULL DEFAULT 0,
                `openRouterStreamingEnabled` INTEGER NOT NULL DEFAULT 1,
                `openRouterReasoningMode` TEXT NOT NULL DEFAULT 'auto',
                `openRouterReasoningEffort` TEXT NOT NULL DEFAULT '',
                `openRouterReasoningExclude` INTEGER NOT NULL DEFAULT 0,        
                `openRouterPinnedModels` TEXT NOT NULL DEFAULT '',
                `openRouterRecentModels` TEXT NOT NULL DEFAULT '',
                `dualOpenRouterThinkingEnabledA` INTEGER,
                `dualOpenRouterThinkingBudgetA` INTEGER,
                `dualOpenRouterReasoningModeA` TEXT,
                `dualOpenRouterReasoningEffortA` TEXT,
                `dualOpenRouterReasoningExcludeA` INTEGER,
                `dualOpenRouterThinkingEnabledB` INTEGER,
                `dualOpenRouterThinkingBudgetB` INTEGER,
                `dualOpenRouterReasoningModeB` TEXT,
                `dualOpenRouterReasoningEffortB` TEXT,
                `dualOpenRouterReasoningExcludeB` INTEGER,
                `autoOpenRouterThinkingEnabledA` INTEGER,
                `autoOpenRouterThinkingBudgetA` INTEGER,
                `autoOpenRouterReasoningModeA` TEXT,
                `autoOpenRouterReasoningEffortA` TEXT,
                `autoOpenRouterReasoningExcludeA` INTEGER,
                `autoOpenRouterThinkingEnabledB` INTEGER,
                `autoOpenRouterThinkingBudgetB` INTEGER,
                `autoOpenRouterReasoningModeB` TEXT,
                `autoOpenRouterReasoningEffortB` TEXT,
                `autoOpenRouterReasoningExcludeB` INTEGER,
                `dualGoogleSearchEnabledA` INTEGER,
                `dualCodeExecutionEnabledA` INTEGER,
                `dualUrlContextEnabledA` INTEGER,
                `dualGoogleMapsEnabledA` INTEGER,
                `dualComputerUseEnabledA` INTEGER,
                `dualThinkingEnabledA` INTEGER,
                `dualThinkingBudgetA` INTEGER,
                `dualThinkingLevelA` TEXT,
                `dualCodexReasoningEffortA` TEXT,
                `dualGoogleSearchEnabledB` INTEGER,
                `dualCodeExecutionEnabledB` INTEGER,
                `dualUrlContextEnabledB` INTEGER,
                `dualGoogleMapsEnabledB` INTEGER,
                `dualComputerUseEnabledB` INTEGER,
                `dualThinkingEnabledB` INTEGER,
                `dualThinkingBudgetB` INTEGER,
                `dualThinkingLevelB` TEXT,
                `dualCodexReasoningEffortB` TEXT,
                `autoGoogleSearchEnabledA` INTEGER,
                `autoCodeExecutionEnabledA` INTEGER,
                `autoUrlContextEnabledA` INTEGER,
                `autoGoogleMapsEnabledA` INTEGER,
                `autoComputerUseEnabledA` INTEGER,
                `autoThinkingEnabledA` INTEGER,
                `autoThinkingBudgetA` INTEGER,
                `autoThinkingLevelA` TEXT,
                `autoCodexReasoningEffortA` TEXT,
                `autoGoogleSearchEnabledB` INTEGER,
                `autoCodeExecutionEnabledB` INTEGER,
                `autoUrlContextEnabledB` INTEGER,
                `autoGoogleMapsEnabledB` INTEGER,
                `autoComputerUseEnabledB` INTEGER,
                `autoThinkingEnabledB` INTEGER,
                `autoThinkingBudgetB` INTEGER,
                `autoThinkingLevelB` TEXT,
                `autoCodexReasoningEffortB` TEXT,
                `isDualModeEnabled` INTEGER NOT NULL DEFAULT 0,
                `dualModelA` TEXT NOT NULL DEFAULT 'gemini-2.5-flash',
                `dualModelB` TEXT NOT NULL DEFAULT 'deepseek/deepseek-chat',
                `dualProviderA` TEXT NOT NULL DEFAULT 'GEMINI',
                `dualProviderB` TEXT NOT NULL DEFAULT 'OPENROUTER',
                `dualSplitLayout` TEXT NOT NULL DEFAULT 'VERTICAL',
                `dualSplitRatio` REAL NOT NULL DEFAULT 0.5,
                `dualSystemPromptA` TEXT,
                `dualSystemPromptB` TEXT,
                `isAutoConversationEnabled` INTEGER NOT NULL DEFAULT 0,
                `autoModelA` TEXT NOT NULL DEFAULT 'gemini-2.5-flash',
                `autoModelB` TEXT NOT NULL DEFAULT 'deepseek/deepseek-chat',
                `autoProviderA` TEXT NOT NULL DEFAULT 'GEMINI',
                `autoProviderB` TEXT NOT NULL DEFAULT 'OPENROUTER',
                `autoSystemPromptA` TEXT NOT NULL DEFAULT 'あなたは親しみやすい日本語AIアシスタントです。自然で温かみのある会話を心がけてください。',
                `autoSystemPromptB` TEXT NOT NULL DEFAULT 'あなたは論理的で分析的なAIアシスタントです。深く考えながら詳細に回答してください。',
                `autoMaxTurns` INTEGER NOT NULL DEFAULT 20,
                `mathRenderingEnabled` INTEGER NOT NULL DEFAULT 1,
                `dynamicColorEnabled` INTEGER NOT NULL DEFAULT 1,
                `themeMode` TEXT NOT NULL DEFAULT 'SYSTEM',
                `themeColor` TEXT NOT NULL DEFAULT 'BLUE_PURPLE',
                `showGlobalProviderPresetsInChat` INTEGER NOT NULL DEFAULT 1,   
                `showGlobalProviderPresetsInChatByProvider` TEXT NOT NULL DEFAULT '',
                `codexUserAgentPreset` TEXT NOT NULL DEFAULT 'ANDROID',
                `codexReasoningEnabled` INTEGER NOT NULL DEFAULT 1,
                `codexReasoningEffort` TEXT NOT NULL DEFAULT 'medium',
                `codexReasoningSummary` TEXT NOT NULL DEFAULT 'auto',
                `codexVerbosity` TEXT NOT NULL DEFAULT 'medium',
                `codexSupportsReasoningSummaries` INTEGER NOT NULL DEFAULT 0,
                `codexShowReasoningSummary` INTEGER NOT NULL DEFAULT 1,
                `codexWebSearchEnabled` INTEGER NOT NULL DEFAULT 0,
                `codexWebSearchContextSize` TEXT NOT NULL DEFAULT 'medium',
                `codexPromptCacheEnabled` INTEGER NOT NULL DEFAULT 1,
                `codexPromptCacheMinLength` INTEGER NOT NULL DEFAULT 512,
                `codexPromptCacheType` TEXT NOT NULL DEFAULT 'ephemeral',
                `preferredProviders` TEXT NOT NULL DEFAULT '',
                `selectedQuantizations` TEXT NOT NULL DEFAULT '',
                `maxPricePerMillionTokens` REAL NOT NULL DEFAULT 0.0,
                `allowFallbacks` INTEGER NOT NULL DEFAULT 1,
                `requireParameters` INTEGER NOT NULL DEFAULT 0,
                `providerSelectionMax` INTEGER NOT NULL DEFAULT 12,
                `providerSort` TEXT NOT NULL DEFAULT 'price',
                `providerDefaultModels` TEXT NOT NULL DEFAULT '',
                `openAiBaseUrl` TEXT NOT NULL DEFAULT 'https://api.openai.com/v1/',
                `miniMaxBaseUrl` TEXT NOT NULL DEFAULT 'https://api.minimax.io/v1/',
                `openAiCompatPresets` TEXT NOT NULL DEFAULT '',
                `selectedOpenAiCompatPreset` TEXT
            )
            """.trimIndent()
        )
        val columns = listOf(
            Column("defaultModel", "TEXT", notNull = true, defaultValue = "'gemini-2.5-flash'"),
            Column("googleSearchEnabled", "INTEGER", notNull = true, defaultValue = "0"),
            Column("codeExecutionEnabled", "INTEGER", notNull = true, defaultValue = "0"),
            Column("thinkingEnabled", "INTEGER", notNull = true, defaultValue = "0"),
            Column("thinkingBudget", "INTEGER", notNull = true, defaultValue = "0"),
            Column("systemPrompt", "TEXT"),
            Column("systemPromptPresets", "TEXT", notNull = true, defaultValue = "''"),
            Column("selectedSystemPromptPreset", "TEXT"),
            Column("isStreamingEnabled", "INTEGER", notNull = true, defaultValue = "1"),
            Column("apiProvider", "TEXT", notNull = true, defaultValue = "'GEMINI'"),
            Column("geminiGoogleSearchEnabled", "INTEGER", notNull = true, defaultValue = "0"),
            Column("geminiCodeExecutionEnabled", "INTEGER", notNull = true, defaultValue = "0"),
            Column("geminiUrlContextEnabled", "INTEGER", notNull = true, defaultValue = "0"),
            Column("geminiGoogleMapsEnabled", "INTEGER", notNull = true, defaultValue = "0"),
            Column("geminiComputerUseEnabled", "INTEGER", notNull = true, defaultValue = "0"),
            Column("geminiThinkingEnabled", "INTEGER", notNull = true, defaultValue = "0"),
            Column("geminiThinkingBudget", "INTEGER", notNull = true, defaultValue = "0"),
            Column("geminiThinkingLevel", "TEXT", notNull = true, defaultValue = "''"),
            Column("geminiStreamingEnabled", "INTEGER", notNull = true, defaultValue = "1"),
            Column("geminiResponseMimeType", "TEXT", notNull = true, defaultValue = "''"),
            Column("geminiResponseJsonSchema", "TEXT", notNull = true, defaultValue = "''"),
            Column("geminiFunctionDeclarations", "TEXT", notNull = true, defaultValue = "''"),
            Column("openRouterGoogleSearchEnabled", "INTEGER", notNull = true, defaultValue = "0"),
            Column("openRouterCodeExecutionEnabled", "INTEGER", notNull = true, defaultValue = "0"),
            Column("openRouterThinkingEnabled", "INTEGER", notNull = true, defaultValue = "0"),
            Column("openRouterThinkingBudget", "INTEGER", notNull = true, defaultValue = "0"),
            Column("openRouterStreamingEnabled", "INTEGER", notNull = true, defaultValue = "1"),
            Column("openRouterReasoningMode", "TEXT", notNull = true, defaultValue = "'auto'"),
            Column("openRouterReasoningEffort", "TEXT", notNull = true, defaultValue = "''"),
            Column("openRouterReasoningExclude", "INTEGER", notNull = true, defaultValue = "0"),
            Column("openRouterPinnedModels", "TEXT", notNull = true, defaultValue = "''"),
            Column("openRouterRecentModels", "TEXT", notNull = true, defaultValue = "''"),
            Column("dualOpenRouterThinkingEnabledA", "INTEGER"),
            Column("dualOpenRouterThinkingBudgetA", "INTEGER"),
            Column("dualOpenRouterReasoningModeA", "TEXT"),
            Column("dualOpenRouterReasoningEffortA", "TEXT"),
            Column("dualOpenRouterReasoningExcludeA", "INTEGER"),
            Column("dualOpenRouterThinkingEnabledB", "INTEGER"),
            Column("dualOpenRouterThinkingBudgetB", "INTEGER"),
            Column("dualOpenRouterReasoningModeB", "TEXT"),
            Column("dualOpenRouterReasoningEffortB", "TEXT"),
            Column("dualOpenRouterReasoningExcludeB", "INTEGER"),
            Column("autoOpenRouterThinkingEnabledA", "INTEGER"),
            Column("autoOpenRouterThinkingBudgetA", "INTEGER"),
            Column("autoOpenRouterReasoningModeA", "TEXT"),
            Column("autoOpenRouterReasoningEffortA", "TEXT"),
            Column("autoOpenRouterReasoningExcludeA", "INTEGER"),
            Column("autoOpenRouterThinkingEnabledB", "INTEGER"),
            Column("autoOpenRouterThinkingBudgetB", "INTEGER"),
            Column("autoOpenRouterReasoningModeB", "TEXT"),
            Column("autoOpenRouterReasoningEffortB", "TEXT"),
            Column("autoOpenRouterReasoningExcludeB", "INTEGER"),
            Column("dualGoogleSearchEnabledA", "INTEGER"),
            Column("dualCodeExecutionEnabledA", "INTEGER"),
            Column("dualUrlContextEnabledA", "INTEGER"),
            Column("dualGoogleMapsEnabledA", "INTEGER"),
            Column("dualComputerUseEnabledA", "INTEGER"),
            Column("dualThinkingEnabledA", "INTEGER"),
            Column("dualThinkingBudgetA", "INTEGER"),
            Column("dualThinkingLevelA", "TEXT"),
            Column("dualCodexReasoningEffortA", "TEXT"),
            Column("dualGoogleSearchEnabledB", "INTEGER"),
            Column("dualCodeExecutionEnabledB", "INTEGER"),
            Column("dualUrlContextEnabledB", "INTEGER"),
            Column("dualGoogleMapsEnabledB", "INTEGER"),
            Column("dualComputerUseEnabledB", "INTEGER"),
            Column("dualThinkingEnabledB", "INTEGER"),
            Column("dualThinkingBudgetB", "INTEGER"),
            Column("dualThinkingLevelB", "TEXT"),
            Column("dualCodexReasoningEffortB", "TEXT"),
            Column("autoGoogleSearchEnabledA", "INTEGER"),
            Column("autoCodeExecutionEnabledA", "INTEGER"),
            Column("autoUrlContextEnabledA", "INTEGER"),
            Column("autoGoogleMapsEnabledA", "INTEGER"),
            Column("autoComputerUseEnabledA", "INTEGER"),
            Column("autoThinkingEnabledA", "INTEGER"),
            Column("autoThinkingBudgetA", "INTEGER"),
            Column("autoThinkingLevelA", "TEXT"),
            Column("autoCodexReasoningEffortA", "TEXT"),
            Column("autoGoogleSearchEnabledB", "INTEGER"),
            Column("autoCodeExecutionEnabledB", "INTEGER"),
            Column("autoUrlContextEnabledB", "INTEGER"),
            Column("autoGoogleMapsEnabledB", "INTEGER"),
            Column("autoComputerUseEnabledB", "INTEGER"),
            Column("autoThinkingEnabledB", "INTEGER"),
            Column("autoThinkingBudgetB", "INTEGER"),
            Column("autoThinkingLevelB", "TEXT"),
            Column("autoCodexReasoningEffortB", "TEXT"),
            Column("isDualModeEnabled", "INTEGER", notNull = true, defaultValue = "0"),
            Column("dualModelA", "TEXT", notNull = true, defaultValue = "'gemini-2.5-flash'"),
            Column("dualModelB", "TEXT", notNull = true, defaultValue = "'deepseek/deepseek-chat'"),
            Column("dualProviderA", "TEXT", notNull = true, defaultValue = "'GEMINI'"),
            Column("dualProviderB", "TEXT", notNull = true, defaultValue = "'OPENROUTER'"),
            Column("dualSplitLayout", "TEXT", notNull = true, defaultValue = "'VERTICAL'"),
            Column("dualSplitRatio", "REAL", notNull = true, defaultValue = "0.5"),
            Column("dualSystemPromptA", "TEXT"),
            Column("dualSystemPromptB", "TEXT"),
            Column("isAutoConversationEnabled", "INTEGER", notNull = true, defaultValue = "0"),
            Column("autoModelA", "TEXT", notNull = true, defaultValue = "'gemini-2.5-flash'"),
            Column("autoModelB", "TEXT", notNull = true, defaultValue = "'deepseek/deepseek-chat'"),
            Column("autoProviderA", "TEXT", notNull = true, defaultValue = "'GEMINI'"),
            Column("autoProviderB", "TEXT", notNull = true, defaultValue = "'OPENROUTER'"),
            Column(
                "autoSystemPromptA",
                "TEXT",
                notNull = true,
                defaultValue = "'あなたは親しみやすい日本語AIアシスタントです。自然で温かみのある会話を心がけてください。'"
            ),
            Column(
                "autoSystemPromptB",
                "TEXT",
                notNull = true,
                defaultValue = "'あなたは論理的で分析的なAIアシスタントです。深く考えながら詳細に回答してください。'"
            ),
            Column("autoMaxTurns", "INTEGER", notNull = true, defaultValue = "20"),
            Column("mathRenderingEnabled", "INTEGER", notNull = true, defaultValue = "1"),
            Column("dynamicColorEnabled", "INTEGER", notNull = true, defaultValue = "1"),
            Column("themeMode", "TEXT", notNull = true, defaultValue = "'SYSTEM'"),
            Column("themeColor", "TEXT", notNull = true, defaultValue = "'BLUE_PURPLE'"),
            Column("showGlobalProviderPresetsInChat", "INTEGER", notNull = true, defaultValue = "1"),
            Column("showGlobalProviderPresetsInChatByProvider", "TEXT", notNull = true, defaultValue = "''"),
            Column("codexUserAgentPreset", "TEXT", notNull = true, defaultValue = "'ANDROID'"),
            Column("codexReasoningEnabled", "INTEGER", notNull = true, defaultValue = "1"),
            Column("codexReasoningEffort", "TEXT", notNull = true, defaultValue = "'medium'"),
            Column("codexReasoningSummary", "TEXT", notNull = true, defaultValue = "'auto'"),
            Column("codexVerbosity", "TEXT", notNull = true, defaultValue = "'medium'"),
            Column("codexSupportsReasoningSummaries", "INTEGER", notNull = true, defaultValue = "0"),
            Column("codexShowReasoningSummary", "INTEGER", notNull = true, defaultValue = "1"),
            Column("codexWebSearchEnabled", "INTEGER", notNull = true, defaultValue = "0"),
            Column("codexWebSearchContextSize", "TEXT", notNull = true, defaultValue = "'medium'"),
            Column("codexPromptCacheEnabled", "INTEGER", notNull = true, defaultValue = "1"),
            Column("codexPromptCacheMinLength", "INTEGER", notNull = true, defaultValue = "512"),
            Column("codexPromptCacheType", "TEXT", notNull = true, defaultValue = "'ephemeral'"),
            Column("preferredProviders", "TEXT", notNull = true, defaultValue = "''"),
            Column("selectedQuantizations", "TEXT", notNull = true, defaultValue = "''"),
            Column("maxPricePerMillionTokens", "REAL", notNull = true, defaultValue = "0.0"),
            Column("allowFallbacks", "INTEGER", notNull = true, defaultValue = "1"),
            Column("requireParameters", "INTEGER", notNull = true, defaultValue = "0"),
            Column("providerSelectionMax", "INTEGER", notNull = true, defaultValue = "12"),
            Column("providerSort", "TEXT", notNull = true, defaultValue = "'price'"),
            Column("providerDefaultModels", "TEXT", notNull = true, defaultValue = "''"),
            Column("openAiBaseUrl", "TEXT", notNull = true, defaultValue = "'https://api.openai.com/v1/'"),
            Column("miniMaxBaseUrl", "TEXT", notNull = true, defaultValue = "'https://api.minimax.io/v1/'"),
            Column("openAiCompatPresets", "TEXT", notNull = true, defaultValue = "''"),
            Column("selectedOpenAiCompatPreset", "TEXT"),
        )
        columns.forEach { ensureColumn(db, "settings", it) }
    }

    private fun createChatMessageThinking(db: SupportSQLiteDatabase) {
        db.execSQL(
            """
            CREATE TABLE IF NOT EXISTS `chat_message_thinking` (
                `messageId` INTEGER NOT NULL,
                `thinkingStream` TEXT,
                PRIMARY KEY(`messageId`),
                FOREIGN KEY(`messageId`) REFERENCES `chat_messages`(`id`) ON DELETE CASCADE
            )
            """.trimIndent()
        )
        ensureColumn(db, "chat_message_thinking", Column("thinkingStream", "TEXT"))
    }

    private fun createModelPresets(db: SupportSQLiteDatabase) {
        db.execSQL(
            """
            CREATE TABLE IF NOT EXISTS `model_presets` (
                `id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
                `name` TEXT NOT NULL,
                `model` TEXT NOT NULL,
                `systemPrompt` TEXT,
                `systemPromptPresetName` TEXT,
                `thinkingEnabled` INTEGER NOT NULL DEFAULT 0,
                `thinkingBudget` INTEGER NOT NULL DEFAULT 0,
                `thinkingLevel` TEXT NOT NULL DEFAULT '',
                `googleSearchEnabled` INTEGER NOT NULL DEFAULT 0,
                `codeExecutionEnabled` INTEGER NOT NULL DEFAULT 0,
                `urlContextEnabled` INTEGER NOT NULL DEFAULT 0,
                `googleMapsEnabled` INTEGER NOT NULL DEFAULT 0,
                `computerUseEnabled` INTEGER NOT NULL DEFAULT 0,
                `responseMimeType` TEXT NOT NULL DEFAULT '',
                `responseJsonSchema` TEXT NOT NULL DEFAULT '',
                `functionDeclarations` TEXT NOT NULL DEFAULT '',
                `apiProvider` TEXT NOT NULL DEFAULT 'GEMINI',
                `reasoningMode` TEXT NOT NULL DEFAULT 'auto',
                `reasoningEffort` TEXT NOT NULL DEFAULT '',
                `reasoningExclude` INTEGER NOT NULL DEFAULT 0,
                `codexReasoningSummary` TEXT NOT NULL DEFAULT 'auto',
                `codexVerbosity` TEXT NOT NULL DEFAULT 'medium',
                `codexWebSearchEnabled` INTEGER NOT NULL DEFAULT 0,
                `codexWebSearchContextSize` TEXT NOT NULL DEFAULT 'medium',
                `codexPromptCacheEnabled` INTEGER NOT NULL DEFAULT 1,
                `codexPromptCacheMinLength` INTEGER NOT NULL DEFAULT 512,
                `codexPromptCacheType` TEXT NOT NULL DEFAULT 'ephemeral',
                `codexShowReasoningSummary` INTEGER NOT NULL DEFAULT 1,
                `codexSupportsReasoningSummaries` INTEGER NOT NULL DEFAULT 0,
                `openAiCompatPresetName` TEXT
            )
            """.trimIndent()
        )
        ensureColumn(db, "model_presets", Column("thinkingEnabled", "INTEGER", notNull = true, defaultValue = "0"))
        ensureColumn(db, "model_presets", Column("thinkingBudget", "INTEGER", notNull = true, defaultValue = "0"))
        ensureColumn(db, "model_presets", Column("thinkingLevel", "TEXT", notNull = true, defaultValue = "''"))
        ensureColumn(db, "model_presets", Column("systemPromptPresetName", "TEXT"))
        ensureColumn(db, "model_presets", Column("googleSearchEnabled", "INTEGER", notNull = true, defaultValue = "0"))
        ensureColumn(db, "model_presets", Column("codeExecutionEnabled", "INTEGER", notNull = true, defaultValue = "0"))
        ensureColumn(db, "model_presets", Column("urlContextEnabled", "INTEGER", notNull = true, defaultValue = "0"))
        ensureColumn(db, "model_presets", Column("googleMapsEnabled", "INTEGER", notNull = true, defaultValue = "0"))
        ensureColumn(db, "model_presets", Column("computerUseEnabled", "INTEGER", notNull = true, defaultValue = "0"))
        ensureColumn(db, "model_presets", Column("responseMimeType", "TEXT", notNull = true, defaultValue = "''"))
        ensureColumn(db, "model_presets", Column("responseJsonSchema", "TEXT", notNull = true, defaultValue = "''"))
        ensureColumn(db, "model_presets", Column("functionDeclarations", "TEXT", notNull = true, defaultValue = "''"))
        ensureColumn(db, "model_presets", Column("apiProvider", "TEXT", notNull = true, defaultValue = "'GEMINI'"))
        ensureColumn(db, "model_presets", Column("reasoningMode", "TEXT", notNull = true, defaultValue = "'auto'"))
        ensureColumn(db, "model_presets", Column("reasoningEffort", "TEXT", notNull = true, defaultValue = "''"))
        ensureColumn(db, "model_presets", Column("reasoningExclude", "INTEGER", notNull = true, defaultValue = "0"))
        ensureColumn(db, "model_presets", Column("codexReasoningSummary", "TEXT", notNull = true, defaultValue = "'auto'"))
        ensureColumn(db, "model_presets", Column("codexVerbosity", "TEXT", notNull = true, defaultValue = "'medium'"))
        ensureColumn(db, "model_presets", Column("codexWebSearchEnabled", "INTEGER", notNull = true, defaultValue = "0"))
        ensureColumn(
            db,
            "model_presets",
            Column("codexWebSearchContextSize", "TEXT", notNull = true, defaultValue = "'medium'")
        )
        ensureColumn(db, "model_presets", Column("codexPromptCacheEnabled", "INTEGER", notNull = true, defaultValue = "1"))
        ensureColumn(db, "model_presets", Column("codexPromptCacheMinLength", "INTEGER", notNull = true, defaultValue = "512"))
        ensureColumn(
            db,
            "model_presets",
            Column("codexPromptCacheType", "TEXT", notNull = true, defaultValue = "'ephemeral'")
        )
        ensureColumn(
            db,
            "model_presets",
            Column("codexShowReasoningSummary", "INTEGER", notNull = true, defaultValue = "1")
        )
        ensureColumn(
            db,
            "model_presets",
            Column("codexSupportsReasoningSummaries", "INTEGER", notNull = true, defaultValue = "0")
        )
        ensureColumn(db, "model_presets", Column("openAiCompatPresetName", "TEXT"))
    }

    private fun createDualChatMessages(db: SupportSQLiteDatabase) {
        db.execSQL(
            """
            CREATE TABLE IF NOT EXISTS `dual_chat_messages` (
                `id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
                `conversationId` INTEGER NOT NULL,
                `role` TEXT NOT NULL,
                `userText` TEXT NOT NULL DEFAULT '',
                `modelAText` TEXT NOT NULL DEFAULT '',
                `modelBText` TEXT NOT NULL DEFAULT '',
                `modelAName` TEXT NOT NULL DEFAULT '',
                `modelBName` TEXT NOT NULL DEFAULT '',
                `modelAProvider` TEXT NOT NULL DEFAULT '',
                `modelBProvider` TEXT NOT NULL DEFAULT '',
                `timestamp` INTEGER NOT NULL DEFAULT 0,
                `modelAThinking` TEXT,
                `modelBThinking` TEXT,
                `attachments` TEXT NOT NULL DEFAULT '[]'
            )
            """.trimIndent()
        )
        ensureColumn(db, "dual_chat_messages", Column("userText", "TEXT", notNull = true, defaultValue = "''"))
        ensureColumn(db, "dual_chat_messages", Column("modelAText", "TEXT", notNull = true, defaultValue = "''"))
        ensureColumn(db, "dual_chat_messages", Column("modelBText", "TEXT", notNull = true, defaultValue = "''"))
        ensureColumn(db, "dual_chat_messages", Column("modelAName", "TEXT", notNull = true, defaultValue = "''"))
        ensureColumn(db, "dual_chat_messages", Column("modelBName", "TEXT", notNull = true, defaultValue = "''"))
        ensureColumn(db, "dual_chat_messages", Column("modelAProvider", "TEXT", notNull = true, defaultValue = "''"))
        ensureColumn(db, "dual_chat_messages", Column("modelBProvider", "TEXT", notNull = true, defaultValue = "''"))
        ensureColumn(db, "dual_chat_messages", Column("timestamp", "INTEGER", notNull = true, defaultValue = "0"))
        ensureColumn(db, "dual_chat_messages", Column("modelAThinking", "TEXT"))
        ensureColumn(db, "dual_chat_messages", Column("modelBThinking", "TEXT"))
        ensureColumn(db, "dual_chat_messages", Column("attachments", "TEXT", notNull = true, defaultValue = "'[]'"))
    }

    private fun createAutoConversations(db: SupportSQLiteDatabase) {
        db.execSQL(
            """
            CREATE TABLE IF NOT EXISTS `auto_conversations` (
                `id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
                `title` TEXT NOT NULL,
                `modelA` TEXT NOT NULL,
                `modelB` TEXT NOT NULL,
                `providerA` TEXT NOT NULL,
                `providerB` TEXT NOT NULL,
                `systemPromptA` TEXT NOT NULL,
                `systemPromptB` TEXT NOT NULL,
                `status` TEXT NOT NULL DEFAULT 'ACTIVE',
                `maxTurns` INTEGER NOT NULL DEFAULT 20,
                `currentTurn` INTEGER NOT NULL DEFAULT 0,
                `createdAt` INTEGER NOT NULL DEFAULT 0,
                `lastActiveAt` INTEGER NOT NULL DEFAULT 0,
                `endReason` TEXT,
                `endSignal` TEXT NOT NULL DEFAULT '[END]',
                `boundChatConversationId` INTEGER
            )
            """.trimIndent()
        )
        ensureColumn(db, "auto_conversations", Column("status", "TEXT", notNull = true, defaultValue = "'ACTIVE'"))
        ensureColumn(db, "auto_conversations", Column("maxTurns", "INTEGER", notNull = true, defaultValue = "20"))
        ensureColumn(db, "auto_conversations", Column("currentTurn", "INTEGER", notNull = true, defaultValue = "0"))
        ensureColumn(db, "auto_conversations", Column("createdAt", "INTEGER", notNull = true, defaultValue = "0"))
        ensureColumn(db, "auto_conversations", Column("lastActiveAt", "INTEGER", notNull = true, defaultValue = "0"))
        ensureColumn(db, "auto_conversations", Column("endReason", "TEXT"))
        ensureColumn(db, "auto_conversations", Column("endSignal", "TEXT", notNull = true, defaultValue = "'[END]'"))
        ensureColumn(db, "auto_conversations", Column("boundChatConversationId", "INTEGER"))
    }

    private fun createAutoConversationMessages(db: SupportSQLiteDatabase) {
        db.execSQL(
            """
            CREATE TABLE IF NOT EXISTS `auto_conversation_messages` (
                `id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
                `autoConversationId` INTEGER NOT NULL,
                `turnNumber` INTEGER NOT NULL,
                `speakerModel` TEXT NOT NULL,
                `content` TEXT NOT NULL,
                `reasoning` TEXT,
                `timestamp` INTEGER NOT NULL DEFAULT 0,
                `isEndSignal` INTEGER NOT NULL DEFAULT 0
            )
            """.trimIndent()
        )
        ensureColumn(db, "auto_conversation_messages", Column("reasoning", "TEXT"))
        ensureColumn(db, "auto_conversation_messages", Column("timestamp", "INTEGER", notNull = true, defaultValue = "0"))
        ensureColumn(db, "auto_conversation_messages", Column("isEndSignal", "INTEGER", notNull = true, defaultValue = "0"))
    }

    private fun createTokenUsageRecords(db: SupportSQLiteDatabase) {
        db.execSQL(
            """
            CREATE TABLE IF NOT EXISTS `token_usage_records` (
                `id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
                `timestamp` INTEGER NOT NULL DEFAULT 0,
                `provider` TEXT NOT NULL,
                `model` TEXT NOT NULL,
                `requestType` TEXT NOT NULL DEFAULT 'chat',
                `conversationId` INTEGER,
                `inputTokens` INTEGER NOT NULL DEFAULT 0,
                `outputTokens` INTEGER NOT NULL DEFAULT 0,
                `totalTokens` INTEGER NOT NULL DEFAULT 0,
                `reasoningTokens` INTEGER,
                `cachedInputTokens` INTEGER,
                `costUsd` REAL,
                FOREIGN KEY(`conversationId`) REFERENCES `conversations`(`id`) ON DELETE SET NULL
            )
            """.trimIndent()
        )
        db.execSQL("CREATE INDEX IF NOT EXISTS `index_token_usage_records_timestamp` ON `token_usage_records`(`timestamp`)")
        db.execSQL("CREATE INDEX IF NOT EXISTS `index_token_usage_records_model_timestamp` ON `token_usage_records`(`model`, `timestamp`)")
        db.execSQL("CREATE INDEX IF NOT EXISTS `index_token_usage_records_conversationId` ON `token_usage_records`(`conversationId`)")
        ensureColumn(db, "token_usage_records", Column("requestType", "TEXT", notNull = true, defaultValue = "'chat'"))
        ensureColumn(db, "token_usage_records", Column("reasoningTokens", "INTEGER"))
        ensureColumn(db, "token_usage_records", Column("cachedInputTokens", "INTEGER"))
        ensureColumn(db, "token_usage_records", Column("costUsd", "REAL"))
    }

    private fun ensureColumn(db: SupportSQLiteDatabase, table: String, column: Column) {
        if (hasColumn(db, table, column.name)) {
            return
        }
        val builder = StringBuilder()
        builder.append("ALTER TABLE `").append(table).append("` ADD COLUMN `")
            .append(column.name).append("` ").append(column.type)
        if (column.notNull) {
            builder.append(" NOT NULL")
        }
        column.defaultValue?.let {
            builder.append(" DEFAULT ").append(it)
        }
        db.execSQL(builder.toString())
    }

    private fun hasColumn(db: SupportSQLiteDatabase, table: String, column: String): Boolean {
        db.query("PRAGMA table_info(`$table`)").use { cursor ->
            val nameIndex = cursor.getColumnIndex("name")
            while (cursor.moveToNext()) {
                if (cursor.getString(nameIndex) == column) {
                    return true
                }
            }
        }
        return false
    }

    private data class Column(
        val name: String,
        val type: String,
        val notNull: Boolean = false,
        val defaultValue: String? = null
    )
}

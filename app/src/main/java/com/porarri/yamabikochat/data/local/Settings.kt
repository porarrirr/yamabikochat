package com.porarri.yamabikochat.data.local

import androidx.room.Entity
import androidx.room.PrimaryKey
import com.google.gson.Gson
import com.google.gson.JsonParser
import com.porarri.yamabikochat.data.remote.ThinkingConfig
import com.porarri.yamabikochat.data.remote.CodexRequestConfig
import com.porarri.yamabikochat.data.remote.OpenCodeGoEndpointKind
import com.porarri.yamabikochat.data.remote.OpenCodeGoModelCatalog
import com.porarri.yamabikochat.data.remote.ProviderCatalog
import com.porarri.yamabikochat.utils.MiniMaxUtils
import com.porarri.yamabikochat.utils.ModelUtils
import com.porarri.yamabikochat.data.local.ModelPreset
import com.porarri.yamabikochat.utils.CodexModelPresets

@Entity(tableName = "settings")
data class Settings(
    @PrimaryKey
    val id: Int = 1,
    val defaultModel: String = "gemini-2.5-flash",
    val googleSearchEnabled: Boolean = false,
    val codeExecutionEnabled: Boolean = false,
    val thinkingEnabled: Boolean = false,
    val thinkingBudget: Int = 0,
    val systemPrompt: String? = null,
    val systemPromptPresets: String = "",
    val selectedSystemPromptPreset: String? = null,
    val isStreamingEnabled: Boolean = true,
    val apiProvider: String = "GEMINI", // GEMINI or OPENROUTER
    
    // Gemini専用設定
    val geminiGoogleSearchEnabled: Boolean = false,
    val geminiCodeExecutionEnabled: Boolean = false,
    val geminiUrlContextEnabled: Boolean = false,
    val geminiGoogleMapsEnabled: Boolean = false,
    val geminiComputerUseEnabled: Boolean = false,
    val geminiThinkingEnabled: Boolean = false,
    val geminiThinkingBudget: Int = 0,
    val geminiThinkingLevel: String = "",
    val geminiStreamingEnabled: Boolean = true,
    val geminiResponseMimeType: String = "",
    val geminiResponseJsonSchema: String = "",
    val geminiFunctionDeclarations: String = "",
    
    // OpenRouter専用設定
    val openRouterGoogleSearchEnabled: Boolean = false,
    val openRouterCodeExecutionEnabled: Boolean = false,
    val openRouterThinkingEnabled: Boolean = false,
    val openRouterThinkingBudget: Int = 0,
    val openRouterStreamingEnabled: Boolean = true,
    val openRouterReasoningMode: String = "auto", // auto | effort | budget     
    val openRouterReasoningEffort: String = "", // low | medium | high (effort mode only)
    val openRouterReasoningExclude: Boolean = false,
    val openRouterPinnedModels: String = "", // JSON形式でList<String>を保存
    val openRouterRecentModels: String = "", // JSON形式でList<String>を保存
    val dualOpenRouterThinkingEnabledA: Boolean? = null,
    val dualOpenRouterThinkingBudgetA: Int? = null,
    val dualOpenRouterReasoningModeA: String? = null,
    val dualOpenRouterReasoningEffortA: String? = null,
    val dualOpenRouterReasoningExcludeA: Boolean? = null,
    val dualOpenRouterThinkingEnabledB: Boolean? = null,
    val dualOpenRouterThinkingBudgetB: Int? = null,
    val dualOpenRouterReasoningModeB: String? = null,
    val dualOpenRouterReasoningEffortB: String? = null,
    val dualOpenRouterReasoningExcludeB: Boolean? = null,
    val autoOpenRouterThinkingEnabledA: Boolean? = null,
    val autoOpenRouterThinkingBudgetA: Int? = null,
    val autoOpenRouterReasoningModeA: String? = null,
    val autoOpenRouterReasoningEffortA: String? = null,
    val autoOpenRouterReasoningExcludeA: Boolean? = null,
    val autoOpenRouterThinkingEnabledB: Boolean? = null,
    val autoOpenRouterThinkingBudgetB: Int? = null,
    val autoOpenRouterReasoningModeB: String? = null,
    val autoOpenRouterReasoningEffortB: String? = null,
    val autoOpenRouterReasoningExcludeB: Boolean? = null,
    val dualGoogleSearchEnabledA: Boolean? = null,
    val dualCodeExecutionEnabledA: Boolean? = null,
    val dualUrlContextEnabledA: Boolean? = null,
    val dualGoogleMapsEnabledA: Boolean? = null,
    val dualComputerUseEnabledA: Boolean? = null,
    val dualThinkingEnabledA: Boolean? = null,
    val dualThinkingBudgetA: Int? = null,
    val dualThinkingLevelA: String? = null,
    val dualCodexReasoningEffortA: String? = null,
    val dualGoogleSearchEnabledB: Boolean? = null,
    val dualCodeExecutionEnabledB: Boolean? = null,
    val dualUrlContextEnabledB: Boolean? = null,
    val dualGoogleMapsEnabledB: Boolean? = null,
    val dualComputerUseEnabledB: Boolean? = null,
    val dualThinkingEnabledB: Boolean? = null,
    val dualThinkingBudgetB: Int? = null,
    val dualThinkingLevelB: String? = null,
    val dualCodexReasoningEffortB: String? = null,
    val autoGoogleSearchEnabledA: Boolean? = null,
    val autoCodeExecutionEnabledA: Boolean? = null,
    val autoUrlContextEnabledA: Boolean? = null,
    val autoGoogleMapsEnabledA: Boolean? = null,
    val autoComputerUseEnabledA: Boolean? = null,
    val autoThinkingEnabledA: Boolean? = null,
    val autoThinkingBudgetA: Int? = null,
    val autoThinkingLevelA: String? = null,
    val autoCodexReasoningEffortA: String? = null,
    val autoGoogleSearchEnabledB: Boolean? = null,
    val autoCodeExecutionEnabledB: Boolean? = null,
    val autoUrlContextEnabledB: Boolean? = null,
    val autoGoogleMapsEnabledB: Boolean? = null,
    val autoComputerUseEnabledB: Boolean? = null,
    val autoThinkingEnabledB: Boolean? = null,
    val autoThinkingBudgetB: Int? = null,
    val autoThinkingLevelB: String? = null,
    val autoCodexReasoningEffortB: String? = null,
    
    // デュアルモード設定
    val isDualModeEnabled: Boolean = false,
    val dualModelA: String = "gemini-2.5-flash",
    val dualModelB: String = "deepseek/deepseek-chat",
    val dualProviderA: String = "GEMINI",
    val dualProviderB: String = "OPENROUTER",
    val dualSplitLayout: String = "VERTICAL", // "VERTICAL" or "HORIZONTAL"
    val dualSplitRatio: Float = 0.5f,
    val dualSystemPromptA: String? = null,
    val dualSystemPromptB: String? = null,
    
    // 自動会話設定
    val isAutoConversationEnabled: Boolean = false,
    val autoModelA: String = "gemini-2.5-flash",
    val autoModelB: String = "deepseek/deepseek-chat",
    val autoProviderA: String = "GEMINI",
    val autoProviderB: String = "OPENROUTER",
    val autoSystemPromptA: String = "あなたは親しみやすい日本語AIアシスタントです。自然で温かみのある会話を心がけてください。",
    val autoSystemPromptB: String = "あなたは論理的で分析的なAIアシスタントです。深く考えながら詳細に回答してください。",
    val autoMaxTurns: Int = 20,
    
    // 数学表記の改善設定
    val mathRenderingEnabled: Boolean = true,
    // 外観設定
    val dynamicColorEnabled: Boolean = true,
    val themeColor: String = "BLUE_PURPLE",
    val themeMode: String = "SYSTEM", // SYSTEM | LIGHT | DARK

    // チャットUIのプリセットにグローバル設定を表示
    val showGlobalProviderPresetsInChat: Boolean = true,
    // チャットUIのプリセットにグローバル設定を表示（プロバイダーごとの上書き）
    // JSON形式でMap<String, Boolean>を保存（例: {"OPENAI": false}）
    val showGlobalProviderPresetsInChatByProvider: String = "",

    // プロバイダー選択設定
    val preferredProviders: String = "", // JSON形式でList<String>を保存        
    val selectedQuantizations: String = "", // JSON形式でList<String>を保存     
    val maxPricePerMillionTokens: Double = 0.0, // 0.0は無制限
    val allowFallbacks: Boolean = true,
    val requireParameters: Boolean = false,
    // OpenRouter拡張: プロバイダー選択上限（0=無制限）
    val providerSelectionMax: Int = 12,
    // OpenRouter拡張: 並べ替え（provider.sort）"price" | "throughput" | "latency"
    val providerSort: String = "price",
    val providerDefaultModels: String = "",

    // OpenAI base URL (override allowed)
    val openAiBaseUrl: String = "https://api.openai.com/v1/",

    // MiniMax base URL (OpenAI-compatible)
    val miniMaxBaseUrl: String = MiniMaxUtils.INTERNATIONAL_BASE_URL,

    // OpenAI-compatible endpoint presets (JSON list of OpenAiCompatPreset)     
    val openAiCompatPresets: String = "",
    val selectedOpenAiCompatPreset: String? = null,
    val alibabaMcpEnabled: Boolean = false,
    val alibabaMcpServerUrl: String = "",
    val alibabaMcpServerName: String = ProviderCatalog.alibabaMcpDefaultServerName,
    val alibabaMcpAllowedTools: String = "",

    // Codex Auth (OpenAI Responses API) reasoning settings
    val codexUserAgentPreset: String = "ANDROID",
    val codexReasoningEnabled: Boolean = true,
    val codexReasoningEffort: String = "medium",
    val codexReasoningSummary: String = "auto",
    val codexVerbosity: String = "medium",
    val codexSupportsReasoningSummaries: Boolean = false,
    val codexShowReasoningSummary: Boolean = true,
    val codexWebSearchEnabled: Boolean = false,
    val codexWebSearchContextSize: String = "medium",
    val codexPromptCacheEnabled: Boolean = true,
    val codexPromptCacheMinLength: Int = 512,
    val codexPromptCacheType: String = "ephemeral"
) {
    // 現在のAPIプロバイダーに基づいて設定を取得するヘルパー関数
    fun getCurrentGoogleSearchEnabled(): Boolean {
        return when (apiProvider.uppercase()) {
            "OPENROUTER" -> openRouterGoogleSearchEnabled
            "GEMINI" -> geminiGoogleSearchEnabled
            else -> false
        }
    }
    
    fun getCurrentCodeExecutionEnabled(): Boolean {
        return when (apiProvider.uppercase()) {
            "OPENROUTER" -> openRouterCodeExecutionEnabled
            "GEMINI" -> geminiCodeExecutionEnabled
            else -> false
        }
    }

    fun getCurrentUrlContextEnabled(): Boolean {
        return when (apiProvider.uppercase()) {
            "GEMINI" -> geminiUrlContextEnabled
            else -> false
        }
    }

    fun getCurrentGoogleMapsEnabled(): Boolean {
        return when (apiProvider.uppercase()) {
            "GEMINI" -> geminiGoogleMapsEnabled
            else -> false
        }
    }

    fun getCurrentComputerUseEnabled(): Boolean {
        return when (apiProvider.uppercase()) {
            "GEMINI" -> geminiComputerUseEnabled
            else -> false
        }
    }
    
    fun getCurrentThinkingEnabled(): Boolean {
        return when (apiProvider) {
            "OPENROUTER" -> openRouterThinkingEnabled
            else -> geminiThinkingEnabled
        }
    }
    
    fun getCurrentThinkingBudget(): Int {
        return when (apiProvider) {
            "OPENROUTER" -> openRouterThinkingBudget
            else -> geminiThinkingBudget
        }
    }

    fun getCurrentThinkingLevel(): String {
        return when (apiProvider) {
            "OPENROUTER" -> ""
            else -> geminiThinkingLevel
        }
    }
    
    fun getCurrentStreamingEnabled(): Boolean {
        return when (apiProvider) {
            "OPENROUTER" -> openRouterStreamingEnabled
            else -> geminiStreamingEnabled
        }
    }

    fun isGoogleSearchEnabledFor(provider: String, context: ReasoningContext? = null): Boolean {
        val override = when (context) {
            ReasoningContext.DUAL_A -> dualGoogleSearchEnabledA
            ReasoningContext.DUAL_B -> dualGoogleSearchEnabledB
            ReasoningContext.AUTO_A -> autoGoogleSearchEnabledA
            ReasoningContext.AUTO_B -> autoGoogleSearchEnabledB
            else -> null
        }
        if (override != null) return override
        return when (provider.uppercase()) {
            "OPENROUTER" -> openRouterGoogleSearchEnabled
            "GEMINI" -> geminiGoogleSearchEnabled
            else -> false
        }
    }

    fun isCodeExecutionEnabledFor(provider: String, context: ReasoningContext? = null): Boolean {
        val override = when (context) {
            ReasoningContext.DUAL_A -> dualCodeExecutionEnabledA
            ReasoningContext.DUAL_B -> dualCodeExecutionEnabledB
            ReasoningContext.AUTO_A -> autoCodeExecutionEnabledA
            ReasoningContext.AUTO_B -> autoCodeExecutionEnabledB
            else -> null
        }
        if (override != null) return override
        return when (provider.uppercase()) {
            "OPENROUTER" -> openRouterCodeExecutionEnabled
            "GEMINI" -> geminiCodeExecutionEnabled
            else -> false
        }
    }

    fun isUrlContextEnabledFor(provider: String, context: ReasoningContext? = null): Boolean {
        val override = when (context) {
            ReasoningContext.DUAL_A -> dualUrlContextEnabledA
            ReasoningContext.DUAL_B -> dualUrlContextEnabledB
            ReasoningContext.AUTO_A -> autoUrlContextEnabledA
            ReasoningContext.AUTO_B -> autoUrlContextEnabledB
            else -> null
        }
        if (override != null) return override
        return when (provider.uppercase()) {
            "GEMINI" -> geminiUrlContextEnabled
            else -> false
        }
    }

    fun isGoogleMapsEnabledFor(provider: String, context: ReasoningContext? = null): Boolean {
        val override = when (context) {
            ReasoningContext.DUAL_A -> dualGoogleMapsEnabledA
            ReasoningContext.DUAL_B -> dualGoogleMapsEnabledB
            ReasoningContext.AUTO_A -> autoGoogleMapsEnabledA
            ReasoningContext.AUTO_B -> autoGoogleMapsEnabledB
            else -> null
        }
        if (override != null) return override
        return when (provider.uppercase()) {
            "GEMINI" -> geminiGoogleMapsEnabled
            else -> false
        }
    }

    fun isComputerUseEnabledFor(provider: String, context: ReasoningContext? = null): Boolean {
        val override = when (context) {
            ReasoningContext.DUAL_A -> dualComputerUseEnabledA
            ReasoningContext.DUAL_B -> dualComputerUseEnabledB
            ReasoningContext.AUTO_A -> autoComputerUseEnabledA
            ReasoningContext.AUTO_B -> autoComputerUseEnabledB
            else -> null
        }
        if (override != null) return override
        return when (provider.uppercase()) {
            "GEMINI" -> geminiComputerUseEnabled
            else -> false
        }
    }

    fun isStreamingEnabledFor(provider: String): Boolean {
        return when (provider.uppercase()) {
            "CODEX_AUTH" -> true
            "OPENROUTER" -> openRouterStreamingEnabled
            else -> geminiStreamingEnabled
        }
    }

    fun getCurrentReasoningMode(): String {
        return when (apiProvider) {
            "OPENROUTER" -> openRouterReasoningMode
            else -> "auto"
        }
    }

    fun getCurrentReasoningEffort(): String? {
        return when (apiProvider) {
            "OPENROUTER" -> openRouterReasoningEffort.takeIf { it.isNotBlank() }
            else -> null
        }
    }

    fun shouldExcludeReasoning(): Boolean {
        return when (apiProvider) {
            "OPENROUTER" -> openRouterReasoningExclude
            else -> false
        }
    }

    fun isThinkingEnabledFor(provider: String): Boolean {
        return when (provider.uppercase()) {
            "OPENROUTER" -> openRouterThinkingEnabled
            else -> geminiThinkingEnabled
        }
    }

    fun thinkingBudgetFor(provider: String): Int {
        return when (provider.uppercase()) {
            "OPENROUTER" -> openRouterThinkingBudget
            else -> geminiThinkingBudget
        }
    }

    fun thinkingLevelFor(provider: String): String {
        return when (provider.uppercase()) {
            "OPENROUTER" -> ""
            else -> geminiThinkingLevel
        }
    }

    fun reasoningModeFor(provider: String): String {
        return when (provider.uppercase()) {
            "OPENROUTER" -> openRouterReasoningMode
            else -> "auto"
        }
    }

    fun reasoningEffortFor(provider: String): String? {
        return when (provider.uppercase()) {
            "OPENROUTER" -> openRouterReasoningEffort.takeIf { it.isNotBlank() }
            else -> null
        }
    }

    fun shouldExcludeReasoningFor(provider: String): Boolean {
        return when (provider.uppercase()) {
            "OPENROUTER" -> openRouterReasoningExclude
            else -> false
        }
    }

    fun buildThinkingConfigFor(
        provider: String,
        model: String,
        context: ReasoningContext = ReasoningContext.DEFAULT
    ): ThinkingConfig? {
        val overrides = when (context) {
            ReasoningContext.DUAL_A -> ThinkingOverrides(
                enabled = dualThinkingEnabledA,
                budget = dualThinkingBudgetA,
                level = dualThinkingLevelA,
                codexEffort = dualCodexReasoningEffortA
            )
            ReasoningContext.DUAL_B -> ThinkingOverrides(
                enabled = dualThinkingEnabledB,
                budget = dualThinkingBudgetB,
                level = dualThinkingLevelB,
                codexEffort = dualCodexReasoningEffortB
            )
            ReasoningContext.AUTO_A -> ThinkingOverrides(
                enabled = autoThinkingEnabledA,
                budget = autoThinkingBudgetA,
                level = autoThinkingLevelA,
                codexEffort = autoCodexReasoningEffortA
            )
            ReasoningContext.AUTO_B -> ThinkingOverrides(
                enabled = autoThinkingEnabledB,
                budget = autoThinkingBudgetB,
                level = autoThinkingLevelB,
                codexEffort = autoCodexReasoningEffortB
            )
            else -> null
        }
        return when (provider.uppercase()) {
            "OPENROUTER" -> {
                val profile = resolveOpenRouterProfile(
                    when (context) {
                        ReasoningContext.DUAL_A -> ReasoningOverrides(
                            enabled = dualOpenRouterThinkingEnabledA,
                            budget = dualOpenRouterThinkingBudgetA,
                            mode = dualOpenRouterReasoningModeA,
                            effort = dualOpenRouterReasoningEffortA,
                            exclude = dualOpenRouterReasoningExcludeA
                        )
                        ReasoningContext.DUAL_B -> ReasoningOverrides(
                            enabled = dualOpenRouterThinkingEnabledB,
                            budget = dualOpenRouterThinkingBudgetB,
                            mode = dualOpenRouterReasoningModeB,
                            effort = dualOpenRouterReasoningEffortB,
                            exclude = dualOpenRouterReasoningExcludeB
                        )
                        ReasoningContext.AUTO_A -> ReasoningOverrides(
                            enabled = autoOpenRouterThinkingEnabledA,
                            budget = autoOpenRouterThinkingBudgetA,
                            mode = autoOpenRouterReasoningModeA,
                            effort = autoOpenRouterReasoningEffortA,
                            exclude = autoOpenRouterReasoningExcludeA
                        )
                        ReasoningContext.AUTO_B -> ReasoningOverrides(
                            enabled = autoOpenRouterThinkingEnabledB,
                            budget = autoOpenRouterThinkingBudgetB,
                            mode = autoOpenRouterReasoningModeB,
                            effort = autoOpenRouterReasoningEffortB,
                            exclude = autoOpenRouterReasoningExcludeB
                        )
                        else -> null
                    }
                )
                buildOpenRouterThinkingConfig(profile)
            }
            "OPENAI", "OPENAI_COMPAT", "MINIMAX", "CLINEPASS" -> buildOpenAiThinkingConfig(
                model,
                enabledOverride = overrides?.enabled,
                budgetOverride = overrides?.budget
            )
            "OPENCODE_GO" -> when (OpenCodeGoModelCatalog.modelFor(model)?.endpointKind) {
                OpenCodeGoEndpointKind.MESSAGES -> buildAnthropicThinkingConfig(
                    enabledOverride = overrides?.enabled,
                    budgetOverride = overrides?.budget
                )
                OpenCodeGoEndpointKind.CHAT_COMPLETIONS -> buildOpenAiThinkingConfig(
                    model,
                    enabledOverride = overrides?.enabled,
                    budgetOverride = overrides?.budget
                )
                null -> null
            }
            "ALIBABA_CODING_PLAN" -> buildAnthropicThinkingConfig(
                enabledOverride = overrides?.enabled,
                budgetOverride = overrides?.budget
            )
            "CODEX_AUTH" -> buildCodexThinkingConfig(
                enabledOverride = overrides?.enabled,
                effortOverride = overrides?.codexEffort
            )
            "ZAI" -> buildZaiThinkingConfig(enabledOverride = overrides?.enabled)
            "GEMINI" -> buildGeminiThinkingConfig(
                model,
                enabledOverride = overrides?.enabled,
                budgetOverride = overrides?.budget,
                levelOverride = overrides?.level
            )
            else -> null
        }
    }

    private fun buildGeminiThinkingConfig(
        model: String,
        enabledOverride: Boolean? = null,
        budgetOverride: Int? = null,
        levelOverride: String? = null
    ): ThinkingConfig? {
        val enabled = enabledOverride ?: geminiThinkingEnabled
        val budget = budgetOverride ?: geminiThinkingBudget
        val level = levelOverride ?: geminiThinkingLevel
        if (ModelUtils.isThinkingLevelSupported(model)) {
            val defaultLevel = ModelUtils.getDefaultThinkingLevel(model)
            val normalized = ModelUtils.normalizeThinkingLevel(model, level) ?: defaultLevel
            val effectiveLevel = when {
                ModelUtils.isThinkingAlwaysOn(model) -> normalized
                !enabled -> ModelUtils.getMinimalThinkingLevel(model) ?: normalized
                else -> normalized
            }
            return ThinkingConfig(
                thinkingLevel = effectiveLevel,
                includeThoughts = true
            )
        }

        val effective = ModelUtils.calculateEffectiveThinkingBudget(
            model,
            enabled,
            budget
        ) ?: return null

        return ThinkingConfig(
            thinkingBudget = effective,
            includeThoughts = true
        )
    }

    private fun resolveOpenRouterProfile(overrides: ReasoningOverrides?): ReasoningProfile {
        val base = ReasoningProfile(
            enabled = openRouterThinkingEnabled,
            budget = openRouterThinkingBudget,
            mode = openRouterReasoningMode,
            effort = openRouterReasoningEffort,
            exclude = openRouterReasoningExclude
        )

        if (overrides == null) return base

        return base.copy(
            enabled = overrides.enabled ?: base.enabled,
            budget = overrides.budget ?: base.budget,
            mode = overrides.mode ?: base.mode,
            effort = overrides.effort ?: base.effort,
            exclude = overrides.exclude ?: base.exclude
        )
    }

    private fun buildOpenRouterThinkingConfig(profile: ReasoningProfile): ThinkingConfig? {
        val includeThoughts = !profile.exclude

        if (!profile.enabled) {
            return ThinkingConfig(
                thinkingBudget = null,
                includeThoughts = includeThoughts,
                enabled = false,
                exclude = true
            )
        }

        val mode = profile.mode.lowercase()
        val budget = if (mode == "budget" && profile.budget > 0) {
            profile.budget
        } else null
        val effort = if (mode == "effort") {
            profile.effort.takeIf { !it.isNullOrBlank() }
        } else null

        val enabledFlag = if (mode == "auto" || (budget == null && effort == null)) {
            true
        } else null

        val excludeFlag = if (profile.exclude) true else null

        if (budget == null && effort == null && enabledFlag == null && excludeFlag == null) {
            return null
        }

        return ThinkingConfig(
            thinkingBudget = budget,
            includeThoughts = includeThoughts,
            effort = effort,
            enabled = enabledFlag,
            exclude = excludeFlag
        )
    }

    private fun buildOpenAiThinkingConfig(
        model: String,
        enabledOverride: Boolean? = null,
        budgetOverride: Int? = null
    ): ThinkingConfig? {
        // For OpenAI Chat Completions, map thinkingBudget to max_tokens (or max_completion_tokens for reasoning models).
        // Use the app's generic thinkingEnabled/thinkingBudget (Gemini fields) as the source when provider is OPENAI.
        val enabled = enabledOverride ?: geminiThinkingEnabled
        val budget = budgetOverride ?: geminiThinkingBudget
        if (!enabled && budget <= 0) return null
        val effective = if (enabled) budget else 0
        return ThinkingConfig(
            thinkingBudget = effective,
            includeThoughts = true
        )
    }

    private fun buildZaiThinkingConfig(enabledOverride: Boolean? = null): ThinkingConfig? {
        val enabled = enabledOverride ?: geminiThinkingEnabled
        return ThinkingConfig(
            enabled = enabled
        )
    }

    private fun buildAnthropicThinkingConfig(
        enabledOverride: Boolean? = null,
        budgetOverride: Int? = null
    ): ThinkingConfig? {
        val enabled = enabledOverride ?: geminiThinkingEnabled
        val budget = budgetOverride ?: geminiThinkingBudget
        if (!enabled) return null
        return ThinkingConfig(
            thinkingBudget = budget,
            includeThoughts = true,
            enabled = true
        )
    }

    private fun buildCodexThinkingConfig(
        enabledOverride: Boolean? = null,
        effortOverride: String? = null
    ): ThinkingConfig? {
        val enabled = enabledOverride ?: codexReasoningEnabled
        val effort = if (enabled) {
            (effortOverride ?: codexReasoningEffort).trim().lowercase().ifBlank { "medium" }
        } else {
            "none"
        }
        return ThinkingConfig(
            effort = effort,
            includeThoughts = true
        )
    }

    private data class ThinkingOverrides(
        val enabled: Boolean?,
        val budget: Int?,
        val level: String?,
        val codexEffort: String?
    )

    fun buildCodexRequestConfig(model: String): CodexRequestConfig? {
        val normalizedSummary = codexReasoningSummary.trim().lowercase().ifBlank { "auto" }
        val summaryRequested = normalizedSummary.takeIf { it != "none" && codexReasoningEnabled }
        val supportsSummaries = codexSupportsReasoningSummaries || CodexModelPresets.supportsReasoningSummary(model)
        val summaryToSend = if (supportsSummaries) summaryRequested else null

        val normalizedVerbosity = codexVerbosity.trim().lowercase().ifBlank { "medium" }
        val verbosityToSend = if (CodexModelPresets.supportsTextVerbosity(model)) normalizedVerbosity else null

        val webSearchEnabled = codexWebSearchEnabled
        val normalizedContextSize = codexWebSearchContextSize.trim().lowercase().ifBlank { "medium" }
        val webSearchContextSize = if (webSearchEnabled) normalizedContextSize else null

        val promptCacheEnabled = codexPromptCacheEnabled
        val promptCacheMinLength = codexPromptCacheMinLength.takeIf { it > 0 }
        val promptCacheType = codexPromptCacheType.trim().lowercase().ifBlank { "ephemeral" }

        return CodexRequestConfig(
            reasoningSummary = summaryToSend,
            verbosity = verbosityToSend,
            webSearchEnabled = webSearchEnabled,
            webSearchContextSize = webSearchContextSize,
            promptCacheEnabled = promptCacheEnabled,
            promptCacheMinLength = promptCacheMinLength,
            promptCacheType = promptCacheType
        )
    }
    
    fun getCurrentModel(): String {
        return getModelForProvider(apiProvider)
    }

    fun getProviderModels(): Map<String, String> {
        return providerModelMap()
    }

    fun buildGlobalProviderPresets(includeSystemPrompt: Boolean = false): List<ModelPreset> {
        val models = getProviderModels()
        if (models.isEmpty()) return emptyList()

        val preferredOrder = listOf(
            "GEMINI",
            "OPENROUTER",
            "OPENCODE_GO",
            "CLINEPASS",
            "ALIBABA_CODING_PLAN",
            "ZAI",
            "MINIMAX",
            "OPENAI",
            "CODEX_AUTH",
            "OPENAI_COMPAT"
        )
        val orderedProviders = preferredOrder.filter { models.containsKey(it) } +
            models.keys.filterNot { preferredOrder.contains(it) }.sorted()

        return orderedProviders.mapIndexedNotNull { index, provider ->
            val modelName = models[provider].orEmpty().ifBlank { getModelForProvider(provider) }
            if (modelName.isBlank()) return@mapIndexedNotNull null

            val providerKey = provider.uppercase()
            val isOpenRouter = providerKey == "OPENROUTER"
            val isGemini = providerKey == "GEMINI"
            val isCodex = providerKey == "CODEX_AUTH"
            val isOpenAiCompat = providerKey == "OPENAI_COMPAT"
            val resolvedPrompt = if (includeSystemPrompt) {
                resolveSelectedSystemPromptPreset()?.prompt ?: systemPrompt
            } else {
                null
            }
            val normalizedCodexSummary = codexReasoningSummary.ifBlank { "auto" }
            val normalizedCodexVerbosity = codexVerbosity.ifBlank { "medium" }
            val normalizedCodexSearchContext = codexWebSearchContextSize.ifBlank { "medium" }
            val normalizedCodexCacheType = codexPromptCacheType.ifBlank { "ephemeral" }
            ModelPreset(
                id = -(index + 1).toLong(),
                name = "グローバル: ${ProviderCatalog.displayName(provider)}",
                model = modelName,
                systemPrompt = resolvedPrompt,
                systemPromptPresetName = if (includeSystemPrompt) selectedSystemPromptPreset else null,
                thinkingEnabled = if (isOpenRouter) openRouterThinkingEnabled else geminiThinkingEnabled,
                thinkingBudget = if (isOpenRouter) openRouterThinkingBudget else geminiThinkingBudget,
                thinkingLevel = if (isOpenRouter) "" else geminiThinkingLevel,
                googleSearchEnabled = isGoogleSearchEnabledFor(provider),
                codeExecutionEnabled = isCodeExecutionEnabledFor(provider),
                urlContextEnabled = isUrlContextEnabledFor(provider),
                googleMapsEnabled = isGoogleMapsEnabledFor(provider),
                computerUseEnabled = isComputerUseEnabledFor(provider),
                responseMimeType = if (isGemini) geminiResponseMimeType else "",
                responseJsonSchema = if (isGemini) geminiResponseJsonSchema else "",
                functionDeclarations = if (isGemini) geminiFunctionDeclarations else "",
                apiProvider = provider,
                reasoningMode = if (isOpenRouter) openRouterReasoningMode else "auto",
                reasoningEffort = if (isOpenRouter) openRouterReasoningEffort else "",
                reasoningExclude = if (isOpenRouter) openRouterReasoningExclude else false,
                codexReasoningSummary = if (isCodex) normalizedCodexSummary else "auto",
                codexVerbosity = if (isCodex) normalizedCodexVerbosity else "medium",
                codexWebSearchEnabled = if (isCodex) codexWebSearchEnabled else false,
                codexWebSearchContextSize = if (isCodex) normalizedCodexSearchContext else "medium",
                codexPromptCacheEnabled = if (isCodex) codexPromptCacheEnabled else true,
                codexPromptCacheMinLength = if (isCodex) codexPromptCacheMinLength else 512,
                codexPromptCacheType = if (isCodex) normalizedCodexCacheType else "ephemeral",
                codexShowReasoningSummary = if (isCodex) codexShowReasoningSummary else true,
                codexSupportsReasoningSummaries = if (isCodex) codexSupportsReasoningSummaries else false,
                openAiCompatPresetName = if (isOpenAiCompat) selectedOpenAiCompatPreset else null
            )
        }
    }

    fun getShowGlobalProviderPresetsInChatByProviderMap(): Map<String, Boolean> {
        if (showGlobalProviderPresetsInChatByProvider.isBlank()) return emptyMap()
        val parsed = parseStringKeyedBooleanMap(showGlobalProviderPresetsInChatByProvider)
        if (parsed.isEmpty()) return emptyMap()
        return parsed.mapKeys { (key, _) -> key.uppercase() }
    }

    fun shouldShowGlobalProviderPresetInChat(provider: String): Boolean {
        val normalized = provider.uppercase()
        val overrides = getShowGlobalProviderPresetsInChatByProviderMap()
        return overrides[normalized] ?: showGlobalProviderPresetsInChat
    }

    fun getModelForProvider(provider: String): String {
        val normalized = provider.uppercase()
        val models = providerModelMap()
        return models[normalized] ?: defaultModel
    }

    fun remapRemovedProviders(): Settings {
        fun remap(provider: String): String = when (provider.uppercase()) {
            "GEMINI_AUTH" -> "GEMINI"
            "QWEN_CODE" -> "OPENROUTER"
            else -> provider.uppercase()
        }

        val legacyRemovedKeys = setOf("GEMINI_AUTH", "QWEN_CODE")
        val remappedModels = linkedMapOf<String, String>()
        providerModelMap().forEach { (key, value) ->
            val newKey = remap(key)
            if (key.uppercase() in legacyRemovedKeys) {
                remappedModels[newKey] = value
            } else if (!remappedModels.containsKey(newKey)) {
                remappedModels[newKey] = value
            }
        }
        val remappedProviderDefaultModels = if (remappedModels.isEmpty()) {
            providerDefaultModels
        } else {
            gson.toJson(remappedModels)
        }

        val remappedVisibility = linkedMapOf<String, Boolean>()
        getShowGlobalProviderPresetsInChatByProviderMap().forEach { (key, value) ->
            remappedVisibility[remap(key)] = value
        }
        val remappedVisibilityJson = if (remappedVisibility.isEmpty()) {
            showGlobalProviderPresetsInChatByProvider
        } else {
            gson.toJson(remappedVisibility)
        }

        return copy(
            apiProvider = remap(apiProvider),
            dualProviderA = remap(dualProviderA),
            dualProviderB = remap(dualProviderB),
            autoProviderA = remap(autoProviderA),
            autoProviderB = remap(autoProviderB),
            providerDefaultModels = remappedProviderDefaultModels,
            showGlobalProviderPresetsInChatByProvider = remappedVisibilityJson
        )
    }

    fun withModelForProvider(
        provider: String,
        model: String,
        additionalModels: Map<String, String> = emptyMap(),
        previousProvider: String? = null,
        previousModel: String? = null
    ): Settings {
        val updated = providerModelMap().toMutableMap()

        val previousNormalized = previousProvider?.uppercase()
        val previousValue = previousModel?.takeIf { it.isNotBlank() }
        if (previousNormalized != null && previousValue != null) {
            updated[previousNormalized] = previousValue
        }

        additionalModels.forEach { (key, value) ->
            val normalizedKey = key.uppercase()
            val normalizedValue = value.trim()
            if (normalizedValue.isNotBlank()) {
                updated[normalizedKey] = normalizedValue
            }
        }

        val normalized = provider.uppercase()
        updated[normalized] = model

        val shouldUpdateDefault = apiProvider.equals(provider, ignoreCase = true)

        return copy(
            defaultModel = if (shouldUpdateDefault) model else defaultModel,
            providerDefaultModels = gson.toJson(updated)
        )
    }
    // プロバイダー設定用のヘルパー関数
    fun getPreferredProvidersList(): List<String> {
        return if (preferredProviders.isBlank()) {
            emptyList()
        } else {
            try {
                com.google.gson.Gson().fromJson(preferredProviders, Array<String>::class.java).toList()
            } catch (e: Exception) {
                emptyList()
            }
        }
    }

    fun getOpenRouterPinnedModelsList(): List<String> {
        return parseStringList(openRouterPinnedModels)
    }

    fun getOpenRouterRecentModelsList(): List<String> {
        return parseStringList(openRouterRecentModels)
    }
    private fun providerModelMap(): Map<String, String> {
        val parsed = parseStringKeyedStringMap(providerDefaultModels)

        val currentProvider = apiProvider.uppercase()
        val currentModel = defaultModel.takeIf { it.isNotBlank() }
        return if (!parsed.containsKey(currentProvider) && currentModel != null) {
            parsed + (currentProvider to currentModel)
        } else {
            parsed
        }
    }

    companion object {
        private val gson = Gson()

        private fun parseStringKeyedStringMap(json: String): Map<String, String> {
            if (json.isBlank()) return emptyMap()
            val obj = try {
                JsonParser().parse(json).asJsonObject
            } catch (_: Exception) {
                return emptyMap()
            }

            val result = mutableMapOf<String, String>()
            for (entry in obj.entrySet()) {
                val value = entry.value
                if (!value.isJsonPrimitive) continue

                val primitive = value.asJsonPrimitive
                if (!primitive.isString) continue
                result[entry.key] = primitive.asString
            }
            return result
        }

        private fun parseStringKeyedBooleanMap(json: String): Map<String, Boolean> {
            if (json.isBlank()) return emptyMap()
            val obj = try {
                JsonParser().parse(json).asJsonObject
            } catch (_: Exception) {
                return emptyMap()
            }

            val result = mutableMapOf<String, Boolean>()
            for (entry in obj.entrySet()) {
                val value = entry.value
                if (!value.isJsonPrimitive) continue

                val primitive = value.asJsonPrimitive
                val parsed = when {
                    primitive.isBoolean -> primitive.asBoolean
                    primitive.isString -> when (primitive.asString.trim().lowercase()) {
                        "true" -> true
                        "false" -> false
                        else -> null
                    }
                    else -> null
                } ?: continue

                result[entry.key] = parsed
            }
            return result
        }
    }

    fun getSelectedQuantizationsList(): List<String> {
        return if (selectedQuantizations.isBlank()) {
            emptyList()
        } else {
            try {
                com.google.gson.Gson().fromJson(selectedQuantizations, Array<String>::class.java).toList()
            } catch (e: Exception) {
                emptyList()
            }
        }
    }
    
    fun createProviderPreferences(): com.porarri.yamabikochat.data.remote.ProviderPreferences? {
        val providers = getPreferredProvidersList()
        val quantizations = getSelectedQuantizationsList()

        if (providers.isEmpty() && quantizations.isEmpty() && maxPricePerMillionTokens == 0.0) {
            return null
        }
        
        // If a single provider is selected and fallbacks are not allowed, prefer strict routing via `only`
        val onlyProviders = if (!allowFallbacks && providers.size == 1) providers else null
        val orderProviders = if (onlyProviders == null) providers.takeIf { it.isNotEmpty() } else null

        val maxPrice = if (maxPricePerMillionTokens > 0.0) {
            // Apply same cap to prompt and completion (USD per 1M tokens)
            com.porarri.yamabikochat.data.remote.MaxPrice(
                prompt = maxPricePerMillionTokens,
                completion = maxPricePerMillionTokens
            )
        } else null

        return com.porarri.yamabikochat.data.remote.ProviderPreferences(
            order = orderProviders,
            only = onlyProviders,
            quantizations = quantizations.takeIf { it.isNotEmpty() },
            max_price = maxPrice,
            allow_fallbacks = allowFallbacks.takeIf { providers.isNotEmpty() },
            require_parameters = requireParameters.takeIf { it },
            sort = providerSort.takeIf { it.isNotBlank() }
        )
    }

    // --- OpenAI-compatible helpers ---
    fun getOpenAiCompatPresetsList(): List<com.porarri.yamabikochat.data.remote.OpenAiCompatPreset> {
        return if (openAiCompatPresets.isBlank()) emptyList() else try {
            com.google.gson.Gson().fromJson(
                openAiCompatPresets,
                Array<com.porarri.yamabikochat.data.remote.OpenAiCompatPreset>::class.java
            ).toList()
        } catch (e: Exception) { emptyList() }
    }

    fun getSystemPromptPresetsList(): List<SystemPromptPreset> {
        return if (systemPromptPresets.isBlank()) emptyList() else try {
            gson.fromJson(systemPromptPresets, Array<SystemPromptPreset>::class.java)?.toList() ?: emptyList()
        } catch (e: Exception) { emptyList() }
    }

    private fun parseStringList(json: String): List<String> {
        if (json.isBlank()) return emptyList()
        return try {
            gson.fromJson(json, Array<String>::class.java)?.toList() ?: emptyList()
        } catch (_: Exception) {
            emptyList()
        }
    }

    fun resolveSelectedSystemPromptPreset(): SystemPromptPreset? {
        val selected = selectedSystemPromptPreset ?: return null
        return getSystemPromptPresetsList().firstOrNull { it.name.equals(selected, ignoreCase = true) }
    }

    fun resolveSelectedCompatBaseUrl(): String? {
        val sel = selectedOpenAiCompatPreset ?: return null
        return getOpenAiCompatPresetsList().firstOrNull { it.name.equals(sel, ignoreCase = true) }?.baseUrl
    }

    fun resolvedAlibabaMcpServerUrl(): String? {
        val raw = alibabaMcpServerUrl.trim()
        if (raw.isBlank()) return null
        val uri = runCatching { java.net.URI(raw) }.getOrNull() ?: return null
        if (!uri.scheme.equals("https", ignoreCase = true)) return null
        if (uri.host.isNullOrBlank()) return null
        if (!uri.userInfo.isNullOrBlank()) return null
        return uri.toString()
    }

    fun resolvedAlibabaMcpServerName(): String =
        alibabaMcpServerName.trim().ifBlank { ProviderCatalog.alibabaMcpDefaultServerName }

    fun alibabaMcpAllowedToolsList(): List<String> =
        alibabaMcpAllowedTools
            .lineSequence()
            .flatMap { it.split(",").asSequence() }
            .map { it.trim() }
            .filter { it.isNotEmpty() }
            .distinctBy { it.lowercase() }
            .toList()

    enum class ReasoningContext {
        DEFAULT,
        DUAL_A,
        DUAL_B,
        AUTO_A,
        AUTO_B
    }

    private data class ReasoningProfile(
        val enabled: Boolean,
        val budget: Int,
        val mode: String,
        val effort: String,
        val exclude: Boolean
    )

    private data class ReasoningOverrides(
        val enabled: Boolean? = null,
        val budget: Int? = null,
        val mode: String? = null,
        val effort: String? = null,
        val exclude: Boolean? = null
    )
}

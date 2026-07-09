package com.porarri.yamabikochat.ui.settings

import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import com.porarri.yamabikochat.data.local.ModelPreset
import com.porarri.yamabikochat.data.local.Settings
import com.porarri.yamabikochat.data.local.SystemPromptPreset
import com.porarri.yamabikochat.data.remote.ModelEndpoint
import com.porarri.yamabikochat.data.remote.OpenAiCompatPreset
import com.porarri.yamabikochat.data.remote.ProviderCatalog
import com.porarri.yamabikochat.data.remote.ProviderDirectory
import com.porarri.yamabikochat.data.remote.SimpleModel
import com.porarri.yamabikochat.ui.settings.sections.ModelPresetDialogState
import com.porarri.yamabikochat.ui.settings.sections.ReasoningOverrideUiState
import com.porarri.yamabikochat.ui.settings.sections.ThinkingOverrideUiState
import com.porarri.yamabikochat.ui.settings.sections.ToolingOverrideUiState
import com.porarri.yamabikochat.ui.theme.ThemeColorPreset
import com.porarri.yamabikochat.utils.MiniMaxUtils
import com.porarri.yamabikochat.utils.CodexModelPresets
import com.porarri.yamabikochat.utils.ModelUtils
import kotlin.math.roundToInt

@Stable
class SettingsScreenState(
    private val viewModel: SettingsViewModel
) {
    var apiKeyInput by mutableStateOf("")
    var model by mutableStateOf("")
    var googleSearchEnabled by mutableStateOf(false)
    var codeExecutionEnabled by mutableStateOf(false)
    var urlContextEnabled by mutableStateOf(false)
    var googleMapsEnabled by mutableStateOf(false)
    var computerUseEnabled by mutableStateOf(false)
    var thinkingEnabled by mutableStateOf(false)
    var thinkingBudget by mutableFloatStateOf(0f)
    var thinkingLevel by mutableStateOf("")
    var responseMimeType by mutableStateOf("")
    var responseJsonSchema by mutableStateOf("")
    var functionDeclarations by mutableStateOf("")
    var reasoningMode by mutableStateOf("auto")
    var reasoningEffort by mutableStateOf("")
    var reasoningExclude by mutableStateOf(false)
    var codexUserAgentPreset by mutableStateOf("ANDROID")
    var codexReasoningEnabled by mutableStateOf(true)
    var codexReasoningEffort by mutableStateOf("medium")
    var codexReasoningSummary by mutableStateOf("auto")
    var codexVerbosity by mutableStateOf("medium")
    var codexSupportsReasoningSummaries by mutableStateOf(false)
    var codexShowReasoningSummary by mutableStateOf(true)
    var codexWebSearchEnabled by mutableStateOf(false)
    var codexWebSearchContextSize by mutableStateOf("medium")
    var codexPromptCacheEnabled by mutableStateOf(true)
    var codexPromptCacheMinLength by mutableIntStateOf(512)
    var codexPromptCacheType by mutableStateOf("ephemeral")
    var superGrokReasoningEnabled by mutableStateOf(true)
    var superGrokReasoningEffort by mutableStateOf("medium")
    var systemPrompt by mutableStateOf("")
    var systemPromptPresetName by mutableStateOf("")
    val systemPromptPresetsLocal = mutableStateListOf<SystemPromptPreset>()
    var selectedSystemPromptPresetLocal by mutableStateOf<String?>(null)
    var isStreamingEnabled by mutableStateOf(true)
    var apiProvider by mutableStateOf("GEMINI")
    val providerModels = mutableStateMapOf<String, String>()

    var openRouterApiKeyInput by mutableStateOf("")
    var openAiApiKeyInput by mutableStateOf("")
    var miniMaxApiKeyInput by mutableStateOf("")
    var openAiCompatApiKeyInput by mutableStateOf("")
    var zaiApiKeyInput by mutableStateOf("")
    var openCodeGoApiKeyInput by mutableStateOf("")
    var clinePassApiKeyInput by mutableStateOf("")
    var alibabaCodingPlanApiKeyInput by mutableStateOf("")
    var alibabaMcpAuthorizationTokenInput by mutableStateOf("")

    var geminiKeyVisible by mutableStateOf(false)
    var openRouterKeyVisible by mutableStateOf(false)
    var openAiKeyVisible by mutableStateOf(false)
    var miniMaxKeyVisible by mutableStateOf(false)
    var openAiCompatKeyVisible by mutableStateOf(false)
    var zaiKeyVisible by mutableStateOf(false)
    var openCodeGoKeyVisible by mutableStateOf(false)
    var clinePassKeyVisible by mutableStateOf(false)
    var alibabaCodingPlanKeyVisible by mutableStateOf(false)
    var alibabaMcpTokenVisible by mutableStateOf(false)

    var geminiKeyLoadedFromStorage by mutableStateOf(false)
    var openRouterKeyLoadedFromStorage by mutableStateOf(false)
    var openAiKeyLoadedFromStorage by mutableStateOf(false)
    var miniMaxKeyLoadedFromStorage by mutableStateOf(false)
    var openAiCompatKeyLoadedFromStorage by mutableStateOf(false)
    var zaiKeyLoadedFromStorage by mutableStateOf(false)
    var openCodeGoKeyLoadedFromStorage by mutableStateOf(false)
    var clinePassKeyLoadedFromStorage by mutableStateOf(false)
    var alibabaCodingPlanKeyLoadedFromStorage by mutableStateOf(false)
    var alibabaMcpTokenLoadedFromStorage by mutableStateOf(false)

    var geminiKeyDirty by mutableStateOf(false)
    var openRouterKeyDirty by mutableStateOf(false)
    var openAiKeyDirty by mutableStateOf(false)
    var miniMaxKeyDirty by mutableStateOf(false)
    var openAiCompatKeyDirty by mutableStateOf(false)
    var zaiKeyDirty by mutableStateOf(false)
    var openCodeGoKeyDirty by mutableStateOf(false)
    var clinePassKeyDirty by mutableStateOf(false)
    var alibabaCodingPlanKeyDirty by mutableStateOf(false)
    var alibabaMcpTokenDirty by mutableStateOf(false)

    // OpenAI base URL & OpenAI-compatible preset editing
    var openAiBaseUrl by mutableStateOf("https://api.openai.com/v1/")
    var miniMaxBaseUrl by mutableStateOf(MiniMaxUtils.INTERNATIONAL_BASE_URL)
    var compatPresetName by mutableStateOf("")
    var compatPresetBaseUrl by mutableStateOf("")
    val openAiCompatPresetsLocal = mutableStateListOf<OpenAiCompatPreset>()     
    var selectedOpenAiCompatPresetLocal by mutableStateOf<String?>(null)
    var alibabaMcpEnabled by mutableStateOf(false)
    var alibabaMcpServerUrl by mutableStateOf("")
    var alibabaMcpServerName by mutableStateOf(ProviderCatalog.alibabaMcpDefaultServerName)
    var alibabaMcpAllowedTools by mutableStateOf("")

    // プロバイダー選択状態
    var selectedProvider by mutableStateOf<String?>(null)

    // 高度なプロバイダー設定
    var preferredProviders by mutableStateOf<List<String>>(emptyList())
    var selectedQuantizations by mutableStateOf<List<String>>(emptyList())
    var maxPrice by mutableFloatStateOf(0f)
    var allowFallbacks by mutableStateOf(true)
    var requireParameters by mutableStateOf(false)
    var advancedSettingsExpanded by mutableStateOf(false)
    var providerSelectionMax by mutableIntStateOf(12)
    var providerSort by mutableStateOf("price") // price | throughput | latency

    // デュアルモード設定
    var isDualModeEnabled by mutableStateOf(false)
    var dualModelA by mutableStateOf("gemini-2.5-flash")
    var dualModelB by mutableStateOf("deepseek/deepseek-chat")
    var dualProviderA by mutableStateOf("GEMINI")
    var dualProviderB by mutableStateOf("OPENROUTER")
    var dualSplitLayout by mutableStateOf("VERTICAL")
    var dualSplitRatio by mutableFloatStateOf(0.5f)
    var dualSystemPromptA by mutableStateOf<String?>(null)
    var dualSystemPromptB by mutableStateOf<String?>(null)
    var dualReasonOverrideA by mutableStateOf(false)
    var dualReasonEnabledA by mutableStateOf(true)
    var dualReasonModeA by mutableStateOf("auto")
    var dualReasonEffortA by mutableStateOf("medium")
    var dualReasonExcludeA by mutableStateOf(false)
    var dualReasonBudgetA by mutableFloatStateOf(0f)
    var dualReasonOverrideB by mutableStateOf(false)
    var dualReasonEnabledB by mutableStateOf(true)
    var dualReasonModeB by mutableStateOf("auto")
    var dualReasonEffortB by mutableStateOf("medium")
    var dualReasonExcludeB by mutableStateOf(false)
    var dualReasonBudgetB by mutableFloatStateOf(0f)
    var dualToolsOverrideA by mutableStateOf(false)
    var dualGoogleSearchEnabledA by mutableStateOf(false)
    var dualCodeExecutionEnabledA by mutableStateOf(false)
    var dualUrlContextEnabledA by mutableStateOf(false)
    var dualGoogleMapsEnabledA by mutableStateOf(false)
    var dualComputerUseEnabledA by mutableStateOf(false)
    var dualThinkingOverrideA by mutableStateOf(false)
    var dualThinkingEnabledA by mutableStateOf(false)
    var dualThinkingBudgetA by mutableFloatStateOf(0f)
    var dualThinkingLevelA by mutableStateOf("")
    var dualCodexReasoningEffortA by mutableStateOf("medium")
    var dualToolsOverrideB by mutableStateOf(false)
    var dualGoogleSearchEnabledB by mutableStateOf(false)
    var dualCodeExecutionEnabledB by mutableStateOf(false)
    var dualUrlContextEnabledB by mutableStateOf(false)
    var dualGoogleMapsEnabledB by mutableStateOf(false)
    var dualComputerUseEnabledB by mutableStateOf(false)
    var dualThinkingOverrideB by mutableStateOf(false)
    var dualThinkingEnabledB by mutableStateOf(false)
    var dualThinkingBudgetB by mutableFloatStateOf(0f)
    var dualThinkingLevelB by mutableStateOf("")
    var dualCodexReasoningEffortB by mutableStateOf("medium")

    // デュアルモード用プロバイダー選択状態
    var dualSelectedProviderA by mutableStateOf<String?>(null)
    var dualSelectedProviderB by mutableStateOf<String?>(null)

    // 自動会話設定
    var isAutoConversationEnabled by mutableStateOf(false)
    var autoModelA by mutableStateOf("gemini-2.5-flash")
    var autoModelB by mutableStateOf("deepseek/deepseek-chat")
    var autoProviderA by mutableStateOf("GEMINI")
    var autoProviderB by mutableStateOf("OPENROUTER")
    var autoSystemPromptA by mutableStateOf("あなたは親しみやすい日本語AIアシスタントです。自然で温かみのある会話を心がけてください。")
    var autoSystemPromptB by mutableStateOf("あなたは論理的で分析的なAIアシスタントです。深く考えながら詳細に回答してください。")
    var autoMaxTurns by mutableIntStateOf(20)
    var autoReasonOverrideA by mutableStateOf(false)
    var autoReasonEnabledA by mutableStateOf(true)
    var autoReasonModeA by mutableStateOf("auto")
    var autoReasonEffortA by mutableStateOf("medium")
    var autoReasonExcludeA by mutableStateOf(false)
    var autoReasonBudgetA by mutableFloatStateOf(0f)
    var autoReasonOverrideB by mutableStateOf(false)
    var autoReasonEnabledB by mutableStateOf(true)
    var autoReasonModeB by mutableStateOf("auto")
    var autoReasonEffortB by mutableStateOf("medium")
    var autoReasonExcludeB by mutableStateOf(false)
    var autoReasonBudgetB by mutableFloatStateOf(0f)
    var autoToolsOverrideA by mutableStateOf(false)
    var autoGoogleSearchEnabledA by mutableStateOf(false)
    var autoCodeExecutionEnabledA by mutableStateOf(false)
    var autoUrlContextEnabledA by mutableStateOf(false)
    var autoGoogleMapsEnabledA by mutableStateOf(false)
    var autoComputerUseEnabledA by mutableStateOf(false)
    var autoThinkingOverrideA by mutableStateOf(false)
    var autoThinkingEnabledA by mutableStateOf(false)
    var autoThinkingBudgetA by mutableFloatStateOf(0f)
    var autoThinkingLevelA by mutableStateOf("")
    var autoCodexReasoningEffortA by mutableStateOf("medium")
    var autoToolsOverrideB by mutableStateOf(false)
    var autoGoogleSearchEnabledB by mutableStateOf(false)
    var autoCodeExecutionEnabledB by mutableStateOf(false)
    var autoUrlContextEnabledB by mutableStateOf(false)
    var autoGoogleMapsEnabledB by mutableStateOf(false)
    var autoComputerUseEnabledB by mutableStateOf(false)
    var autoThinkingOverrideB by mutableStateOf(false)
    var autoThinkingEnabledB by mutableStateOf(false)
    var autoThinkingBudgetB by mutableFloatStateOf(0f)
    var autoThinkingLevelB by mutableStateOf("")
    var autoCodexReasoningEffortB by mutableStateOf("medium")

    // 自動会話用プロバイダー選択状態
    var autoSelectedProviderA by mutableStateOf<String?>(null)
    var autoSelectedProviderB by mutableStateOf<String?>(null)

    // モデル依存のダイナミック情報（OpenRouter）
    var dynamicProviders by mutableStateOf<List<String>>(emptyList())
    var dynamicQuantizations by mutableStateOf<List<String>>(emptyList())
    var modelEndpoints by mutableStateOf<List<ModelEndpoint>>(emptyList())
    var providerDirectory by mutableStateOf(ProviderDirectory.EMPTY)

    // 数学表記の改善設定
    var mathRenderingEnabled by mutableStateOf(true)
    var dynamicColorEnabled by mutableStateOf(true)
    var themeColor by mutableStateOf(ThemeColorPreset.BluePurple.key)
    var themeMode by mutableStateOf("SYSTEM")
    var showGlobalProviderPresetsInChat by mutableStateOf(true)
    val showGlobalProviderPresetsInChatByProvider = mutableStateMapOf<String, Boolean>()

    // プリセット関連
    var showPresetDialog by mutableStateOf(false)
    var isEditingPreset by mutableStateOf(false)
    var editingPresetId by mutableStateOf(0L)
    var presetName by mutableStateOf("")
    var presetModel by mutableStateOf("")
    var presetSystemPrompt by mutableStateOf("")
    var presetSystemPromptPresetName by mutableStateOf<String?>(null)
    var presetThinkingEnabled by mutableStateOf(false)
    var presetThinkingBudget by mutableFloatStateOf(0f)
    var presetThinkingLevel by mutableStateOf("")
    var presetGoogleSearchEnabled by mutableStateOf(false)
    var presetCodeExecutionEnabled by mutableStateOf(false)
    var presetUrlContextEnabled by mutableStateOf(false)
    var presetGoogleMapsEnabled by mutableStateOf(false)
    var presetComputerUseEnabled by mutableStateOf(false)
    var presetResponseMimeType by mutableStateOf("")
    var presetResponseJsonSchema by mutableStateOf("")
    var presetFunctionDeclarations by mutableStateOf("")
    var presetApiProvider by mutableStateOf("GEMINI")
    var presetApiKey by mutableStateOf("")
    var presetReasoningMode by mutableStateOf("auto")
    var presetReasoningEffort by mutableStateOf("")
    var presetReasoningExclude by mutableStateOf(false)
    var presetCodexReasoningSummary by mutableStateOf("auto")
    var presetCodexVerbosity by mutableStateOf("medium")
    var presetCodexWebSearchEnabled by mutableStateOf(false)
    var presetCodexWebSearchContextSize by mutableStateOf("medium")
    var presetCodexPromptCacheEnabled by mutableStateOf(true)
    var presetCodexPromptCacheMinLength by mutableIntStateOf(512)
    var presetCodexPromptCacheType by mutableStateOf("ephemeral")
    var presetCodexShowReasoningSummary by mutableStateOf(true)
    var presetCodexSupportsReasoningSummaries by mutableStateOf(false)
    var presetOpenAiCompatPresetName by mutableStateOf<String?>(null)
    var presetSelectedProvider by mutableStateOf<String?>(null)

    // OpenRouter models shared across sections
    var openRouterModels by mutableStateOf<List<SimpleModel>>(emptyList())      
    var openRouterModelsLoading by mutableStateOf(false)
    var openRouterModelsError by mutableStateOf<String?>(null)
    var openRouterPinnedModels by mutableStateOf<List<String>>(emptyList())
    var openRouterRecentModels by mutableStateOf<List<String>>(emptyList())

    private var latestSettings: Settings? = null
    private val openRouterRecentLimit = 5

    fun switchApiProvider(newProvider: String) {
        val currentProviderKey = apiProvider.uppercase()
        val currentModel = model.trim()
        if (currentModel.isNotBlank()) {
            providerModels[currentProviderKey] = currentModel
        } else {
            providerModels.remove(currentProviderKey)
        }

        apiProvider = newProvider

        val nextProviderKey = newProvider.uppercase()
        model = providerModels[nextProviderKey]
            ?: latestSettings?.getModelForProvider(newProvider)
            ?: ""
        if (nextProviderKey == "MINIMAX" && model.isBlank()) {
            model = "MiniMax-M2.1"
        }
        if (nextProviderKey == "CODEX_AUTH" && model.isBlank()) {
            model = com.porarri.yamabikochat.utils.CodexModelPresets.defaultModel()
        }
        if (nextProviderKey == "SUPERGROK" && model.isBlank()) {
            model = com.porarri.yamabikochat.data.remote.SuperGrokModelCatalog.defaultModel
        }
        if (model.isBlank()) {
            model = ProviderCatalog.defaultModel(nextProviderKey)
        }
    }

    private fun resolveGlobalReasoningDefaults(source: Settings? = latestSettings): ReasoningBaseline {
        val enabled = source?.openRouterThinkingEnabled ?: true
        val budget = source?.openRouterThinkingBudget ?: 0
        val mode = source?.openRouterReasoningMode ?: "auto"
        val effort = (source?.openRouterReasoningEffort ?: "medium").ifBlank { "medium" }
        val exclude = source?.openRouterReasoningExclude ?: false
        return ReasoningBaseline(enabled, budget, mode, effort, exclude)
    }

    fun applyDualDefaultsA(source: Settings? = latestSettings) {
        val global = resolveGlobalReasoningDefaults(source)
        dualReasonEnabledA = source?.dualOpenRouterThinkingEnabledA ?: global.enabled
        dualReasonBudgetA = (source?.dualOpenRouterThinkingBudgetA ?: global.budget).toFloat()
        dualReasonModeA = source?.dualOpenRouterReasoningModeA ?: global.mode
        dualReasonEffortA = (source?.dualOpenRouterReasoningEffortA ?: global.effort).ifBlank { "medium" }
        dualReasonExcludeA = source?.dualOpenRouterReasoningExcludeA ?: global.exclude
    }

    fun applyDualDefaultsB(source: Settings? = latestSettings) {
        val global = resolveGlobalReasoningDefaults(source)
        dualReasonEnabledB = source?.dualOpenRouterThinkingEnabledB ?: global.enabled
        dualReasonBudgetB = (source?.dualOpenRouterThinkingBudgetB ?: global.budget).toFloat()
        dualReasonModeB = source?.dualOpenRouterReasoningModeB ?: global.mode
        dualReasonEffortB = (source?.dualOpenRouterReasoningEffortB ?: global.effort).ifBlank { "medium" }
        dualReasonExcludeB = source?.dualOpenRouterReasoningExcludeB ?: global.exclude
    }

    fun applyAutoDefaultsA(source: Settings? = latestSettings) {
        val global = resolveGlobalReasoningDefaults(source)
        autoReasonEnabledA = source?.autoOpenRouterThinkingEnabledA ?: global.enabled
        autoReasonBudgetA = (source?.autoOpenRouterThinkingBudgetA ?: global.budget).toFloat()
        autoReasonModeA = source?.autoOpenRouterReasoningModeA ?: global.mode
        autoReasonEffortA = (source?.autoOpenRouterReasoningEffortA ?: global.effort).ifBlank { "medium" }
        autoReasonExcludeA = source?.autoOpenRouterReasoningExcludeA ?: global.exclude
    }

    fun applyAutoDefaultsB(source: Settings? = latestSettings) {
        val global = resolveGlobalReasoningDefaults(source)
        autoReasonEnabledB = source?.autoOpenRouterThinkingEnabledB ?: global.enabled
        autoReasonBudgetB = (source?.autoOpenRouterThinkingBudgetB ?: global.budget).toFloat()
        autoReasonModeB = source?.autoOpenRouterReasoningModeB ?: global.mode
        autoReasonEffortB = (source?.autoOpenRouterReasoningEffortB ?: global.effort).ifBlank { "medium" }
        autoReasonExcludeB = source?.autoOpenRouterReasoningExcludeB ?: global.exclude
    }

    private fun resolveToolDefaults(provider: String, source: Settings?): ToolDefaults {
        val defaults = source ?: return ToolDefaults()
        return ToolDefaults(
            googleSearchEnabled = defaults.isGoogleSearchEnabledFor(provider),
            codeExecutionEnabled = defaults.isCodeExecutionEnabledFor(provider),
            urlContextEnabled = defaults.isUrlContextEnabledFor(provider),
            googleMapsEnabled = defaults.isGoogleMapsEnabledFor(provider),
            computerUseEnabled = defaults.isComputerUseEnabledFor(provider)
        )
    }

    private fun resolveThinkingDefaults(provider: String, source: Settings?): ThinkingDefaults {
        val defaults = source ?: return ThinkingDefaults()
        return when (provider.uppercase()) {
            "CODEX_AUTH" -> ThinkingDefaults(
                enabled = defaults.codexReasoningEnabled,
                budget = 0,
                level = "",
                codexEffort = defaults.codexReasoningEffort.ifBlank { "medium" }
            )
            "SUPERGROK" -> ThinkingDefaults(
                enabled = defaults.superGrokReasoningEnabled,
                budget = 0,
                level = "",
                codexEffort = defaults.superGrokReasoningEffort.ifBlank { "medium" }
            )
            else -> ThinkingDefaults(
                enabled = defaults.isThinkingEnabledFor(provider),
                budget = defaults.thinkingBudgetFor(provider),
                level = defaults.thinkingLevelFor(provider),
                codexEffort = "medium"
            )
        }
    }

    fun applyDualToolDefaultsA(source: Settings? = latestSettings, useOverrides: Boolean = true) {
        val global = resolveToolDefaults(dualProviderA, source)
        dualGoogleSearchEnabledA = if (useOverrides) source?.dualGoogleSearchEnabledA ?: global.googleSearchEnabled else global.googleSearchEnabled
        dualCodeExecutionEnabledA = if (useOverrides) source?.dualCodeExecutionEnabledA ?: global.codeExecutionEnabled else global.codeExecutionEnabled
        dualUrlContextEnabledA = if (useOverrides) source?.dualUrlContextEnabledA ?: global.urlContextEnabled else global.urlContextEnabled
        dualGoogleMapsEnabledA = if (useOverrides) source?.dualGoogleMapsEnabledA ?: global.googleMapsEnabled else global.googleMapsEnabled
        dualComputerUseEnabledA = if (useOverrides) source?.dualComputerUseEnabledA ?: global.computerUseEnabled else global.computerUseEnabled
    }

    fun applyDualToolDefaultsB(source: Settings? = latestSettings, useOverrides: Boolean = true) {
        val global = resolveToolDefaults(dualProviderB, source)
        dualGoogleSearchEnabledB = if (useOverrides) source?.dualGoogleSearchEnabledB ?: global.googleSearchEnabled else global.googleSearchEnabled
        dualCodeExecutionEnabledB = if (useOverrides) source?.dualCodeExecutionEnabledB ?: global.codeExecutionEnabled else global.codeExecutionEnabled
        dualUrlContextEnabledB = if (useOverrides) source?.dualUrlContextEnabledB ?: global.urlContextEnabled else global.urlContextEnabled
        dualGoogleMapsEnabledB = if (useOverrides) source?.dualGoogleMapsEnabledB ?: global.googleMapsEnabled else global.googleMapsEnabled
        dualComputerUseEnabledB = if (useOverrides) source?.dualComputerUseEnabledB ?: global.computerUseEnabled else global.computerUseEnabled
    }

    fun applyAutoToolDefaultsA(source: Settings? = latestSettings, useOverrides: Boolean = true) {
        val global = resolveToolDefaults(autoProviderA, source)
        autoGoogleSearchEnabledA = if (useOverrides) source?.autoGoogleSearchEnabledA ?: global.googleSearchEnabled else global.googleSearchEnabled
        autoCodeExecutionEnabledA = if (useOverrides) source?.autoCodeExecutionEnabledA ?: global.codeExecutionEnabled else global.codeExecutionEnabled
        autoUrlContextEnabledA = if (useOverrides) source?.autoUrlContextEnabledA ?: global.urlContextEnabled else global.urlContextEnabled
        autoGoogleMapsEnabledA = if (useOverrides) source?.autoGoogleMapsEnabledA ?: global.googleMapsEnabled else global.googleMapsEnabled
        autoComputerUseEnabledA = if (useOverrides) source?.autoComputerUseEnabledA ?: global.computerUseEnabled else global.computerUseEnabled
    }

    fun applyAutoToolDefaultsB(source: Settings? = latestSettings, useOverrides: Boolean = true) {
        val global = resolveToolDefaults(autoProviderB, source)
        autoGoogleSearchEnabledB = if (useOverrides) source?.autoGoogleSearchEnabledB ?: global.googleSearchEnabled else global.googleSearchEnabled
        autoCodeExecutionEnabledB = if (useOverrides) source?.autoCodeExecutionEnabledB ?: global.codeExecutionEnabled else global.codeExecutionEnabled
        autoUrlContextEnabledB = if (useOverrides) source?.autoUrlContextEnabledB ?: global.urlContextEnabled else global.urlContextEnabled
        autoGoogleMapsEnabledB = if (useOverrides) source?.autoGoogleMapsEnabledB ?: global.googleMapsEnabled else global.googleMapsEnabled
        autoComputerUseEnabledB = if (useOverrides) source?.autoComputerUseEnabledB ?: global.computerUseEnabled else global.computerUseEnabled
    }

    fun applyDualThinkingDefaultsA(source: Settings? = latestSettings, useOverrides: Boolean = true) {
        val global = resolveThinkingDefaults(dualProviderA, source)
        dualThinkingEnabledA = if (useOverrides) source?.dualThinkingEnabledA ?: global.enabled else global.enabled
        dualThinkingBudgetA = (if (useOverrides) source?.dualThinkingBudgetA ?: global.budget else global.budget).toFloat()
        dualThinkingLevelA = if (useOverrides) source?.dualThinkingLevelA ?: global.level else global.level
        dualCodexReasoningEffortA = if (useOverrides) source?.dualCodexReasoningEffortA ?: global.codexEffort else global.codexEffort
    }

    fun applyDualThinkingDefaultsB(source: Settings? = latestSettings, useOverrides: Boolean = true) {
        val global = resolveThinkingDefaults(dualProviderB, source)
        dualThinkingEnabledB = if (useOverrides) source?.dualThinkingEnabledB ?: global.enabled else global.enabled
        dualThinkingBudgetB = (if (useOverrides) source?.dualThinkingBudgetB ?: global.budget else global.budget).toFloat()
        dualThinkingLevelB = if (useOverrides) source?.dualThinkingLevelB ?: global.level else global.level
        dualCodexReasoningEffortB = if (useOverrides) source?.dualCodexReasoningEffortB ?: global.codexEffort else global.codexEffort
    }

    fun applyAutoThinkingDefaultsA(source: Settings? = latestSettings, useOverrides: Boolean = true) {
        val global = resolveThinkingDefaults(autoProviderA, source)
        autoThinkingEnabledA = if (useOverrides) source?.autoThinkingEnabledA ?: global.enabled else global.enabled
        autoThinkingBudgetA = (if (useOverrides) source?.autoThinkingBudgetA ?: global.budget else global.budget).toFloat()
        autoThinkingLevelA = if (useOverrides) source?.autoThinkingLevelA ?: global.level else global.level
        autoCodexReasoningEffortA = if (useOverrides) source?.autoCodexReasoningEffortA ?: global.codexEffort else global.codexEffort
    }

    fun applyAutoThinkingDefaultsB(source: Settings? = latestSettings, useOverrides: Boolean = true) {
        val global = resolveThinkingDefaults(autoProviderB, source)
        autoThinkingEnabledB = if (useOverrides) source?.autoThinkingEnabledB ?: global.enabled else global.enabled
        autoThinkingBudgetB = (if (useOverrides) source?.autoThinkingBudgetB ?: global.budget else global.budget).toFloat()
        autoThinkingLevelB = if (useOverrides) source?.autoThinkingLevelB ?: global.level else global.level
        autoCodexReasoningEffortB = if (useOverrides) source?.autoCodexReasoningEffortB ?: global.codexEffort else global.codexEffort
    }

    fun applySettings(currentSettingsState: Settings?) {
        val previousSettings = latestSettings
        latestSettings = currentSettingsState
        if (currentSettingsState != null && previousSettings != null) {
            val onlyPinnedRecentChanged = previousSettings.copy(
                openRouterPinnedModels = currentSettingsState.openRouterPinnedModels,
                openRouterRecentModels = currentSettingsState.openRouterRecentModels
            ) == currentSettingsState
            if (onlyPinnedRecentChanged) {
                openRouterPinnedModels = currentSettingsState.getOpenRouterPinnedModelsList()
                openRouterRecentModels = currentSettingsState.getOpenRouterRecentModelsList()
                return
            }
        }
        currentSettingsState?.let { settingsState ->
            providerModels.clear()
            providerModels.putAll(settingsState.getProviderModels())
            val promptPresets = settingsState.getSystemPromptPresetsList()
            systemPromptPresetsLocal.clear()
            systemPromptPresetsLocal.addAll(promptPresets)
            val selectedPreset = settingsState.selectedSystemPromptPreset
                ?.takeIf { name -> promptPresets.any { it.name.equals(name, ignoreCase = true) } }
            val preset = selectedPreset?.let { name ->
                promptPresets.firstOrNull { it.name.equals(name, ignoreCase = true) }
            }
            selectedSystemPromptPresetLocal = selectedPreset
            systemPrompt = settingsState.systemPrompt ?: preset?.prompt.orEmpty()
            systemPromptPresetName = preset?.name ?: systemPromptPresetName
            apiProvider = settingsState.apiProvider
            model = settingsState.getModelForProvider(apiProvider)
            if (apiProvider == "MINIMAX" && model.isBlank()) {
                model = "MiniMax-M2.1"
            }
            openAiCompatPresetsLocal.clear()
            openAiCompatPresetsLocal.addAll(settingsState.getOpenAiCompatPresetsList())
            selectedOpenAiCompatPresetLocal = settingsState.selectedOpenAiCompatPreset

            // API鍵の入力状態をリセット（セキュア表示の都度読み込み）
            apiKeyInput = ""
            openRouterApiKeyInput = ""
            openAiApiKeyInput = ""
            miniMaxApiKeyInput = ""
            openAiCompatApiKeyInput = ""
            zaiApiKeyInput = ""
            openCodeGoApiKeyInput = ""
            clinePassApiKeyInput = ""
            alibabaCodingPlanApiKeyInput = ""
            alibabaMcpAuthorizationTokenInput = ""
            geminiKeyDirty = false
            openRouterKeyDirty = false
            openAiKeyDirty = false
            miniMaxKeyDirty = false
            openAiCompatKeyDirty = false
            zaiKeyDirty = false
            openCodeGoKeyDirty = false
            clinePassKeyDirty = false
            alibabaCodingPlanKeyDirty = false
            alibabaMcpTokenDirty = false
            geminiKeyVisible = false
            openRouterKeyVisible = false
            openAiKeyVisible = false
            miniMaxKeyVisible = false
            openAiCompatKeyVisible = false
            zaiKeyVisible = false
            openCodeGoKeyVisible = false
            clinePassKeyVisible = false
            alibabaCodingPlanKeyVisible = false
            alibabaMcpTokenVisible = false
            geminiKeyLoadedFromStorage = false
            openRouterKeyLoadedFromStorage = false
            openAiKeyLoadedFromStorage = false
            miniMaxKeyLoadedFromStorage = false
            openAiCompatKeyLoadedFromStorage = false
            zaiKeyLoadedFromStorage = false
            openCodeGoKeyLoadedFromStorage = false
            clinePassKeyLoadedFromStorage = false
            alibabaCodingPlanKeyLoadedFromStorage = false
            alibabaMcpTokenLoadedFromStorage = false

            // APIプロバイダーに基づいて適切な設定を読み込み
            googleSearchEnabled = settingsState.getCurrentGoogleSearchEnabled()
            codeExecutionEnabled = settingsState.getCurrentCodeExecutionEnabled()
            urlContextEnabled = settingsState.getCurrentUrlContextEnabled()
            googleMapsEnabled = settingsState.getCurrentGoogleMapsEnabled()
            computerUseEnabled = settingsState.getCurrentComputerUseEnabled()
            thinkingEnabled = settingsState.getCurrentThinkingEnabled()
            thinkingBudget = settingsState.getCurrentThinkingBudget().toFloat()
            thinkingLevel = settingsState.getCurrentThinkingLevel()
            isStreamingEnabled = settingsState.getCurrentStreamingEnabled()
            reasoningMode = settingsState.openRouterReasoningMode
            reasoningEffort = settingsState.openRouterReasoningEffort
            reasoningExclude = settingsState.openRouterReasoningExclude
            codexUserAgentPreset = settingsState.codexUserAgentPreset.ifBlank { "ANDROID" }
            responseMimeType = settingsState.geminiResponseMimeType
            responseJsonSchema = settingsState.geminiResponseJsonSchema
            functionDeclarations = settingsState.geminiFunctionDeclarations

            // デュアルモード設定を読み込み
            isDualModeEnabled = settingsState.isDualModeEnabled
            dualModelA = settingsState.dualModelA
            dualModelB = settingsState.dualModelB
            dualProviderA = settingsState.dualProviderA
            dualProviderB = settingsState.dualProviderB
            dualSplitLayout = settingsState.dualSplitLayout
            dualSplitRatio = settingsState.dualSplitRatio
            dualSystemPromptA = settingsState.dualSystemPromptA
            dualSystemPromptB = settingsState.dualSystemPromptB

            // 自動会話設定を読み込み
            isAutoConversationEnabled = settingsState.isAutoConversationEnabled
            autoModelA = settingsState.autoModelA
            autoModelB = settingsState.autoModelB
            autoProviderA = settingsState.autoProviderA
            autoProviderB = settingsState.autoProviderB
            autoSystemPromptA = settingsState.autoSystemPromptA
            autoSystemPromptB = settingsState.autoSystemPromptB
            autoMaxTurns = settingsState.autoMaxTurns

            // 数学表記の改善設定を読み込み
            mathRenderingEnabled = settingsState.mathRenderingEnabled
            dynamicColorEnabled = settingsState.dynamicColorEnabled
            themeColor = ThemeColorPreset.fromKey(settingsState.themeColor).key
            themeMode = settingsState.themeMode
            showGlobalProviderPresetsInChat = settingsState.showGlobalProviderPresetsInChat
            showGlobalProviderPresetsInChatByProvider.clear()
            showGlobalProviderPresetsInChatByProvider.putAll(
                settingsState.getShowGlobalProviderPresetsInChatByProviderMap()
            )

            // プロバイダー設定を読み込み
            preferredProviders = settingsState.getPreferredProvidersList()
            selectedQuantizations = settingsState.getSelectedQuantizationsList()
            maxPrice = settingsState.maxPricePerMillionTokens.toFloat()
            allowFallbacks = settingsState.allowFallbacks
            requireParameters = settingsState.requireParameters
            providerSelectionMax = settingsState.providerSelectionMax
            providerSort = settingsState.providerSort
            openAiBaseUrl = settingsState.openAiBaseUrl.ifBlank { "https://api.openai.com/v1/" }
            miniMaxBaseUrl = settingsState.miniMaxBaseUrl.ifBlank { MiniMaxUtils.INTERNATIONAL_BASE_URL }
            alibabaMcpEnabled = settingsState.alibabaMcpEnabled
            alibabaMcpServerUrl = settingsState.alibabaMcpServerUrl
            alibabaMcpServerName = settingsState.alibabaMcpServerName.ifBlank {
                ProviderCatalog.alibabaMcpDefaultServerName
            }
            alibabaMcpAllowedTools = settingsState.alibabaMcpAllowedTools
            openRouterPinnedModels = settingsState.getOpenRouterPinnedModelsList()
            openRouterRecentModels = settingsState.getOpenRouterRecentModelsList()

            fun resolveOverrideState(
                enabled: Boolean?,
                budget: Int?,
                mode: String?,
                effort: String?,
                exclude: Boolean?
            ): Boolean {
                return enabled != null || budget != null || mode != null || effort != null || exclude != null
            }

            fun resolveToolOverrideState(
                googleSearch: Boolean?,
                codeExecution: Boolean?,
                urlContext: Boolean?,
                googleMaps: Boolean?,
                computerUse: Boolean?
            ): Boolean {
                return googleSearch != null ||
                    codeExecution != null ||
                    urlContext != null ||
                    googleMaps != null ||
                    computerUse != null
            }

            fun resolveThinkingOverrideState(
                enabled: Boolean?,
                budget: Int?,
                level: String?,
                codexEffort: String?
            ): Boolean {
                return enabled != null || budget != null || !level.isNullOrBlank() || !codexEffort.isNullOrBlank()
            }

            dualReasonOverrideA = resolveOverrideState(
                settingsState.dualOpenRouterThinkingEnabledA,
                settingsState.dualOpenRouterThinkingBudgetA,
                settingsState.dualOpenRouterReasoningModeA,
                settingsState.dualOpenRouterReasoningEffortA,
                settingsState.dualOpenRouterReasoningExcludeA
            )
            applyDualDefaultsA(settingsState)

            dualReasonOverrideB = resolveOverrideState(
                settingsState.dualOpenRouterThinkingEnabledB,
                settingsState.dualOpenRouterThinkingBudgetB,
                settingsState.dualOpenRouterReasoningModeB,
                settingsState.dualOpenRouterReasoningEffortB,
                settingsState.dualOpenRouterReasoningExcludeB
            )
            applyDualDefaultsB(settingsState)

            autoReasonOverrideA = resolveOverrideState(
                settingsState.autoOpenRouterThinkingEnabledA,
                settingsState.autoOpenRouterThinkingBudgetA,
                settingsState.autoOpenRouterReasoningModeA,
                settingsState.autoOpenRouterReasoningEffortA,
                settingsState.autoOpenRouterReasoningExcludeA
            )
            applyAutoDefaultsA(settingsState)

            autoReasonOverrideB = resolveOverrideState(
                settingsState.autoOpenRouterThinkingEnabledB,
                settingsState.autoOpenRouterThinkingBudgetB,
                settingsState.autoOpenRouterReasoningModeB,
                settingsState.autoOpenRouterReasoningEffortB,
                settingsState.autoOpenRouterReasoningExcludeB
            )
            applyAutoDefaultsB(settingsState)

            dualToolsOverrideA = resolveToolOverrideState(
                settingsState.dualGoogleSearchEnabledA,
                settingsState.dualCodeExecutionEnabledA,
                settingsState.dualUrlContextEnabledA,
                settingsState.dualGoogleMapsEnabledA,
                settingsState.dualComputerUseEnabledA
            )
            applyDualToolDefaultsA(settingsState)

            dualToolsOverrideB = resolveToolOverrideState(
                settingsState.dualGoogleSearchEnabledB,
                settingsState.dualCodeExecutionEnabledB,
                settingsState.dualUrlContextEnabledB,
                settingsState.dualGoogleMapsEnabledB,
                settingsState.dualComputerUseEnabledB
            )
            applyDualToolDefaultsB(settingsState)

            autoToolsOverrideA = resolveToolOverrideState(
                settingsState.autoGoogleSearchEnabledA,
                settingsState.autoCodeExecutionEnabledA,
                settingsState.autoUrlContextEnabledA,
                settingsState.autoGoogleMapsEnabledA,
                settingsState.autoComputerUseEnabledA
            )
            applyAutoToolDefaultsA(settingsState)

            autoToolsOverrideB = resolveToolOverrideState(
                settingsState.autoGoogleSearchEnabledB,
                settingsState.autoCodeExecutionEnabledB,
                settingsState.autoUrlContextEnabledB,
                settingsState.autoGoogleMapsEnabledB,
                settingsState.autoComputerUseEnabledB
            )
            applyAutoToolDefaultsB(settingsState)

            dualThinkingOverrideA = resolveThinkingOverrideState(
                settingsState.dualThinkingEnabledA,
                settingsState.dualThinkingBudgetA,
                settingsState.dualThinkingLevelA,
                settingsState.dualCodexReasoningEffortA
            )
            applyDualThinkingDefaultsA(settingsState)

            dualThinkingOverrideB = resolveThinkingOverrideState(
                settingsState.dualThinkingEnabledB,
                settingsState.dualThinkingBudgetB,
                settingsState.dualThinkingLevelB,
                settingsState.dualCodexReasoningEffortB
            )
            applyDualThinkingDefaultsB(settingsState)

            autoThinkingOverrideA = resolveThinkingOverrideState(
                settingsState.autoThinkingEnabledA,
                settingsState.autoThinkingBudgetA,
                settingsState.autoThinkingLevelA,
                settingsState.autoCodexReasoningEffortA
            )
            applyAutoThinkingDefaultsA(settingsState)

            autoThinkingOverrideB = resolveThinkingOverrideState(
                settingsState.autoThinkingEnabledB,
                settingsState.autoThinkingBudgetB,
                settingsState.autoThinkingLevelB,
                settingsState.autoCodexReasoningEffortB
            )
            applyAutoThinkingDefaultsB(settingsState)
        }
    }

    fun buildUpdateRequest(): SettingsUpdateRequest {
        val dualEnabledAOverride = if (dualProviderA == "OPENROUTER" && dualReasonOverrideA) dualReasonEnabledA else null
        val dualBudgetAOverride = if (dualProviderA == "OPENROUTER" && dualReasonOverrideA) dualReasonBudgetA.roundToInt() else null
        val dualModeAOverride = if (dualProviderA == "OPENROUTER" && dualReasonOverrideA) dualReasonModeA else null
        val dualEffortAOverride = if (dualProviderA == "OPENROUTER" && dualReasonOverrideA && dualReasonModeA == "effort") dualReasonEffortA else null
        val dualExcludeAOverride = if (dualProviderA == "OPENROUTER" && dualReasonOverrideA) dualReasonExcludeA else null

        val dualEnabledBOverride = if (dualProviderB == "OPENROUTER" && dualReasonOverrideB) dualReasonEnabledB else null
        val dualBudgetBOverride = if (dualProviderB == "OPENROUTER" && dualReasonOverrideB) dualReasonBudgetB.roundToInt() else null
        val dualModeBOverride = if (dualProviderB == "OPENROUTER" && dualReasonOverrideB) dualReasonModeB else null
        val dualEffortBOverride = if (dualProviderB == "OPENROUTER" && dualReasonOverrideB && dualReasonModeB == "effort") dualReasonEffortB else null
        val dualExcludeBOverride = if (dualProviderB == "OPENROUTER" && dualReasonOverrideB) dualReasonExcludeB else null

        val autoEnabledAOverride = if (autoProviderA == "OPENROUTER" && autoReasonOverrideA) autoReasonEnabledA else null
        val autoBudgetAOverride = if (autoProviderA == "OPENROUTER" && autoReasonOverrideA) autoReasonBudgetA.roundToInt() else null
        val autoModeAOverride = if (autoProviderA == "OPENROUTER" && autoReasonOverrideA) autoReasonModeA else null
        val autoEffortAOverride = if (autoProviderA == "OPENROUTER" && autoReasonOverrideA && autoReasonModeA == "effort") autoReasonEffortA else null
        val autoExcludeAOverride = if (autoProviderA == "OPENROUTER" && autoReasonOverrideA) autoReasonExcludeA else null

        val autoEnabledBOverride = if (autoProviderB == "OPENROUTER" && autoReasonOverrideB) autoReasonEnabledB else null
        val autoBudgetBOverride = if (autoProviderB == "OPENROUTER" && autoReasonOverrideB) autoReasonBudgetB.roundToInt() else null
        val autoModeBOverride = if (autoProviderB == "OPENROUTER" && autoReasonOverrideB) autoReasonModeB else null
        val autoEffortBOverride = if (autoProviderB == "OPENROUTER" && autoReasonOverrideB && autoReasonModeB == "effort") autoReasonEffortB else null
        val autoExcludeBOverride = if (autoProviderB == "OPENROUTER" && autoReasonOverrideB) autoReasonExcludeB else null

        fun supportsGoogleSearch(provider: String): Boolean =
            provider.uppercase() == "GEMINI" || provider.uppercase() == "OPENROUTER"

        fun supportsCodeExecution(provider: String): Boolean =
            provider.uppercase() == "GEMINI" || provider.uppercase() == "OPENROUTER"

        fun supportsUrlContext(provider: String): Boolean =
            provider.uppercase() == "GEMINI"

        fun supportsGoogleMaps(provider: String): Boolean =
            provider.uppercase() == "GEMINI"

        fun supportsComputerUse(provider: String): Boolean =
            provider.uppercase() == "GEMINI"

        fun supportsThinkingLevel(provider: String, model: String): Boolean {
            val normalized = provider.uppercase()
            return (normalized == "GEMINI") &&
                ModelUtils.isThinkingLevelSupported(model)
        }

        fun supportsThinkingBudget(provider: String, model: String): Boolean {
            if (provider.uppercase() == "CODEX_AUTH" || provider.uppercase() == "SUPERGROK" || provider.uppercase() == "ZAI") {
                return false
            }
            return !supportsThinkingLevel(provider, model)
        }

        val dualToolOverrideAEnabled = dualToolsOverrideA
        val dualToolOverrideBEnabled = dualToolsOverrideB
        val autoToolOverrideAEnabled = autoToolsOverrideA
        val autoToolOverrideBEnabled = autoToolsOverrideB

        val dualThinkingOverrideAEnabled = dualThinkingOverrideA && dualProviderA.uppercase() != "OPENROUTER"
        val dualThinkingOverrideBEnabled = dualThinkingOverrideB && dualProviderB.uppercase() != "OPENROUTER"
        val autoThinkingOverrideAEnabled = autoThinkingOverrideA && autoProviderA.uppercase() != "OPENROUTER"
        val autoThinkingOverrideBEnabled = autoThinkingOverrideB && autoProviderB.uppercase() != "OPENROUTER"

        val dualGoogleSearchOverrideA = if (dualToolOverrideAEnabled && supportsGoogleSearch(dualProviderA)) dualGoogleSearchEnabledA else null
        val dualCodeExecutionOverrideA = if (dualToolOverrideAEnabled && supportsCodeExecution(dualProviderA)) dualCodeExecutionEnabledA else null
        val dualUrlContextOverrideA = if (dualToolOverrideAEnabled && supportsUrlContext(dualProviderA)) dualUrlContextEnabledA else null
        val dualGoogleMapsOverrideA = if (dualToolOverrideAEnabled && supportsGoogleMaps(dualProviderA)) dualGoogleMapsEnabledA else null
        val dualComputerUseOverrideA = if (dualToolOverrideAEnabled && supportsComputerUse(dualProviderA)) dualComputerUseEnabledA else null

        val dualGoogleSearchOverrideB = if (dualToolOverrideBEnabled && supportsGoogleSearch(dualProviderB)) dualGoogleSearchEnabledB else null
        val dualCodeExecutionOverrideB = if (dualToolOverrideBEnabled && supportsCodeExecution(dualProviderB)) dualCodeExecutionEnabledB else null
        val dualUrlContextOverrideB = if (dualToolOverrideBEnabled && supportsUrlContext(dualProviderB)) dualUrlContextEnabledB else null
        val dualGoogleMapsOverrideB = if (dualToolOverrideBEnabled && supportsGoogleMaps(dualProviderB)) dualGoogleMapsEnabledB else null
        val dualComputerUseOverrideB = if (dualToolOverrideBEnabled && supportsComputerUse(dualProviderB)) dualComputerUseEnabledB else null

        val autoGoogleSearchOverrideA = if (autoToolOverrideAEnabled && supportsGoogleSearch(autoProviderA)) autoGoogleSearchEnabledA else null
        val autoCodeExecutionOverrideA = if (autoToolOverrideAEnabled && supportsCodeExecution(autoProviderA)) autoCodeExecutionEnabledA else null
        val autoUrlContextOverrideA = if (autoToolOverrideAEnabled && supportsUrlContext(autoProviderA)) autoUrlContextEnabledA else null
        val autoGoogleMapsOverrideA = if (autoToolOverrideAEnabled && supportsGoogleMaps(autoProviderA)) autoGoogleMapsEnabledA else null
        val autoComputerUseOverrideA = if (autoToolOverrideAEnabled && supportsComputerUse(autoProviderA)) autoComputerUseEnabledA else null

        val autoGoogleSearchOverrideB = if (autoToolOverrideBEnabled && supportsGoogleSearch(autoProviderB)) autoGoogleSearchEnabledB else null
        val autoCodeExecutionOverrideB = if (autoToolOverrideBEnabled && supportsCodeExecution(autoProviderB)) autoCodeExecutionEnabledB else null
        val autoUrlContextOverrideB = if (autoToolOverrideBEnabled && supportsUrlContext(autoProviderB)) autoUrlContextEnabledB else null
        val autoGoogleMapsOverrideB = if (autoToolOverrideBEnabled && supportsGoogleMaps(autoProviderB)) autoGoogleMapsEnabledB else null
        val autoComputerUseOverrideB = if (autoToolOverrideBEnabled && supportsComputerUse(autoProviderB)) autoComputerUseEnabledB else null

        val dualThinkingEnabledOverrideA = if (dualThinkingOverrideAEnabled) dualThinkingEnabledA else null
        val dualThinkingBudgetOverrideA = if (dualThinkingOverrideAEnabled && supportsThinkingBudget(dualProviderA, dualModelA)) dualThinkingBudgetA.roundToInt() else null
        val dualThinkingLevelOverrideA = if (dualThinkingOverrideAEnabled && supportsThinkingLevel(dualProviderA, dualModelA)) {
            dualThinkingLevelA.takeIf { it.isNotBlank() }
        } else null
        val dualCodexEffortOverrideA = if (dualThinkingOverrideAEnabled &&
            (dualProviderA.uppercase() == "CODEX_AUTH" || dualProviderA.uppercase() == "SUPERGROK")
        ) {
            dualCodexReasoningEffortA.ifBlank { "medium" }
        } else null

        val dualThinkingEnabledOverrideB = if (dualThinkingOverrideBEnabled) dualThinkingEnabledB else null
        val dualThinkingBudgetOverrideB = if (dualThinkingOverrideBEnabled && supportsThinkingBudget(dualProviderB, dualModelB)) dualThinkingBudgetB.roundToInt() else null
        val dualThinkingLevelOverrideB = if (dualThinkingOverrideBEnabled && supportsThinkingLevel(dualProviderB, dualModelB)) {
            dualThinkingLevelB.takeIf { it.isNotBlank() }
        } else null
        val dualCodexEffortOverrideB = if (dualThinkingOverrideBEnabled &&
            (dualProviderB.uppercase() == "CODEX_AUTH" || dualProviderB.uppercase() == "SUPERGROK")
        ) {
            dualCodexReasoningEffortB.ifBlank { "medium" }
        } else null

        val autoThinkingEnabledOverrideA = if (autoThinkingOverrideAEnabled) autoThinkingEnabledA else null
        val autoThinkingBudgetOverrideA = if (autoThinkingOverrideAEnabled && supportsThinkingBudget(autoProviderA, autoModelA)) autoThinkingBudgetA.roundToInt() else null
        val autoThinkingLevelOverrideA = if (autoThinkingOverrideAEnabled && supportsThinkingLevel(autoProviderA, autoModelA)) {
            autoThinkingLevelA.takeIf { it.isNotBlank() }
        } else null
        val autoCodexEffortOverrideA = if (autoThinkingOverrideAEnabled &&
            (autoProviderA.uppercase() == "CODEX_AUTH" || autoProviderA.uppercase() == "SUPERGROK")
        ) {
            autoCodexReasoningEffortA.ifBlank { "medium" }
        } else null

        val autoThinkingEnabledOverrideB = if (autoThinkingOverrideBEnabled) autoThinkingEnabledB else null
        val autoThinkingBudgetOverrideB = if (autoThinkingOverrideBEnabled && supportsThinkingBudget(autoProviderB, autoModelB)) autoThinkingBudgetB.roundToInt() else null
        val autoThinkingLevelOverrideB = if (autoThinkingOverrideBEnabled && supportsThinkingLevel(autoProviderB, autoModelB)) {
            autoThinkingLevelB.takeIf { it.isNotBlank() }
        } else null
        val autoCodexEffortOverrideB = if (autoThinkingOverrideBEnabled &&
            (autoProviderB.uppercase() == "CODEX_AUTH" || autoProviderB.uppercase() == "SUPERGROK")
        ) {
            autoCodexReasoningEffortB.ifBlank { "medium" }
        } else null

        val geminiApiKeyAction = when {
            geminiKeyDirty && apiKeyInput.isNotBlank() -> ApiKeyAction.Update
            geminiKeyDirty && apiKeyInput.isBlank() -> ApiKeyAction.Clear
            else -> ApiKeyAction.NoChange
        }

        val openRouterApiKeyAction = when {
            openRouterKeyDirty && openRouterApiKeyInput.isNotBlank() -> ApiKeyAction.Update
            openRouterKeyDirty && openRouterApiKeyInput.isBlank() -> ApiKeyAction.Clear
            else -> ApiKeyAction.NoChange
        }

        val zaiApiKeyAction = when {
            zaiKeyDirty && zaiApiKeyInput.isNotBlank() -> ApiKeyAction.Update
            zaiKeyDirty && zaiApiKeyInput.isBlank() -> ApiKeyAction.Clear
            else -> ApiKeyAction.NoChange
        }
        val openAiApiKeyAction = when {
            openAiKeyDirty && openAiApiKeyInput.isNotBlank() -> ApiKeyAction.Update
            openAiKeyDirty && openAiApiKeyInput.isBlank() -> ApiKeyAction.Clear
            else -> ApiKeyAction.NoChange
        }
        val miniMaxApiKeyAction = when {
            miniMaxKeyDirty && miniMaxApiKeyInput.isNotBlank() -> ApiKeyAction.Update
            miniMaxKeyDirty && miniMaxApiKeyInput.isBlank() -> ApiKeyAction.Clear
            else -> ApiKeyAction.NoChange
        }
        val openAiCompatApiKeyAction = when {
            openAiCompatKeyDirty && openAiCompatApiKeyInput.isNotBlank() -> ApiKeyAction.Update
            openAiCompatKeyDirty && openAiCompatApiKeyInput.isBlank() -> ApiKeyAction.Clear
            else -> ApiKeyAction.NoChange
        }
        val openCodeGoApiKeyAction = when {
            openCodeGoKeyDirty && openCodeGoApiKeyInput.isNotBlank() -> ApiKeyAction.Update
            openCodeGoKeyDirty && openCodeGoApiKeyInput.isBlank() -> ApiKeyAction.Clear
            else -> ApiKeyAction.NoChange
        }
        val clinePassApiKeyAction = when {
            clinePassKeyDirty && clinePassApiKeyInput.isNotBlank() -> ApiKeyAction.Update
            clinePassKeyDirty && clinePassApiKeyInput.isBlank() -> ApiKeyAction.Clear
            else -> ApiKeyAction.NoChange
        }
        val alibabaCodingPlanApiKeyAction = when {
            alibabaCodingPlanKeyDirty && alibabaCodingPlanApiKeyInput.isNotBlank() -> ApiKeyAction.Update
            alibabaCodingPlanKeyDirty && alibabaCodingPlanApiKeyInput.isBlank() -> ApiKeyAction.Clear
            else -> ApiKeyAction.NoChange
        }
        val alibabaMcpAuthorizationTokenAction = when {
            alibabaMcpTokenDirty && alibabaMcpAuthorizationTokenInput.isNotBlank() -> ApiKeyAction.Update
            alibabaMcpTokenDirty && alibabaMcpAuthorizationTokenInput.isBlank() -> ApiKeyAction.Clear
            else -> ApiKeyAction.NoChange
        }

        val normalizedSelectedPreset = selectedSystemPromptPresetLocal
            ?.takeIf { name -> systemPromptPresetsLocal.any { it.name.equals(name, ignoreCase = true) } }

        return SettingsUpdateRequest(
            apiKey = apiKeyInput,
            model = model,
            providerModels = providerModels.toMap(),
            googleSearchEnabled = googleSearchEnabled,
            codeExecutionEnabled = codeExecutionEnabled,
            urlContextEnabled = urlContextEnabled,
            googleMapsEnabled = googleMapsEnabled,
            computerUseEnabled = computerUseEnabled,
            thinkingEnabled = thinkingEnabled,
            thinkingBudget = thinkingBudget.toInt(),
            thinkingLevel = thinkingLevel,
            responseMimeType = responseMimeType,
            responseJsonSchema = responseJsonSchema,
            functionDeclarations = functionDeclarations,
            systemPrompt = systemPrompt,
            systemPromptPresets = systemPromptPresetsLocal.toList(),
            selectedSystemPromptPreset = normalizedSelectedPreset,
            isStreamingEnabled = isStreamingEnabled,
            apiProvider = apiProvider,
            openRouterApiKey = openRouterApiKeyInput,
            openAiApiKey = openAiApiKeyInput,
            miniMaxApiKey = miniMaxApiKeyInput,
            zaiApiKey = zaiApiKeyInput,
            openCodeGoApiKey = openCodeGoApiKeyInput,
            clinePassApiKey = clinePassApiKeyInput,
            alibabaCodingPlanApiKey = alibabaCodingPlanApiKeyInput,
            openAiCompatApiKey = openAiCompatApiKeyInput,
            geminiApiKeyAction = geminiApiKeyAction,
            openRouterApiKeyAction = openRouterApiKeyAction,
            openAiApiKeyAction = openAiApiKeyAction,
            miniMaxApiKeyAction = miniMaxApiKeyAction,
            zaiApiKeyAction = zaiApiKeyAction,
            openCodeGoApiKeyAction = openCodeGoApiKeyAction,
            clinePassApiKeyAction = clinePassApiKeyAction,
            alibabaCodingPlanApiKeyAction = alibabaCodingPlanApiKeyAction,
            openAiCompatApiKeyAction = openAiCompatApiKeyAction,
            isDualModeEnabled = isDualModeEnabled,
            dualModelA = dualModelA,
            dualModelB = dualModelB,
            dualProviderA = dualProviderA,
            dualProviderB = dualProviderB,
            dualSplitLayout = dualSplitLayout,
            dualSplitRatio = dualSplitRatio,
            dualSystemPromptA = dualSystemPromptA,
            dualSystemPromptB = dualSystemPromptB,
            isAutoConversationEnabled = isAutoConversationEnabled,
            autoModelA = autoModelA,
            autoModelB = autoModelB,
            autoProviderA = autoProviderA,
            autoProviderB = autoProviderB,
            autoSystemPromptA = autoSystemPromptA,
            autoSystemPromptB = autoSystemPromptB,
            autoMaxTurns = autoMaxTurns,
            mathRenderingEnabled = mathRenderingEnabled,
            dynamicColorEnabled = dynamicColorEnabled,
            themeColor = themeColor,
            themeMode = themeMode,
            showGlobalProviderPresetsInChat = showGlobalProviderPresetsInChat,  
            showGlobalProviderPresetsInChatByProvider = showGlobalProviderPresetsInChatByProvider
                .mapKeys { (key, _) -> key.uppercase() }
                .toMap(),
            preferredProviders = preferredProviders,
            selectedQuantizations = selectedQuantizations,
            maxPricePerMillionTokens = maxPrice.toDouble(),
            allowFallbacks = allowFallbacks,
            requireParameters = requireParameters,
            providerSelectionMax = providerSelectionMax,
            providerSort = providerSort,
            openAiBaseUrl = openAiBaseUrl,
            miniMaxBaseUrl = miniMaxBaseUrl,
            openAiCompatPresets = openAiCompatPresetsLocal.toList(),
            selectedOpenAiCompatPreset = selectedOpenAiCompatPresetLocal,
            alibabaMcpEnabled = alibabaMcpEnabled,
            alibabaMcpServerUrl = alibabaMcpServerUrl,
            alibabaMcpServerName = alibabaMcpServerName,
            alibabaMcpAllowedTools = alibabaMcpAllowedTools,
            alibabaMcpAuthorizationToken = alibabaMcpAuthorizationTokenInput,
            alibabaMcpAuthorizationTokenAction = alibabaMcpAuthorizationTokenAction,
            openRouterReasoningMode = reasoningMode,
            openRouterReasoningEffort = reasoningEffort,
            openRouterReasoningExclude = reasoningExclude,
            codexUserAgentPreset = codexUserAgentPreset,
            codexReasoningEnabled = codexReasoningEnabled,
            codexReasoningEffort = codexReasoningEffort,
            codexReasoningSummary = codexReasoningSummary,
            codexVerbosity = codexVerbosity,
            codexSupportsReasoningSummaries = codexSupportsReasoningSummaries,
            codexShowReasoningSummary = codexShowReasoningSummary,
            codexWebSearchEnabled = codexWebSearchEnabled,
            codexWebSearchContextSize = codexWebSearchContextSize,
            codexPromptCacheEnabled = codexPromptCacheEnabled,
            codexPromptCacheMinLength = codexPromptCacheMinLength,
            codexPromptCacheType = codexPromptCacheType,
            superGrokReasoningEnabled = superGrokReasoningEnabled,
            superGrokReasoningEffort = superGrokReasoningEffort,
            dualOpenRouterThinkingEnabledA = dualEnabledAOverride,
            dualOpenRouterThinkingBudgetA = dualBudgetAOverride,
            dualOpenRouterReasoningModeA = dualModeAOverride,
            dualOpenRouterReasoningEffortA = dualEffortAOverride,
            dualOpenRouterReasoningExcludeA = dualExcludeAOverride,
            dualOpenRouterThinkingEnabledB = dualEnabledBOverride,
            dualOpenRouterThinkingBudgetB = dualBudgetBOverride,
            dualOpenRouterReasoningModeB = dualModeBOverride,
            dualOpenRouterReasoningEffortB = dualEffortBOverride,
            dualOpenRouterReasoningExcludeB = dualExcludeBOverride,
            autoOpenRouterThinkingEnabledA = autoEnabledAOverride,
            autoOpenRouterThinkingBudgetA = autoBudgetAOverride,
            autoOpenRouterReasoningModeA = autoModeAOverride,
            autoOpenRouterReasoningEffortA = autoEffortAOverride,
            autoOpenRouterReasoningExcludeA = autoExcludeAOverride,
            autoOpenRouterThinkingEnabledB = autoEnabledBOverride,
            autoOpenRouterThinkingBudgetB = autoBudgetBOverride,
            autoOpenRouterReasoningModeB = autoModeBOverride,
            autoOpenRouterReasoningEffortB = autoEffortBOverride,
            autoOpenRouterReasoningExcludeB = autoExcludeBOverride,
            dualGoogleSearchEnabledA = dualGoogleSearchOverrideA,
            dualCodeExecutionEnabledA = dualCodeExecutionOverrideA,
            dualUrlContextEnabledA = dualUrlContextOverrideA,
            dualGoogleMapsEnabledA = dualGoogleMapsOverrideA,
            dualComputerUseEnabledA = dualComputerUseOverrideA,
            dualThinkingEnabledA = dualThinkingEnabledOverrideA,
            dualThinkingBudgetA = dualThinkingBudgetOverrideA,
            dualThinkingLevelA = dualThinkingLevelOverrideA,
            dualCodexReasoningEffortA = dualCodexEffortOverrideA,
            dualGoogleSearchEnabledB = dualGoogleSearchOverrideB,
            dualCodeExecutionEnabledB = dualCodeExecutionOverrideB,
            dualUrlContextEnabledB = dualUrlContextOverrideB,
            dualGoogleMapsEnabledB = dualGoogleMapsOverrideB,
            dualComputerUseEnabledB = dualComputerUseOverrideB,
            dualThinkingEnabledB = dualThinkingEnabledOverrideB,
            dualThinkingBudgetB = dualThinkingBudgetOverrideB,
            dualThinkingLevelB = dualThinkingLevelOverrideB,
            dualCodexReasoningEffortB = dualCodexEffortOverrideB,
            autoGoogleSearchEnabledA = autoGoogleSearchOverrideA,
            autoCodeExecutionEnabledA = autoCodeExecutionOverrideA,
            autoUrlContextEnabledA = autoUrlContextOverrideA,
            autoGoogleMapsEnabledA = autoGoogleMapsOverrideA,
            autoComputerUseEnabledA = autoComputerUseOverrideA,
            autoThinkingEnabledA = autoThinkingEnabledOverrideA,
            autoThinkingBudgetA = autoThinkingBudgetOverrideA,
            autoThinkingLevelA = autoThinkingLevelOverrideA,
            autoCodexReasoningEffortA = autoCodexEffortOverrideA,
            autoGoogleSearchEnabledB = autoGoogleSearchOverrideB,
            autoCodeExecutionEnabledB = autoCodeExecutionOverrideB,
            autoUrlContextEnabledB = autoUrlContextOverrideB,
            autoGoogleMapsEnabledB = autoGoogleMapsOverrideB,
            autoComputerUseEnabledB = autoComputerUseOverrideB,
            autoThinkingEnabledB = autoThinkingEnabledOverrideB,
            autoThinkingBudgetB = autoThinkingBudgetOverrideB,
            autoThinkingLevelB = autoThinkingLevelOverrideB,
            autoCodexReasoningEffortB = autoCodexEffortOverrideB
        )
    }

    fun resetAfterSave() {
        geminiKeyDirty = false
        openRouterKeyDirty = false
        zaiKeyDirty = false
        openCodeGoKeyDirty = false
        clinePassKeyDirty = false
        alibabaCodingPlanKeyDirty = false
        alibabaMcpTokenDirty = false
        openAiKeyDirty = false
        miniMaxKeyDirty = false
        openAiCompatKeyDirty = false
        geminiKeyVisible = false
        openRouterKeyVisible = false
        zaiKeyVisible = false
        openCodeGoKeyVisible = false
        clinePassKeyVisible = false
        alibabaCodingPlanKeyVisible = false
        alibabaMcpTokenVisible = false
        openAiKeyVisible = false
        miniMaxKeyVisible = false
        openAiCompatKeyVisible = false
        geminiKeyLoadedFromStorage = false
        openRouterKeyLoadedFromStorage = false
        zaiKeyLoadedFromStorage = false
        openCodeGoKeyLoadedFromStorage = false
        clinePassKeyLoadedFromStorage = false
        alibabaCodingPlanKeyLoadedFromStorage = false
        alibabaMcpTokenLoadedFromStorage = false
        openAiKeyLoadedFromStorage = false
        miniMaxKeyLoadedFromStorage = false
        openAiCompatKeyLoadedFromStorage = false
        apiKeyInput = ""
        openRouterApiKeyInput = ""
        zaiApiKeyInput = ""
        openCodeGoApiKeyInput = ""
        clinePassApiKeyInput = ""
        alibabaCodingPlanApiKeyInput = ""
        alibabaMcpAuthorizationTokenInput = ""
        openAiApiKeyInput = ""
        miniMaxApiKeyInput = ""
        openAiCompatApiKeyInput = ""
    }

    private fun resolvePresetSystemPrompt(preset: ModelPreset): String? {
        val presetName = preset.systemPromptPresetName?.takeIf { it.isNotBlank() }
        if (presetName != null) {
            systemPromptPresetsLocal.firstOrNull { it.name.equals(presetName, ignoreCase = true) }
                ?.let { return it.prompt }
        }
        return preset.systemPrompt
    }

    fun startEditingPreset(preset: ModelPreset) {
        isEditingPreset = true
        editingPresetId = preset.id
        presetName = preset.name
        presetModel = preset.model
        presetSystemPrompt = resolvePresetSystemPrompt(preset).orEmpty()
        presetSystemPromptPresetName = preset.systemPromptPresetName
        presetThinkingEnabled = preset.thinkingEnabled
        presetThinkingBudget = preset.thinkingBudget.toFloat()
        presetThinkingLevel = preset.thinkingLevel
        presetGoogleSearchEnabled = preset.googleSearchEnabled
        presetCodeExecutionEnabled = preset.codeExecutionEnabled
        presetUrlContextEnabled = preset.urlContextEnabled
        presetGoogleMapsEnabled = preset.googleMapsEnabled
        presetComputerUseEnabled = preset.computerUseEnabled
        presetResponseMimeType = preset.responseMimeType
        presetResponseJsonSchema = preset.responseJsonSchema
        presetFunctionDeclarations = preset.functionDeclarations
        presetApiProvider = preset.apiProvider
        presetReasoningMode = preset.reasoningMode
        presetReasoningEffort = preset.reasoningEffort
        presetReasoningExclude = preset.reasoningExclude
        presetCodexReasoningSummary = preset.codexReasoningSummary
        presetCodexVerbosity = preset.codexVerbosity
        presetCodexWebSearchEnabled = preset.codexWebSearchEnabled
        presetCodexWebSearchContextSize = preset.codexWebSearchContextSize
        presetCodexPromptCacheEnabled = preset.codexPromptCacheEnabled
        presetCodexPromptCacheMinLength = preset.codexPromptCacheMinLength
        presetCodexPromptCacheType = preset.codexPromptCacheType
        presetCodexShowReasoningSummary = preset.codexShowReasoningSummary
        presetCodexSupportsReasoningSummaries = preset.codexSupportsReasoningSummaries
        presetOpenAiCompatPresetName = if (preset.apiProvider.uppercase() == "OPENAI_COMPAT") {
            preset.openAiCompatPresetName
        } else {
            null
        }
        showPresetDialog = true
    }

    fun startCreatingPreset() {
        isEditingPreset = false
        editingPresetId = 0L
        presetName = ""
        presetModel = ""
        presetSystemPrompt = ""
        presetSystemPromptPresetName = null
        presetThinkingEnabled = false
        presetThinkingBudget = 0f
        presetThinkingLevel = ""
        presetGoogleSearchEnabled = false
        presetCodeExecutionEnabled = false
        presetUrlContextEnabled = false
        presetGoogleMapsEnabled = false
        presetComputerUseEnabled = false
        presetResponseMimeType = ""
        presetResponseJsonSchema = ""
        presetFunctionDeclarations = ""
        presetApiProvider = "GEMINI"
        presetApiKey = ""
        presetReasoningMode = "auto"
        presetReasoningEffort = ""
        presetReasoningExclude = false
        presetCodexReasoningSummary = "auto"
        presetCodexVerbosity = "medium"
        presetCodexWebSearchEnabled = false
        presetCodexWebSearchContextSize = "medium"
        presetCodexPromptCacheEnabled = true
        presetCodexPromptCacheMinLength = 512
        presetCodexPromptCacheType = "ephemeral"
        presetCodexShowReasoningSummary = true
        presetCodexSupportsReasoningSummaries = false
        presetOpenAiCompatPresetName = null
        showPresetDialog = true
    }

    fun buildPresetDialogState(): ModelPresetDialogState = ModelPresetDialogState(
        isVisible = showPresetDialog,
        isEditing = isEditingPreset,
        name = presetName,
        onNameChange = { presetName = it },
        model = presetModel,
        onModelChange = { presetModel = it },
        systemPrompt = presetSystemPrompt,
        onSystemPromptChange = { value ->
            if (!presetSystemPromptPresetName.isNullOrBlank()) {
                presetSystemPromptPresetName = null
            }
            presetSystemPrompt = value
        },
        systemPromptPresetName = presetSystemPromptPresetName,
        onSystemPromptPresetSelected = { preset ->
            presetSystemPromptPresetName = preset?.name
            if (preset != null) {
                presetSystemPrompt = preset.prompt
            }
        },
        thinkingEnabled = presetThinkingEnabled,
        onThinkingEnabledChange = { enabled ->
            presetThinkingEnabled = enabled
            if (presetApiProvider != "OPENROUTER" && ModelUtils.isThinkingLevelSupported(presetModel) &&
                !ModelUtils.isThinkingAlwaysOn(presetModel)
            ) {
                val minimal = ModelUtils.getMinimalThinkingLevel(presetModel)
                if (!enabled && minimal != null) {
                    presetThinkingLevel = minimal
                } else if (enabled) {
                    val defaultLevel = ModelUtils.getDefaultThinkingLevel(presetModel)
                    if (presetThinkingLevel.isBlank() || presetThinkingLevel == minimal) {
                        presetThinkingLevel = defaultLevel
                    }
                }
            }
        },
        thinkingBudget = presetThinkingBudget,
        onThinkingBudgetChange = { presetThinkingBudget = it },
        thinkingLevel = presetThinkingLevel,
        onThinkingLevelChange = { presetThinkingLevel = it },
        googleSearchEnabled = presetGoogleSearchEnabled,
        onGoogleSearchEnabledChange = { presetGoogleSearchEnabled = it },
        codeExecutionEnabled = presetCodeExecutionEnabled,
        onCodeExecutionEnabledChange = { presetCodeExecutionEnabled = it },
        urlContextEnabled = presetUrlContextEnabled,
        onUrlContextEnabledChange = { presetUrlContextEnabled = it },
        googleMapsEnabled = presetGoogleMapsEnabled,
        onGoogleMapsEnabledChange = { presetGoogleMapsEnabled = it },
        computerUseEnabled = presetComputerUseEnabled,
        onComputerUseEnabledChange = { presetComputerUseEnabled = it },
        responseMimeType = presetResponseMimeType,
        onResponseMimeTypeChange = { presetResponseMimeType = it },
        responseJsonSchema = presetResponseJsonSchema,
        onResponseJsonSchemaChange = { presetResponseJsonSchema = it },
        functionDeclarations = presetFunctionDeclarations,
        onFunctionDeclarationsChange = { presetFunctionDeclarations = it },
        apiProvider = presetApiProvider,
        onApiProviderChange = { provider ->
            presetApiProvider = provider
            if (provider == "OPENAI_COMPAT") {
                if (presetOpenAiCompatPresetName == null) {
                    presetOpenAiCompatPresetName = selectedOpenAiCompatPresetLocal
                }
            } else {
                presetOpenAiCompatPresetName = null
            }
        },
        apiKey = presetApiKey,
        onApiKeyChange = { presetApiKey = it },
        reasoningMode = presetReasoningMode,
        onReasoningModeChange = { presetReasoningMode = it },
        reasoningEffort = presetReasoningEffort,
        onReasoningEffortChange = { presetReasoningEffort = it },
        reasoningExclude = presetReasoningExclude,
        onReasoningExcludeChange = { presetReasoningExclude = it },
        codexReasoningSummary = presetCodexReasoningSummary,
        onCodexReasoningSummaryChange = { presetCodexReasoningSummary = it },
        codexVerbosity = presetCodexVerbosity,
        onCodexVerbosityChange = { presetCodexVerbosity = it },
        codexWebSearchEnabled = presetCodexWebSearchEnabled,
        onCodexWebSearchEnabledChange = { presetCodexWebSearchEnabled = it },
        codexWebSearchContextSize = presetCodexWebSearchContextSize,
        onCodexWebSearchContextSizeChange = { presetCodexWebSearchContextSize = it },
        codexPromptCacheEnabled = presetCodexPromptCacheEnabled,
        onCodexPromptCacheEnabledChange = { presetCodexPromptCacheEnabled = it },
        codexPromptCacheMinLength = presetCodexPromptCacheMinLength,
        onCodexPromptCacheMinLengthChange = { presetCodexPromptCacheMinLength = it },
        codexPromptCacheType = presetCodexPromptCacheType,
        onCodexPromptCacheTypeChange = { presetCodexPromptCacheType = it },
        codexShowReasoningSummary = presetCodexShowReasoningSummary,
        onCodexShowReasoningSummaryChange = { presetCodexShowReasoningSummary = it },
        codexSupportsReasoningSummaries = presetCodexSupportsReasoningSummaries,
        onCodexSupportsReasoningSummariesChange = { presetCodexSupportsReasoningSummaries = it },
        openAiCompatPresetName = presetOpenAiCompatPresetName,
        onOpenAiCompatPresetNameChange = { presetOpenAiCompatPresetName = it?.takeIf { name -> name.isNotBlank() } },
        selectedProvider = presetSelectedProvider,
        onSelectedProviderChange = { presetSelectedProvider = it }
    )

    fun applyPresetToDualA(preset: ModelPreset) {
        dualProviderA = preset.apiProvider
        dualModelA = preset.model
        dualToolsOverrideA = true
        dualGoogleSearchEnabledA = preset.googleSearchEnabled
        dualCodeExecutionEnabledA = preset.codeExecutionEnabled
        dualUrlContextEnabledA = preset.urlContextEnabled
        dualGoogleMapsEnabledA = preset.googleMapsEnabled
        dualComputerUseEnabledA = preset.computerUseEnabled
        if (preset.apiProvider.uppercase() == "OPENROUTER") {
            dualReasonOverrideA = true
            dualReasonEnabledA = preset.thinkingEnabled
            dualReasonBudgetA = preset.thinkingBudget.toFloat()
            dualReasonModeA = preset.reasoningMode
            dualReasonEffortA = if (preset.reasoningMode == "effort") {
                preset.reasoningEffort.ifBlank { "medium" }
            } else {
                ""
            }
            dualReasonExcludeA = preset.reasoningExclude
            dualThinkingOverrideA = false
        } else {
            dualReasonOverrideA = false
            dualThinkingOverrideA = true
            dualThinkingEnabledA = preset.thinkingEnabled
            dualThinkingBudgetA = preset.thinkingBudget.toFloat()
            dualThinkingLevelA = preset.thinkingLevel
            dualCodexReasoningEffortA = preset.reasoningEffort.ifBlank { "medium" }
        }
    }

    fun applyPresetToDualB(preset: ModelPreset) {
        dualProviderB = preset.apiProvider
        dualModelB = preset.model
        dualToolsOverrideB = true
        dualGoogleSearchEnabledB = preset.googleSearchEnabled
        dualCodeExecutionEnabledB = preset.codeExecutionEnabled
        dualUrlContextEnabledB = preset.urlContextEnabled
        dualGoogleMapsEnabledB = preset.googleMapsEnabled
        dualComputerUseEnabledB = preset.computerUseEnabled
        if (preset.apiProvider.uppercase() == "OPENROUTER") {
            dualReasonOverrideB = true
            dualReasonEnabledB = preset.thinkingEnabled
            dualReasonBudgetB = preset.thinkingBudget.toFloat()
            dualReasonModeB = preset.reasoningMode
            dualReasonEffortB = if (preset.reasoningMode == "effort") {
                preset.reasoningEffort.ifBlank { "medium" }
            } else {
                ""
            }
            dualReasonExcludeB = preset.reasoningExclude
            dualThinkingOverrideB = false
        } else {
            dualReasonOverrideB = false
            dualThinkingOverrideB = true
            dualThinkingEnabledB = preset.thinkingEnabled
            dualThinkingBudgetB = preset.thinkingBudget.toFloat()
            dualThinkingLevelB = preset.thinkingLevel
            dualCodexReasoningEffortB = preset.reasoningEffort.ifBlank { "medium" }
        }
    }

    fun applyPresetToAutoA(preset: ModelPreset) {
        autoProviderA = preset.apiProvider
        autoModelA = preset.model
        resolvePresetSystemPrompt(preset)?.takeIf { it.isNotBlank() }?.let { autoSystemPromptA = it }
        autoToolsOverrideA = true
        autoGoogleSearchEnabledA = preset.googleSearchEnabled
        autoCodeExecutionEnabledA = preset.codeExecutionEnabled
        autoUrlContextEnabledA = preset.urlContextEnabled
        autoGoogleMapsEnabledA = preset.googleMapsEnabled
        autoComputerUseEnabledA = preset.computerUseEnabled
        if (preset.apiProvider.uppercase() == "OPENROUTER") {
            autoReasonOverrideA = true
            autoReasonEnabledA = preset.thinkingEnabled
            autoReasonBudgetA = preset.thinkingBudget.toFloat()
            autoReasonModeA = preset.reasoningMode
            autoReasonEffortA = if (preset.reasoningMode == "effort") {
                preset.reasoningEffort.ifBlank { "medium" }
            } else {
                ""
            }
            autoReasonExcludeA = preset.reasoningExclude
            autoThinkingOverrideA = false
        } else {
            autoReasonOverrideA = false
            autoThinkingOverrideA = true
            autoThinkingEnabledA = preset.thinkingEnabled
            autoThinkingBudgetA = preset.thinkingBudget.toFloat()
            autoThinkingLevelA = preset.thinkingLevel
            autoCodexReasoningEffortA = preset.reasoningEffort.ifBlank { "medium" }
        }
    }

    fun applyPresetToAutoB(preset: ModelPreset) {
        autoProviderB = preset.apiProvider
        autoModelB = preset.model
        resolvePresetSystemPrompt(preset)?.takeIf { it.isNotBlank() }?.let { autoSystemPromptB = it }
        autoToolsOverrideB = true
        autoGoogleSearchEnabledB = preset.googleSearchEnabled
        autoCodeExecutionEnabledB = preset.codeExecutionEnabled
        autoUrlContextEnabledB = preset.urlContextEnabled
        autoGoogleMapsEnabledB = preset.googleMapsEnabled
        autoComputerUseEnabledB = preset.computerUseEnabled
        if (preset.apiProvider.uppercase() == "OPENROUTER") {
            autoReasonOverrideB = true
            autoReasonEnabledB = preset.thinkingEnabled
            autoReasonBudgetB = preset.thinkingBudget.toFloat()
            autoReasonModeB = preset.reasoningMode
            autoReasonEffortB = if (preset.reasoningMode == "effort") {
                preset.reasoningEffort.ifBlank { "medium" }
            } else {
                ""
            }
            autoReasonExcludeB = preset.reasoningExclude
            autoThinkingOverrideB = false
        } else {
            autoReasonOverrideB = false
            autoThinkingOverrideB = true
            autoThinkingEnabledB = preset.thinkingEnabled
            autoThinkingBudgetB = preset.thinkingBudget.toFloat()
            autoThinkingLevelB = preset.thinkingLevel
            autoCodexReasoningEffortB = preset.reasoningEffort.ifBlank { "medium" }
        }
    }

    fun onPresetConfirm() {
        val dialogState = buildPresetDialogState()
        if (dialogState.name.isNotBlank() && dialogState.model.isNotBlank()) {
            viewModel.upsertModelPreset(
                ModelPreset(
                    id = if (isEditingPreset) editingPresetId else 0L,
                    name = dialogState.name,
                    model = dialogState.model,
                    systemPrompt = dialogState.systemPrompt.takeIf { it.isNotBlank() },
                    systemPromptPresetName = dialogState.systemPromptPresetName?.takeIf { it.isNotBlank() },
                    thinkingEnabled = dialogState.thinkingEnabled,
                    thinkingBudget = dialogState.thinkingBudget.toInt(),
                    thinkingLevel = dialogState.thinkingLevel,
                    googleSearchEnabled = dialogState.googleSearchEnabled,
                    codeExecutionEnabled = dialogState.codeExecutionEnabled,
                    urlContextEnabled = dialogState.urlContextEnabled,
                    googleMapsEnabled = dialogState.googleMapsEnabled,
                    computerUseEnabled = dialogState.computerUseEnabled,
                    responseMimeType = dialogState.responseMimeType,
                    responseJsonSchema = dialogState.responseJsonSchema,
                    functionDeclarations = dialogState.functionDeclarations,
                    apiProvider = dialogState.apiProvider,
                    reasoningMode = dialogState.reasoningMode,
                    reasoningEffort = dialogState.reasoningEffort,
                    reasoningExclude = dialogState.reasoningExclude,
                    codexReasoningSummary = dialogState.codexReasoningSummary.ifBlank { "auto" },
                    codexVerbosity = dialogState.codexVerbosity.ifBlank { "medium" },
                    codexWebSearchEnabled = dialogState.codexWebSearchEnabled,
                    codexWebSearchContextSize = dialogState.codexWebSearchContextSize.ifBlank { "medium" },
                    codexPromptCacheEnabled = dialogState.codexPromptCacheEnabled,
                    codexPromptCacheMinLength = dialogState.codexPromptCacheMinLength.coerceAtLeast(0),
                    codexPromptCacheType = dialogState.codexPromptCacheType.ifBlank { "ephemeral" },
                    codexShowReasoningSummary = dialogState.codexShowReasoningSummary,
                    codexSupportsReasoningSummaries = dialogState.codexSupportsReasoningSummaries,
                    openAiCompatPresetName = if (dialogState.apiProvider == "OPENAI_COMPAT") {
                        dialogState.openAiCompatPresetName?.takeIf { it.isNotBlank() }
                    } else {
                        null
                    }
                )
            )
            showPresetDialog = false
        }
    }

    fun dualReasoningStateA(): ReasoningOverrideUiState = ReasoningOverrideUiState(
        overrideEnabled = dualReasonOverrideA,
        onOverrideEnabledChange = { dualReasonOverrideA = it },
        reasoningEnabled = dualReasonEnabledA,
        onReasoningEnabledChange = { dualReasonEnabledA = it },
        reasoningMode = dualReasonModeA,
        onReasoningModeChange = { dualReasonModeA = it },
        reasoningEffort = dualReasonEffortA,
        onReasoningEffortChange = { dualReasonEffortA = it },
        reasoningExclude = dualReasonExcludeA,
        onReasoningExcludeChange = { dualReasonExcludeA = it },
        reasoningBudget = dualReasonBudgetA,
        onReasoningBudgetChange = { dualReasonBudgetA = it },
        onApplyDefaults = { applyDualDefaultsA() }
    )

    fun dualReasoningStateB(): ReasoningOverrideUiState = ReasoningOverrideUiState(
        overrideEnabled = dualReasonOverrideB,
        onOverrideEnabledChange = { dualReasonOverrideB = it },
        reasoningEnabled = dualReasonEnabledB,
        onReasoningEnabledChange = { dualReasonEnabledB = it },
        reasoningMode = dualReasonModeB,
        onReasoningModeChange = { dualReasonModeB = it },
        reasoningEffort = dualReasonEffortB,
        onReasoningEffortChange = { dualReasonEffortB = it },
        reasoningExclude = dualReasonExcludeB,
        onReasoningExcludeChange = { dualReasonExcludeB = it },
        reasoningBudget = dualReasonBudgetB,
        onReasoningBudgetChange = { dualReasonBudgetB = it },
        onApplyDefaults = { applyDualDefaultsB() }
    )

    fun dualToolsStateA(): ToolingOverrideUiState = ToolingOverrideUiState(
        overrideEnabled = dualToolsOverrideA,
        onOverrideEnabledChange = { dualToolsOverrideA = it },
        googleSearchEnabled = dualGoogleSearchEnabledA,
        onGoogleSearchEnabledChange = { dualGoogleSearchEnabledA = it },
        codeExecutionEnabled = dualCodeExecutionEnabledA,
        onCodeExecutionEnabledChange = { dualCodeExecutionEnabledA = it },
        urlContextEnabled = dualUrlContextEnabledA,
        onUrlContextEnabledChange = { dualUrlContextEnabledA = it },
        googleMapsEnabled = dualGoogleMapsEnabledA,
        onGoogleMapsEnabledChange = { dualGoogleMapsEnabledA = it },
        computerUseEnabled = dualComputerUseEnabledA,
        onComputerUseEnabledChange = { dualComputerUseEnabledA = it },
        onApplyDefaults = { applyDualToolDefaultsA(useOverrides = false) }
    )

    fun dualToolsStateB(): ToolingOverrideUiState = ToolingOverrideUiState(
        overrideEnabled = dualToolsOverrideB,
        onOverrideEnabledChange = { dualToolsOverrideB = it },
        googleSearchEnabled = dualGoogleSearchEnabledB,
        onGoogleSearchEnabledChange = { dualGoogleSearchEnabledB = it },
        codeExecutionEnabled = dualCodeExecutionEnabledB,
        onCodeExecutionEnabledChange = { dualCodeExecutionEnabledB = it },
        urlContextEnabled = dualUrlContextEnabledB,
        onUrlContextEnabledChange = { dualUrlContextEnabledB = it },
        googleMapsEnabled = dualGoogleMapsEnabledB,
        onGoogleMapsEnabledChange = { dualGoogleMapsEnabledB = it },
        computerUseEnabled = dualComputerUseEnabledB,
        onComputerUseEnabledChange = { dualComputerUseEnabledB = it },
        onApplyDefaults = { applyDualToolDefaultsB(useOverrides = false) }
    )

    fun dualThinkingStateA(): ThinkingOverrideUiState = ThinkingOverrideUiState(
        overrideEnabled = dualThinkingOverrideA,
        onOverrideEnabledChange = { dualThinkingOverrideA = it },
        thinkingEnabled = dualThinkingEnabledA,
        onThinkingEnabledChange = { dualThinkingEnabledA = it },
        thinkingBudget = dualThinkingBudgetA,
        onThinkingBudgetChange = { dualThinkingBudgetA = it },
        thinkingLevel = dualThinkingLevelA,
        onThinkingLevelChange = { dualThinkingLevelA = it },
        codexReasoningEffort = dualCodexReasoningEffortA,
        onCodexReasoningEffortChange = { dualCodexReasoningEffortA = it },
        onApplyDefaults = { applyDualThinkingDefaultsA(useOverrides = false) }
    )

    fun dualThinkingStateB(): ThinkingOverrideUiState = ThinkingOverrideUiState(
        overrideEnabled = dualThinkingOverrideB,
        onOverrideEnabledChange = { dualThinkingOverrideB = it },
        thinkingEnabled = dualThinkingEnabledB,
        onThinkingEnabledChange = { dualThinkingEnabledB = it },
        thinkingBudget = dualThinkingBudgetB,
        onThinkingBudgetChange = { dualThinkingBudgetB = it },
        thinkingLevel = dualThinkingLevelB,
        onThinkingLevelChange = { dualThinkingLevelB = it },
        codexReasoningEffort = dualCodexReasoningEffortB,
        onCodexReasoningEffortChange = { dualCodexReasoningEffortB = it },
        onApplyDefaults = { applyDualThinkingDefaultsB(useOverrides = false) }
    )

    fun autoReasoningStateA(): ReasoningOverrideUiState = ReasoningOverrideUiState(
        overrideEnabled = autoReasonOverrideA,
        onOverrideEnabledChange = { autoReasonOverrideA = it },
        reasoningEnabled = autoReasonEnabledA,
        onReasoningEnabledChange = { autoReasonEnabledA = it },
        reasoningMode = autoReasonModeA,
        onReasoningModeChange = { autoReasonModeA = it },
        reasoningEffort = autoReasonEffortA,
        onReasoningEffortChange = { autoReasonEffortA = it },
        reasoningExclude = autoReasonExcludeA,
        onReasoningExcludeChange = { autoReasonExcludeA = it },
        reasoningBudget = autoReasonBudgetA,
        onReasoningBudgetChange = { autoReasonBudgetA = it },
        onApplyDefaults = { applyAutoDefaultsA() }
    )

    fun autoReasoningStateB(): ReasoningOverrideUiState = ReasoningOverrideUiState(
        overrideEnabled = autoReasonOverrideB,
        onOverrideEnabledChange = { autoReasonOverrideB = it },
        reasoningEnabled = autoReasonEnabledB,
        onReasoningEnabledChange = { autoReasonEnabledB = it },
        reasoningMode = autoReasonModeB,
        onReasoningModeChange = { autoReasonModeB = it },
        reasoningEffort = autoReasonEffortB,
        onReasoningEffortChange = { autoReasonEffortB = it },
        reasoningExclude = autoReasonExcludeB,
        onReasoningExcludeChange = { autoReasonExcludeB = it },
        reasoningBudget = autoReasonBudgetB,
        onReasoningBudgetChange = { autoReasonBudgetB = it },
        onApplyDefaults = { applyAutoDefaultsB() }
    )

    fun autoToolsStateA(): ToolingOverrideUiState = ToolingOverrideUiState(
        overrideEnabled = autoToolsOverrideA,
        onOverrideEnabledChange = { autoToolsOverrideA = it },
        googleSearchEnabled = autoGoogleSearchEnabledA,
        onGoogleSearchEnabledChange = { autoGoogleSearchEnabledA = it },
        codeExecutionEnabled = autoCodeExecutionEnabledA,
        onCodeExecutionEnabledChange = { autoCodeExecutionEnabledA = it },
        urlContextEnabled = autoUrlContextEnabledA,
        onUrlContextEnabledChange = { autoUrlContextEnabledA = it },
        googleMapsEnabled = autoGoogleMapsEnabledA,
        onGoogleMapsEnabledChange = { autoGoogleMapsEnabledA = it },
        computerUseEnabled = autoComputerUseEnabledA,
        onComputerUseEnabledChange = { autoComputerUseEnabledA = it },
        onApplyDefaults = { applyAutoToolDefaultsA(useOverrides = false) }
    )

    fun autoToolsStateB(): ToolingOverrideUiState = ToolingOverrideUiState(
        overrideEnabled = autoToolsOverrideB,
        onOverrideEnabledChange = { autoToolsOverrideB = it },
        googleSearchEnabled = autoGoogleSearchEnabledB,
        onGoogleSearchEnabledChange = { autoGoogleSearchEnabledB = it },
        codeExecutionEnabled = autoCodeExecutionEnabledB,
        onCodeExecutionEnabledChange = { autoCodeExecutionEnabledB = it },
        urlContextEnabled = autoUrlContextEnabledB,
        onUrlContextEnabledChange = { autoUrlContextEnabledB = it },
        googleMapsEnabled = autoGoogleMapsEnabledB,
        onGoogleMapsEnabledChange = { autoGoogleMapsEnabledB = it },
        computerUseEnabled = autoComputerUseEnabledB,
        onComputerUseEnabledChange = { autoComputerUseEnabledB = it },
        onApplyDefaults = { applyAutoToolDefaultsB(useOverrides = false) }
    )

    fun autoThinkingStateA(): ThinkingOverrideUiState = ThinkingOverrideUiState(
        overrideEnabled = autoThinkingOverrideA,
        onOverrideEnabledChange = { autoThinkingOverrideA = it },
        thinkingEnabled = autoThinkingEnabledA,
        onThinkingEnabledChange = { autoThinkingEnabledA = it },
        thinkingBudget = autoThinkingBudgetA,
        onThinkingBudgetChange = { autoThinkingBudgetA = it },
        thinkingLevel = autoThinkingLevelA,
        onThinkingLevelChange = { autoThinkingLevelA = it },
        codexReasoningEffort = autoCodexReasoningEffortA,
        onCodexReasoningEffortChange = { autoCodexReasoningEffortA = it },
        onApplyDefaults = { applyAutoThinkingDefaultsA(useOverrides = false) }
    )

    fun autoThinkingStateB(): ThinkingOverrideUiState = ThinkingOverrideUiState(
        overrideEnabled = autoThinkingOverrideB,
        onOverrideEnabledChange = { autoThinkingOverrideB = it },
        thinkingEnabled = autoThinkingEnabledB,
        onThinkingEnabledChange = { autoThinkingEnabledB = it },
        thinkingBudget = autoThinkingBudgetB,
        onThinkingBudgetChange = { autoThinkingBudgetB = it },
        thinkingLevel = autoThinkingLevelB,
        onThinkingLevelChange = { autoThinkingLevelB = it },
        codexReasoningEffort = autoCodexReasoningEffortB,
        onCodexReasoningEffortChange = { autoCodexReasoningEffortB = it },
        onApplyDefaults = { applyAutoThinkingDefaultsB(useOverrides = false) }
    )

    fun isCurrentModelFree(): Boolean {
        val selected = openRouterModels.find { it.id == model }
        return (selected?.isFree == true) || model.contains(":free", ignoreCase = true)
    }

    fun registerOpenRouterRecentModel(modelId: String) {
        if (modelId.isBlank()) return
        openRouterRecentModels = updateRecentList(openRouterRecentModels, modelId, openRouterRecentLimit)
        viewModel.registerOpenRouterRecentModel(modelId, openRouterRecentLimit)
    }

    fun toggleOpenRouterPinnedModel(modelId: String) {
        if (modelId.isBlank()) return
        openRouterPinnedModels = togglePinnedList(openRouterPinnedModels, modelId)
        viewModel.toggleOpenRouterPinnedModel(modelId)
    }

    private fun updateRecentList(source: List<String>, modelId: String, limit: Int): List<String> {
        val normalized = source.filterNot { it.equals(modelId, ignoreCase = true) }
        val merged = listOf(modelId) + normalized
        return if (limit > 0) merged.take(limit) else merged
    }

    private fun togglePinnedList(source: List<String>, modelId: String): List<String> {
        val filtered = source.filterNot { it.equals(modelId, ignoreCase = true) }
        return if (filtered.size == source.size) listOf(modelId) + filtered else filtered
    }
}

@Composable
fun rememberSettingsScreenState(
    viewModel: SettingsViewModel,
    settings: Settings?,
    openRouterModels: List<SimpleModel>,
    openRouterModelsLoading: Boolean,
    openRouterModelsError: String?
): SettingsScreenState {
    val state = remember(viewModel) { SettingsScreenState(viewModel) }

    LaunchedEffect(settings) {
        state.applySettings(settings)
    }

    LaunchedEffect(openRouterModels, openRouterModelsLoading, openRouterModelsError) {
        state.openRouterModels = openRouterModels
        state.openRouterModelsLoading = openRouterModelsLoading
        state.openRouterModelsError = openRouterModelsError
    }

    // OpenRouter選択時は高度設定をデフォルトで開く
    LaunchedEffect(state.apiProvider) {
        if (state.apiProvider == "OPENROUTER") state.advancedSettingsExpanded = true
    }

    // エンドポイント取得後、優先プロバイダーが未設定なら「最安」を自動初期選択
    LaunchedEffect(state.apiProvider, state.modelEndpoints) {
        if (state.apiProvider != "OPENROUTER") return@LaunchedEffect
        if (state.preferredProviders.isNotEmpty()) return@LaunchedEffect
        if (state.modelEndpoints.isEmpty()) return@LaunchedEffect
        val grouped = state.modelEndpoints
            .filter { !it.providerName.isNullOrBlank() }
            .groupBy { it.providerName!!.trim() }
        if (grouped.isEmpty()) return@LaunchedEffect
        val cheapest = grouped.minByOrNull { (_, eps) ->
            val p = eps.minOfOrNull { it.pricing.prompt?.toDoubleOrNull() ?: Double.POSITIVE_INFINITY }
                ?: Double.POSITIVE_INFINITY
            val c = eps.minOfOrNull { it.pricing.completion?.toDoubleOrNull() ?: Double.POSITIVE_INFINITY }
                ?: Double.POSITIVE_INFINITY
            minOf(p, c)
        }?.key
        if (!cheapest.isNullOrBlank()) {
            state.preferredProviders = listOf(cheapest)
        }
    }

    // モデル変更時にエンドポイント情報を更新（OpenRouter選択時）
    LaunchedEffect(state.apiProvider, state.model) {
        if (state.apiProvider == "OPENROUTER" && state.model.isNotBlank()) {
            runCatching {
                state.providerDirectory = viewModel.getProviderDirectory()
                state.dynamicProviders = viewModel.getAvailableProvidersForModel(state.model)
                state.dynamicQuantizations = viewModel.getAvailableQuantizationsForModel(state.model)
                state.modelEndpoints = viewModel.getModelEndpoints(state.model)
            }
        } else {
            state.dynamicProviders = emptyList()
            state.dynamicQuantizations = emptyList()
            state.modelEndpoints = emptyList()
            state.providerDirectory = ProviderDirectory.EMPTY
        }
    }

    // 無料モデル選択時は、有料のプロバイダーが選択状態に残らないようにクリーンアップ
    LaunchedEffect(state.apiProvider, state.modelEndpoints, state.providerDirectory, state.model) {
        if (state.apiProvider != "OPENROUTER") return@LaunchedEffect
        if (!state.isCurrentModelFree()) return@LaunchedEffect
        if (state.modelEndpoints.isEmpty()) return@LaunchedEffect

        val freeProviderSlugs: Set<String> = state.modelEndpoints
            .filter { ep ->
                val p = ep.pricing.prompt?.toDoubleOrNull()
                val c = ep.pricing.completion?.toDoubleOrNull()
                val req = ep.pricing.request?.toDoubleOrNull()
                (req == null || req == 0.0) && ((p == null || p == 0.0) && (c == null || c == 0.0))
            }
            .mapNotNull { ep -> state.providerDirectory.slugForName(ep.providerName) ?: ep.providerName?.lowercase() }
            .toSet()

        if (freeProviderSlugs.isEmpty()) return@LaunchedEffect

        val cleaned = state.preferredProviders.filter { slug -> freeProviderSlugs.any { it.equals(slug, ignoreCase = true) } }
        if (cleaned != state.preferredProviders) {
            state.preferredProviders = if (state.providerSelectionMax > 0) cleaned.take(state.providerSelectionMax) else cleaned
        }
        if (state.preferredProviders.isEmpty()) {
            state.preferredProviders = listOf(freeProviderSlugs.first())
        }
    }

    // プロバイダー絞り込みの選択を優先プロバイダーへ自動反映
    LaunchedEffect(state.selectedProvider) {
        if (state.apiProvider != "OPENROUTER") return@LaunchedEffect
        val sel = state.selectedProvider ?: return@LaunchedEffect
        val merged = listOf(sel) + state.preferredProviders.filterNot { it.equals(sel, ignoreCase = true) }
        state.preferredProviders = if (state.providerSelectionMax > 0) merged.take(state.providerSelectionMax) else merged
    }

    // モデル選択変更時に、まだ優先プロバイダーが未設定ならモデルの既定プロバイダーを初期値にする
    LaunchedEffect(state.model, state.apiProvider, state.openRouterModels) {
        val selectedModelInfo = state.openRouterModels.find { it.id == state.model }
        if (state.apiProvider == "OPENROUTER" && state.preferredProviders.isEmpty()) {
            selectedModelInfo?.provider?.let { prov ->
                state.preferredProviders = listOf(prov)
            }
        }
    }

    // --- デュアルモード: A/Bのプロバイダー選択の自動反映 ---
    LaunchedEffect(state.dualSelectedProviderA, state.dualProviderA) {
        if (state.dualProviderA != "OPENROUTER") return@LaunchedEffect
        val sel = state.dualSelectedProviderA ?: return@LaunchedEffect
        val merged = listOf(sel) + state.preferredProviders.filterNot { it.equals(sel, ignoreCase = true) }
        state.preferredProviders = if (state.providerSelectionMax > 0) merged.take(state.providerSelectionMax) else merged
    }
    LaunchedEffect(state.dualSelectedProviderB, state.dualProviderB) {
        if (state.dualProviderB != "OPENROUTER") return@LaunchedEffect
        val sel = state.dualSelectedProviderB ?: return@LaunchedEffect
        val merged = listOf(sel) + state.preferredProviders.filterNot { it.equals(sel, ignoreCase = true) }
        state.preferredProviders = if (state.providerSelectionMax > 0) merged.take(state.providerSelectionMax) else merged
    }
    LaunchedEffect(state.dualModelA, state.dualProviderA, state.openRouterModels) {
        val dualModelInfoA = state.openRouterModels.find { it.id == state.dualModelA }
        if (state.dualProviderA == "OPENROUTER" && state.preferredProviders.isEmpty()) {
            dualModelInfoA?.provider?.let { state.preferredProviders = listOf(it) }
        }
    }
    LaunchedEffect(state.dualModelB, state.dualProviderB, state.openRouterModels) {
        val dualModelInfoB = state.openRouterModels.find { it.id == state.dualModelB }
        if (state.dualProviderB == "OPENROUTER" && state.preferredProviders.isEmpty()) {
            dualModelInfoB?.provider?.let { state.preferredProviders = listOf(it) }
        }
    }

    // --- 自動会話: A/Bのプロバイダー選択の自動反映 ---
    LaunchedEffect(state.autoSelectedProviderA, state.autoProviderA) {
        if (state.autoProviderA != "OPENROUTER") return@LaunchedEffect
        val sel = state.autoSelectedProviderA ?: return@LaunchedEffect
        val merged = listOf(sel) + state.preferredProviders.filterNot { it.equals(sel, ignoreCase = true) }
        state.preferredProviders = if (state.providerSelectionMax > 0) merged.take(state.providerSelectionMax) else merged
    }
    LaunchedEffect(state.autoSelectedProviderB, state.autoProviderB) {
        if (state.autoProviderB != "OPENROUTER") return@LaunchedEffect
        val sel = state.autoSelectedProviderB ?: return@LaunchedEffect
        val merged = listOf(sel) + state.preferredProviders.filterNot { it.equals(sel, ignoreCase = true) }
        state.preferredProviders = if (state.providerSelectionMax > 0) merged.take(state.providerSelectionMax) else merged
    }
    LaunchedEffect(state.autoModelA, state.autoProviderA, state.openRouterModels) {
        val autoModelInfoA = state.openRouterModels.find { it.id == state.autoModelA }
        if (state.autoProviderA == "OPENROUTER" && state.preferredProviders.isEmpty()) {
            autoModelInfoA?.provider?.let { state.preferredProviders = listOf(it) }
        }
    }
    LaunchedEffect(state.autoModelB, state.autoProviderB, state.openRouterModels) {
        val autoModelInfoB = state.openRouterModels.find { it.id == state.autoModelB }
        if (state.autoProviderB == "OPENROUTER" && state.preferredProviders.isEmpty()) {
            autoModelInfoB?.provider?.let { state.preferredProviders = listOf(it) }
        }
    }

    // --- プリセットダイアログ: プロバイダー選択の自動反映 ---
    LaunchedEffect(state.presetSelectedProvider, state.presetApiProvider) {
        if (state.presetApiProvider != "OPENROUTER") return@LaunchedEffect
        val sel = state.presetSelectedProvider ?: return@LaunchedEffect
        val exists = state.preferredProviders.any { it.equals(sel, ignoreCase = true) }
        state.preferredProviders = if (!exists) {
            val merged = (listOf(sel) + state.preferredProviders).distinctBy { it.lowercase() }
            if (state.providerSelectionMax > 0) merged.take(state.providerSelectionMax) else merged
        } else {
            (listOf(sel) + state.preferredProviders.filterNot { it.equals(sel, ignoreCase = true) })
        }
    }
    LaunchedEffect(state.presetModel, state.presetApiProvider, state.openRouterModels) {
        val presetModelInfo = state.openRouterModels.find { it.id == state.presetModel }
        if (state.presetApiProvider == "OPENROUTER" && state.preferredProviders.isEmpty()) {
            presetModelInfo?.provider?.let { state.preferredProviders = listOf(it) }
        }
    }

    LaunchedEffect(state.presetModel, state.presetApiProvider) {
        if (state.presetApiProvider == "CODEX_AUTH") {
            val preset = CodexModelPresets.findPreset(state.presetModel)
            val supported = preset?.supportedReasoningEfforts?.map { it.effort }.orEmpty()
            val defaultEffort = preset?.defaultReasoningEffort ?: "medium"
            if (supported.isNotEmpty() && !supported.contains(state.presetReasoningEffort)) {
                state.presetReasoningEffort = defaultEffort
            } else if (state.presetReasoningEffort.isBlank()) {
                state.presetReasoningEffort = defaultEffort
            }
            if (state.presetCodexReasoningSummary.isBlank()) {
                state.presetCodexReasoningSummary = "auto"
            }
            if (state.presetCodexVerbosity.isBlank()) {
                state.presetCodexVerbosity = "medium"
            }
            if (state.presetCodexWebSearchContextSize.isBlank()) {
                state.presetCodexWebSearchContextSize = "medium"
            }
            if (state.presetCodexPromptCacheType.isBlank()) {
                state.presetCodexPromptCacheType = "ephemeral"
            }
            if (state.presetCodexPromptCacheMinLength < 0) {
                state.presetCodexPromptCacheMinLength = 0
            }
        }
        if (state.presetApiProvider == "GEMINI") {
            val isSupported = ModelUtils.isThinkingSupported(state.presetModel)
            if (!isSupported && state.presetThinkingEnabled) {
                state.presetThinkingEnabled = false
            }
            if (ModelUtils.isThinkingAlwaysOn(state.presetModel) && !state.presetThinkingEnabled) {
                state.presetThinkingEnabled = true
            }
            if (ModelUtils.isThinkingLevelSupported(state.presetModel)) {
                val minimal = ModelUtils.getMinimalThinkingLevel(state.presetModel)
                val normalized = ModelUtils.normalizeThinkingLevel(state.presetModel, state.presetThinkingLevel)
                if (!state.presetThinkingEnabled && minimal != null) {
                    state.presetThinkingLevel = minimal
                } else if (normalized == null) {
                    state.presetThinkingLevel = ModelUtils.getDefaultThinkingLevel(state.presetModel)
                } else if (normalized != state.presetThinkingLevel) {
                    state.presetThinkingLevel = normalized
                }
            }
        }
    }

    LaunchedEffect(state.reasoningMode, state.apiProvider) {
        if (state.apiProvider == "OPENROUTER" && state.reasoningMode != "effort" && state.reasoningEffort.isNotEmpty()) {
            state.reasoningEffort = ""
        }
    }

    LaunchedEffect(state.presetReasoningMode, state.presetApiProvider) {
        if (state.presetApiProvider == "OPENROUTER" &&
            state.presetReasoningMode != "effort" &&
            state.presetReasoningEffort.isNotEmpty()
        ) {
            state.presetReasoningEffort = ""
        }
    }

    // APIプロバイダー切り替え時の表示制御
    LaunchedEffect(state.apiProvider) {
        val selected = state.apiProvider.uppercase()
        if (selected != "GEMINI") {
            state.geminiKeyVisible = false
            state.geminiKeyLoadedFromStorage = false
        }
        if (selected != "OPENROUTER") {
            state.openRouterKeyVisible = false
            state.openRouterKeyLoadedFromStorage = false
        }
        if (selected != "OPENAI") {
            state.openAiKeyVisible = false
            state.openAiKeyLoadedFromStorage = false
        }
        if (selected != "MINIMAX") {
            state.miniMaxKeyVisible = false
            state.miniMaxKeyLoadedFromStorage = false
        }
        if (selected != "OPENAI_COMPAT") {
            state.openAiCompatKeyVisible = false
            state.openAiCompatKeyLoadedFromStorage = false
        }
        if (selected != "ZAI") {
            state.zaiKeyVisible = false
            state.zaiKeyLoadedFromStorage = false
        }
        if (selected != "OPENCODE_GO") {
            state.openCodeGoKeyVisible = false
            state.openCodeGoKeyLoadedFromStorage = false
        }
        if (selected != "CLINEPASS") {
            state.clinePassKeyVisible = false
            state.clinePassKeyLoadedFromStorage = false
        }
        if (selected != "ALIBABA_CODING_PLAN") {
            state.alibabaCodingPlanKeyVisible = false
            state.alibabaCodingPlanKeyLoadedFromStorage = false
            state.alibabaMcpTokenVisible = false
            state.alibabaMcpTokenLoadedFromStorage = false
        }
    }

    // APIプロバイダーが変更された時の設定更新
    LaunchedEffect(state.apiProvider, settings) {
        state.googleSearchEnabled = false
        state.codeExecutionEnabled = false
        state.urlContextEnabled = false
        state.googleMapsEnabled = false
        state.computerUseEnabled = false
        settings?.let {
            val provider = state.apiProvider
            state.googleSearchEnabled = it.isGoogleSearchEnabledFor(provider)
            state.codeExecutionEnabled = it.isCodeExecutionEnabledFor(provider)
            state.urlContextEnabled = it.isUrlContextEnabledFor(provider)
            state.googleMapsEnabled = it.isGoogleMapsEnabledFor(provider)
            state.computerUseEnabled = it.isComputerUseEnabledFor(provider)
            state.thinkingEnabled = it.isThinkingEnabledFor(provider)
            state.thinkingBudget = it.thinkingBudgetFor(provider).toFloat()
            state.thinkingLevel = it.thinkingLevelFor(provider)
            state.isStreamingEnabled = it.isStreamingEnabledFor(provider)
            state.codexUserAgentPreset = it.codexUserAgentPreset.ifBlank { "ANDROID" }
            state.codexReasoningEnabled = it.codexReasoningEnabled
            state.codexReasoningEffort = it.codexReasoningEffort
            state.codexReasoningSummary = it.codexReasoningSummary.ifBlank { "auto" }
            state.codexVerbosity = it.codexVerbosity.ifBlank { "medium" }
            state.codexSupportsReasoningSummaries = it.codexSupportsReasoningSummaries
            state.codexShowReasoningSummary = it.codexShowReasoningSummary
            state.codexWebSearchEnabled = it.codexWebSearchEnabled
            state.codexWebSearchContextSize = it.codexWebSearchContextSize.ifBlank { "medium" }
            state.codexPromptCacheEnabled = it.codexPromptCacheEnabled
            state.codexPromptCacheMinLength = it.codexPromptCacheMinLength
            state.codexPromptCacheType = it.codexPromptCacheType.ifBlank { "ephemeral" }
            state.superGrokReasoningEnabled = it.superGrokReasoningEnabled
            state.superGrokReasoningEffort = it.superGrokReasoningEffort.ifBlank { "medium" }
            if (state.apiProvider == "OPENROUTER") {
                state.reasoningMode = it.openRouterReasoningMode
                state.reasoningEffort = it.openRouterReasoningEffort
                state.reasoningExclude = it.openRouterReasoningExclude
            }
            if (state.apiProvider == "GEMINI") {
                state.responseMimeType = it.geminiResponseMimeType
                state.responseJsonSchema = it.geminiResponseJsonSchema
                state.functionDeclarations = it.geminiFunctionDeclarations
            }
        }

        if (state.apiProvider == "OPENROUTER" && state.openRouterModels.isEmpty()) {
            viewModel.loadOpenRouterModels()
        }
    }

    // Geminiモデル変更時のthinking自動制御
    LaunchedEffect(state.model, state.apiProvider) {
        val normalizedProvider = state.apiProvider.uppercase()
        val normalizedModel = state.model.trim()
        if (normalizedModel.isNotBlank()) {
            state.providerModels[normalizedProvider] = normalizedModel
        } else {
            state.providerModels.remove(normalizedProvider)
        }

        if (state.apiProvider == "GEMINI") {
            val isSupported = ModelUtils.isThinkingSupported(state.model)
            if (!isSupported && state.thinkingEnabled) {
                state.thinkingEnabled = false
                android.util.Log.d("SettingsScreen", "Auto-disabled thinking for non-thinking model: ${state.model}")
            }
            if (ModelUtils.isThinkingAlwaysOn(state.model) && !state.thinkingEnabled) {
                state.thinkingEnabled = true
            }
            if (ModelUtils.isThinkingLevelSupported(state.model)) {
                val minimal = ModelUtils.getMinimalThinkingLevel(state.model)
                val normalized = ModelUtils.normalizeThinkingLevel(state.model, state.thinkingLevel)
                if (!state.thinkingEnabled && minimal != null) {
                    state.thinkingLevel = minimal
                } else if (normalized == null) {
                    state.thinkingLevel = ModelUtils.getDefaultThinkingLevel(state.model)
                } else if (normalized != state.thinkingLevel) {
                    state.thinkingLevel = normalized
                }
            }
        }

        if (state.apiProvider == "SUPERGROK") {
            val selected = com.porarri.yamabikochat.data.remote.SuperGrokModelCatalog.modelFor(state.model)
            if (selected?.supportsReasoning == false && state.superGrokReasoningEnabled) {
                state.superGrokReasoningEnabled = false
            } else if (state.superGrokReasoningEffort.isBlank()) {
                state.superGrokReasoningEffort = "medium"
            }
        }

        if (state.apiProvider == "CODEX_AUTH") {
            val preset = com.porarri.yamabikochat.utils.CodexModelPresets.findPreset(state.model)
            val supported = preset?.supportedReasoningEfforts?.map { it.effort }
            val defaultEffort = preset?.defaultReasoningEffort ?: "medium"
            if (supported != null && supported.isNotEmpty()) {
                if (!supported.contains(state.codexReasoningEffort)) {
                    state.codexReasoningEffort = defaultEffort
                }
            } else if (state.codexReasoningEffort.isBlank()) {
                state.codexReasoningEffort = defaultEffort
            }
            if (state.codexReasoningSummary.isBlank()) {
                state.codexReasoningSummary = "auto"
            }
            if (state.codexVerbosity.isBlank()) {
                state.codexVerbosity = "medium"
            }
            if (state.codexWebSearchContextSize.isBlank()) {
                state.codexWebSearchContextSize = "medium"
            }
            if (state.codexPromptCacheType.isBlank()) {
                state.codexPromptCacheType = "ephemeral"
            }
        }
    }

    // デュアルモード、自動会話モード、プリセットでOpenRouterが選択された時のモデル読み込み
    LaunchedEffect(state.dualProviderA, state.dualProviderB, state.autoProviderA, state.autoProviderB, state.presetApiProvider) {
        val needsOpenRouterModels = state.dualProviderA == "OPENROUTER" ||
            state.dualProviderB == "OPENROUTER" ||
            state.autoProviderA == "OPENROUTER" ||
            state.autoProviderB == "OPENROUTER" ||
            state.presetApiProvider == "OPENROUTER"

        if (needsOpenRouterModels && state.openRouterModels.isEmpty()) {
            viewModel.loadOpenRouterModels()
        }
    }

    LaunchedEffect(state.dualProviderA, state.dualModelA, state.dualThinkingOverrideA) {
        if (!state.dualThinkingOverrideA) return@LaunchedEffect
        if (state.dualProviderA == "GEMINI") {
            val isSupported = ModelUtils.isThinkingSupported(state.dualModelA)
            if (!isSupported && state.dualThinkingEnabledA) {
                state.dualThinkingEnabledA = false
            }
            if (ModelUtils.isThinkingAlwaysOn(state.dualModelA) && !state.dualThinkingEnabledA) {
                state.dualThinkingEnabledA = true
            }
            if (ModelUtils.isThinkingLevelSupported(state.dualModelA)) {
                val minimal = ModelUtils.getMinimalThinkingLevel(state.dualModelA)
                val normalized = ModelUtils.normalizeThinkingLevel(state.dualModelA, state.dualThinkingLevelA)
                if (!state.dualThinkingEnabledA && minimal != null) {
                    state.dualThinkingLevelA = minimal
                } else if (normalized == null) {
                    state.dualThinkingLevelA = ModelUtils.getDefaultThinkingLevel(state.dualModelA)
                } else if (normalized != state.dualThinkingLevelA) {
                    state.dualThinkingLevelA = normalized
                }
            }
        }
        if (state.dualProviderA == "CODEX_AUTH") {
            val preset = CodexModelPresets.findPreset(state.dualModelA)
            val supported = preset?.supportedReasoningEfforts?.map { it.effort }
            val defaultEffort = preset?.defaultReasoningEffort ?: "medium"
            if (supported != null && supported.isNotEmpty()) {
                if (!supported.contains(state.dualCodexReasoningEffortA)) {
                    state.dualCodexReasoningEffortA = defaultEffort
                }
            } else if (state.dualCodexReasoningEffortA.isBlank()) {
                state.dualCodexReasoningEffortA = defaultEffort
            }
        }
    }

    LaunchedEffect(state.dualProviderB, state.dualModelB, state.dualThinkingOverrideB) {
        if (!state.dualThinkingOverrideB) return@LaunchedEffect
        if (state.dualProviderB == "GEMINI") {
            val isSupported = ModelUtils.isThinkingSupported(state.dualModelB)
            if (!isSupported && state.dualThinkingEnabledB) {
                state.dualThinkingEnabledB = false
            }
            if (ModelUtils.isThinkingAlwaysOn(state.dualModelB) && !state.dualThinkingEnabledB) {
                state.dualThinkingEnabledB = true
            }
            if (ModelUtils.isThinkingLevelSupported(state.dualModelB)) {
                val minimal = ModelUtils.getMinimalThinkingLevel(state.dualModelB)
                val normalized = ModelUtils.normalizeThinkingLevel(state.dualModelB, state.dualThinkingLevelB)
                if (!state.dualThinkingEnabledB && minimal != null) {
                    state.dualThinkingLevelB = minimal
                } else if (normalized == null) {
                    state.dualThinkingLevelB = ModelUtils.getDefaultThinkingLevel(state.dualModelB)
                } else if (normalized != state.dualThinkingLevelB) {
                    state.dualThinkingLevelB = normalized
                }
            }
        }
        if (state.dualProviderB == "CODEX_AUTH") {
            val preset = CodexModelPresets.findPreset(state.dualModelB)
            val supported = preset?.supportedReasoningEfforts?.map { it.effort }
            val defaultEffort = preset?.defaultReasoningEffort ?: "medium"
            if (supported != null && supported.isNotEmpty()) {
                if (!supported.contains(state.dualCodexReasoningEffortB)) {
                    state.dualCodexReasoningEffortB = defaultEffort
                }
            } else if (state.dualCodexReasoningEffortB.isBlank()) {
                state.dualCodexReasoningEffortB = defaultEffort
            }
        }
    }

    LaunchedEffect(state.autoProviderA, state.autoModelA, state.autoThinkingOverrideA) {
        if (!state.autoThinkingOverrideA) return@LaunchedEffect
        if (state.autoProviderA == "GEMINI") {
            val isSupported = ModelUtils.isThinkingSupported(state.autoModelA)
            if (!isSupported && state.autoThinkingEnabledA) {
                state.autoThinkingEnabledA = false
            }
            if (ModelUtils.isThinkingAlwaysOn(state.autoModelA) && !state.autoThinkingEnabledA) {
                state.autoThinkingEnabledA = true
            }
            if (ModelUtils.isThinkingLevelSupported(state.autoModelA)) {
                val minimal = ModelUtils.getMinimalThinkingLevel(state.autoModelA)
                val normalized = ModelUtils.normalizeThinkingLevel(state.autoModelA, state.autoThinkingLevelA)
                if (!state.autoThinkingEnabledA && minimal != null) {
                    state.autoThinkingLevelA = minimal
                } else if (normalized == null) {
                    state.autoThinkingLevelA = ModelUtils.getDefaultThinkingLevel(state.autoModelA)
                } else if (normalized != state.autoThinkingLevelA) {
                    state.autoThinkingLevelA = normalized
                }
            }
        }
        if (state.autoProviderA == "CODEX_AUTH") {
            val preset = CodexModelPresets.findPreset(state.autoModelA)
            val supported = preset?.supportedReasoningEfforts?.map { it.effort }
            val defaultEffort = preset?.defaultReasoningEffort ?: "medium"
            if (supported != null && supported.isNotEmpty()) {
                if (!supported.contains(state.autoCodexReasoningEffortA)) {
                    state.autoCodexReasoningEffortA = defaultEffort
                }
            } else if (state.autoCodexReasoningEffortA.isBlank()) {
                state.autoCodexReasoningEffortA = defaultEffort
            }
        }
    }

    LaunchedEffect(state.autoProviderB, state.autoModelB, state.autoThinkingOverrideB) {
        if (!state.autoThinkingOverrideB) return@LaunchedEffect
        if (state.autoProviderB == "GEMINI") {
            val isSupported = ModelUtils.isThinkingSupported(state.autoModelB)
            if (!isSupported && state.autoThinkingEnabledB) {
                state.autoThinkingEnabledB = false
            }
            if (ModelUtils.isThinkingAlwaysOn(state.autoModelB) && !state.autoThinkingEnabledB) {
                state.autoThinkingEnabledB = true
            }
            if (ModelUtils.isThinkingLevelSupported(state.autoModelB)) {
                val minimal = ModelUtils.getMinimalThinkingLevel(state.autoModelB)
                val normalized = ModelUtils.normalizeThinkingLevel(state.autoModelB, state.autoThinkingLevelB)
                if (!state.autoThinkingEnabledB && minimal != null) {
                    state.autoThinkingLevelB = minimal
                } else if (normalized == null) {
                    state.autoThinkingLevelB = ModelUtils.getDefaultThinkingLevel(state.autoModelB)
                } else if (normalized != state.autoThinkingLevelB) {
                    state.autoThinkingLevelB = normalized
                }
            }
        }
        if (state.autoProviderB == "CODEX_AUTH") {
            val preset = CodexModelPresets.findPreset(state.autoModelB)
            val supported = preset?.supportedReasoningEfforts?.map { it.effort }
            val defaultEffort = preset?.defaultReasoningEffort ?: "medium"
            if (supported != null && supported.isNotEmpty()) {
                if (!supported.contains(state.autoCodexReasoningEffortB)) {
                    state.autoCodexReasoningEffortB = defaultEffort
                }
            } else if (state.autoCodexReasoningEffortB.isBlank()) {
                state.autoCodexReasoningEffortB = defaultEffort
            }
        }
    }

    return state
}

private data class ReasoningBaseline(
    val enabled: Boolean,
    val budget: Int,
    val mode: String,
    val effort: String,
    val exclude: Boolean
)

private data class ToolDefaults(
    val googleSearchEnabled: Boolean = false,
    val codeExecutionEnabled: Boolean = false,
    val urlContextEnabled: Boolean = false,
    val googleMapsEnabled: Boolean = false,
    val computerUseEnabled: Boolean = false
)

private data class ThinkingDefaults(
    val enabled: Boolean = false,
    val budget: Int = 0,
    val level: String = "",
    val codexEffort: String = "medium"
)

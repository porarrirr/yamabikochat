package com.porarri.yamabikochat.ui.settings

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.porarri.yamabikochat.data.ChatRepository
import com.porarri.yamabikochat.data.auth.CodexAuthState
import com.porarri.yamabikochat.data.auth.CodexUsageStatus
import com.porarri.yamabikochat.data.local.ModelPreset
import com.porarri.yamabikochat.data.local.Settings
import com.porarri.yamabikochat.data.local.TokenUsageByModel
import com.porarri.yamabikochat.data.local.TokenUsageDailyPoint
import com.porarri.yamabikochat.data.local.TokenUsageTotals
import com.porarri.yamabikochat.data.remote.SimpleModel
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.time.Instant

private const val OPENROUTER_RECENT_LIMIT = 5
private const val TOKEN_STATS_RANGE_DAYS = 30L
private const val TOKEN_STATS_MODEL_LIMIT = 12

class SettingsViewModel(private val repository: ChatRepository) : ViewModel() {

    val settings: StateFlow<Settings?> = repository.getSettings()
        .stateIn(viewModelScope, SharingStarted.Eagerly, null)

    private val _apiKeyStatus = MutableStateFlow(ApiKeyStatus())
    val apiKeyStatus: StateFlow<ApiKeyStatus> = _apiKeyStatus.asStateFlow()

    val modelPresets: StateFlow<List<ModelPreset>> = repository.getAllModelPresets()
        .stateIn(viewModelScope, SharingStarted.Eagerly, emptyList())

    // OpenRouter Models
    val openRouterModels: StateFlow<List<SimpleModel>> = repository.getOpenRouterModelsFlow()
        .stateIn(viewModelScope, SharingStarted.Lazily, emptyList())

    val openRouterModelsLoading: StateFlow<Boolean> = repository.getOpenRouterModelsLoading()
        .stateIn(viewModelScope, SharingStarted.Lazily, false)

    val openRouterModelsError: StateFlow<String?> = repository.getOpenRouterModelsError()
        .stateIn(viewModelScope, SharingStarted.Lazily, null)

    private val _secureStorageError = MutableStateFlow<String?>(null)
    val secureStorageError: StateFlow<String?> = _secureStorageError.asStateFlow()

    val codexAuthState: StateFlow<CodexAuthState> = repository.codexAuthState

    private val _codexAuthError = MutableStateFlow<String?>(null)
    val codexAuthError: StateFlow<String?> = _codexAuthError.asStateFlow()

    private val _codexUsageState = MutableStateFlow(CodexUsageUiState())
    val codexUsageState: StateFlow<CodexUsageUiState> = _codexUsageState.asStateFlow()
    private val _tokenUsageState = MutableStateFlow(TokenUsageUiState())
    val tokenUsageState: StateFlow<TokenUsageUiState> = _tokenUsageState.asStateFlow()

    init {
        viewModelScope.launch { updateApiKeyStatus() }
        observeTokenUsageStats()
    }

    fun clearSecureStorageError() { _secureStorageError.value = null }

    fun clearCodexAuthError() { _codexAuthError.value = null }

    fun refreshApiKeyStatus() {
        viewModelScope.launch { updateApiKeyStatus() }
    }

    fun loginCodexAuth() {
        viewModelScope.launch {
            val result = repository.loginCodexAuth()
            _codexAuthError.value = result.exceptionOrNull()?.message
            updateApiKeyStatus()
        }
    }

    fun logoutCodexAuth() {
        viewModelScope.launch {
            val result = repository.logoutCodexAuth()
            _codexAuthError.value = result.exceptionOrNull()?.message
            clearCodexUsage()
            updateApiKeyStatus()
        }
    }

    fun refreshCodexAuth(force: Boolean = false) {
        viewModelScope.launch {
            val result = repository.refreshCodexAuth(force)
            _codexAuthError.value = result.exceptionOrNull()?.message
            updateApiKeyStatus()
        }
    }

    fun refreshCodexUsage() {
        viewModelScope.launch {
            val current = _codexUsageState.value
            _codexUsageState.value = current.copy(isLoading = true, error = null)
            val result = repository.retrieveCodexAuthUsage()
            _codexUsageState.value = result.fold(
                onSuccess = { usage ->
                    CodexUsageUiState(
                        isLoading = false,
                        error = null,
                        usage = usage,
                        lastUpdated = Instant.now().toString()
                    )
                },
                onFailure = { err ->
                    current.copy(
                        isLoading = false,
                        error = err.message ?: "Failed to load rate limits"
                    )
                }
            )
        }
    }

    private fun clearCodexUsage() {
        _codexUsageState.value = CodexUsageUiState()
    }

    private fun observeTokenUsageStats() {
        val now = System.currentTimeMillis()
        val since = now - TOKEN_STATS_RANGE_DAYS * 24L * 60L * 60L * 1000L
        viewModelScope.launch {
            combine(
                repository.observeTokenUsageTotals(since),
                repository.observeTokenUsageByModel(since, TOKEN_STATS_MODEL_LIMIT),
                repository.observeTokenUsageDaily(since)
            ) { totals, byModel, daily ->
                TokenUsageUiState(
                    rangeDays = TOKEN_STATS_RANGE_DAYS.toInt(),
                    totals = totals,
                    byModel = byModel,
                    daily = daily,
                    lastUpdated = Instant.now().toString()
                )
            }.collect { newState ->
                _tokenUsageState.value = newState
            }
        }
    }

    suspend fun revealApiKey(provider: String): String? = withContext(Dispatchers.IO) {
        repository.peekApiKey(provider)
    }

    fun clearApiKey(provider: String) {
        viewModelScope.launch {
            val success = repository.saveApiKey(provider, null)
            _secureStorageError.value = if (!success) {
                "暗号化ストレージを初期化できなかったため、APIキーを保存できませんでした。"
            } else null
            updateApiKeyStatus()
        }
    }

    private suspend fun updateApiKeyStatus() {
        _apiKeyStatus.value = ApiKeyStatus(
            hasGeminiKey = repository.hasApiKey("GEMINI"),
            hasOpenRouterKey = repository.hasApiKey("OPENROUTER"),
            hasOpenAiKey = repository.hasApiKey("OPENAI"),
            hasMiniMaxKey = repository.hasApiKey("MINIMAX"),
            hasZaiKey = repository.hasApiKey("ZAI"),
            hasCodexAuth = repository.hasCodexAuth()
        )
    }

    fun saveSettings(request: SettingsUpdateRequest) {
        viewModelScope.launch {
            val currentSettings = settings.value ?: Settings()

            val preferredProvidersJson = request.preferredProviders.takeIf { it.isNotEmpty() }?.let {
                com.google.gson.Gson().toJson(it)
            } ?: ""
            val selectedQuantizationsJson = request.selectedQuantizations.takeIf { it.isNotEmpty() }?.let {
                com.google.gson.Gson().toJson(it)
            } ?: ""
            val showGlobalProviderPresetsInChatByProviderJson = request.showGlobalProviderPresetsInChatByProvider
                .filterKeys { it.isNotBlank() }
                .mapKeys { (key, _) -> key.uppercase() }
                .takeIf { it.isNotEmpty() }
                ?.let { com.google.gson.Gson().toJson(it) }
                ?: ""
            val systemPromptPresetsJson = request.systemPromptPresets.takeIf { it.isNotEmpty() }?.let {
                com.google.gson.Gson().toJson(it)
            } ?: ""
            val selectedSystemPromptPreset = request.selectedSystemPromptPreset
                ?.takeIf { name -> request.systemPromptPresets.any { it.name.equals(name, ignoreCase = true) } }
            val normalizedRequest = request.copy(
                codexUserAgentPreset = request.codexUserAgentPreset.ifBlank { "ANDROID" },
                codexReasoningSummary = request.codexReasoningSummary.ifBlank { "auto" },
                codexVerbosity = request.codexVerbosity.ifBlank { "medium" },
                codexWebSearchContextSize = request.codexWebSearchContextSize.ifBlank { "medium" },
                codexPromptCacheType = request.codexPromptCacheType.ifBlank { "ephemeral" }
            )

            val updatedSettingsBase = when (normalizedRequest.apiProvider) {
                "OPENROUTER" -> currentSettings.toOpenRouterUpdate(
                    normalizedRequest,
                    preferredProvidersJson,
                    selectedQuantizationsJson,
                    showGlobalProviderPresetsInChatByProviderJson
                )
                else -> currentSettings.toGeminiUpdate(
                    normalizedRequest,
                    preferredProvidersJson,
                    selectedQuantizationsJson,
                    showGlobalProviderPresetsInChatByProviderJson
                )
            }

            val compatJson = request.openAiCompatPresets.takeIf { it.isNotEmpty() }?.let {
                com.google.gson.Gson().toJson(it)
            } ?: updatedSettingsBase.openAiCompatPresets

            val updatedSettings = updatedSettingsBase.copy(
                openAiBaseUrl = request.openAiBaseUrl,
                miniMaxBaseUrl = request.miniMaxBaseUrl,
                openAiCompatPresets = compatJson,
                selectedOpenAiCompatPreset = request.selectedOpenAiCompatPreset
                    ?: updatedSettingsBase.selectedOpenAiCompatPreset,
                systemPromptPresets = systemPromptPresetsJson,
                selectedSystemPromptPreset = selectedSystemPromptPreset
            )

            val previousProvider = currentSettings.apiProvider
            val previousProviderModel = currentSettings.getModelForProvider(previousProvider)

            val settingsWithModel = updatedSettings.withModelForProvider(
                provider = normalizedRequest.apiProvider,
                model = request.model,
                additionalModels = request.providerModels,
                previousProvider = previousProvider,
                previousModel = previousProviderModel
            )
            repository.saveSettings(settingsWithModel.remapRemovedProviders())
            val codexUaPresetSaved = repository.saveCodexUserAgentPreset(normalizedRequest.codexUserAgentPreset)

            val geminiSaveResult = when (request.geminiApiKeyAction) {
                ApiKeyAction.Update -> repository.saveApiKey("GEMINI", request.apiKey.ifBlank { null })
                ApiKeyAction.Clear -> repository.saveApiKey("GEMINI", null)
                ApiKeyAction.NoChange -> true
            }

            val openRouterSaveResult = when (request.openRouterApiKeyAction) {
                ApiKeyAction.Update -> repository.saveApiKey("OPENROUTER", request.openRouterApiKey.ifBlank { null })
                ApiKeyAction.Clear -> repository.saveApiKey("OPENROUTER", null)
                ApiKeyAction.NoChange -> true
            }

            val zaiSaveResult = when (request.zaiApiKeyAction) {
                ApiKeyAction.Update -> repository.saveApiKey("ZAI", request.zaiApiKey.ifBlank { null })
                ApiKeyAction.Clear -> repository.saveApiKey("ZAI", null)
                ApiKeyAction.NoChange -> true
            }

            val openAiSaveResult = when (request.openAiApiKeyAction) {
                ApiKeyAction.Update -> repository.saveApiKey("OPENAI", request.openAiApiKey.ifBlank { null })
                ApiKeyAction.Clear -> repository.saveApiKey("OPENAI", null)
                ApiKeyAction.NoChange -> true
            }

            val miniMaxSaveResult = when (request.miniMaxApiKeyAction) {
                ApiKeyAction.Update -> repository.saveApiKey("MINIMAX", request.miniMaxApiKey.ifBlank { null })
                ApiKeyAction.Clear -> repository.saveApiKey("MINIMAX", null)
                ApiKeyAction.NoChange -> true
            }

            val compatPresetName = request.selectedOpenAiCompatPreset?.takeIf { it.isNotBlank() }
            val openAiCompatSaveResult = when (request.openAiCompatApiKeyAction) {
                ApiKeyAction.Update -> {
                    if (compatPresetName == null) false
                    else repository.saveOpenAiCompatApiKey(compatPresetName, request.openAiCompatApiKey.ifBlank { null })
                }
                ApiKeyAction.Clear -> {
                    if (compatPresetName == null) false
                    else repository.saveOpenAiCompatApiKey(compatPresetName, null)
                }
                ApiKeyAction.NoChange -> true
            }

            _secureStorageError.value = when {
                request.openAiCompatApiKeyAction != ApiKeyAction.NoChange && compatPresetName == null ->
                    "OpenAI (Custom) のプリセットを選択してください。"
                !geminiSaveResult || !openRouterSaveResult || !zaiSaveResult || !openAiSaveResult ||
                    !miniMaxSaveResult || !openAiCompatSaveResult || !codexUaPresetSaved ->
                    "暗号化ストレージを初期化できなかったため、APIキーを保存できませんでした。"
                else -> null
            }

            updateApiKeyStatus()
        }
    }

    suspend fun getAvailableQuantizationsForModel(modelId: String): List<String> =
        repository.getAvailableQuantizationsForModel(modelId)

    suspend fun getModelEndpoints(modelId: String): List<com.porarri.yamabikochat.data.remote.ModelEndpoint> =
        repository.getModelEndpoints(modelId)

    suspend fun getProviderDirectory(): com.porarri.yamabikochat.data.remote.ProviderDirectory =
        repository.getProvidersDirectory()

    suspend fun getAvailableProvidersForModel(modelId: String): List<String> =
        repository.getAvailableProvidersForModel(modelId)

    fun loadOpenRouterModels() {
        viewModelScope.launch { repository.getOpenRouterModels(forceRefresh = false) }
    }

    fun refreshOpenRouterModels() {
        viewModelScope.launch { repository.getOpenRouterModels(forceRefresh = true) }
    }

    fun upsertModelPreset(preset: ModelPreset) {
        viewModelScope.launch { repository.upsertModelPreset(preset) }
    }

    fun deleteModelPreset(id: Long) {
        viewModelScope.launch { repository.deleteModelPresetById(id) }
    }

    fun updateMathRenderingEnabled(enabled: Boolean) {
        viewModelScope.launch {
            val current = settings.value ?: Settings()
            repository.saveSettings(current.copy(mathRenderingEnabled = enabled))
        }
    }

    fun toggleOpenRouterPinnedModel(modelId: String) {
        if (modelId.isBlank()) return
        viewModelScope.launch {
            val current = settings.value ?: Settings()
            val pinned = current.getOpenRouterPinnedModelsList().toMutableList()
            val removed = pinned.removeAll { it.equals(modelId, ignoreCase = true) }
            if (!removed) {
                pinned.add(0, modelId)
            }
            val json = com.google.gson.Gson().toJson(pinned)
            repository.saveSettings(current.copy(openRouterPinnedModels = json))
        }
    }

    fun registerOpenRouterRecentModel(modelId: String, limit: Int = OPENROUTER_RECENT_LIMIT) {
        if (modelId.isBlank()) return
        viewModelScope.launch {
            val current = settings.value ?: Settings()
            val recents = current.getOpenRouterRecentModelsList()
                .filterNot { it.equals(modelId, ignoreCase = true) }
                .toMutableList()
            recents.add(0, modelId)
            val trimmed = if (limit > 0) recents.take(limit) else recents
            val json = com.google.gson.Gson().toJson(trimmed)
            repository.saveSettings(current.copy(openRouterRecentModels = json))
        }
    }

    // --- OpenAI-compatible preset helpers ---
    fun addOrUpdateOpenAiCompatPreset(name: String, baseUrl: String) {
        viewModelScope.launch {
            val current = settings.value ?: Settings()
            val list = current.getOpenAiCompatPresetsList().toMutableList()
            val idx = list.indexOfFirst { it.name.equals(name, ignoreCase = true) }
            if (idx >= 0) list[idx] = com.porarri.yamabikochat.data.remote.OpenAiCompatPreset(name, baseUrl)
            else list.add(com.porarri.yamabikochat.data.remote.OpenAiCompatPreset(name, baseUrl))
            val json = com.google.gson.Gson().toJson(list)
            repository.saveSettings(current.copy(openAiCompatPresets = json, selectedOpenAiCompatPreset = name))
        }
    }

    fun removeOpenAiCompatPreset(name: String) {
        viewModelScope.launch {
            val current = settings.value ?: Settings()
            val list = current.getOpenAiCompatPresetsList().filterNot { it.name.equals(name, ignoreCase = true) }
            val json = com.google.gson.Gson().toJson(list)
            val newSelected = if (current.selectedOpenAiCompatPreset.equals(name, ignoreCase = true)) null else current.selectedOpenAiCompatPreset
            repository.saveSettings(current.copy(openAiCompatPresets = json, selectedOpenAiCompatPreset = newSelected))
        }
    }

    fun selectOpenAiCompatPreset(name: String) {
        viewModelScope.launch {
            val current = settings.value ?: Settings()
            repository.saveSettings(current.copy(selectedOpenAiCompatPreset = name))
        }
    }

    suspend fun saveOpenAiCompatApiKey(name: String, apiKey: String?): Boolean =
        repository.saveOpenAiCompatApiKey(name, apiKey)

    suspend fun revealOpenAiCompatApiKey(name: String): String? = withContext(Dispatchers.IO) {
        repository.peekOpenAiCompatApiKey(name)
    }

    fun clearOpenAiCompatApiKey(name: String) {
        viewModelScope.launch { repository.clearOpenAiCompatApiKey(name) }
    }

    fun hasOpenAiCompatApiKey(name: String?): Boolean = repository.hasOpenAiCompatApiKey(name)

    private fun Settings.toGeminiUpdate(
        request: SettingsUpdateRequest,
        preferredProvidersJson: String,
        selectedQuantizationsJson: String,
        showGlobalProviderPresetsInChatByProviderJson: String
    ): Settings = copy(
        defaultModel = request.model,
        systemPrompt = request.systemPrompt,
        apiProvider = request.apiProvider,
        geminiGoogleSearchEnabled = request.googleSearchEnabled,
        geminiCodeExecutionEnabled = request.codeExecutionEnabled,
        geminiUrlContextEnabled = request.urlContextEnabled,
        geminiGoogleMapsEnabled = request.googleMapsEnabled,
        geminiComputerUseEnabled = request.computerUseEnabled,
        geminiThinkingEnabled = request.thinkingEnabled,
        geminiThinkingBudget = request.thinkingBudget,
        geminiThinkingLevel = request.thinkingLevel,
        geminiStreamingEnabled = request.isStreamingEnabled,
        geminiResponseMimeType = request.responseMimeType,
        geminiResponseJsonSchema = request.responseJsonSchema,
        geminiFunctionDeclarations = request.functionDeclarations,
        isDualModeEnabled = request.isDualModeEnabled,
        dualModelA = request.dualModelA,
        dualModelB = request.dualModelB,
        dualProviderA = request.dualProviderA,
        dualProviderB = request.dualProviderB,
        dualSplitLayout = request.dualSplitLayout,
        dualSplitRatio = request.dualSplitRatio,
        dualSystemPromptA = request.dualSystemPromptA ?: dualSystemPromptA,
        dualSystemPromptB = request.dualSystemPromptB ?: dualSystemPromptB,
        isAutoConversationEnabled = request.isAutoConversationEnabled,
        autoModelA = request.autoModelA,
        autoModelB = request.autoModelB,
        autoProviderA = request.autoProviderA,
        autoProviderB = request.autoProviderB,
        autoSystemPromptA = request.autoSystemPromptA,
        autoSystemPromptB = request.autoSystemPromptB,
        autoMaxTurns = request.autoMaxTurns,
        mathRenderingEnabled = request.mathRenderingEnabled,
        dynamicColorEnabled = request.dynamicColorEnabled,
        themeColor = request.themeColor,
        themeMode = request.themeMode,
        showGlobalProviderPresetsInChat = request.showGlobalProviderPresetsInChat,
        showGlobalProviderPresetsInChatByProvider = showGlobalProviderPresetsInChatByProviderJson,
        preferredProviders = preferredProvidersJson,
        selectedQuantizations = selectedQuantizationsJson,
        maxPricePerMillionTokens = request.maxPricePerMillionTokens,
        allowFallbacks = request.allowFallbacks,
        requireParameters = request.requireParameters,
        providerSelectionMax = request.providerSelectionMax,
        providerSort = request.providerSort,
        dualOpenRouterThinkingEnabledA = request.dualOpenRouterThinkingEnabledA,
        dualOpenRouterThinkingBudgetA = request.dualOpenRouterThinkingBudgetA,
        dualOpenRouterReasoningModeA = request.dualOpenRouterReasoningModeA,
        dualOpenRouterReasoningEffortA = request.dualOpenRouterReasoningEffortA,
        dualOpenRouterReasoningExcludeA = request.dualOpenRouterReasoningExcludeA,
        dualOpenRouterThinkingEnabledB = request.dualOpenRouterThinkingEnabledB,
        dualOpenRouterThinkingBudgetB = request.dualOpenRouterThinkingBudgetB,
        dualOpenRouterReasoningModeB = request.dualOpenRouterReasoningModeB,
        dualOpenRouterReasoningEffortB = request.dualOpenRouterReasoningEffortB,
        dualOpenRouterReasoningExcludeB = request.dualOpenRouterReasoningExcludeB,
        autoOpenRouterThinkingEnabledA = request.autoOpenRouterThinkingEnabledA,
        autoOpenRouterThinkingBudgetA = request.autoOpenRouterThinkingBudgetA,
        autoOpenRouterReasoningModeA = request.autoOpenRouterReasoningModeA,
        autoOpenRouterReasoningEffortA = request.autoOpenRouterReasoningEffortA,
        autoOpenRouterReasoningExcludeA = request.autoOpenRouterReasoningExcludeA,
        autoOpenRouterThinkingEnabledB = request.autoOpenRouterThinkingEnabledB,
        autoOpenRouterThinkingBudgetB = request.autoOpenRouterThinkingBudgetB,
        autoOpenRouterReasoningModeB = request.autoOpenRouterReasoningModeB,
        autoOpenRouterReasoningEffortB = request.autoOpenRouterReasoningEffortB,
        autoOpenRouterReasoningExcludeB = request.autoOpenRouterReasoningExcludeB,
        codexReasoningEnabled = request.codexReasoningEnabled,
        codexReasoningEffort = request.codexReasoningEffort,
        codexReasoningSummary = request.codexReasoningSummary,
        codexVerbosity = request.codexVerbosity,
        codexSupportsReasoningSummaries = request.codexSupportsReasoningSummaries,
        codexShowReasoningSummary = request.codexShowReasoningSummary,
        codexWebSearchEnabled = request.codexWebSearchEnabled,
        codexWebSearchContextSize = request.codexWebSearchContextSize,
        codexPromptCacheEnabled = request.codexPromptCacheEnabled,
        codexPromptCacheMinLength = request.codexPromptCacheMinLength,
        codexPromptCacheType = request.codexPromptCacheType,
        codexUserAgentPreset = request.codexUserAgentPreset,
        dualGoogleSearchEnabledA = request.dualGoogleSearchEnabledA,
        dualCodeExecutionEnabledA = request.dualCodeExecutionEnabledA,
        dualUrlContextEnabledA = request.dualUrlContextEnabledA,
        dualGoogleMapsEnabledA = request.dualGoogleMapsEnabledA,
        dualComputerUseEnabledA = request.dualComputerUseEnabledA,
        dualThinkingEnabledA = request.dualThinkingEnabledA,
        dualThinkingBudgetA = request.dualThinkingBudgetA,
        dualThinkingLevelA = request.dualThinkingLevelA,
        dualCodexReasoningEffortA = request.dualCodexReasoningEffortA,
        dualGoogleSearchEnabledB = request.dualGoogleSearchEnabledB,
        dualCodeExecutionEnabledB = request.dualCodeExecutionEnabledB,
        dualUrlContextEnabledB = request.dualUrlContextEnabledB,
        dualGoogleMapsEnabledB = request.dualGoogleMapsEnabledB,
        dualComputerUseEnabledB = request.dualComputerUseEnabledB,
        dualThinkingEnabledB = request.dualThinkingEnabledB,
        dualThinkingBudgetB = request.dualThinkingBudgetB,
        dualThinkingLevelB = request.dualThinkingLevelB,
        dualCodexReasoningEffortB = request.dualCodexReasoningEffortB,
        autoGoogleSearchEnabledA = request.autoGoogleSearchEnabledA,
        autoCodeExecutionEnabledA = request.autoCodeExecutionEnabledA,
        autoUrlContextEnabledA = request.autoUrlContextEnabledA,
        autoGoogleMapsEnabledA = request.autoGoogleMapsEnabledA,
        autoComputerUseEnabledA = request.autoComputerUseEnabledA,
        autoThinkingEnabledA = request.autoThinkingEnabledA,
        autoThinkingBudgetA = request.autoThinkingBudgetA,
        autoThinkingLevelA = request.autoThinkingLevelA,
        autoCodexReasoningEffortA = request.autoCodexReasoningEffortA,
        autoGoogleSearchEnabledB = request.autoGoogleSearchEnabledB,
        autoCodeExecutionEnabledB = request.autoCodeExecutionEnabledB,
        autoUrlContextEnabledB = request.autoUrlContextEnabledB,
        autoGoogleMapsEnabledB = request.autoGoogleMapsEnabledB,
        autoComputerUseEnabledB = request.autoComputerUseEnabledB,
        autoThinkingEnabledB = request.autoThinkingEnabledB,
        autoThinkingBudgetB = request.autoThinkingBudgetB,
        autoThinkingLevelB = request.autoThinkingLevelB,
        autoCodexReasoningEffortB = request.autoCodexReasoningEffortB
    )

    private fun Settings.toOpenRouterUpdate(
        request: SettingsUpdateRequest,
        preferredProvidersJson: String,
        selectedQuantizationsJson: String,
        showGlobalProviderPresetsInChatByProviderJson: String
    ): Settings = copy(
        defaultModel = request.model,
        systemPrompt = request.systemPrompt,
        apiProvider = request.apiProvider,
        openRouterGoogleSearchEnabled = request.googleSearchEnabled,
        openRouterCodeExecutionEnabled = request.codeExecutionEnabled,
        openRouterThinkingEnabled = request.thinkingEnabled,
        openRouterThinkingBudget = request.thinkingBudget,
        openRouterStreamingEnabled = request.isStreamingEnabled,
        openRouterReasoningMode = request.openRouterReasoningMode,
        openRouterReasoningEffort = request.openRouterReasoningEffort,
        openRouterReasoningExclude = request.openRouterReasoningExclude,
        dualOpenRouterThinkingEnabledA = request.dualOpenRouterThinkingEnabledA,
        dualOpenRouterThinkingBudgetA = request.dualOpenRouterThinkingBudgetA,
        dualOpenRouterReasoningModeA = request.dualOpenRouterReasoningModeA,
        dualOpenRouterReasoningEffortA = request.dualOpenRouterReasoningEffortA,
        dualOpenRouterReasoningExcludeA = request.dualOpenRouterReasoningExcludeA,
        dualOpenRouterThinkingEnabledB = request.dualOpenRouterThinkingEnabledB,
        dualOpenRouterThinkingBudgetB = request.dualOpenRouterThinkingBudgetB,
        dualOpenRouterReasoningModeB = request.dualOpenRouterReasoningModeB,
        dualOpenRouterReasoningEffortB = request.dualOpenRouterReasoningEffortB,
        dualOpenRouterReasoningExcludeB = request.dualOpenRouterReasoningExcludeB,
        isDualModeEnabled = request.isDualModeEnabled,
        dualModelA = request.dualModelA,
        dualModelB = request.dualModelB,
        dualProviderA = request.dualProviderA,
        dualProviderB = request.dualProviderB,
        dualSplitLayout = request.dualSplitLayout,
        dualSplitRatio = request.dualSplitRatio,
        dualSystemPromptA = request.dualSystemPromptA ?: dualSystemPromptA,
        dualSystemPromptB = request.dualSystemPromptB ?: dualSystemPromptB,
        isAutoConversationEnabled = request.isAutoConversationEnabled,
        autoModelA = request.autoModelA,
        autoModelB = request.autoModelB,
        autoProviderA = request.autoProviderA,
        autoProviderB = request.autoProviderB,
        autoSystemPromptA = request.autoSystemPromptA,
        autoSystemPromptB = request.autoSystemPromptB,
        autoMaxTurns = request.autoMaxTurns,
        mathRenderingEnabled = request.mathRenderingEnabled,
        dynamicColorEnabled = request.dynamicColorEnabled,
        themeColor = request.themeColor,
        themeMode = request.themeMode,
        showGlobalProviderPresetsInChat = request.showGlobalProviderPresetsInChat,
        showGlobalProviderPresetsInChatByProvider = showGlobalProviderPresetsInChatByProviderJson,
        preferredProviders = preferredProvidersJson,
        selectedQuantizations = selectedQuantizationsJson,
        maxPricePerMillionTokens = request.maxPricePerMillionTokens,
        allowFallbacks = request.allowFallbacks,
        requireParameters = request.requireParameters,
        providerSelectionMax = request.providerSelectionMax,
        providerSort = request.providerSort,
        codexReasoningEnabled = request.codexReasoningEnabled,
        codexReasoningEffort = request.codexReasoningEffort,
        codexReasoningSummary = request.codexReasoningSummary,
        codexVerbosity = request.codexVerbosity,
        codexSupportsReasoningSummaries = request.codexSupportsReasoningSummaries,
        codexShowReasoningSummary = request.codexShowReasoningSummary,
        codexWebSearchEnabled = request.codexWebSearchEnabled,
        codexWebSearchContextSize = request.codexWebSearchContextSize,
        codexPromptCacheEnabled = request.codexPromptCacheEnabled,
        codexPromptCacheMinLength = request.codexPromptCacheMinLength,
        codexPromptCacheType = request.codexPromptCacheType,
        codexUserAgentPreset = request.codexUserAgentPreset,
        dualGoogleSearchEnabledA = request.dualGoogleSearchEnabledA,
        dualCodeExecutionEnabledA = request.dualCodeExecutionEnabledA,
        dualUrlContextEnabledA = request.dualUrlContextEnabledA,
        dualGoogleMapsEnabledA = request.dualGoogleMapsEnabledA,
        dualComputerUseEnabledA = request.dualComputerUseEnabledA,
        dualThinkingEnabledA = request.dualThinkingEnabledA,
        dualThinkingBudgetA = request.dualThinkingBudgetA,
        dualThinkingLevelA = request.dualThinkingLevelA,
        dualCodexReasoningEffortA = request.dualCodexReasoningEffortA,
        dualGoogleSearchEnabledB = request.dualGoogleSearchEnabledB,
        dualCodeExecutionEnabledB = request.dualCodeExecutionEnabledB,
        dualUrlContextEnabledB = request.dualUrlContextEnabledB,
        dualGoogleMapsEnabledB = request.dualGoogleMapsEnabledB,
        dualComputerUseEnabledB = request.dualComputerUseEnabledB,
        dualThinkingEnabledB = request.dualThinkingEnabledB,
        dualThinkingBudgetB = request.dualThinkingBudgetB,
        dualThinkingLevelB = request.dualThinkingLevelB,
        dualCodexReasoningEffortB = request.dualCodexReasoningEffortB,
        autoGoogleSearchEnabledA = request.autoGoogleSearchEnabledA,
        autoCodeExecutionEnabledA = request.autoCodeExecutionEnabledA,
        autoUrlContextEnabledA = request.autoUrlContextEnabledA,
        autoGoogleMapsEnabledA = request.autoGoogleMapsEnabledA,
        autoComputerUseEnabledA = request.autoComputerUseEnabledA,
        autoThinkingEnabledA = request.autoThinkingEnabledA,
        autoThinkingBudgetA = request.autoThinkingBudgetA,
        autoThinkingLevelA = request.autoThinkingLevelA,
        autoCodexReasoningEffortA = request.autoCodexReasoningEffortA,
        autoGoogleSearchEnabledB = request.autoGoogleSearchEnabledB,
        autoCodeExecutionEnabledB = request.autoCodeExecutionEnabledB,
        autoUrlContextEnabledB = request.autoUrlContextEnabledB,
        autoGoogleMapsEnabledB = request.autoGoogleMapsEnabledB,
        autoComputerUseEnabledB = request.autoComputerUseEnabledB,
        autoThinkingEnabledB = request.autoThinkingEnabledB,
        autoThinkingBudgetB = request.autoThinkingBudgetB,
        autoThinkingLevelB = request.autoThinkingLevelB,
        autoCodexReasoningEffortB = request.autoCodexReasoningEffortB
    )
}

data class ApiKeyStatus(
    val hasGeminiKey: Boolean = false,
    val hasOpenRouterKey: Boolean = false,
    val hasOpenAiKey: Boolean = false,
    val hasMiniMaxKey: Boolean = false,
    val hasZaiKey: Boolean = false,
    val hasCodexAuth: Boolean = false
)

data class CodexUsageUiState(
    val isLoading: Boolean = false,
    val error: String? = null,
    val usage: CodexUsageStatus? = null,
    val lastUpdated: String? = null
)

data class TokenUsageUiState(
    val rangeDays: Int = TOKEN_STATS_RANGE_DAYS.toInt(),
    val totals: TokenUsageTotals = TokenUsageTotals(),
    val byModel: List<TokenUsageByModel> = emptyList(),
    val daily: List<TokenUsageDailyPoint> = emptyList(),
    val lastUpdated: String? = null
)

enum class ApiKeyAction { NoChange, Update, Clear }

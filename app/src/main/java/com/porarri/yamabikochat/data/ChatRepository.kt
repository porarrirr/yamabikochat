package com.porarri.yamabikochat.data

import android.net.Uri
import com.porarri.yamabikochat.data.auth.CodexAuthRepository
import com.porarri.yamabikochat.data.auth.CodexAuthState
import com.porarri.yamabikochat.data.auth.CodexUsageStatus
import com.porarri.yamabikochat.data.auth.SuperGrokAuthRepository
import com.porarri.yamabikochat.data.auth.SuperGrokAuthState
import com.porarri.yamabikochat.data.database.DatabaseRepository
import com.porarri.yamabikochat.data.files.FileProcessingRepository
import com.porarri.yamabikochat.data.fusion.FusionPhase
import com.porarri.yamabikochat.data.fusion.FusionPresetLoader
import com.porarri.yamabikochat.data.fusion.FusionProgressSnapshot
import com.porarri.yamabikochat.data.fusion.FusionRunOptions
import com.porarri.yamabikochat.data.fusion.FusionRunResult
import com.porarri.yamabikochat.data.fusion.FusionService
import com.porarri.yamabikochat.data.fusion.FusionTraceStore
import com.porarri.yamabikochat.data.fusion.SynthesisPhaseResult
import com.porarri.yamabikochat.data.fusion.FusionHistoryMessage
import com.porarri.yamabikochat.data.fusion.FusionPanelChipStatus
import com.porarri.yamabikochat.data.fusion.FusionPanelChipState
import com.porarri.yamabikochat.data.local.AutoConversation
import com.porarri.yamabikochat.data.local.AutoConversationConfig
import com.porarri.yamabikochat.data.local.AutoConversationMessage
import com.porarri.yamabikochat.data.local.ChatMessage
import com.porarri.yamabikochat.data.local.ChatMessageSummary
import com.porarri.yamabikochat.data.local.ChatMessageVariant
import com.porarri.yamabikochat.data.local.ChatProject
import com.porarri.yamabikochat.data.local.Conversation
import com.porarri.yamabikochat.data.local.ConversationListEntry
import com.porarri.yamabikochat.data.local.ConversationSearchResult
import com.porarri.yamabikochat.data.local.DualChatMessage
import com.porarri.yamabikochat.data.local.FullAutoConversation
import com.porarri.yamabikochat.data.local.FullChatMessage
import com.porarri.yamabikochat.data.local.ModelPreset
import com.porarri.yamabikochat.data.local.ProjectListEntry
import com.porarri.yamabikochat.data.local.Settings
import com.porarri.yamabikochat.data.local.TokenUsageByModel
import com.porarri.yamabikochat.data.local.TokenUsageDailyPoint
import com.porarri.yamabikochat.data.local.TokenUsageRecord
import com.porarri.yamabikochat.data.local.TokenUsageTotals
import com.porarri.yamabikochat.data.model.LLMProvider
import com.porarri.yamabikochat.data.model.ModelRepository
import com.porarri.yamabikochat.data.model.ProviderRequest
import com.porarri.yamabikochat.data.model.ProviderRequestMessage
import com.porarri.yamabikochat.data.model.ProviderResponse
import com.porarri.yamabikochat.data.model.ProviderStreamEvent
import com.porarri.yamabikochat.data.model.ProviderUsage
import com.porarri.yamabikochat.data.modelsdev.CatalogLoadState
import com.porarri.yamabikochat.data.modelsdev.ModelsDevCatalogRepository
import com.porarri.yamabikochat.data.modelsdev.ProviderReference
import com.porarri.yamabikochat.data.remote.LiteLlmPricingRepository
import com.porarri.yamabikochat.data.repositories.ProviderGateway
import com.porarri.yamabikochat.data.repositories.ProviderRequestSettingsResolver
import com.porarri.yamabikochat.data.skills.AgentSkillPromptComposer
import com.porarri.yamabikochat.data.skills.AgentSkillRepository
import com.porarri.yamabikochat.utils.DiagnosticsLogger
import com.porarri.yamabikochat.utils.FileValidationUtils
import com.porarri.yamabikochat.utils.SecurePreferencesManager
import com.porarri.yamabikochat.utils.SqlLikeUtils
import com.porarri.yamabikochat.utils.UserFacingErrorFormatter
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.first

class ChatRepository(
    private val databaseRepository: DatabaseRepository,
    val providerGateway: ProviderGateway,
    val requestSettingsResolver: ProviderRequestSettingsResolver,
    private val fileProcessingRepository: FileProcessingRepository,
    private val modelRepository: ModelRepository,
    private val codexAuthRepository: CodexAuthRepository,
    private val superGrokAuthRepository: SuperGrokAuthRepository,
    private val pricingRepository: LiteLlmPricingRepository,
    private val modelsDevCatalogRepository: ModelsDevCatalogRepository,
    val agentSkillRepository: AgentSkillRepository,
    private val securePreferences: SecurePreferencesManager
) {
    private val fusionTraceStore = FusionTraceStore(
        saveRecord = { databaseRepository.saveFusionTrace(it) },
        loadRecord = { databaseRepository.getFusionTrace(it) }
    )

    private val fusionService = FusionService(
        settingsProvider = {
            databaseRepository.getLatestSettings() ?: Settings()
        },
        providerGateway = providerGateway,
        estimateCost = { provider, model, usage ->
            pricingRepository.estimateCostUsd(
                provider = provider,
                model = model,
                inputTokens = usage?.inputTokens ?: 0,
                outputTokens = usage?.outputTokens ?: 0,
                reasoningTokens = usage?.reasoningTokens
            )
        },
        modelSupportsVision = { provider, model ->
            pricingRepository.modelSupportsVision(provider, model)
        },
        traceStore = fusionTraceStore,
        requestSettingsResolver = requestSettingsResolver,
        skillRepository = agentSkillRepository
    )

    // region Database / Conversation Operations
    fun getConversationListEntries(): Flow<List<ConversationListEntry>> =
        databaseRepository.getConversationListEntries()

    fun getProjects(): Flow<List<ProjectListEntry>> =
        databaseRepository.getProjects()

    suspend fun upsertProject(project: ChatProject): Long =
        databaseRepository.upsertProject(project)

    suspend fun assignConversationToProject(conversationId: Long, projectId: Long?) =
        databaseRepository.assignConversationToProject(conversationId, projectId)

    suspend fun deleteProject(id: Long, deleteConversations: Boolean = false) =
        databaseRepository.deleteProject(id, deleteConversations)

    suspend fun countConversationsInProject(projectId: Long): Int =
        databaseRepository.countConversationsInProject(projectId)

    fun getMessagesForConversation(conversationId: Long): Flow<List<ChatMessageSummary>> =
        databaseRepository.getMessagesForConversation(conversationId)

    suspend fun getFullMessageById(messageId: Long): FullChatMessage? =
        databaseRepository.getFullMessageById(messageId)

    suspend fun getFullMessagesByIds(ids: List<Long>): Map<Long, FullChatMessage> =
        databaseRepository.getFullMessagesByIds(ids)

    suspend fun getConversationById(id: Long): Conversation? =
        databaseRepository.getConversationById(id)

    suspend fun upsertConversation(conversation: Conversation): Long =
        databaseRepository.upsertConversation(conversation)

    suspend fun insertMessage(message: ChatMessage): Long =
        databaseRepository.insertMessage(message)

    suspend fun updateMessage(message: ChatMessage) =
        databaseRepository.updateMessage(message)

    suspend fun insertMessageVariant(
        baseMessageId: Long,
        text: String,
        attachments: List<String> = emptyList(),
        thinkingStream: String? = null
    ): ChatMessageVariant =
        databaseRepository.insertMessageVariant(baseMessageId, text, attachments, thinkingStream)

    suspend fun updateMessageVariant(variant: ChatMessageVariant) =
        databaseRepository.updateMessageVariant(variant)

    suspend fun setMessageSelectedVariantIndex(messageId: Long, selectedIndex: Int) =
        databaseRepository.setMessageSelectedVariantIndex(messageId, selectedIndex)

    suspend fun insertThinking(messageId: Long, thinking: String) =
        databaseRepository.insertThinking(messageId, thinking)

    suspend fun findLatestEmptyConversationByTitle(title: String, projectId: Long? = null): Conversation? =
        databaseRepository.findLatestEmptyConversationByTitle(title, projectId)

    fun getSettings(): Flow<Settings?> = databaseRepository.getSettings()

    suspend fun saveSettings(settings: Settings) = databaseRepository.saveSettings(settings)

    suspend fun getProjectById(id: Long): ChatProject? = databaseRepository.getProjectById(id)

    suspend fun createProject(name: String, instructions: String?): Long =
        databaseRepository.upsertProject(ChatProject(title = name, instructions = instructions))

    suspend fun fetchFusionTrace(id: String): com.porarri.yamabikochat.data.fusion.FusionTrace? =
        fusionTraceStore?.load(id)

    // OpenRouter / Models
    fun getOpenRouterModelsFlow(): StateFlow<List<com.porarri.yamabikochat.data.remote.SimpleModel>> =
        modelRepository.getOpenRouterModelsFlow()

    fun getOpenRouterModelsLoading(): StateFlow<Boolean> =
        modelRepository.getOpenRouterModelsLoading()

    fun getOpenRouterModelsError(): StateFlow<String?> =
        modelRepository.getOpenRouterModelsError()

    suspend fun getOpenRouterModels(forceRefresh: Boolean = false): List<com.porarri.yamabikochat.data.remote.SimpleModel> =
        modelRepository.getOpenRouterModels(forceRefresh)

    suspend fun getAvailableQuantizationsForModel(modelId: String): List<String> =
        modelRepository.getAvailableQuantizationsForModel(modelId)

    suspend fun getModelEndpoints(modelId: String) =
        modelRepository.getModelEndpoints(modelId)

    suspend fun getProvidersDirectory() =
        modelRepository.getProvidersDirectory()

    suspend fun getAvailableProvidersForModel(modelId: String): List<String> =
        modelRepository.getAvailableProvidersForModel(modelId)

    suspend fun refreshModelsDevCatalog(forceRefresh: Boolean = false) {
        modelsDevCatalogRepository.load(forceRefresh)
    }

    suspend fun deleteConversationById(id: Long) = databaseRepository.deleteConversationById(id)

    suspend fun clearHistory(conversationId: Long) =
        databaseRepository.deleteMessagesForConversation(conversationId)

    suspend fun updateConversation(conversation: Conversation) =
        databaseRepository.upsertConversation(conversation)

    suspend fun saveAttachment(uri: Uri): String? = fileProcessingRepository.saveAttachment(uri)

    suspend fun validateFile(uri: Uri): FileValidationUtils.FileValidationResult =
        fileProcessingRepository.validateFile(uri)

    fun getAllModelPresets(): Flow<List<ModelPreset>> = databaseRepository.getAllModelPresets()

    suspend fun upsertModelPreset(preset: ModelPreset) = databaseRepository.upsertModelPreset(preset)

    suspend fun deleteModelPresetById(id: Long) = databaseRepository.deleteModelPresetById(id)

    suspend fun insertDualMessage(message: DualChatMessage): Long =
        databaseRepository.insertDualMessage(message)

    suspend fun updateDualMessage(message: DualChatMessage) =
        databaseRepository.updateDualMessage(message)

    fun getDualMessagesForConversation(conversationId: Long): Flow<List<DualChatMessage>> =
        databaseRepository.getDualMessagesForConversation(conversationId)

    fun searchMessages(
        query: String,
        limit: Int = 200,
        projectId: Long? = null
    ): Flow<List<ConversationSearchResult>> =
        databaseRepository.searchMessages(
            pattern = SqlLikeUtils.buildEscapedContainsPattern(query),
            limit = limit,
            projectId = projectId
        )

    suspend fun getDualMessageById(id: Long): DualChatMessage? =
        databaseRepository.getDualMessageById(id)

    suspend fun createAutoConversation(
        config: AutoConversationConfig,
        boundChatConversationId: Long?
    ): Long = databaseRepository.createAutoConversation(config, boundChatConversationId)

    suspend fun updateAutoConversation(conversation: AutoConversation) =
        databaseRepository.updateAutoConversation(conversation)

    fun getAllAutoConversations(): Flow<List<AutoConversation>> =
        databaseRepository.getAllAutoConversations()

    suspend fun getAutoConversationById(id: Long): AutoConversation? =
        databaseRepository.getAutoConversationById(id)

    suspend fun deleteAutoConversationById(id: Long) =
        databaseRepository.deleteAutoConversationById(id)

    suspend fun insertAutoConversationMessage(message: AutoConversationMessage): Long =
        databaseRepository.insertAutoConversationMessage(message)

    fun getAutoConversationMessages(conversationId: Long): Flow<List<AutoConversationMessage>> =
        databaseRepository.getAutoConversationMessages(conversationId)

    suspend fun getLastAutoConversationMessage(conversationId: Long): AutoConversationMessage? =
        databaseRepository.getLastAutoConversationMessage(conversationId)

    suspend fun getFullAutoConversation(id: Long): FullAutoConversation? =
        databaseRepository.getFullAutoConversation(id)
    // endregion

    // region Token Usage
    suspend fun recordTokenUsage(
        provider: String,
        model: String,
        usage: ProviderUsage,
        conversationId: Long? = null,
        requestType: String = "chat"
    ) {
        val normalized = usage.normalized()
        if (normalized.isEmpty) return
        val costUsd = pricingRepository.estimateCostUsd(
            provider = provider,
            model = model,
            inputTokens = normalized.inputTokens ?: 0,
            outputTokens = normalized.outputTokens ?: 0,
            reasoningTokens = normalized.reasoningTokens
        )
        databaseRepository.insertTokenUsage(
            TokenUsageRecord(
                provider = provider.uppercase(),
                model = model.trim().ifBlank { "unknown" },
                requestType = requestType,
                conversationId = conversationId,
                inputTokens = normalized.inputTokens ?: 0,
                outputTokens = normalized.outputTokens ?: 0,
                totalTokens = normalized.totalTokens ?: 0,
                reasoningTokens = normalized.reasoningTokens,
                cachedInputTokens = normalized.cachedInputTokens,
                costUsd = costUsd
            )
        )
    }

    fun observeTokenUsageTotals(sinceEpochMs: Long): Flow<TokenUsageTotals> =
        databaseRepository.observeTokenUsageTotals(sinceEpochMs)

    fun observeTokenUsageByModel(sinceEpochMs: Long, limit: Int): Flow<List<TokenUsageByModel>> =
        databaseRepository.observeTokenUsageByModel(sinceEpochMs, limit)

    fun observeTokenUsageDaily(sinceEpochMs: Long): Flow<List<TokenUsageDailyPoint>> =
        databaseRepository.observeTokenUsageDaily(sinceEpochMs)
    // endregion

    suspend fun resolveCanAttachImages(
        settings: Settings,
        conversationProvider: String,
        conversationModel: String
    ): Boolean {
        if (settings.isDualModeEnabled) {
            val supportsA = pricingRepository.modelSupportsVision(settings.dualProviderA, settings.dualModelA)
            val supportsB = pricingRepository.modelSupportsVision(settings.dualProviderB, settings.dualModelB)
            return supportsA && supportsB
        }
        if (settings.isAutoConversationEnabled) {
            val supportsA = pricingRepository.modelSupportsVision(settings.autoProviderA, settings.autoModelA)
            val supportsB = pricingRepository.modelSupportsVision(settings.autoProviderB, settings.autoModelB)
            return supportsA && supportsB
        }
        if (settings.isFusionModeEnabled) {
            val preset = runCatching {
                FusionPresetLoader.resolveDefinition(settings.fusionCustomPresetJSON)
            }.getOrNull() ?: return false
            return preset.panelModels.all { panel ->
                pricingRepository.modelSupportsVision(panel.provider, panel.modelId)
            }
        }
        return pricingRepository.modelSupportsVision(conversationProvider, conversationModel)
    }

    // region Provider Gateway Operations
    suspend fun buildProviderRequest(
        conversation: Conversation,
        settings: Settings,
        provider: String,
        model: String,
        messages: List<ProviderRequestMessage>,
        systemPrompt: String?,
        context: Settings.ReasoningContext = Settings.ReasoningContext.DEFAULT,
        promptCacheKey: String? = null
    ): ProviderRequest {
        val resolved = requestSettingsResolver.resolve(
            settings = settings,
            provider = provider,
            model = model,
            context = context
        )

        val cacheKey = promptCacheKey?.trim()?.takeIf { it.isNotEmpty() }
            ?: "conversation-${conversation.id}"
        val supportsTools = ProviderReference(provider).isModelsDev ||
                LLMProvider.fromRawOrDefault(provider).supportsClientWebSearchTool
        val skillApplied = AgentSkillPromptComposer.apply(
            repository = agentSkillRepository,
            messages = messages,
            conversationId = cacheKey,
            clientToolsSupported = supportsTools
        )

        val metadata = resolved.metadata.toMutableMap()
        metadata["provider"] = provider
        metadata["promptCacheKey"] = cacheKey
        metadata["supportsVision"] = visionMetadataFlag(provider, model)
        if (provider.equals("CODEX_AUTH", ignoreCase = true)) {
            metadata["codexSessionId"] = databaseRepository.getOrCreateCodexSessionId(conversation.id)
        }

        return ProviderRequest(
            model = model,
            messages = skillApplied.messages,
            systemPrompt = systemPrompt?.trim()?.takeIf { it.isNotEmpty() },
            stream = true,
            tools = resolved.tools,
            thinking = resolved.thinking,
            provider = resolved.routing,
            metadata = metadata
        )
    }

    suspend fun streamProviderRequest(
        request: ProviderRequest,
        provider: String
    ): Flow<ProviderStreamEvent> =
        providerGateway.stream(request, provider)

    suspend fun generateProviderRequest(
        request: ProviderRequest,
        provider: String
    ): ProviderResponse =
        providerGateway.generate(request, provider)

    suspend fun generateAutoConversationResponse(
        model: String,
        provider: String,
        systemPrompt: String,
        conversationHistory: List<ProviderRequestMessage>,
        reasoningContext: Settings.ReasoningContext,
        promptCacheKey: String? = null
    ): ProviderResponse {
        val settings = databaseRepository.getLatestSettings() ?: Settings()
        val resolved = requestSettingsResolver.resolve(
            settings = settings,
            provider = provider,
            model = model,
            context = reasoningContext
        )
        val metadata = resolved.metadata.toMutableMap()
        metadata["provider"] = provider
        promptCacheKey?.trim()?.takeIf { it.isNotEmpty() }?.let { metadata["promptCacheKey"] = it }
        metadata["supportsVision"] = visionMetadataFlag(provider, model)
        val request = ProviderRequest(
            model = model,
            messages = conversationHistory,
            systemPrompt = systemPrompt.trim().takeIf { it.isNotEmpty() },
            stream = false,
            tools = resolved.tools,
            thinking = resolved.thinking,
            provider = resolved.routing,
            metadata = metadata
        )
        return providerGateway.generate(request, provider)
    }

    private suspend fun visionMetadataFlag(provider: String, model: String): String =
        if (pricingRepository.modelSupportsVision(provider, model)) "true" else "false"
    // endregion

    // region Fusion
    suspend fun runFusion(
        userPrompt: String,
        options: FusionRunOptions = FusionRunOptions()
    ): FusionRunResult = fusionService.runFusion(userPrompt, options)

    suspend fun sendFusionMessage(
        conversationId: Long,
        userText: String,
        attachments: List<String> = emptyList(),
        onProgress: (FusionProgressSnapshot) -> Unit = {}
    ): Long {
        val conversation = databaseRepository.getConversationById(conversationId)
            ?: throw IllegalArgumentException("Conversation $conversationId not found")
        val settings = databaseRepository.getLatestSettings() ?: Settings()

        val normalizedAttachments = attachments.map { uriString ->
            runCatching { Uri.parse(uriString) }.getOrNull()?.let { uri ->
                saveAttachment(uri)
            } ?: uriString
        }

        val userMessage = ChatMessage(
            conversationId = conversationId,
            role = "user",
            text = userText,
            attachments = normalizedAttachments
        )
        databaseRepository.insertMessage(userMessage)

        val summaries = databaseRepository.getMessagesForConversation(conversationId).first()
        val historyIds = summaries.map { it.id }
        val fullMessages = databaseRepository.getFullMessagesByIds(historyIds)
        val history = summaries.mapNotNull { summary ->
            val full = fullMessages[summary.id] ?: return@mapNotNull null
            FusionHistoryMessage(
                role = if (full.chatMessage.role == "model" || full.chatMessage.role == "assistant") "assistant" else "user",
                text = full.displayText,
                attachments = full.displayAttachments
            )
        }

        val allowWebSearchOverride = if (settings.clientWebSearchToolEnabled) null else false
        val fusionRequest = FusionPresetLoader.buildRequest(
            userPrompt = userText,
            systemPrompt = conversation.systemPrompt,
            taskTypeOverride = com.porarri.yamabikochat.data.fusion.FusionTaskType.auto,
            allowWebSearchOverride = allowWebSearchOverride,
            customPresetJSON = settings.fusionCustomPresetJSON
        )
        val context = com.porarri.yamabikochat.data.fusion.FusionContext(
            fusionDepth = 0,
            debugMode = false,
            logPrompts = true,
            conversationId = conversationId
        )

        val initialChips = FusionProgressSnapshot.initialPanels(from = fusionRequest)
        onProgress(FusionProgressSnapshot.panelPhase(panels = initialChips))

        val judgeOutcome = try {
            fusionService.runThroughJudge(
                request = fusionRequest,
                context = context,
                conversationHistory = history,
                userAttachments = normalizedAttachments,
                onProgress = onProgress
            )
        } catch (e: com.porarri.yamabikochat.data.fusion.FusionError.AllPanelsFailed) {
            val failedTraceId = java.util.UUID.randomUUID().toString()
            val failedTrace = com.porarri.yamabikochat.data.fusion.FusionTrace(
                requestId = failedTraceId,
                preset = fusionRequest.preset,
                startedAtMs = System.currentTimeMillis(),
                completedAtMs = System.currentTimeMillis(),
                panelResults = e.panelResults,
                judgeResult = null,
                synthesisResult = null,
                totalLatencyMs = 0L,
                totalCost = com.porarri.yamabikochat.data.fusion.FusionOrchestrator.sumCosts(e.panelResults, null, null),
                failedModels = e.panelResults.map { it.modelId },
                status = "all_panels_failed",
                userPrompt = userText,
                finalAnswer = null
            )
            fusionTraceStore.save(failedTrace, conversationId)

            val failedPanelChips = e.panelResults.map { result ->
                FusionPanelChipStatus(
                    modelId = result.modelId,
                    provider = result.provider,
                    state = if (result.success) FusionPanelChipState.succeeded else FusionPanelChipState.failed
                )
            }
            onProgress(FusionProgressSnapshot.phaseOnly(FusionPhase.fallback, failedPanelChips))

            val fallbackModel = fusionRequest.synthesizerModel
            val fallbackRequest = fusionService.buildProviderRequest(
                model = fallbackModel,
                systemPrompt = conversation.systemPrompt.orEmpty(),
                phase = FusionPhase.fallback,
                allowTools = false,
                settings = settings,
                fusionDepth = 0,
                userPrompt = userText,
                conversationHistory = history.map { ProviderRequestMessage(role = it.role, content = it.text, attachments = it.attachments) },
                userAttachments = normalizedAttachments
            )
            val assistantMessageId = databaseRepository.insertMessage(
                ChatMessage(
                    conversationId = conversationId,
                    role = "model",
                    text = "",
                    fusionTraceId = failedTraceId
                )
            )
            val response = try {
                providerGateway.generate(fallbackRequest, fallbackModel.provider)
            } catch (err: Exception) {
                ProviderResponse(text = UserFacingErrorFormatter.placeholder(err))
            }
            val finalText = response.text.ifBlank { "Fusion フォールバックに失敗しました。" }
            val existing = databaseRepository.getFullMessageById(assistantMessageId)?.chatMessage
            if (existing != null) {
                databaseRepository.updateMessage(existing.copy(text = finalText, fusionTraceId = failedTraceId))
            }
            response.usage?.let { usage ->
                recordTokenUsage(
                    provider = fallbackModel.provider,
                    model = fallbackModel.modelId,
                    usage = usage,
                    conversationId = conversationId,
                    requestType = "fusion_fallback"
                )
            }
            return assistantMessageId
        }

        for (usage in judgeOutcome.panelTokenUsages) {
            usage.usage?.let {
                recordTokenUsage(
                    provider = usage.provider,
                    model = usage.model,
                    usage = it,
                    conversationId = conversationId,
                    requestType = usage.requestType
                )
            }
        }
        judgeOutcome.judgeTokenUsage?.usage?.let {
            recordTokenUsage(
                provider = judgeOutcome.judgeTokenUsage.provider,
                model = judgeOutcome.judgeTokenUsage.model,
                usage = it,
                conversationId = conversationId,
                requestType = "fusion_judge"
            )
        }

        val assistantMessageId = databaseRepository.insertMessage(
            ChatMessage(
                conversationId = conversationId,
                role = "model",
                text = "",
                fusionTraceId = judgeOutcome.trace.requestId
            )
        )

        val synthPanelChips = judgeOutcome.trace.panelResults.map { result ->
            FusionPanelChipStatus(
                modelId = result.modelId,
                provider = result.provider,
                state = if (result.success) FusionPanelChipState.succeeded else FusionPanelChipState.failed
            )
        }
        onProgress(FusionProgressSnapshot.phaseOnly(FusionPhase.synthesizer, synthPanelChips))

        val synthStarted = System.currentTimeMillis()
        var finalText = ""
        var synthUsage: ProviderUsage? = null
        var synthesisResult: SynthesisPhaseResult

        try {
            var textAcc = ""
            var lastPersistMs = 0L

            providerGateway.stream(judgeOutcome.synthesisRequest, judgeOutcome.synthesizerProvider).collect { event ->
                when (event) {
                    is ProviderStreamEvent.TextDelta -> textAcc += event.delta
                    is ProviderStreamEvent.Completed -> {
                        if (event.response.text.isNotBlank()) textAcc = event.response.text
                        synthUsage = event.response.usage
                    }
                    is ProviderStreamEvent.ReasoningDelta -> {}
                }
                val now = System.currentTimeMillis()
                if (now - lastPersistMs >= 100L) {
                    lastPersistMs = now
                    val existing = databaseRepository.getFullMessageById(assistantMessageId)?.chatMessage
                    if (existing != null) {
                        databaseRepository.updateMessage(existing.copy(text = textAcc, fusionTraceId = judgeOutcome.trace.requestId))
                    }
                }
            }

            finalText = textAcc
            val latencyMs = System.currentTimeMillis() - synthStarted
            val cost = pricingRepository.estimateCostUsd(
                provider = judgeOutcome.synthesizerModel.provider,
                model = judgeOutcome.synthesizerModel.modelId,
                inputTokens = synthUsage?.inputTokens ?: 0,
                outputTokens = synthUsage?.outputTokens ?: 0,
                reasoningTokens = synthUsage?.reasoningTokens
            )
            synthesisResult = SynthesisPhaseResult(
                modelId = judgeOutcome.synthesizerModel.modelId,
                provider = judgeOutcome.synthesizerModel.provider.uppercase(),
                success = true,
                content = finalText,
                latencyMs = latencyMs,
                inputTokens = synthUsage?.inputTokens,
                outputTokens = synthUsage?.outputTokens,
                cost = cost,
                error = null,
                usedFallback = false
            )
        } catch (e: Exception) {
            finalText = judgeOutcome.staticFallbackAnswer.ifBlank { UserFacingErrorFormatter.placeholder(e) }
            synthesisResult = SynthesisPhaseResult(
                modelId = judgeOutcome.synthesizerModel.modelId,
                provider = judgeOutcome.synthesizerModel.provider.uppercase(),
                success = false,
                content = finalText,
                latencyMs = System.currentTimeMillis() - synthStarted,
                inputTokens = null,
                outputTokens = null,
                cost = null,
                error = e.message ?: e.toString(),
                usedFallback = true
            )
            DiagnosticsLogger.log("Fusion synthesizer failed traceId=${judgeOutcome.trace.requestId}", e)
        }

        val existing = databaseRepository.getFullMessageById(assistantMessageId)?.chatMessage
        if (existing != null) {
            databaseRepository.updateMessage(existing.copy(text = finalText, fusionTraceId = judgeOutcome.trace.requestId))
        }

        synthUsage?.let {
            recordTokenUsage(
                provider = judgeOutcome.synthesizerModel.provider,
                model = judgeOutcome.synthesizerModel.modelId,
                usage = it,
                conversationId = conversationId,
                requestType = "fusion_synth"
            )
        }

        val finalTrace = fusionService.finalizeTrace(
            trace = judgeOutcome.trace,
            synthesisResult = synthesisResult,
            finalAnswer = finalText,
            logPrompts = context.logPrompts
        )
        fusionTraceStore.save(finalTrace, conversationId)

        return assistantMessageId
    }
    // endregion

    // region API Key Management
    fun saveApiKey(provider: String, apiKey: String?): Boolean {
        val trimmed = apiKey?.trim()?.takeIf { it.isNotEmpty() }
        val norm = provider.trim().uppercase()
        return when (norm) {
            "GEMINI" -> securePreferences.storeGeminiApiKey(trimmed)
            "OPENROUTER" -> securePreferences.storeOpenRouterApiKey(trimmed)
            "OPENAI" -> securePreferences.storeOpenAiApiKey(trimmed)
            "MINIMAX" -> securePreferences.storeMiniMaxApiKey(trimmed)
            "ZAI" -> securePreferences.storeZaiApiKey(trimmed)
            "CLINEPASS" -> securePreferences.storeClinePassApiKey(trimmed)
            "ALIBABA_CODING_PLAN" -> securePreferences.storeAlibabaCodingPlanApiKey(trimmed)
            "OPENCODE_GO" -> securePreferences.storeOpenCodeGoApiKey(trimmed)
            else -> securePreferences.saveSecret(norm, trimmed)
        }
    }

    fun hasApiKey(provider: String): Boolean {
        return !peekApiKey(provider).isNullOrBlank()
    }

    fun peekApiKey(provider: String): String? {
        val norm = provider.trim().uppercase()
        return when (norm) {
            "GEMINI" -> securePreferences.getGeminiApiKey()
            "OPENROUTER" -> securePreferences.getOpenRouterApiKey()
            "OPENAI" -> securePreferences.getOpenAiApiKey()
            "MINIMAX" -> securePreferences.getMiniMaxApiKey()
            "ZAI" -> securePreferences.getZaiApiKey()
            "CLINEPASS" -> securePreferences.getClinePassApiKey()
            "ALIBABA_CODING_PLAN" -> securePreferences.getAlibabaCodingPlanApiKey()
            "OPENCODE_GO" -> securePreferences.getOpenCodeGoApiKey()
            else -> securePreferences.readSecret(norm)
        }
    }

    fun saveOpenAiCompatApiKey(name: String, apiKey: String?): Boolean =
        securePreferences.storeCustomApiKey(name, apiKey)

    fun peekOpenAiCompatApiKey(name: String): String? =
        securePreferences.getCustomApiKey(name)

    fun hasOpenAiCompatApiKey(name: String?): Boolean =
        !name.isNullOrBlank() && !peekOpenAiCompatApiKey(name).isNullOrBlank()

    suspend fun clearOpenAiCompatApiKey(name: String) =
        securePreferences.clearCustomApiKey(name)

    fun saveModelsDevField(providerId: String, fieldName: String, value: String?): Boolean =
        securePreferences.storeModelsDevField(providerId, fieldName, value)

    fun peekModelsDevField(providerId: String, fieldName: String): String? =
        securePreferences.getModelsDevField(providerId, fieldName)

    fun saveAlibabaMcpAuthorizationToken(token: String?): Boolean =
        securePreferences.storeAlibabaMcpAuthorizationToken(token)

    fun peekAlibabaMcpAuthorizationToken(): String? =
        securePreferences.getAlibabaMcpAuthorizationToken()
    // endregion

    // region Codex Auth
    val codexAuthState: StateFlow<CodexAuthState> = codexAuthRepository.state

    suspend fun loginCodexAuth(): Result<CodexAuthState> = codexAuthRepository.loginWithBrowser()

    suspend fun logoutCodexAuth(): Result<CodexAuthState> = codexAuthRepository.logout()

    suspend fun refreshCodexAuth(force: Boolean = false): Result<CodexAuthState> =
        codexAuthRepository.refreshIfNeeded(force)

    fun hasCodexAuth(): Boolean = codexAuthRepository.hasAuthToken()

    suspend fun retrieveCodexAuthUsage(): Result<CodexUsageStatus> =
        codexAuthRepository.retrieveUsageStatus()
    // endregion

    // region SuperGrok Auth
    val superGrokAuthState: StateFlow<SuperGrokAuthState> = superGrokAuthRepository.state

    suspend fun loginSuperGrokWithBrowser(): Result<SuperGrokAuthState> =
        superGrokAuthRepository.loginWithBrowser()

    suspend fun loginSuperGrokWithDeviceCode(): Result<SuperGrokAuthState> =
        superGrokAuthRepository.loginWithDeviceCode()

    suspend fun logoutSuperGrok(): Result<SuperGrokAuthState> = superGrokAuthRepository.logout()

    suspend fun refreshSuperGrok(force: Boolean = false): Result<SuperGrokAuthState> =
        superGrokAuthRepository.refreshIfNeeded(force)

    fun hasSuperGrokAuth(): Boolean = superGrokAuthRepository.hasAuthToken()
    // endregion

    // region ModelsDev
    val modelsDevCatalogState: StateFlow<CatalogLoadState> = modelsDevCatalogRepository.state

    suspend fun loadModelsDevCatalog(forceRefresh: Boolean = false) {
        modelsDevCatalogRepository.load(forceRefresh)
    }
    // endregion
}

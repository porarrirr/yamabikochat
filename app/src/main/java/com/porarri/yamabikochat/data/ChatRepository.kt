package com.porarri.yamabikochat.data

import android.net.Uri
import com.porarri.yamabikochat.data.api.ApiRepository
import com.porarri.yamabikochat.data.auth.CodexAuthRepository
import com.porarri.yamabikochat.data.auth.CodexAuthState
import com.porarri.yamabikochat.data.auth.CodexUsageStatus
import com.porarri.yamabikochat.data.auth.SuperGrokAuthRepository
import com.porarri.yamabikochat.data.auth.SuperGrokAuthState
import com.porarri.yamabikochat.data.database.DatabaseRepository
import com.porarri.yamabikochat.data.files.FileProcessingRepository
import com.porarri.yamabikochat.data.local.AutoConversation
import com.porarri.yamabikochat.data.local.AutoConversationConfig
import com.porarri.yamabikochat.data.local.AutoConversationMessage
import com.porarri.yamabikochat.data.local.ChatMessage
import com.porarri.yamabikochat.data.local.ChatMessageSummary
import com.porarri.yamabikochat.data.local.ChatMessageVariant
import com.porarri.yamabikochat.data.local.ChatProject
import com.porarri.yamabikochat.data.local.ConversationListEntry
import com.porarri.yamabikochat.data.local.ConversationSearchResult
import com.porarri.yamabikochat.data.local.Conversation
import com.porarri.yamabikochat.data.local.DualChatMessage
import com.porarri.yamabikochat.data.local.FullAutoConversation
import com.porarri.yamabikochat.data.local.FullChatMessage
import com.porarri.yamabikochat.data.fusion.DefaultClientToolCallingRunner
import com.porarri.yamabikochat.data.fusion.FusionError
import com.porarri.yamabikochat.data.fusion.FusionGenerate
import com.porarri.yamabikochat.data.fusion.FusionHistoryMessage
import com.porarri.yamabikochat.data.fusion.FusionPanelChipStatus
import com.porarri.yamabikochat.data.fusion.FusionPhase
import com.porarri.yamabikochat.data.fusion.FusionPresetLoader
import com.porarri.yamabikochat.data.fusion.FusionProgressSnapshot
import com.porarri.yamabikochat.data.fusion.FusionService
import com.porarri.yamabikochat.data.fusion.FusionTaskType
import com.porarri.yamabikochat.data.fusion.FusionTrace
import com.porarri.yamabikochat.data.fusion.FusionTraceStore
import com.porarri.yamabikochat.data.fusion.FusionPanelChipState
import com.porarri.yamabikochat.data.fusion.SynthesisPhaseResult
import com.porarri.yamabikochat.data.fusion.toFusionInvokeResult
import com.porarri.yamabikochat.data.local.FusionTraceRecord
import com.porarri.yamabikochat.data.local.ModelPreset
import com.porarri.yamabikochat.data.local.ProjectListEntry
import com.porarri.yamabikochat.data.local.Settings
import com.porarri.yamabikochat.data.local.TokenUsageByModel
import com.porarri.yamabikochat.data.local.TokenUsageDailyPoint
import com.porarri.yamabikochat.data.local.TokenUsageRecord
import com.porarri.yamabikochat.data.local.TokenUsageTotals
import com.porarri.yamabikochat.data.model.ModelRepository
import com.porarri.yamabikochat.data.remote.Content
import com.porarri.yamabikochat.data.remote.GenerateContentRequest
import com.porarri.yamabikochat.data.remote.GenerateContentResponse
import com.porarri.yamabikochat.data.remote.InlineData
import com.porarri.yamabikochat.data.remote.LiteLlmPricingRepository
import com.porarri.yamabikochat.data.remote.ModelEndpoint
import com.porarri.yamabikochat.data.remote.Part
import com.porarri.yamabikochat.data.remote.ProviderDirectory
import com.porarri.yamabikochat.data.remote.SimpleModel
import com.porarri.yamabikochat.data.remote.TokenUsageSnapshot
import com.porarri.yamabikochat.data.remote.extractTokenUsageSnapshot
import com.porarri.yamabikochat.utils.DiagnosticsLogger
import com.porarri.yamabikochat.utils.FileValidationUtils
import com.porarri.yamabikochat.utils.SqlLikeUtils
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.first
import okhttp3.ResponseBody
import java.util.UUID

class ChatRepository(
    private val databaseRepository: DatabaseRepository,
    private val apiRepository: ApiRepository,
    private val fileProcessingRepository: FileProcessingRepository,
    private val modelRepository: ModelRepository,
    private val codexAuthRepository: CodexAuthRepository,
    private val superGrokAuthRepository: SuperGrokAuthRepository,
    private val pricingRepository: LiteLlmPricingRepository
) {
    private val fusionTraceStore = FusionTraceStore(
        saveRecord = { databaseRepository.saveFusionTrace(it) },
        loadRecord = { databaseRepository.getFusionTrace(it) }
    )

    private val fusionGenerate: FusionGenerate = { model, provider, request ->
        val response = apiRepository.generateContent(
            model = model,
            request = request,
            providerOverride = provider
        )
        if (!response.isSuccessful) {
            val err = response.errorBody()?.string()?.take(500).orEmpty()
            throw IllegalStateException("HTTP ${response.code()}: $err")
        }
        response.body() ?: throw IllegalStateException("Empty generate response body")
    }

    private val fusionService = FusionService(
        generate = fusionGenerate,
        estimateCost = { provider, model, input, output ->
            pricingRepository.estimateCostUsd(
                provider = provider,
                model = model,
                inputTokens = input,
                outputTokens = output,
                reasoningTokens = null
            )
        },
        settingsProvider = {
            databaseRepository.getLatestSettings() ?: Settings()
        },
        toolRunner = DefaultClientToolCallingRunner(fusionGenerate),
        traceStore = fusionTraceStore
    )

    // region Database delegation
    fun getAllConversations(): Flow<List<Conversation>> = databaseRepository.getAllConversations()

    fun getConversationListEntries(): Flow<List<ConversationListEntry>> =       
        databaseRepository.getConversationListEntries()

    fun getProjects(): Flow<List<ProjectListEntry>> = databaseRepository.getProjects()

    suspend fun getProjectById(id: Long): ChatProject? = databaseRepository.getProjectById(id)

    suspend fun upsertProject(project: ChatProject): Long = databaseRepository.upsertProject(project)

    suspend fun assignConversationToProject(conversationId: Long, projectId: Long?) =
        databaseRepository.assignConversationToProject(conversationId, projectId)

    suspend fun deleteProject(id: Long, deleteConversations: Boolean) =
        databaseRepository.deleteProject(id, deleteConversations)

    suspend fun countConversationsInProject(projectId: Long): Int =
        databaseRepository.countConversationsInProject(projectId)

    suspend fun getConversationById(id: Long): Conversation? = databaseRepository.getConversationById(id)

    suspend fun findLatestEmptyConversationByTitle(title: String, projectId: Long? = null): Conversation? =
        databaseRepository.findLatestEmptyConversationByTitle(title, projectId)

    suspend fun upsertConversation(conversation: Conversation): Long =
        databaseRepository.upsertConversation(conversation)

    suspend fun deleteConversationById(id: Long) = databaseRepository.deleteConversationById(id)

    fun getMessagesForConversation(conversationId: Long): Flow<List<ChatMessageSummary>> =
        databaseRepository.getMessagesForConversation(conversationId)

    suspend fun getFullMessageById(id: Long): FullChatMessage? =
        databaseRepository.getFullMessageById(id)

    suspend fun getFullMessagesByIds(ids: Collection<Long>): Map<Long, FullChatMessage> =
        databaseRepository.getFullMessagesByIds(ids)

    suspend fun insertMessage(message: ChatMessage): Long =
        databaseRepository.insertMessage(message)

    suspend fun updateMessage(message: ChatMessage) =
        databaseRepository.updateMessage(message)

    suspend fun insertThinking(messageId: Long, thinkingStream: String) =
        databaseRepository.insertThinking(messageId, thinkingStream)

    suspend fun updateThinkingStream(messageId: Long, thinkingStream: String) =
        databaseRepository.updateThinkingStream(messageId, thinkingStream)

    suspend fun insertMessageVariant(
        baseMessageId: Long,
        text: String,
        attachments: List<String> = emptyList(),
        thinkingStream: String? = null
    ): ChatMessageVariant =
        databaseRepository.insertMessageVariant(baseMessageId, text, attachments, thinkingStream)

    suspend fun updateMessageVariant(variant: ChatMessageVariant) =
        databaseRepository.updateMessageVariant(variant)

    suspend fun setMessageSelectedVariantIndex(messageId: Long, variantIndex: Int) =
        databaseRepository.setMessageSelectedVariantIndex(messageId, variantIndex)

    fun getSettings(): Flow<Settings?> = databaseRepository.getSettings()

    suspend fun saveSettings(settings: Settings) = databaseRepository.saveSettings(settings)

    suspend fun saveToolActivities(messageId: Long, stepsJSON: String) =
        databaseRepository.saveToolActivities(messageId, stepsJSON)

    suspend fun saveToolActivitiesForVariant(variantId: Long, stepsJSON: String) =
        databaseRepository.saveToolActivitiesForVariant(variantId, stepsJSON)

    suspend fun getToolActivityForMessage(messageId: Long) =
        databaseRepository.getToolActivityForMessage(messageId)

    suspend fun getToolActivityForVariant(variantId: Long) =
        databaseRepository.getToolActivityForVariant(variantId)

    suspend fun saveFusionTrace(record: FusionTraceRecord) =
        databaseRepository.saveFusionTrace(record)

    suspend fun getFusionTrace(id: String) =
        databaseRepository.getFusionTrace(id)

    suspend fun fetchFusionTrace(id: String): FusionTrace? =
        fusionTraceStore.fetch(id)

    /**
     * Runs Fusion panel→judge→synthesizer for a conversation turn.
     * @return assistant message id
     */
    suspend fun sendFusionMessage(
        conversationId: Long,
        userText: String,
        attachments: List<String> = emptyList(),
        onProgress: (FusionProgressSnapshot) -> Unit = {}
    ): Long {
        val settings = databaseRepository.getLatestSettings() ?: Settings()
        if (!settings.isFusionModeEnabled) {
            throw IllegalStateException("Fusion モードが有効ではありません。")
        }
        val conversation = databaseRepository.getConversationById(conversationId)
            ?: throw IllegalStateException("Conversation not found")

        val summaries = databaseRepository.getMessagesForConversation(conversationId).first()
        val isFirstMessage = summaries.isEmpty()

        val normalizedAttachments = attachments.filter { it.isNotBlank() }
        databaseRepository.insertMessage(
            ChatMessage(
                conversationId = conversationId,
                role = "user",
                text = userText,
                attachments = normalizedAttachments
            )
        )

        if (isFirstMessage && conversation.title == "New Chat") {
            databaseRepository.upsertConversation(
                conversation.copy(title = userText.take(50))
            )
        }

        val taskType = FusionTaskType.fromRaw(settings.fusionTaskType)
        val allowWebSearchOverride: Boolean? =
            if (settings.clientWebSearchToolEnabled) null else false

        val fusionRequest = try {
            FusionPresetLoader.buildRequest(
                userPrompt = userText,
                systemPrompt = conversation.systemPrompt,
                taskTypeOverride = taskType,
                allowWebSearchOverride = allowWebSearchOverride,
                customPresetJSON = settings.fusionCustomPresetJSON
            )
        } catch (e: Exception) {
            DiagnosticsLogger.log("Fusion preset load failed", e)
            throw e
        }

        val updatedSummaries = databaseRepository.getMessagesForConversation(conversationId).first()
        val historyIds = updatedSummaries.map { it.id }
        val fullById = databaseRepository.getFullMessagesByIds(historyIds)
        val history = updatedSummaries.mapNotNull { summary ->
            val full = fullById[summary.id]?.chatMessage ?: return@mapNotNull null
            FusionHistoryMessage(
                role = full.role,
                text = full.text,
                attachments = full.attachments
            )
        }

        val context = com.porarri.yamabikochat.data.fusion.FusionContext(
            fusionDepth = 0,
            debugMode = settings.fusionDebugModeEnabled,
            logPrompts = settings.fusionLogPromptsEnabled,
            conversationId = conversationId
        )

        val judgeOutcome = try {
            fusionService.runThroughJudge(
                request = fusionRequest,
                context = context,
                conversationHistory = history,
                userAttachments = normalizedAttachments,
                onProgress = onProgress
            )
        } catch (e: FusionError.AllPanelsFailed) {
            DiagnosticsLogger.log(
                "Fusion all panels failed; falling back to single model conversationId=$conversationId"
            )
            val failedTraceId = UUID.randomUUID().toString()
            val failedTrace = FusionTrace(
                requestId = failedTraceId,
                preset = fusionRequest.preset,
                startedAtMs = System.currentTimeMillis(),
                completedAtMs = System.currentTimeMillis(),
                panelResults = e.panelResults,
                judgeResult = null,
                synthesisResult = null,
                totalLatencyMs = e.panelResults.maxOfOrNull { it.latencyMs },
                totalCost = null,
                failedModels = e.panelResults.map { it.modelId },
                status = "all_panels_failed",
                userPrompt = if (settings.fusionLogPromptsEnabled) userText else null,
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

            val fallbackModel = fusionRequest.fallbackModel ?: fusionRequest.synthesizerModel
            val fallbackRequest = fusionService.buildGenerateRequest(
                model = fallbackModel,
                systemPrompt = conversation.systemPrompt.orEmpty(),
                phase = FusionPhase.fallback,
                allowTools = false,
                maxTokens = fusionRequest.maxSynthesizerTokens,
                settings = settings,
                fusionDepth = 0,
                userPrompt = userText,
                conversationHistory = history,
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
            val response = apiRepository.generateContent(
                model = fallbackModel.modelId,
                request = fallbackRequest,
                providerOverride = fallbackModel.provider
            )
            val text = if (response.isSuccessful) {
                response.body()?.toFusionInvokeResult()?.text.orEmpty()
            } else {
                "エラー: HTTP ${response.code()}"
            }
            val finalText = text.ifBlank { "Fusion フォールバックに失敗しました。" }
            val existing = databaseRepository.getFullMessageById(assistantMessageId)?.chatMessage
            if (existing != null) {
                databaseRepository.updateMessage(
                    existing.copy(text = finalText, fusionTraceId = failedTraceId)
                )
            }
            response.body()?.tokenUsage?.let { usage ->
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
        var finalText: String
        var synthUsage: TokenUsageSnapshot? = null
        var synthesisResult: SynthesisPhaseResult
        val streamJson = kotlinx.serialization.json.Json {
            ignoreUnknownKeys = true
            isLenient = true
        }

        suspend fun persistPartialSynth(text: String) {
            val existing = databaseRepository.getFullMessageById(assistantMessageId)?.chatMessage
            if (existing != null) {
                databaseRepository.updateMessage(
                    existing.copy(
                        text = text,
                        fusionTraceId = judgeOutcome.trace.requestId
                    )
                )
            }
        }

        try {
            val streamResponse = apiRepository.streamGenerateContent(
                model = judgeOutcome.synthesizerModel.modelId,
                request = judgeOutcome.synthesisRequest,
                providerOverride = judgeOutcome.synthesizerProvider
            )
            if (!streamResponse.isSuccessful) {
                throw IllegalStateException("HTTP ${streamResponse.code()}")
            }
            val streamBody = streamResponse.body()
                ?: throw IllegalStateException("Empty synthesizer stream body")

            var lastPersistMs = 0L
            val streamResult = com.porarri.yamabikochat.ui.chat.logic.StreamChunkConsumer.consumeStreamDetailed(
                body = streamBody,
                provider = judgeOutcome.synthesizerProvider,
                model = judgeOutcome.synthesizerModel.modelId,
                json = streamJson,
                onDelta = { text, _, _ ->
                    val now = System.currentTimeMillis()
                    if (now - lastPersistMs >= 100L) {
                        lastPersistMs = now
                        persistPartialSynth(text)
                    }
                },
                onUsage = { usage -> synthUsage = usage }
            )

            if (!streamResult.hasData || streamResult.text.isBlank()) {
                // Fall back to non-streaming generate when stream yields nothing.
                val response = apiRepository.generateContent(
                    model = judgeOutcome.synthesizerModel.modelId,
                    request = judgeOutcome.synthesisRequest,
                    providerOverride = judgeOutcome.synthesizerProvider
                )
                if (!response.isSuccessful) {
                    throw IllegalStateException("HTTP ${response.code()}")
                }
                val body = response.body() ?: throw IllegalStateException("Empty synthesizer body")
                val invokeResult = body.toFusionInvokeResult()
                finalText = invokeResult.text
                synthUsage = body.extractTokenUsageOrNull() ?: synthUsage
            } else {
                finalText = streamResult.text
            }

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
            finalText = judgeOutcome.staticFallbackAnswer
            if (finalText.isEmpty()) {
                finalText = "エラー: ${e.message ?: e}"
            }
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
            DiagnosticsLogger.log(
                "Fusion synthesizer failed; using fallback traceId=${judgeOutcome.trace.requestId}",
                e
            )
        }

        persistPartialSynth(finalText)

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

    private fun GenerateContentResponse.extractTokenUsageOrNull(): TokenUsageSnapshot? {
        return extractTokenUsageSnapshot()
    }

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

    suspend fun getOrCreateCodexSessionId(conversationId: Long): String =
        databaseRepository.getOrCreateCodexSessionId(conversationId)

    suspend fun insertAutoConversationMessage(message: AutoConversationMessage): Long =
        databaseRepository.insertAutoConversationMessage(message)

    fun getAutoConversationMessages(conversationId: Long): Flow<List<AutoConversationMessage>> =
        databaseRepository.getAutoConversationMessages(conversationId)

    suspend fun getLastAutoConversationMessage(conversationId: Long): AutoConversationMessage? =
        databaseRepository.getLastAutoConversationMessage(conversationId)

    suspend fun getFullAutoConversation(id: Long): FullAutoConversation? =
        databaseRepository.getFullAutoConversation(id)

    suspend fun recordTokenUsage(
        provider: String,
        model: String,
        usage: TokenUsageSnapshot,
        conversationId: Long? = null,
        requestType: String = "chat"
    ) {
        val normalized = usage.normalized()
        if (normalized.isEmpty()) return
        val costUsd = pricingRepository.estimateCostUsd(
            provider = provider,
            model = model,
            inputTokens = normalized.inputTokens,
            outputTokens = normalized.outputTokens,
            reasoningTokens = normalized.reasoningTokens
        )
        databaseRepository.insertTokenUsage(
            TokenUsageRecord(
                provider = provider.uppercase(),
                model = model.trim().ifBlank { "unknown" },
                requestType = requestType,
                conversationId = conversationId,
                inputTokens = normalized.inputTokens,
                outputTokens = normalized.outputTokens,
                totalTokens = normalized.totalTokens,
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

    // region API delegation
    suspend fun generateContent(
        model: String,
        request: GenerateContentRequest,
        providerOverride: String? = null,
        sessionId: String? = null
    ): retrofit2.Response<GenerateContentResponse> =
        apiRepository.generateContent(model, request, providerOverride, sessionId)

    suspend fun streamGenerateContent(
        model: String,
        request: GenerateContentRequest,
        providerOverride: String? = null,
        sessionId: String? = null
    ): retrofit2.Response<ResponseBody> =
        apiRepository.streamGenerateContent(model, request, providerOverride, sessionId)

    suspend fun generateDualContent(
        modelA: String,
        modelB: String,
        providerA: String,
        providerB: String,
        requestA: GenerateContentRequest,
        requestB: GenerateContentRequest
    ): Pair<retrofit2.Response<GenerateContentResponse>, retrofit2.Response<GenerateContentResponse>> =
        apiRepository.generateDualContent(modelA, modelB, providerA, providerB, requestA, requestB)

    suspend fun streamDualContent(
        modelA: String,
        modelB: String,
        providerA: String,
        providerB: String,
        requestA: GenerateContentRequest,
        requestB: GenerateContentRequest
    ): Pair<retrofit2.Response<ResponseBody>, retrofit2.Response<ResponseBody>> =
        apiRepository.streamDualContent(modelA, modelB, providerA, providerB, requestA, requestB)

    suspend fun generateAutoConversationResponse(
        model: String,
        provider: String,
        systemPrompt: String,
        conversationHistory: List<Content>,
        reasoningContext: Settings.ReasoningContext
    ): retrofit2.Response<GenerateContentResponse> =
        apiRepository.generateAutoConversationResponse(model, provider, systemPrompt, conversationHistory, reasoningContext)

    suspend fun saveApiKey(provider: String, apiKey: String?): Boolean =
        apiRepository.saveApiKey(provider, apiKey)

    fun hasApiKey(provider: String): Boolean = apiRepository.hasApiKey(provider)

    fun peekApiKey(provider: String): String? = apiRepository.peekApiKey(provider)
    // endregion

    // region Codex Auth
    val codexAuthState: StateFlow<CodexAuthState> = codexAuthRepository.state

    suspend fun loginCodexAuth(): Result<CodexAuthState> = codexAuthRepository.login()

    suspend fun logoutCodexAuth(): Result<CodexAuthState> = codexAuthRepository.logout()

    suspend fun refreshCodexAuth(force: Boolean = false): Result<CodexAuthState> =
        codexAuthRepository.refreshIfNeeded(force)

    fun hasCodexAuth(): Boolean = codexAuthRepository.hasAuthToken()

    fun saveCodexUserAgentPreset(preset: String?): Boolean =
        codexAuthRepository.saveUserAgentPreset(preset)

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

    // region OpenAI-compatible key helpers
    suspend fun saveOpenAiCompatApiKey(name: String, apiKey: String?): Boolean =
        apiRepository.saveOpenAiCompatApiKey(name, apiKey)

    fun peekOpenAiCompatApiKey(name: String): String? = apiRepository.peekOpenAiCompatApiKey(name)

    fun hasOpenAiCompatApiKey(name: String?): Boolean = apiRepository.hasOpenAiCompatApiKey(name)

    suspend fun clearOpenAiCompatApiKey(name: String) = apiRepository.clearOpenAiCompatApiKey(name)
    // endregion

    suspend fun saveAlibabaMcpAuthorizationToken(token: String?): Boolean =
        apiRepository.saveAlibabaMcpAuthorizationToken(token)

    fun peekAlibabaMcpAuthorizationToken(): String? =
        apiRepository.peekAlibabaMcpAuthorizationToken()

    // region File processing delegation
    suspend fun validateFile(uri: Uri): FileValidationUtils.FileValidationResult =
        fileProcessingRepository.validateFile(uri)

    suspend fun saveAttachment(uri: Uri): String? = fileProcessingRepository.saveAttachment(uri)

    suspend fun getPartFromUri(uri: Uri): Part? = fileProcessingRepository.getPartFromUri(uri)

    suspend fun saveInlineData(inlineData: InlineData, displayName: String? = null): String? =
        fileProcessingRepository.saveInlineData(inlineData, displayName)
    // endregion

    // region Model delegation
    suspend fun getOpenRouterModels(forceRefresh: Boolean = false): List<SimpleModel> =
        modelRepository.getOpenRouterModels(forceRefresh)

    fun getOpenRouterModelsFlow(): StateFlow<List<SimpleModel>> =
        modelRepository.getOpenRouterModelsFlow()

    fun getOpenRouterModelsLoading(): StateFlow<Boolean> =
        modelRepository.getOpenRouterModelsLoading()

    fun getOpenRouterModelsError(): StateFlow<String?> =
        modelRepository.getOpenRouterModelsError()

    fun searchOpenRouterModels(query: String): List<SimpleModel> =
        modelRepository.searchOpenRouterModels(query)

    fun getOpenRouterModelsByProvider(provider: String): List<SimpleModel> =
        modelRepository.getOpenRouterModelsByProvider(provider)

    fun getFreeOpenRouterModels(): List<SimpleModel> =
        modelRepository.getFreeOpenRouterModels()

    fun getOpenRouterModelById(modelId: String): SimpleModel? =
        modelRepository.getOpenRouterModelById(modelId)

    fun clearOpenRouterModelsCache() = modelRepository.clearOpenRouterModelsCache()

    suspend fun getAvailableProvidersForModel(modelId: String): List<String> =
        modelRepository.getAvailableProvidersForModel(modelId)

    suspend fun getAvailableQuantizationsForModel(modelId: String): List<String> =
        modelRepository.getAvailableQuantizationsForModel(modelId)

    suspend fun getModelEndpoints(modelId: String): List<ModelEndpoint> =
        modelRepository.getModelEndpoints(modelId)

    suspend fun getProvidersDirectory(): ProviderDirectory = modelRepository.getProvidersDirectory()
    // endregion
}

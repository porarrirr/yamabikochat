package com.porarri.yamabikochat.data

import android.net.Uri
import com.porarri.yamabikochat.data.api.ApiRepository
import com.porarri.yamabikochat.data.auth.CodexAuthRepository
import com.porarri.yamabikochat.data.auth.CodexAuthState
import com.porarri.yamabikochat.data.auth.CodexUsageStatus
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
import com.porarri.yamabikochat.utils.FileValidationUtils
import com.porarri.yamabikochat.utils.SqlLikeUtils
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.StateFlow
import okhttp3.ResponseBody

class ChatRepository(
    private val databaseRepository: DatabaseRepository,
    private val apiRepository: ApiRepository,
    private val fileProcessingRepository: FileProcessingRepository,
    private val modelRepository: ModelRepository,
    private val codexAuthRepository: CodexAuthRepository,
    private val pricingRepository: LiteLlmPricingRepository
) {

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

    // region OpenAI-compatible key helpers
    suspend fun saveOpenAiCompatApiKey(name: String, apiKey: String?): Boolean =
        apiRepository.saveOpenAiCompatApiKey(name, apiKey)

    fun peekOpenAiCompatApiKey(name: String): String? = apiRepository.peekOpenAiCompatApiKey(name)

    fun hasOpenAiCompatApiKey(name: String?): Boolean = apiRepository.hasOpenAiCompatApiKey(name)

    suspend fun clearOpenAiCompatApiKey(name: String) = apiRepository.clearOpenAiCompatApiKey(name)
    // endregion

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

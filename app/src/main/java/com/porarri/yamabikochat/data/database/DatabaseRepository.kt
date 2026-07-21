package com.porarri.yamabikochat.data.database

import com.porarri.yamabikochat.data.local.AutoConversation
import com.porarri.yamabikochat.data.local.AutoConversationConfig
import com.porarri.yamabikochat.data.local.AutoConversationMessage
import com.porarri.yamabikochat.data.local.AutoConversationStatus
import com.porarri.yamabikochat.data.local.ChatDao
import com.porarri.yamabikochat.data.local.ChatMessage
import com.porarri.yamabikochat.data.local.ChatMessageSummary
import com.porarri.yamabikochat.data.local.ChatMessageThinking
import com.porarri.yamabikochat.data.local.ChatMessageToolActivity
import com.porarri.yamabikochat.data.local.ChatMessageVariant
import com.porarri.yamabikochat.data.local.ChatProject
import com.porarri.yamabikochat.data.local.ConversationSearchResult
import com.porarri.yamabikochat.data.local.Conversation
import com.porarri.yamabikochat.data.local.ConversationListEntry
import com.porarri.yamabikochat.data.local.DualChatMessage
import com.porarri.yamabikochat.data.local.FullAutoConversation
import com.porarri.yamabikochat.data.local.FullChatMessage
import com.porarri.yamabikochat.data.local.FusionTraceRecord
import com.porarri.yamabikochat.data.local.ModelPreset
import com.porarri.yamabikochat.data.local.ProjectListEntry
import com.porarri.yamabikochat.data.local.Settings
import com.porarri.yamabikochat.data.local.TokenUsageByModel
import com.porarri.yamabikochat.data.local.TokenUsageDailyPoint
import com.porarri.yamabikochat.data.local.TokenUsageRecord
import com.porarri.yamabikochat.data.local.TokenUsageTotals
import com.porarri.yamabikochat.utils.CodexSessionIdUtils
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first

class DatabaseRepository(private val chatDao: ChatDao) {

    fun getAllConversations(): Flow<List<Conversation>> = chatDao.getAllConversations()

    fun getConversationListEntries(): Flow<List<ConversationListEntry>> =
        chatDao.getConversationListEntries()

    fun getProjects(): Flow<List<ProjectListEntry>> = chatDao.getProjects()

    suspend fun getProjectById(id: Long): ChatProject? = chatDao.getProjectById(id)

    suspend fun upsertProject(project: ChatProject): Long = chatDao.upsertProject(project)

    suspend fun assignConversationToProject(conversationId: Long, projectId: Long?) {
        val conversation = chatDao.getConversationById(conversationId)
            ?: throw IllegalArgumentException("Conversation not found: $conversationId")
        if (projectId != null) {
            chatDao.getProjectById(projectId)
                ?: throw IllegalArgumentException("Project not found: $projectId")
        }
        val now = System.currentTimeMillis()
        chatDao.assignConversationToProject(conversationId, projectId, now)
        projectId?.let { chatDao.touchProject(it, now) }
        conversation.projectId?.takeIf { it != projectId }?.let { chatDao.touchProject(it, now) }
    }

    suspend fun deleteProject(id: Long, deleteConversations: Boolean) {
        chatDao.getProjectById(id) ?: throw IllegalArgumentException("Project not found: $id")
        chatDao.deleteProject(id, deleteConversations)
    }

    suspend fun countConversationsInProject(projectId: Long): Int =
        chatDao.countConversationsInProject(projectId)

    suspend fun getConversationById(id: Long): Conversation? = chatDao.getConversationById(id)

    suspend fun findLatestEmptyConversationByTitle(title: String, projectId: Long? = null): Conversation? =
        chatDao.findLatestEmptyConversationByTitle(title, projectId)

    suspend fun upsertConversation(conversation: Conversation): Long =
        chatDao.upsertConversation(conversation)

    suspend fun getOrCreateCodexSessionId(conversationId: Long): String {
        val existing = chatDao.getCodexSessionId(conversationId)?.trim().orEmpty()
        if (existing.isNotBlank()) return existing

        val created = CodexSessionIdUtils.newSessionId()
        chatDao.updateCodexSessionId(conversationId, created)
        return created
    }

    suspend fun deleteConversationById(id: Long) {
        chatDao.deleteConversationCascade(id)
    }

    suspend fun purgeSecretConversations() {
        chatDao.purgeSecretConversations()
    }

    fun getMessagesForConversation(conversationId: Long): Flow<List<ChatMessageSummary>> =
        chatDao.getMessagesForConversation(conversationId)

    suspend fun getFullMessageById(id: Long): FullChatMessage? {
        val chatMessage = chatDao.getFullMessageById(id) ?: return null
        val thinking = chatDao.getThinkingByMessageId(id)
        val variants = chatDao.getVariantsForMessage(id)
        val toolActivity = chatDao.getToolActivityForMessage(id)
        val variantIds = variants.map { it.id }.filter { it > 0L }
        val variantToolActivities = if (variantIds.isEmpty()) {
            emptyMap()
        } else {
            chatDao.getToolActivitiesForVariants(variantIds)
                .mapNotNull { activity -> activity.variantId?.let { it to activity } }
                .toMap()
        }
        return FullChatMessage(
            chatMessage = chatMessage,
            thinkingStream = thinking?.thinkingStream,
            variants = variants,
            toolActivity = toolActivity,
            variantToolActivities = variantToolActivities
        )
    }

    suspend fun getFullMessagesByIds(ids: Collection<Long>): Map<Long, FullChatMessage> {
        if (ids.isEmpty()) return emptyMap()

        val idList = ids.toList()
        val messages = chatDao.getFullMessagesByIds(idList)
        val thinking = chatDao.getThinkingByMessageIds(idList)
        val thinkingMap = thinking.associateBy { it.messageId }
        val variantsByMessageId = chatDao.getVariantsForMessages(idList).groupBy { it.baseMessageId }
        val toolActivitiesByMessageId = chatDao.getToolActivitiesForMessages(idList)
            .mapNotNull { activity -> activity.messageId?.let { it to activity } }
            .toMap()
        val allVariantIds = variantsByMessageId.values.flatten().map { it.id }.filter { it > 0L }
        val variantToolActivities = if (allVariantIds.isEmpty()) {
            emptyMap()
        } else {
            chatDao.getToolActivitiesForVariants(allVariantIds)
                .mapNotNull { activity -> activity.variantId?.let { it to activity } }
                .toMap()
        }
        return messages.associate { message ->
            val variants = variantsByMessageId[message.id].orEmpty()
            val variantIds = variants.map { it.id }.toSet()
            message.id to FullChatMessage(
                chatMessage = message,
                thinkingStream = thinkingMap[message.id]?.thinkingStream,
                variants = variants,
                toolActivity = toolActivitiesByMessageId[message.id],
                variantToolActivities = variantToolActivities.filterKeys { it in variantIds }
            )
        }
    }

    suspend fun insertMessage(message: ChatMessage): Long {
        val id = chatDao.insertMessage(message)
        touchConversation(message.conversationId)
        return id
    }

    suspend fun updateMessage(message: ChatMessage) {
        chatDao.updateMessage(message)
        touchConversation(message.conversationId)
    }

    suspend fun insertThinking(messageId: Long, thinkingStream: String) {
        chatDao.insertThinking(ChatMessageThinking(messageId, thinkingStream))
    }

    suspend fun updateThinkingStream(messageId: Long, thinkingStream: String) {
        chatDao.insertThinking(ChatMessageThinking(messageId, thinkingStream))
    }

    suspend fun insertMessageVariant(
        baseMessageId: Long,
        text: String,
        attachments: List<String> = emptyList(),
        thinkingStream: String? = null
    ): ChatMessageVariant {
        val baseMessage = chatDao.getFullMessageById(baseMessageId)
            ?: throw IllegalArgumentException("Base message not found: $baseMessageId")
        val nextIndex = (chatDao.getMaxVariantIndex(baseMessageId) + 1).coerceAtLeast(1)
        val variant = ChatMessageVariant(
            baseMessageId = baseMessageId,
            variantIndex = nextIndex,
            text = text,
            attachments = attachments,
            thinkingStream = thinkingStream
        )
        val variantId = chatDao.insertMessageVariant(variant)
        chatDao.updateMessageSelectedVariantIndex(baseMessageId, nextIndex)
        touchConversation(baseMessage.conversationId)
        return variant.copy(id = variantId)
    }

    suspend fun updateMessageVariant(variant: ChatMessageVariant) {
        val existing = chatDao.getMessageVariantById(variant.id)
            ?: throw IllegalArgumentException("Message variant not found: ${variant.id}")
        chatDao.updateMessageVariant(variant)
        chatDao.getFullMessageById(existing.baseMessageId)?.let { touchConversation(it.conversationId) }
    }

    suspend fun setMessageSelectedVariantIndex(messageId: Long, variantIndex: Int) {
        val message = chatDao.getFullMessageById(messageId)
            ?: throw IllegalArgumentException("Message not found: $messageId")
        val maxVariantIndex = chatDao.getMaxVariantIndex(messageId)
        val normalized = variantIndex.coerceIn(0, maxVariantIndex)
        chatDao.updateMessageSelectedVariantIndex(messageId, normalized)
        touchConversation(message.conversationId)
    }

    private suspend fun touchConversation(conversationId: Long) {
        chatDao.updateConversationTimestamp(conversationId, System.currentTimeMillis())
    }

    fun getSettings(): Flow<Settings?> = chatDao.getSettings()

    suspend fun getLatestSettings(): Settings? = chatDao.getSettings().first()

    suspend fun saveSettings(settings: Settings) =
        chatDao.saveSettings(settings.normalizedForPersistence())

    suspend fun saveToolActivities(messageId: Long, stepsJSON: String) {
        chatDao.deleteToolActivityForMessage(messageId)
        chatDao.insertToolActivity(
            ChatMessageToolActivity(messageId = messageId, stepsJSON = stepsJSON)
        )
    }

    suspend fun saveToolActivitiesForVariant(variantId: Long, stepsJSON: String) {
        chatDao.deleteToolActivityForVariant(variantId)
        chatDao.insertToolActivity(
            ChatMessageToolActivity(variantId = variantId, stepsJSON = stepsJSON)
        )
    }

    suspend fun getToolActivityForMessage(messageId: Long): ChatMessageToolActivity? =
        chatDao.getToolActivityForMessage(messageId)

    suspend fun getToolActivityForVariant(variantId: Long): ChatMessageToolActivity? =
        chatDao.getToolActivityForVariant(variantId)

    suspend fun saveFusionTrace(record: FusionTraceRecord) =
        chatDao.upsertFusionTrace(record)

    suspend fun getFusionTrace(id: String): FusionTraceRecord? =
        chatDao.getFusionTrace(id)

    fun getAllModelPresets(): Flow<List<ModelPreset>> = chatDao.getAllModelPresets()

    suspend fun upsertModelPreset(preset: ModelPreset) = chatDao.upsertModelPreset(preset)

    suspend fun deleteModelPresetById(id: Long) = chatDao.deleteModelPresetById(id)

    suspend fun insertDualMessage(message: DualChatMessage): Long {
        val id = chatDao.insertDualMessage(message)
        touchConversation(message.conversationId)
        return id
    }

    suspend fun updateDualMessage(message: DualChatMessage) {
        chatDao.updateDualMessage(message)
        touchConversation(message.conversationId)
    }

    fun getDualMessagesForConversation(conversationId: Long): Flow<List<DualChatMessage>> =
        chatDao.getDualMessagesForConversation(conversationId)

    fun searchMessages(pattern: String, limit: Int, projectId: Long?): Flow<List<ConversationSearchResult>> =
        chatDao.searchMessages(pattern, projectId, limit)

    suspend fun getDualMessageById(id: Long): DualChatMessage? = chatDao.getDualMessageById(id)

    suspend fun createAutoConversation(
        config: AutoConversationConfig,
        boundChatConversationId: Long?
    ): Long {
        val conversation = AutoConversation(
            title = config.title,
            modelA = config.modelA,
            modelB = config.modelB,
            providerA = config.providerA,
            providerB = config.providerB,
            systemPromptA = config.systemPromptA,
            systemPromptB = config.systemPromptB,
            status = AutoConversationStatus.ACTIVE,
            maxTurns = config.maxTurns,
            endSignal = config.endSignal,
            boundChatConversationId = boundChatConversationId
        )
        return chatDao.insertAutoConversation(conversation)
    }

    suspend fun updateAutoConversation(conversation: AutoConversation) =
        chatDao.updateAutoConversation(conversation)

    fun getAllAutoConversations(): Flow<List<AutoConversation>> = chatDao.getAllAutoConversations()

    suspend fun getAutoConversationById(id: Long): AutoConversation? = chatDao.getAutoConversationById(id)

    suspend fun deleteAutoConversationById(id: Long) {
        chatDao.deleteAutoConversationMessages(id)
        chatDao.deleteAutoConversationById(id)
    }

    suspend fun insertAutoConversationMessage(message: AutoConversationMessage): Long =
        chatDao.insertAutoConversationMessage(message)

    fun getAutoConversationMessages(conversationId: Long): Flow<List<AutoConversationMessage>> =
        chatDao.getAutoConversationMessages(conversationId)

    suspend fun getLastAutoConversationMessage(conversationId: Long): AutoConversationMessage? =
        chatDao.getLastAutoConversationMessage(conversationId)

    suspend fun getFullAutoConversation(id: Long): FullAutoConversation? {
        val conversation = getAutoConversationById(id) ?: return null
        val messages = getAutoConversationMessages(id).first()
        return FullAutoConversation(conversation, messages)
    }

    suspend fun insertTokenUsage(record: TokenUsageRecord) =
        chatDao.insertTokenUsage(record)

    fun observeTokenUsageTotals(sinceEpochMs: Long): Flow<TokenUsageTotals> =
        chatDao.observeTokenUsageTotals(sinceEpochMs)

    fun observeTokenUsageByModel(sinceEpochMs: Long, limit: Int): Flow<List<TokenUsageByModel>> =
        chatDao.observeTokenUsageByModel(sinceEpochMs, limit)

    fun observeTokenUsageDaily(sinceEpochMs: Long): Flow<List<TokenUsageDailyPoint>> =
        chatDao.observeTokenUsageDaily(sinceEpochMs)
}

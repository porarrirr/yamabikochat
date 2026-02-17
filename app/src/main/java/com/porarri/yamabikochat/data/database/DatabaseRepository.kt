package com.porarri.yamabikochat.data.database

import com.porarri.yamabikochat.data.local.AutoConversation
import com.porarri.yamabikochat.data.local.AutoConversationConfig
import com.porarri.yamabikochat.data.local.AutoConversationMessage
import com.porarri.yamabikochat.data.local.AutoConversationStatus
import com.porarri.yamabikochat.data.local.ChatDao
import com.porarri.yamabikochat.data.local.ChatMessage
import com.porarri.yamabikochat.data.local.ChatMessageSummary
import com.porarri.yamabikochat.data.local.ChatMessageThinking
import com.porarri.yamabikochat.data.local.ConversationSearchResult
import com.porarri.yamabikochat.data.local.Conversation
import com.porarri.yamabikochat.data.local.ConversationListEntry
import com.porarri.yamabikochat.data.local.DualChatMessage
import com.porarri.yamabikochat.data.local.FullAutoConversation
import com.porarri.yamabikochat.data.local.FullChatMessage
import com.porarri.yamabikochat.data.local.ModelPreset
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

    suspend fun getConversationById(id: Long): Conversation? = chatDao.getConversationById(id)

    suspend fun findLatestEmptyConversationByTitle(title: String): Conversation? =
        chatDao.findLatestEmptyConversationByTitle(title)

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
        val chatMessage = chatDao.getFullMessageById(id)
        val thinking = chatDao.getThinkingByMessageId(id)
        return if (chatMessage != null) {
            FullChatMessage(chatMessage, thinking?.thinkingStream)
        } else {
            null
        }
    }

    suspend fun getFullMessagesByIds(ids: Collection<Long>): Map<Long, FullChatMessage> {
        if (ids.isEmpty()) return emptyMap()

        val idList = ids.toList()
        val messages = chatDao.getFullMessagesByIds(idList)
        val thinking = chatDao.getThinkingByMessageIds(idList)
        val thinkingMap = thinking.associateBy { it.messageId }
        return messages.associate { message ->
            message.id to FullChatMessage(message, thinkingMap[message.id]?.thinkingStream)
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

    private suspend fun touchConversation(conversationId: Long) {
        chatDao.updateConversationTimestamp(conversationId, System.currentTimeMillis())
    }

    fun getSettings(): Flow<Settings?> = chatDao.getSettings()

    suspend fun getLatestSettings(): Settings? = chatDao.getSettings().first()

    suspend fun saveSettings(settings: Settings) = chatDao.saveSettings(settings)

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

    fun searchMessages(pattern: String, limit: Int): Flow<List<ConversationSearchResult>> =
        chatDao.searchMessages(pattern, limit)

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

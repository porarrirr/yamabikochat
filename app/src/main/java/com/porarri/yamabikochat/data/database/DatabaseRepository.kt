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
import com.porarri.yamabikochat.data.security.SecretConversationVault
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map

class DatabaseRepository(private val chatDao: ChatDao) {

    fun getAllConversations(): Flow<List<Conversation>> = chatDao.getAllConversations()

    suspend fun getAllConversationIds(): List<Long> = chatDao.getAllConversations().first().map { it.id }

    fun getConversationListEntries(): Flow<List<ConversationListEntry>> =
        chatDao.getConversationListEntries().map { entries ->
            entries.map { entry ->
                if (!entry.isSecret) {
                    entry
                } else {
                    entry.copy(
                        title = "Secret Chat",
                        lastChatSnippet = entry.lastChatSnippet?.let {
                            SecretConversationVault.open(it, entry.conversationId).take(120)
                        },
                        lastDualSnippet = entry.lastDualSnippet?.let {
                            SecretConversationVault.open(it, entry.conversationId).take(120)
                        }
                    )
                }
            }
        }

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
        val secretIds = if (deleteConversations) {
            chatDao.getConversationIdsForProject(id).filter { conversationId -> isSecret(conversationId) }
        } else {
            emptyList()
        }
        chatDao.deleteProject(id, deleteConversations)
        secretIds.forEach(SecretConversationVault::destroy)
    }

    suspend fun getConversationIdsForProject(projectId: Long): List<Long> = chatDao.getConversationIdsForProject(projectId)

    suspend fun getSecretConversationIds(): List<Long> = chatDao.getSecretConversationIds()

    suspend fun getSecretAttachmentPaths(): List<String> =
        chatDao.getSecretConversationIds()
            .flatMap { conversationId -> getAttachmentPathsForConversation(conversationId) }
            .distinct()

    suspend fun getAttachmentPathsForSecretConversation(conversationId: Long): List<String> {
        if (!isSecret(conversationId)) return emptyList()
        return getAttachmentPathsForConversation(conversationId)
    }

    suspend fun getAttachmentPathsForConversation(conversationId: Long): List<String> {
        val secret = isSecret(conversationId)
        val storedPaths = chatDao.getChatMessagesForPurge(conversationId).flatMap { it.attachments } +
            chatDao.getVariantsForPurge(conversationId).flatMap { it.attachments } +
            chatDao.getDualMessagesForPurge(conversationId).flatMap { it.attachments }
        return storedPaths.mapNotNull { path ->
            if (!secret || !path.startsWith(SecretConversationVault.PREFIX)) {
                path
            } else {
                runCatching { SecretConversationVault.open(path, conversationId) }.getOrNull()
            }
        }.distinct()
    }

    suspend fun countConversationsInProject(projectId: Long): Int =
        chatDao.countConversationsInProject(projectId)

    suspend fun getConversationById(id: Long): Conversation? =
        chatDao.getConversationById(id)?.let(::revealConversation)

    suspend fun findLatestEmptyConversationByTitle(title: String, projectId: Long? = null): Conversation? =
        chatDao.findLatestEmptyConversationByTitle(title, projectId)

    suspend fun upsertConversation(conversation: Conversation): Long {
        val existing = conversation.id.takeIf { it > 0 }?.let { chatDao.getConversationById(it) }
        if (!conversation.isSecret) {
            val id = chatDao.upsertConversation(conversation)
            if (existing?.isSecret == true) SecretConversationVault.destroy(id)
            return id
        }

        if (conversation.id == 0L) {
            val id = chatDao.upsertConversation(
                conversation.copy(title = "Secret Chat", systemPrompt = null)
            )
            SecretConversationVault.activate(id)
            chatDao.upsertConversation(
                conversation.copy(
                    id = id,
                    title = "Secret Chat",
                    systemPrompt = conversation.systemPrompt?.let { SecretConversationVault.seal(it, id) }
                )
            )
            return id
        }

        SecretConversationVault.activate(conversation.id)
        return chatDao.upsertConversation(protectConversation(conversation))
    }

    suspend fun getOrCreateCodexSessionId(conversationId: Long): String {
        val existing = chatDao.getCodexSessionId(conversationId)?.trim().orEmpty()
        if (existing.isNotBlank()) return existing

        val created = CodexSessionIdUtils.newSessionId()
        chatDao.updateCodexSessionId(conversationId, created)
        return created
    }

    suspend fun deleteConversationById(id: Long) {
        chatDao.deleteConversationCascade(id)
        SecretConversationVault.destroy(id)
    }

    suspend fun deleteMessagesForConversation(conversationId: Long) {
        chatDao.deleteVariantsForConversation(conversationId)
        chatDao.deleteMessagesForConversation(conversationId)
        chatDao.deleteDualMessagesForConversation(conversationId)
    }

    suspend fun purgeSecretConversations() {
        val ids = chatDao.getSecretConversationIds()
        chatDao.purgeSecretConversations()
        ids.forEach(SecretConversationVault::destroy)
    }

    fun getMessagesForConversation(conversationId: Long): Flow<List<ChatMessageSummary>> =
        chatDao.getMessagesForConversation(conversationId).map { summaries ->
            if (!isSecret(conversationId)) summaries else summaries.map {
                it.copy(textPreview = SecretConversationVault.open(it.textPreview, conversationId).take(100))
            }
        }

    suspend fun getFullMessageById(id: Long): FullChatMessage? {
        val storedMessage = chatDao.getFullMessageById(id) ?: return null
        val chatMessage = revealMessage(storedMessage)
        val thinking = chatDao.getThinkingByMessageId(id)
        val variants = chatDao.getVariantsForMessage(id).map { revealVariant(it, chatMessage.conversationId) }
        val toolActivity = if (isSecret(chatMessage.conversationId)) null else chatDao.getToolActivityForMessage(id)
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
            thinkingStream = thinking?.thinkingStream?.let {
                if (isSecret(chatMessage.conversationId)) {
                    SecretConversationVault.open(it, chatMessage.conversationId)
                } else {
                    it
                }
            },
            variants = variants,
            toolActivity = toolActivity,
            variantToolActivities = variantToolActivities
        )
    }

    suspend fun getFullMessagesByIds(ids: Collection<Long>): Map<Long, FullChatMessage> {
        if (ids.isEmpty()) return emptyMap()

        val idList = ids.toList()
        val messages = chatDao.getFullMessagesByIds(idList).map { message -> revealMessage(message) }
        val thinking = chatDao.getThinkingByMessageIds(idList)
        val thinkingMap = thinking.associateBy { it.messageId }
        val conversationByMessage = messages.associate { it.id to it.conversationId }
        val variantsByMessageId = chatDao.getVariantsForMessages(idList)
            .map { variant -> revealVariant(variant, conversationByMessage.getValue(variant.baseMessageId)) }
            .groupBy { it.baseMessageId }
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
                thinkingStream = thinkingMap[message.id]?.thinkingStream?.let {
                    if (isSecret(message.conversationId)) SecretConversationVault.open(it, message.conversationId) else it
                },
                variants = variants,
                toolActivity = toolActivitiesByMessageId[message.id],
                variantToolActivities = variantToolActivities.filterKeys { it in variantIds }
            )
        }
    }

    suspend fun insertMessage(message: ChatMessage): Long {
        val id = chatDao.insertMessage(protectMessage(message))
        touchConversation(message.conversationId)
        return id
    }

    suspend fun updateMessage(message: ChatMessage) {
        chatDao.updateMessage(protectMessage(message))
        touchConversation(message.conversationId)
    }

    suspend fun insertThinking(messageId: Long, thinkingStream: String) {
        val conversationId = chatDao.getFullMessageById(messageId)?.conversationId
            ?: error("Message not found: $messageId")
        chatDao.insertThinking(ChatMessageThinking(messageId, protectText(thinkingStream, conversationId)))
    }

    suspend fun updateThinkingStream(messageId: Long, thinkingStream: String) {
        insertThinking(messageId, thinkingStream)
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
        val variant = protectVariant(ChatMessageVariant(
            baseMessageId = baseMessageId,
            variantIndex = nextIndex,
            text = text,
            attachments = attachments,
            thinkingStream = thinkingStream
        ), baseMessage.conversationId)
        val variantId = chatDao.insertMessageVariant(variant)
        chatDao.updateMessageSelectedVariantIndex(baseMessageId, nextIndex)
        touchConversation(baseMessage.conversationId)
        return revealVariant(variant.copy(id = variantId), baseMessage.conversationId)
    }

    suspend fun updateMessageVariant(variant: ChatMessageVariant) {
        val existing = chatDao.getMessageVariantById(variant.id)
            ?: throw IllegalArgumentException("Message variant not found: ${variant.id}")
        val base = chatDao.getFullMessageById(existing.baseMessageId)
            ?: error("Base message not found: ${existing.baseMessageId}")
        chatDao.updateMessageVariant(protectVariant(variant, base.conversationId))
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

    suspend fun saveToolActivities(
        messageId: Long,
        stepsJSON: String,
        providerTranscriptJSON: String? = null,
        attachmentPathsJSON: String? = null
    ) {
        val conversationId = chatDao.getFullMessageById(messageId)?.conversationId
            ?: error("Message not found: $messageId")
        if (isSecret(conversationId)) return
        val existing = chatDao.getToolActivityForMessage(messageId)
        chatDao.deleteToolActivityForMessage(messageId)
        chatDao.insertToolActivity(
            ChatMessageToolActivity(
                messageId = messageId,
                stepsJSON = stepsJSON,
                providerTranscriptJSON = providerTranscriptJSON ?: existing?.providerTranscriptJSON,
                attachmentPathsJSON = attachmentPathsJSON ?: existing?.attachmentPathsJSON
            )
        )
    }

    suspend fun saveToolActivitiesForVariant(
        variantId: Long,
        stepsJSON: String,
        providerTranscriptJSON: String? = null,
        attachmentPathsJSON: String? = null
    ) {
        val variant = chatDao.getMessageVariantById(variantId)
            ?: error("Variant not found: $variantId")
        val conversationId = chatDao.getFullMessageById(variant.baseMessageId)?.conversationId
            ?: error("Base message not found: ${variant.baseMessageId}")
        if (isSecret(conversationId)) return
        val existing = chatDao.getToolActivityForVariant(variantId)
        chatDao.deleteToolActivityForVariant(variantId)
        chatDao.insertToolActivity(
            ChatMessageToolActivity(
                variantId = variantId,
                stepsJSON = stepsJSON,
                providerTranscriptJSON = providerTranscriptJSON ?: existing?.providerTranscriptJSON,
                attachmentPathsJSON = attachmentPathsJSON ?: existing?.attachmentPathsJSON
            )
        )
    }

    suspend fun getToolActivityForMessage(messageId: Long): ChatMessageToolActivity? =
        chatDao.getToolActivityForMessage(messageId)

    suspend fun getToolActivityForVariant(variantId: Long): ChatMessageToolActivity? =
        chatDao.getToolActivityForVariant(variantId)

    suspend fun saveFusionTrace(record: FusionTraceRecord) {
        if (record.conversationId?.let { isSecret(it) } == true) return
        chatDao.upsertFusionTrace(record)
    }

    suspend fun getFusionTrace(id: String): FusionTraceRecord? =
        chatDao.getFusionTrace(id)

    fun getAllModelPresets(): Flow<List<ModelPreset>> = chatDao.getAllModelPresets()

    suspend fun upsertModelPreset(preset: ModelPreset) = chatDao.upsertModelPreset(preset)

    suspend fun deleteModelPresetById(id: Long) = chatDao.deleteModelPresetById(id)

    suspend fun insertDualMessage(message: DualChatMessage): Long {
        val id = chatDao.insertDualMessage(protectDualMessage(message))
        touchConversation(message.conversationId)
        return id
    }

    suspend fun updateDualMessage(message: DualChatMessage) {
        chatDao.updateDualMessage(protectDualMessage(message))
        touchConversation(message.conversationId)
    }

    fun getDualMessagesForConversation(conversationId: Long): Flow<List<DualChatMessage>> =
        chatDao.getDualMessagesForConversation(conversationId).map { rows ->
            rows.map { revealDualMessage(it) }
        }

    fun searchMessages(pattern: String, limit: Int, projectId: Long?): Flow<List<ConversationSearchResult>> =
        chatDao.searchMessages(pattern, projectId, limit)

    suspend fun getDualMessageById(id: Long): DualChatMessage? =
        chatDao.getDualMessageById(id)?.let { message -> revealDualMessage(message) }

    suspend fun createAutoConversation(
        config: AutoConversationConfig,
        boundChatConversationId: Long?
    ): Long {
        if (boundChatConversationId?.let { isSecret(it) } == true) {
            throw IllegalStateException("シークレットチャットでは自動会話を利用できません。")
        }
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

    private suspend fun isSecret(conversationId: Long): Boolean =
        chatDao.getConversationById(conversationId)?.isSecret == true

    private fun protectConversation(conversation: Conversation): Conversation = conversation.copy(
        title = "Secret Chat",
        systemPrompt = conversation.systemPrompt?.let {
            SecretConversationVault.seal(it, conversation.id)
        }
    )

    private fun revealConversation(conversation: Conversation): Conversation = conversation.copy(
        systemPrompt = conversation.systemPrompt?.let {
            SecretConversationVault.open(it, conversation.id)
        }
    )

    private suspend fun protectText(value: String, conversationId: Long): String =
        if (isSecret(conversationId)) SecretConversationVault.seal(value, conversationId) else value

    private suspend fun protectMessage(message: ChatMessage): ChatMessage =
        if (!isSecret(message.conversationId)) message else message.copy(
            text = SecretConversationVault.seal(message.text, message.conversationId),
            attachments = message.attachments.map {
                SecretConversationVault.seal(it, message.conversationId)
            },
            thinkingSummary = message.thinkingSummary?.let {
                SecretConversationVault.seal(it, message.conversationId)
            }
        )

    private suspend fun revealMessage(message: ChatMessage): ChatMessage =
        if (!isSecret(message.conversationId)) message else message.copy(
            text = SecretConversationVault.open(message.text, message.conversationId),
            attachments = message.attachments.map {
                SecretConversationVault.open(it, message.conversationId)
            },
            thinkingSummary = message.thinkingSummary?.let {
                SecretConversationVault.open(it, message.conversationId)
            }
        )

    private suspend fun protectVariant(variant: ChatMessageVariant, conversationId: Long): ChatMessageVariant =
        if (!isSecret(conversationId)) variant else variant.copy(
            text = SecretConversationVault.seal(variant.text, conversationId),
            attachments = variant.attachments.map { SecretConversationVault.seal(it, conversationId) },
            thinkingStream = variant.thinkingStream?.let { SecretConversationVault.seal(it, conversationId) }
        )

    private suspend fun revealVariant(variant: ChatMessageVariant, conversationId: Long): ChatMessageVariant =
        if (!isSecret(conversationId)) variant else variant.copy(
            text = SecretConversationVault.open(variant.text, conversationId),
            attachments = variant.attachments.map { SecretConversationVault.open(it, conversationId) },
            thinkingStream = variant.thinkingStream?.let { SecretConversationVault.open(it, conversationId) }
        )

    private suspend fun protectDualMessage(message: DualChatMessage): DualChatMessage =
        if (!isSecret(message.conversationId)) message else message.copy(
            userText = SecretConversationVault.seal(message.userText, message.conversationId),
            modelAText = SecretConversationVault.seal(message.modelAText, message.conversationId),
            modelBText = SecretConversationVault.seal(message.modelBText, message.conversationId),
            modelAThinking = message.modelAThinking?.let { SecretConversationVault.seal(it, message.conversationId) },
            modelBThinking = message.modelBThinking?.let { SecretConversationVault.seal(it, message.conversationId) },
            attachments = message.attachments.map { SecretConversationVault.seal(it, message.conversationId) },
            modelAToolActivityJSON = null,
            modelBToolActivityJSON = null
        )

    private suspend fun revealDualMessage(message: DualChatMessage): DualChatMessage =
        if (!isSecret(message.conversationId)) message else message.copy(
            userText = SecretConversationVault.open(message.userText, message.conversationId),
            modelAText = SecretConversationVault.open(message.modelAText, message.conversationId),
            modelBText = SecretConversationVault.open(message.modelBText, message.conversationId),
            modelAThinking = message.modelAThinking?.let { SecretConversationVault.open(it, message.conversationId) },
            modelBThinking = message.modelBThinking?.let { SecretConversationVault.open(it, message.conversationId) },
            attachments = message.attachments.map { SecretConversationVault.open(it, message.conversationId) }
        )
}

package com.porarri.yamabikochat.data.local

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Update
import androidx.room.Upsert
import androidx.room.Transaction
import kotlinx.coroutines.flow.Flow

@Dao
interface ChatDao {

    // Conversation queries
    @Upsert
    suspend fun upsertConversation(conversation: Conversation): Long

    @Query("SELECT * FROM conversations WHERE isSecret = 0 ORDER BY timestamp DESC")
    fun getAllConversations(): Flow<List<Conversation>>

    @Upsert
    suspend fun upsertProject(project: ChatProject): Long

    @Query(
        """
        SELECT
            p.id as id,
            p.title as title,
            p.iconName as iconName,
            p.colorHex as colorHex,
            p.instructions as instructions,
            p.createdAtMs as createdAtMs,
            p.updatedAtMs as updatedAtMs,
            COUNT(c.id) as conversationCount
        FROM projects p
        LEFT JOIN conversations c ON c.projectId = p.id
        GROUP BY p.id
        ORDER BY p.updatedAtMs DESC, p.createdAtMs DESC
        """
    )
    fun getProjects(): Flow<List<ProjectListEntry>>

    @Query("SELECT * FROM projects WHERE id = :id")
    suspend fun getProjectById(id: Long): ChatProject?

    @Query("UPDATE conversations SET projectId = :projectId, timestamp = :timestamp WHERE id = :conversationId")
    suspend fun assignConversationToProject(conversationId: Long, projectId: Long?, timestamp: Long)

    @Query("UPDATE projects SET updatedAtMs = :timestamp WHERE id = :projectId")
    suspend fun touchProject(projectId: Long, timestamp: Long)

    @Query("UPDATE conversations SET projectId = NULL WHERE projectId = :projectId")
    suspend fun clearProjectAssignments(projectId: Long)

    @Query("DELETE FROM projects WHERE id = :projectId")
    suspend fun deleteProjectById(projectId: Long)

    @Query("SELECT COUNT(*) FROM conversations WHERE projectId = :projectId")
    suspend fun countConversationsInProject(projectId: Long): Int

    @Query(
        """
        SELECT
            c.id as conversationId,
            c.title as title,
            c.timestamp as timestamp,
            c.apiProvider as apiProvider,
            c.model as model,
            c.isSecret as isSecret,
            c.projectId as projectId,
            p.title as projectTitle,
            (SELECT MAX(timestamp) FROM chat_messages WHERE conversationId = c.id) as lastChatTimestamp,
            (SELECT CASE
                WHEN LENGTH(resolvedText) > 120 THEN SUBSTR(resolvedText, 1, 120) || '...'
                ELSE resolvedText
            END
            FROM (
                SELECT
                    timestamp,
                    CASE
                        WHEN role = 'model' AND selectedVariantIndex > 0 THEN COALESCE(
                            (SELECT v.text
                             FROM chat_message_variants v
                             WHERE v.baseMessageId = chat_messages.id
                               AND v.variantIndex = chat_messages.selectedVariantIndex
                             LIMIT 1),
                            text
                        )
                        ELSE text
                    END as resolvedText
                FROM chat_messages
                WHERE conversationId = c.id
            ) AS chat_preview
            ORDER BY timestamp DESC
            LIMIT 1) as lastChatSnippet,
            (SELECT MAX(timestamp) FROM dual_chat_messages WHERE conversationId = c.id) as lastDualTimestamp,
            (SELECT CASE
                WHEN role = 'user' THEN
                    CASE WHEN LENGTH(userText) > 120 THEN SUBSTR(userText, 1, 120) || '...'
                    ELSE userText END
                WHEN role = 'dual_model' THEN
                    CASE
                        WHEN LENGTH(modelAText) > 0 THEN
                            CASE WHEN LENGTH(modelAText) > 120 THEN SUBSTR(modelAText, 1, 120) || '...'
                            ELSE modelAText END
                        WHEN LENGTH(modelBText) > 0 THEN
                            CASE WHEN LENGTH(modelBText) > 120 THEN SUBSTR(modelBText, 1, 120) || '...'
                            ELSE modelBText END
                        ELSE ''
                    END
                ELSE ''
            END
            FROM dual_chat_messages
            WHERE conversationId = c.id
            ORDER BY timestamp DESC
            LIMIT 1) as lastDualSnippet,
            (SELECT MAX(timestamp) FROM chat_messages WHERE conversationId = c.id AND role = 'model') as lastChatModelTimestamp,
            (SELECT MAX(timestamp) FROM dual_chat_messages WHERE conversationId = c.id AND role = 'dual_model') as lastDualModelTimestamp,
            (SELECT modelAProvider FROM dual_chat_messages WHERE conversationId = c.id AND role = 'dual_model' ORDER BY timestamp DESC LIMIT 1) as lastDualModelAProvider,
            (SELECT modelAName FROM dual_chat_messages WHERE conversationId = c.id AND role = 'dual_model' ORDER BY timestamp DESC LIMIT 1) as lastDualModelAName,
            (SELECT modelBProvider FROM dual_chat_messages WHERE conversationId = c.id AND role = 'dual_model' ORDER BY timestamp DESC LIMIT 1) as lastDualModelBProvider,
            (SELECT modelBName FROM dual_chat_messages WHERE conversationId = c.id AND role = 'dual_model' ORDER BY timestamp DESC LIMIT 1) as lastDualModelBName
        FROM conversations c
        LEFT JOIN projects p ON p.id = c.projectId
        WHERE EXISTS (SELECT 1 FROM chat_messages cm WHERE cm.conversationId = c.id)
           OR EXISTS (SELECT 1 FROM dual_chat_messages dcm WHERE dcm.conversationId = c.id)
        ORDER BY c.timestamp DESC
        """
    )
    fun getConversationListEntries(): Flow<List<ConversationListEntry>>

    @Query("SELECT * FROM conversations WHERE id = :id")
    suspend fun getConversationById(id: Long): Conversation?

    @Query(
        """
        SELECT *
        FROM conversations c
        WHERE c.title = :title
          AND c.isSecret = 0
          AND ((:projectId IS NULL AND c.projectId IS NULL) OR c.projectId = :projectId)
          AND NOT EXISTS (SELECT 1 FROM chat_messages cm WHERE cm.conversationId = c.id)
          AND NOT EXISTS (SELECT 1 FROM dual_chat_messages dcm WHERE dcm.conversationId = c.id)
        ORDER BY c.timestamp DESC
        LIMIT 1
        """
    )
    suspend fun findLatestEmptyConversationByTitle(title: String, projectId: Long?): Conversation?

    @Query("DELETE FROM conversations WHERE id = :id")
    suspend fun deleteConversationById(id: Long)

    @Query("UPDATE conversations SET timestamp = :timestamp WHERE id = :conversationId")
    suspend fun updateConversationTimestamp(conversationId: Long, timestamp: Long)

    @Query("SELECT codexSessionId FROM conversations WHERE id = :conversationId")
    suspend fun getCodexSessionId(conversationId: Long): String?

    @Query("UPDATE conversations SET codexSessionId = :codexSessionId WHERE id = :conversationId")
    suspend fun updateCodexSessionId(conversationId: Long, codexSessionId: String?)

    @Query("DELETE FROM chat_messages WHERE conversationId = :conversationId")
    suspend fun deleteMessagesForConversation(conversationId: Long)

    @Query("DELETE FROM dual_chat_messages WHERE conversationId = :conversationId")
    suspend fun deleteDualMessagesForConversation(conversationId: Long)

    @Query("DELETE FROM token_usage_records WHERE conversationId = :conversationId")
    suspend fun deleteTokenUsageForConversation(conversationId: Long)

    @Query("DELETE FROM chat_message_variants WHERE baseMessageId IN (SELECT id FROM chat_messages WHERE conversationId = :conversationId)")
    suspend fun deleteVariantsForConversation(conversationId: Long)

    @Transaction
    suspend fun deleteConversationCascade(id: Long) {
        deleteVariantsForConversation(id)
        deleteMessagesForConversation(id)
        deleteDualMessagesForConversation(id)
        deleteTokenUsageForConversation(id)
        deleteConversationById(id)
    }

    @Transaction
    suspend fun deleteProject(id: Long, deleteConversations: Boolean) {
        if (deleteConversations) {
            val conversationIds = getConversationIdsForProject(id)
            conversationIds.forEach { deleteConversationCascade(it) }
        } else {
            clearProjectAssignments(id)
        }
        deleteProjectById(id)
    }

    @Query("SELECT id FROM conversations WHERE projectId = :projectId")
    suspend fun getConversationIdsForProject(projectId: Long): List<Long>

    // ChatMessage queries
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertMessage(message: ChatMessage): Long

    @Update
    suspend fun updateMessage(message: ChatMessage)

    @Query("""
        SELECT 
            id, 
            conversationId, 
            role, 
            timestamp,
            CASE WHEN attachments != '[]' AND attachments IS NOT NULL THEN 1 ELSE 0 END as hasAttachments,
            CASE WHEN thinkingSummary IS NOT NULL THEN 1 ELSE 0 END as hasThinking,
            CASE WHEN LENGTH(resolvedText) > 100 THEN SUBSTR(resolvedText, 1, 100) || '...' ELSE resolvedText END as textPreview,
            selectedVariantIndex,
            1 + variantCount as variantCount
        FROM (
            SELECT
                cm.id as id,
                cm.conversationId as conversationId,
                cm.role as role,
                cm.timestamp as timestamp,
                CASE
                    WHEN cm.role = 'model' AND cm.selectedVariantIndex > 0 THEN COALESCE(
                        (SELECT v.attachments
                         FROM chat_message_variants v
                         WHERE v.baseMessageId = cm.id AND v.variantIndex = cm.selectedVariantIndex
                         LIMIT 1),
                        cm.attachments
                    )
                    ELSE cm.attachments
                END as attachments,
                CASE
                    WHEN cm.role = 'model' AND cm.selectedVariantIndex > 0 THEN (
                        SELECT v.thinkingStream
                        FROM chat_message_variants v
                        WHERE v.baseMessageId = cm.id AND v.variantIndex = cm.selectedVariantIndex
                        LIMIT 1
                    )
                    ELSE cm.thinkingSummary
                END as thinkingSummary,
                CASE
                    WHEN cm.role = 'model' AND cm.selectedVariantIndex > 0 THEN COALESCE(
                        (SELECT v.text
                         FROM chat_message_variants v
                         WHERE v.baseMessageId = cm.id AND v.variantIndex = cm.selectedVariantIndex
                         LIMIT 1),
                        cm.text
                    )
                    ELSE cm.text
                END as resolvedText,
                cm.selectedVariantIndex as selectedVariantIndex,
                (SELECT COUNT(*) FROM chat_message_variants v WHERE v.baseMessageId = cm.id) as variantCount
            FROM chat_messages cm
            WHERE cm.conversationId = :conversationId
        ) AS resolved_messages
        ORDER BY timestamp ASC
    """)
    fun getMessagesForConversation(conversationId: Long): Flow<List<ChatMessageSummary>>

    @Query("""
        SELECT
            id,
            conversationId,
            role,
            timestamp,
            CASE WHEN attachments != '[]' AND attachments IS NOT NULL THEN 1 ELSE 0 END as hasAttachments,
            CASE WHEN thinkingSummary IS NOT NULL THEN 1 ELSE 0 END as hasThinking,
            CASE WHEN LENGTH(resolvedText) > 100 THEN SUBSTR(resolvedText, 1, 100) || '...' ELSE resolvedText END as textPreview,
            selectedVariantIndex,
            1 + variantCount as variantCount
        FROM (
            SELECT
                cm.id as id,
                cm.conversationId as conversationId,
                cm.role as role,
                cm.timestamp as timestamp,
                CASE
                    WHEN cm.role = 'model' AND cm.selectedVariantIndex > 0 THEN (
                        SELECT v.attachments
                        FROM chat_message_variants v
                        WHERE v.baseMessageId = cm.id AND v.variantIndex = cm.selectedVariantIndex
                        LIMIT 1
                    )
                    ELSE cm.attachments
                END as attachments,
                CASE
                    WHEN cm.role = 'model' AND cm.selectedVariantIndex > 0 THEN (
                        SELECT v.thinkingStream
                        FROM chat_message_variants v
                        WHERE v.baseMessageId = cm.id AND v.variantIndex = cm.selectedVariantIndex
                        LIMIT 1
                    )
                    ELSE cm.thinkingSummary
                END as thinkingSummary,
                CASE
                    WHEN cm.role = 'model' AND cm.selectedVariantIndex > 0 THEN (
                        SELECT v.text
                        FROM chat_message_variants v
                        WHERE v.baseMessageId = cm.id AND v.variantIndex = cm.selectedVariantIndex
                        LIMIT 1
                    )
                    ELSE cm.text
                END as resolvedText,
                cm.selectedVariantIndex as selectedVariantIndex,
                (SELECT COUNT(*) FROM chat_message_variants v WHERE v.baseMessageId = cm.id) as variantCount
            FROM chat_messages cm
            WHERE cm.id = :messageId
        ) AS resolved_message
        ORDER BY timestamp ASC
    """)
    suspend fun getMessageSummaryById(messageId: Long): ChatMessageSummary?

    @Query("SELECT * FROM chat_messages WHERE id = :id")
    suspend fun getFullMessageById(id: Long): ChatMessage?

    @Query("SELECT * FROM chat_messages WHERE id IN (:ids)")
    suspend fun getFullMessagesByIds(ids: List<Long>): List<ChatMessage>        

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertMessageVariant(variant: ChatMessageVariant): Long

    @Update
    suspend fun updateMessageVariant(variant: ChatMessageVariant)

    @Query("SELECT * FROM chat_message_variants WHERE id = :id")
    suspend fun getMessageVariantById(id: Long): ChatMessageVariant?

    @Query("SELECT * FROM chat_message_variants WHERE baseMessageId = :baseMessageId ORDER BY variantIndex ASC")
    suspend fun getVariantsForMessage(baseMessageId: Long): List<ChatMessageVariant>

    @Query("SELECT * FROM chat_message_variants WHERE baseMessageId IN (:messageIds) ORDER BY baseMessageId ASC, variantIndex ASC")
    suspend fun getVariantsForMessages(messageIds: List<Long>): List<ChatMessageVariant>

    @Query("SELECT COALESCE(MAX(variantIndex), 0) FROM chat_message_variants WHERE baseMessageId = :baseMessageId")
    suspend fun getMaxVariantIndex(baseMessageId: Long): Int

    @Query("UPDATE chat_messages SET selectedVariantIndex = :variantIndex WHERE id = :messageId")
    suspend fun updateMessageSelectedVariantIndex(messageId: Long, variantIndex: Int)

    @Query(
        """
        WITH resolved_chat_messages AS (
            SELECT
                cm.id as id,
                cm.conversationId as conversationId,
                cm.timestamp as timestamp,
                cm.role as role,
                CASE
                    WHEN cm.role = 'model' AND cm.selectedVariantIndex > 0 THEN (
                        SELECT v.text
                        FROM chat_message_variants v
                        WHERE v.baseMessageId = cm.id AND v.variantIndex = cm.selectedVariantIndex
                        LIMIT 1
                    )
                    ELSE cm.text
                END as resolvedText
            FROM chat_messages cm
        )
        SELECT
            c.id as conversationId,
            c.title as conversationTitle,
            'CHAT' as source,
            rcm.id as messageId,
            rcm.timestamp as timestamp,
            rcm.role as role,
            'CHAT' as matchedField,
            CASE
                WHEN LENGTH(rcm.resolvedText) > 120 THEN SUBSTR(rcm.resolvedText, 1, 120) || '...'
                ELSE rcm.resolvedText
            END as snippet
        FROM resolved_chat_messages rcm
        JOIN conversations c ON c.id = rcm.conversationId
        WHERE c.isSecret = 0
          AND (:projectId IS NULL OR c.projectId = :projectId)
          AND rcm.resolvedText LIKE :pattern ESCAPE '\'

        UNION ALL

        SELECT
            c.id as conversationId,
            c.title as conversationTitle,
            'DUAL' as source,
            dcm.id as messageId,
            dcm.timestamp as timestamp,
            dcm.role as role,
            CASE
                WHEN dcm.userText LIKE :pattern ESCAPE '\' THEN 'USER'
                WHEN dcm.modelAText LIKE :pattern ESCAPE '\' THEN 'MODEL_A'
                ELSE 'MODEL_B'
            END as matchedField,
            CASE
                WHEN dcm.userText LIKE :pattern ESCAPE '\' THEN
                    CASE
                        WHEN LENGTH(dcm.userText) > 120 THEN SUBSTR(dcm.userText, 1, 120) || '...'
                        ELSE dcm.userText
                    END
                WHEN dcm.modelAText LIKE :pattern ESCAPE '\' THEN
                    CASE
                        WHEN LENGTH(dcm.modelAText) > 120 THEN SUBSTR(dcm.modelAText, 1, 120) || '...'
                        ELSE dcm.modelAText
                    END
                ELSE
                    CASE
                        WHEN LENGTH(dcm.modelBText) > 120 THEN SUBSTR(dcm.modelBText, 1, 120) || '...'
                        ELSE dcm.modelBText
                    END
            END as snippet
        FROM dual_chat_messages dcm
        JOIN conversations c ON c.id = dcm.conversationId
        WHERE c.isSecret = 0
          AND (:projectId IS NULL OR c.projectId = :projectId)
          AND (
                dcm.userText LIKE :pattern ESCAPE '\'
             OR dcm.modelAText LIKE :pattern ESCAPE '\'
             OR dcm.modelBText LIKE :pattern ESCAPE '\'
          )
        ORDER BY timestamp DESC
        LIMIT :limit
        """
    )
    fun searchMessages(pattern: String, projectId: Long?, limit: Int): Flow<List<ConversationSearchResult>>

    // Thinking queries
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertThinking(thinking: ChatMessageThinking)

    @Query("SELECT * FROM chat_message_thinking WHERE messageId = :messageId")
    suspend fun getThinkingByMessageId(messageId: Long): ChatMessageThinking?

    @Query("SELECT * FROM chat_message_thinking WHERE messageId IN (:messageIds)")
    suspend fun getThinkingByMessageIds(messageIds: List<Long>): List<ChatMessageThinking>

    // Tool activity queries
    @Insert
    suspend fun insertToolActivity(activity: ChatMessageToolActivity): Long

    @Query("SELECT * FROM chat_message_tool_activity WHERE messageId = :messageId AND variantId IS NULL LIMIT 1")
    suspend fun getToolActivityForMessage(messageId: Long): ChatMessageToolActivity?

    @Query("SELECT * FROM chat_message_tool_activity WHERE messageId IN (:messageIds) AND variantId IS NULL")
    suspend fun getToolActivitiesForMessages(messageIds: List<Long>): List<ChatMessageToolActivity>

    @Query("SELECT * FROM chat_message_tool_activity WHERE variantId = :variantId LIMIT 1")
    suspend fun getToolActivityForVariant(variantId: Long): ChatMessageToolActivity?

    @Query("SELECT * FROM chat_message_tool_activity WHERE variantId IN (:variantIds)")
    suspend fun getToolActivitiesForVariants(variantIds: List<Long>): List<ChatMessageToolActivity>

    @Query("DELETE FROM chat_message_tool_activity WHERE messageId = :messageId")
    suspend fun deleteToolActivityForMessage(messageId: Long)

    @Query("DELETE FROM chat_message_tool_activity WHERE variantId = :variantId")
    suspend fun deleteToolActivityForVariant(variantId: Long)

    // Fusion trace queries
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertFusionTrace(record: FusionTraceRecord)

    @Query("SELECT * FROM fusion_traces WHERE id = :id")
    suspend fun getFusionTrace(id: String): FusionTraceRecord?

    // Settings queries
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun saveSettings(settings: Settings)

    @Query("SELECT * FROM settings WHERE id = 1")
    fun getSettings(): Flow<Settings?>

    // ModelPreset queries
    @Upsert
    suspend fun upsertModelPreset(preset: ModelPreset)

    @Query("SELECT * FROM model_presets ORDER BY name ASC")
    fun getAllModelPresets(): Flow<List<ModelPreset>>

    @Query("DELETE FROM model_presets WHERE id = :id")
    suspend fun deleteModelPresetById(id: Long)

    // DualChatMessage queries
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertDualMessage(message: DualChatMessage): Long

    @Update
    suspend fun updateDualMessage(message: DualChatMessage)

    @Query("SELECT * FROM dual_chat_messages WHERE conversationId = :conversationId ORDER BY timestamp ASC")
    fun getDualMessagesForConversation(conversationId: Long): Flow<List<DualChatMessage>>

    @Query("SELECT * FROM dual_chat_messages WHERE id = :id")
    suspend fun getDualMessageById(id: Long): DualChatMessage?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertTokenUsage(record: TokenUsageRecord)

    @Query(
        """
        SELECT
            COUNT(*) as requestCount,
            COALESCE(SUM(inputTokens), 0) as inputTokens,
            COALESCE(SUM(outputTokens), 0) as outputTokens,
            COALESCE(SUM(totalTokens), 0) as totalTokens,
            COALESCE(SUM(costUsd), 0.0) as totalCostUsd
        FROM token_usage_records
        WHERE timestamp >= :sinceEpochMs
        """
    )
    fun observeTokenUsageTotals(sinceEpochMs: Long): Flow<TokenUsageTotals>

    @Query(
        """
        SELECT
            model as model,
            COUNT(*) as requestCount,
            COALESCE(SUM(inputTokens), 0) as inputTokens,
            COALESCE(SUM(outputTokens), 0) as outputTokens,
            COALESCE(SUM(totalTokens), 0) as totalTokens,
            COALESCE(SUM(costUsd), 0.0) as totalCostUsd
        FROM token_usage_records
        WHERE timestamp >= :sinceEpochMs
        GROUP BY model
        ORDER BY totalTokens DESC, requestCount DESC, model ASC
        LIMIT :limit
        """
    )
    fun observeTokenUsageByModel(sinceEpochMs: Long, limit: Int): Flow<List<TokenUsageByModel>>

    @Query(
        """
        SELECT
            ((timestamp / 86400000) * 86400000) as dayBucketStartMs,
            COUNT(*) as requestCount,
            COALESCE(SUM(totalTokens), 0) as totalTokens,
            COALESCE(SUM(costUsd), 0.0) as totalCostUsd
        FROM token_usage_records
        WHERE timestamp >= :sinceEpochMs
        GROUP BY dayBucketStartMs
        ORDER BY dayBucketStartMs ASC
        """
    )
    fun observeTokenUsageDaily(sinceEpochMs: Long): Flow<List<TokenUsageDailyPoint>>
    
    // AutoConversation queries
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertAutoConversation(conversation: AutoConversation): Long
    
    @Update
    suspend fun updateAutoConversation(conversation: AutoConversation)
    
    @Query("SELECT * FROM auto_conversations ORDER BY lastActiveAt DESC")
    fun getAllAutoConversations(): Flow<List<AutoConversation>>
    
    @Query("SELECT * FROM auto_conversations WHERE id = :id")
    suspend fun getAutoConversationById(id: Long): AutoConversation?
    
    @Query("DELETE FROM auto_conversations WHERE id = :id")
    suspend fun deleteAutoConversationById(id: Long)
    
    // AutoConversationMessage queries
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertAutoConversationMessage(message: AutoConversationMessage): Long
    
    @Query("SELECT * FROM auto_conversation_messages WHERE autoConversationId = :conversationId ORDER BY turnNumber ASC")
    fun getAutoConversationMessages(conversationId: Long): Flow<List<AutoConversationMessage>>
    
    @Query("SELECT * FROM auto_conversation_messages WHERE autoConversationId = :conversationId ORDER BY turnNumber DESC LIMIT 1")
    suspend fun getLastAutoConversationMessage(conversationId: Long): AutoConversationMessage?
    
    @Query("DELETE FROM auto_conversation_messages WHERE autoConversationId = :conversationId")
    suspend fun deleteAutoConversationMessages(conversationId: Long)

    @Query(
        """
        DELETE FROM chat_message_thinking
        WHERE messageId IN (
            SELECT id FROM chat_messages
            WHERE conversationId IN (SELECT id FROM conversations WHERE isSecret = 1)
        )
        """
    )
    suspend fun deleteThinkingForSecretConversations()

    @Query(
        """
        DELETE FROM chat_message_variants
        WHERE baseMessageId IN (
            SELECT id FROM chat_messages
            WHERE conversationId IN (SELECT id FROM conversations WHERE isSecret = 1)
        )
        """
    )
    suspend fun deleteVariantsForSecretConversations()

    @Query("DELETE FROM chat_messages WHERE conversationId IN (SELECT id FROM conversations WHERE isSecret = 1)")
    suspend fun deleteChatMessagesForSecretConversations()

    @Query("DELETE FROM dual_chat_messages WHERE conversationId IN (SELECT id FROM conversations WHERE isSecret = 1)")
    suspend fun deleteDualMessagesForSecretConversations()

    @Query("DELETE FROM token_usage_records WHERE conversationId IN (SELECT id FROM conversations WHERE isSecret = 1)")
    suspend fun deleteTokenUsageForSecretConversations()

    @Query(
        """
        DELETE FROM auto_conversation_messages
        WHERE autoConversationId IN (
            SELECT id FROM auto_conversations
            WHERE boundChatConversationId IN (SELECT id FROM conversations WHERE isSecret = 1)
        )
        """
    )
    suspend fun deleteAutoConversationMessagesForSecretConversations()

    @Query("DELETE FROM auto_conversations WHERE boundChatConversationId IN (SELECT id FROM conversations WHERE isSecret = 1)")
    suspend fun deleteAutoConversationsForSecretConversations()

    @Query("DELETE FROM conversations WHERE isSecret = 1")
    suspend fun deleteSecretConversations()

    @Transaction
    suspend fun purgeSecretConversations() {
        deleteVariantsForSecretConversations()
        deleteThinkingForSecretConversations()
        deleteChatMessagesForSecretConversations()
        deleteDualMessagesForSecretConversations()
        deleteTokenUsageForSecretConversations()
        deleteAutoConversationMessagesForSecretConversations()
        deleteAutoConversationsForSecretConversations()
        deleteSecretConversations()
    }
}

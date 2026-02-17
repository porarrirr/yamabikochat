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

    @Query(
        """
        SELECT
            c.id as conversationId,
            c.title as title,
            c.timestamp as timestamp,
            c.apiProvider as apiProvider,
            c.model as model,
            (SELECT MAX(timestamp) FROM chat_messages WHERE conversationId = c.id) as lastChatTimestamp,
            (SELECT CASE
                WHEN LENGTH(text) > 120 THEN SUBSTR(text, 1, 120) || '...'
                ELSE text
            END
            FROM chat_messages
            WHERE conversationId = c.id
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
        WHERE c.isSecret = 0
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
          AND NOT EXISTS (SELECT 1 FROM chat_messages cm WHERE cm.conversationId = c.id)
          AND NOT EXISTS (SELECT 1 FROM dual_chat_messages dcm WHERE dcm.conversationId = c.id)
        ORDER BY c.timestamp DESC
        LIMIT 1
        """
    )
    suspend fun findLatestEmptyConversationByTitle(title: String): Conversation?

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

    @Transaction
    suspend fun deleteConversationCascade(id: Long) {
        deleteMessagesForConversation(id)
        deleteDualMessagesForConversation(id)
        deleteTokenUsageForConversation(id)
        deleteConversationById(id)
    }

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
            CASE WHEN LENGTH(text) > 100 THEN SUBSTR(text, 1, 100) || '...' ELSE text END as textPreview
        FROM chat_messages 
        WHERE conversationId = :conversationId 
        ORDER BY timestamp ASC
    """)
    fun getMessagesForConversation(conversationId: Long): Flow<List<ChatMessageSummary>>

    @Query("SELECT * FROM chat_messages WHERE id = :id")
    suspend fun getFullMessageById(id: Long): ChatMessage?

    @Query("SELECT * FROM chat_messages WHERE id IN (:ids)")
    suspend fun getFullMessagesByIds(ids: List<Long>): List<ChatMessage>        

    @Query(
        """
        SELECT
            c.id as conversationId,
            c.title as conversationTitle,
            'CHAT' as source,
            cm.id as messageId,
            cm.timestamp as timestamp,
            cm.role as role,
            'CHAT' as matchedField,
            CASE
                WHEN LENGTH(cm.text) > 120 THEN SUBSTR(cm.text, 1, 120) || '...'
                ELSE cm.text
            END as snippet
        FROM chat_messages cm
        JOIN conversations c ON c.id = cm.conversationId
        WHERE c.isSecret = 0
          AND cm.text LIKE :pattern ESCAPE '\'

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
          AND (
                dcm.userText LIKE :pattern ESCAPE '\'
             OR dcm.modelAText LIKE :pattern ESCAPE '\'
             OR dcm.modelBText LIKE :pattern ESCAPE '\'
          )
        ORDER BY timestamp DESC
        LIMIT :limit
        """
    )
    fun searchMessages(pattern: String, limit: Int): Flow<List<ConversationSearchResult>>

    // Thinking queries
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertThinking(thinking: ChatMessageThinking)

    @Query("SELECT * FROM chat_message_thinking WHERE messageId = :messageId")
    suspend fun getThinkingByMessageId(messageId: Long): ChatMessageThinking?

    @Query("SELECT * FROM chat_message_thinking WHERE messageId IN (:messageIds)")
    suspend fun getThinkingByMessageIds(messageIds: List<Long>): List<ChatMessageThinking>

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
        deleteThinkingForSecretConversations()
        deleteChatMessagesForSecretConversations()
        deleteDualMessagesForSecretConversations()
        deleteTokenUsageForSecretConversations()
        deleteAutoConversationMessagesForSecretConversations()
        deleteAutoConversationsForSecretConversations()
        deleteSecretConversations()
    }
}

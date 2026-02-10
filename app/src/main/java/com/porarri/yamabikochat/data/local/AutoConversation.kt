package com.porarri.yamabikochat.data.local

import androidx.room.Entity
import androidx.room.PrimaryKey

@Entity(tableName = "auto_conversations")
data class AutoConversation(
    @PrimaryKey(autoGenerate = true)
    val id: Long = 0,
    val title: String,
    val modelA: String,
    val modelB: String,
    val providerA: String,
    val providerB: String,
    val systemPromptA: String,
    val systemPromptB: String,
    val status: AutoConversationStatus,
    val maxTurns: Int = 20, // デフォルトは20ターン
    val currentTurn: Int = 0,
    val createdAt: Long = System.currentTimeMillis(),
    val lastActiveAt: Long = System.currentTimeMillis(),
    val endReason: String? = null,
    val endSignal: String = "[END]",
    val boundChatConversationId: Long? = null
)

enum class AutoConversationStatus {
    ACTIVE,    // 進行中
    PAUSED,    // 一時停止
    ENDED      // 終了
}

@Entity(tableName = "auto_conversation_messages")
data class AutoConversationMessage(
    @PrimaryKey(autoGenerate = true)
    val id: Long = 0,
    val autoConversationId: Long,
    val turnNumber: Int,
    val speakerModel: String, // "A" or "B"
    val content: String,
    val reasoning: String? = null,
    val timestamp: Long = System.currentTimeMillis(),
    val isEndSignal: Boolean = false // 終了シグナルが含まれているか
)

// 会話の設定情報をまとめたデータクラス
data class AutoConversationConfig(
    val title: String,
    val modelA: String,
    val modelB: String,
    val providerA: String,
    val providerB: String,
    val systemPromptA: String,
    val systemPromptB: String,
    val maxTurns: Int = 20,
    val endSignal: String = "[END]" // 終了シグナルのキーワード
)

// 会話の詳細情報（メッセージ付き）
data class FullAutoConversation(
    val conversation: AutoConversation,
    val messages: List<AutoConversationMessage>
)

// 終了理由の定数
object AutoConversationEndReason {
    const val USER_STOP = "USER_STOP"           // ユーザーが手動停止
    const val MAX_TURNS = "MAX_TURNS"           // 最大ターン数到達
    const val END_SIGNAL = "END_SIGNAL"         // 終了シグナル検出
    const val ERROR = "ERROR"                   // エラーによる停止
    const val TIMEOUT = "TIMEOUT"               // タイムアウト
    const val API_ERROR = "API_ERROR"           // API エラー
}
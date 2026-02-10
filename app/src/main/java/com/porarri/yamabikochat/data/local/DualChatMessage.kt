package com.porarri.yamabikochat.data.local

import androidx.room.Entity
import androidx.room.PrimaryKey

@Entity(tableName = "dual_chat_messages")
data class DualChatMessage(
    @PrimaryKey(autoGenerate = true)
    val id: Long = 0,
    val conversationId: Long,
    val role: String, // "user" or "dual_model"
    val userText: String = "", // ユーザーの入力テキスト
    val modelAText: String = "", // モデルAの応答
    val modelBText: String = "", // モデルBの応答
    val modelAName: String = "", // 使用されたモデルA名
    val modelBName: String = "", // 使用されたモデルB名
    val modelAProvider: String = "", // モデルAのプロバイダー
    val modelBProvider: String = "", // モデルBのプロバイダー
    val timestamp: Long = System.currentTimeMillis(),
    val modelAThinking: String? = null, // モデルAのthinking
    val modelBThinking: String? = null, // モデルBのthinking
    val attachments: List<String> = emptyList() // ファイル添付のパス
)

data class DualChatSettings(
    val isDualModeEnabled: Boolean = false,
    val modelA: String = "gemini-2.5-flash",
    val modelB: String = "deepseek/deepseek-chat",
    val providerA: String = "GEMINI",
    val providerB: String = "OPENROUTER",
    val splitLayout: SplitLayoutType = SplitLayoutType.VERTICAL, // 左右分割
    val splitRatio: Float = 0.5f, // 分割比率 (0.1 - 0.9)
    val showBothResponses: Boolean = true
)

enum class SplitLayoutType {
    VERTICAL,   // 左右分割 (|)
    HORIZONTAL  // 上下分割 (-)
}

data class FullDualChatMessage(
    val dualMessage: DualChatMessage,
    val modelAThinkingStream: String? = null,
    val modelBThinkingStream: String? = null
)

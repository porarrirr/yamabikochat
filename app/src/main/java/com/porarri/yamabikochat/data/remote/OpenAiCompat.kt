package com.porarri.yamabikochat.data.remote

import kotlinx.serialization.Serializable
import com.google.gson.annotations.SerializedName
import java.net.URI

@Serializable
data class OpenAiCompatPreset(
    val name: String,
    @SerializedName(value = "baseUrl", alternate = ["baseURL"]) val baseUrl: String,
    val protocol: String = "",
    val modelId: String = "",
    val contextWindow: Int = 128000,
    val maxTokens: Int = 8192,
    val reasoning: Boolean = false,
    val toolCall: Boolean = false,
    val vision: Boolean = false,
    val reasoningEffort: String = "off",
    val thinkingBudget: Int? = null,
    val temperature: Double? = null,
    val maxTokensField: String = "max_completion_tokens",
    val supportsStore: Boolean = false,
    val supportsDeveloperRole: Boolean = false,
    val supportsUsageInStreaming: Boolean = true
) {
    fun validationError(): String? {
        if (name.isBlank()) return "プリセット名を入力してください"
        if (protocol !in listOf("anthropic-messages", "openai-completions", "openai-responses")) return "APIプロトコルを選択してください"
        val url = runCatching { URI(baseUrl) }.getOrNull()
        if (url == null || url.scheme !in listOf("http", "https") || url.host == null || url.userInfo != null || url.query != null || url.fragment != null) return "有効なBase URLを入力してください"
        if (modelId.isBlank()) return "モデルIDを入力してください"
        if (contextWindow <= 0 || maxTokens <= 0 || maxTokens > contextWindow) return "トークン上限を確認してください"
        if (reasoningEffort !in listOf("off", "minimal", "low", "medium", "high", "xhigh", "max") || (!reasoning && reasoningEffort != "off")) return "reasoning設定を確認してください"
        if (thinkingBudget != null && (protocol != "anthropic-messages" || !reasoning || reasoningEffort == "off" || thinkingBudget < 1024 || thinkingBudget >= maxTokens)) return "Thinking budgetはAnthropicのreasoning有効時に1024以上、出力上限未満を指定してください"
        if (temperature != null && (!temperature.isFinite() || temperature !in 0.0..2.0)) return "temperatureは0〜2を指定してください"
        return null
    }
}

package com.porarri.yamabikochat.data.model

enum class LLMProvider(val rawValue: String) {
    GEMINI("GEMINI"),
    OPENROUTER("OPENROUTER"),
    OPENCODE_GO("OPENCODE_GO"),
    CLINEPASS("CLINEPASS"),
    ALIBABA_CODING_PLAN("ALIBABA_CODING_PLAN"),
    OPENAI("OPENAI"),
    OPENAI_COMPAT("OPENAI_COMPAT"),
    MINIMAX("MINIMAX"),
    CODEX_AUTH("CODEX_AUTH"),
    SUPERGROK("SUPERGROK"),
    ZAI("ZAI"),
    APPLE_INTELLIGENCE("APPLE_INTELLIGENCE");

    val supportsClientWebSearchTool: Boolean
        get() = this != APPLE_INTELLIGENCE

    companion object {
        fun fromRawOrDefault(value: String): LLMProvider {
            return when (value.trim().uppercase()) {
                "GEMINI_AUTH" -> GEMINI
                "QWEN_CODE" -> OPENROUTER
                else -> entries.firstOrNull { it.rawValue == value.trim().uppercase() } ?: GEMINI
            }
        }

        fun fromRawOrNull(value: String): LLMProvider? {
            return when (value.trim().uppercase()) {
                "GEMINI_AUTH" -> GEMINI
                "QWEN_CODE" -> OPENROUTER
                else -> entries.firstOrNull { it.rawValue == value.trim().uppercase() }
            }
        }
    }
}

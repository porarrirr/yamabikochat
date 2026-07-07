package com.porarri.yamabikochat.data.remote

data class ProviderDisplay(
    val key: String,
    val title: String
)

object ProviderCatalog {
    const val GEMINI = "GEMINI"
    const val OPENROUTER = "OPENROUTER"
    const val OPENCODE_GO = "OPENCODE_GO"
    const val CLINEPASS = "CLINEPASS"
    const val ALIBABA_CODING_PLAN = "ALIBABA_CODING_PLAN"
    const val ZAI = "ZAI"
    const val MINIMAX = "MINIMAX"
    const val OPENAI = "OPENAI"
    const val CODEX_AUTH = "CODEX_AUTH"
    const val OPENAI_COMPAT = "OPENAI_COMPAT"

    const val defaultOpenAiBaseUrl = "https://api.openai.com/v1/"
    const val defaultMiniMaxBaseUrl = "https://api.minimax.io/v1/"
    const val defaultOpenCodeGoBaseUrl = "https://opencode.ai/zen/go/v1/"
    const val defaultClinePassBaseUrl = "https://api.cline.bot/api/v1/"
    const val defaultAlibabaCodingPlanBaseUrl = "https://coding-intl.dashscope.aliyuncs.com/apps/anthropic/v1/"
    const val alibabaMcpDefaultServerName = "firecrawl"
    const val firecrawlRemoteMcpUrlTemplate = "https://mcp.firecrawl.dev/fc-YOUR_API_KEY/v2/mcp"

    val options = listOf(
        ProviderDisplay(GEMINI, "Google Gemini"),
        ProviderDisplay(OPENROUTER, "OpenRouter"),
        ProviderDisplay(OPENCODE_GO, "OpenCode Go"),
        ProviderDisplay(CLINEPASS, "Cline Pass"),
        ProviderDisplay(ALIBABA_CODING_PLAN, "Alibaba Coding Plan"),
        ProviderDisplay(ZAI, "Z.ai"),
        ProviderDisplay(MINIMAX, "MiniMax"),
        ProviderDisplay(OPENAI, "OpenAI"),
        ProviderDisplay(CODEX_AUTH, "Codex Auth"),
        ProviderDisplay(OPENAI_COMPAT, "OpenAI (Custom)")
    )

    val dualAutoConversationOptions: List<ProviderDisplay> = options

    fun displayName(provider: String?): String {
        val normalized = provider?.uppercase().orEmpty()
        return options.firstOrNull { it.key == normalized }?.title ?: provider.orEmpty()
    }

    fun defaultModel(provider: String): String = when (provider.uppercase()) {
        GEMINI -> "gemini-2.5-flash"
        OPENCODE_GO -> OpenCodeGoModelCatalog.defaultModel
        CLINEPASS -> ClinePassModelCatalog.defaultModel
        ALIBABA_CODING_PLAN -> AlibabaCodingPlanModelCatalog.defaultModel
        ZAI -> "glm-4.6"
        MINIMAX -> "MiniMax-M2.1"
        OPENAI -> "gpt-4.1-mini"
        CODEX_AUTH -> com.porarri.yamabikochat.utils.CodexModelPresets.defaultModel()
        OPENAI_COMPAT -> ""
        OPENROUTER -> "deepseek/deepseek-chat"
        else -> ""
    }

    fun remapRemovedProvider(provider: String): String = when (provider.uppercase()) {
        "GEMINI_AUTH" -> GEMINI
        "QWEN_CODE" -> OPENROUTER
        else -> provider.uppercase()
    }
}

enum class OpenCodeGoEndpointKind {
    CHAT_COMPLETIONS,
    MESSAGES
}

data class OpenCodeGoModel(
    val id: String,
    val displayName: String,
    val endpointKind: OpenCodeGoEndpointKind
)

object OpenCodeGoModelCatalog {
    const val defaultModel = "glm-5.1"

    val supportedModels = listOf(
        OpenCodeGoModel("glm-5.2", "GLM-5.2", OpenCodeGoEndpointKind.CHAT_COMPLETIONS),
        OpenCodeGoModel("glm-5.1", "GLM-5.1", OpenCodeGoEndpointKind.CHAT_COMPLETIONS),
        OpenCodeGoModel("kimi-k2.7-code", "Kimi K2.7 Code", OpenCodeGoEndpointKind.CHAT_COMPLETIONS),
        OpenCodeGoModel("kimi-k2.6", "Kimi K2.6", OpenCodeGoEndpointKind.CHAT_COMPLETIONS),
        OpenCodeGoModel("deepseek-v4-pro", "DeepSeek V4 Pro", OpenCodeGoEndpointKind.CHAT_COMPLETIONS),
        OpenCodeGoModel("deepseek-v4-flash", "DeepSeek V4 Flash", OpenCodeGoEndpointKind.CHAT_COMPLETIONS),
        OpenCodeGoModel("mimo-v2.5-pro", "MiMo-V2.5-Pro", OpenCodeGoEndpointKind.CHAT_COMPLETIONS),
        OpenCodeGoModel("mimo-v2.5", "MiMo-V2.5", OpenCodeGoEndpointKind.CHAT_COMPLETIONS),
        OpenCodeGoModel("qwen3.7-max", "Qwen3.7 Max", OpenCodeGoEndpointKind.MESSAGES),
        OpenCodeGoModel("qwen3.7-plus", "Qwen3.7 Plus", OpenCodeGoEndpointKind.MESSAGES),
        OpenCodeGoModel("qwen3.6-plus", "Qwen3.6 Plus", OpenCodeGoEndpointKind.MESSAGES),
        OpenCodeGoModel("minimax-m3", "MiniMax M3", OpenCodeGoEndpointKind.MESSAGES),
        OpenCodeGoModel("minimax-m2.7", "MiniMax M2.7", OpenCodeGoEndpointKind.MESSAGES)
    )

    fun normalizedModelId(raw: String): String {
        val trimmed = raw.trim()
        return if (trimmed.startsWith("opencode-go/", ignoreCase = true)) {
            trimmed.drop("opencode-go/".length)
        } else {
            trimmed
        }
    }

    fun modelFor(raw: String): OpenCodeGoModel? {
        val normalized = normalizedModelId(raw).lowercase()
        return supportedModels.firstOrNull { it.id.lowercase() == normalized }
    }
}

data class ClinePassModel(
    val id: String,
    val displayName: String
)

object ClinePassModelCatalog {
    const val defaultModel = "cline-pass/glm-5.2"

    val supportedModels = listOf(
        ClinePassModel("cline-pass/glm-5.2", "GLM 5.2"),
        ClinePassModel("cline-pass/kimi-k2.7-code", "Kimi K2.7 Code"),
        ClinePassModel("cline-pass/kimi-k2.6", "Kimi K2.6"),
        ClinePassModel("cline-pass/deepseek-v4-pro", "DeepSeek V4 Pro"),
        ClinePassModel("cline-pass/deepseek-v4-flash", "DeepSeek V4 Flash"),
        ClinePassModel("cline-pass/mimo-v2.5", "MiMo V2.5"),
        ClinePassModel("cline-pass/mimo-v2.5-pro", "MiMo V2.5 Pro"),
        ClinePassModel("cline-pass/minimax-m3", "MiniMax M3"),
        ClinePassModel("cline-pass/qwen3.7-max", "Qwen3.7 Max"),
        ClinePassModel("cline-pass/qwen3.7-plus", "Qwen3.7 Plus")
    )

    fun normalizedModelId(raw: String): String {
        val trimmed = raw.trim()
        return if (trimmed.startsWith("cline-pass/", ignoreCase = true)) {
            trimmed
        } else if (trimmed.isNotEmpty()) {
            "cline-pass/$trimmed"
        } else {
            trimmed
        }
    }

    fun modelFor(raw: String): ClinePassModel? {
        val normalized = normalizedModelId(raw).lowercase()
        return supportedModels.firstOrNull { it.id.lowercase() == normalized }
    }
}

object AlibabaCodingPlanModelCatalog {
    const val defaultModel = "qwen3.5-plus"

    val supportedModels = listOf(
        "qwen3.5-plus",
        "kimi-k2.5",
        "glm-5",
        "MiniMax-M2.5",
        "qwen3-max-2026-01-23",
        "qwen3-coder-next",
        "qwen3-coder-plus",
        "glm-4.7"
    )
}

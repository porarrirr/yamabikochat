package com.porarri.yamabikochat.data.remote

data class ProviderDisplay(
    val key: String,
    val title: String
)

object ProviderCatalog {
    const val GEMINI = "GEMINI"
    const val OPENROUTER = "OPENROUTER"
    const val OPENCODE_GO = "OPENCODE_GO"
    const val SUPERGROK = "SUPERGROK"
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
    const val defaultSuperGrokBaseUrl = "https://api.x.ai/v1/"
    const val defaultClinePassBaseUrl = "https://api.cline.bot/api/v1/"
    const val defaultAlibabaCodingPlanBaseUrl = "https://coding-intl.dashscope.aliyuncs.com/apps/anthropic/v1/"
    const val defaultZaiCodingPlanBaseUrl = "https://api.z.ai/api/coding/paas/v4/"
    const val alibabaMcpDefaultServerName = "firecrawl"
    const val firecrawlRemoteMcpUrlTemplate = "https://mcp.firecrawl.dev/fc-YOUR_API_KEY/v2/mcp"

    val options = listOf(
        ProviderDisplay(GEMINI, "Google Gemini"),
        ProviderDisplay(OPENROUTER, "OpenRouter"),
        ProviderDisplay(OPENCODE_GO, "OpenCode Go"),
        ProviderDisplay(SUPERGROK, "SuperGrok"),
        ProviderDisplay(CLINEPASS, "Cline Pass"),
        ProviderDisplay(ALIBABA_CODING_PLAN, "Alibaba Coding Plan"),
        ProviderDisplay(ZAI, "Z.ai Coding Plan"),
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
        SUPERGROK -> SuperGrokModelCatalog.defaultModel
        CLINEPASS -> ClinePassModelCatalog.defaultModel
        ALIBABA_CODING_PLAN -> AlibabaCodingPlanModelCatalog.defaultModel
        ZAI -> ZaiCodingPlanModelCatalog.defaultModel
        MINIMAX -> "MiniMax-M2.1"
        OPENAI -> "gpt-4.1-mini"
        CODEX_AUTH -> com.porarri.yamabikochat.utils.CodexModelPresets.defaultModel()
        OPENAI_COMPAT -> ""
        OPENROUTER -> "deepseek/deepseek-chat"
        else -> ""
    }

    fun constrainedModelIds(provider: String): List<String>? = when (provider.uppercase()) {
        OPENCODE_GO -> OpenCodeGoModelCatalog.supportedModels.map { it.id }
        CLINEPASS -> ClinePassModelCatalog.supportedModels.map { it.id }
        ALIBABA_CODING_PLAN -> AlibabaCodingPlanModelCatalog.supportedModels
        ZAI -> ZaiCodingPlanModelCatalog.supportedModels
        else -> null
    }

    fun migrateLegacyModelId(provider: String, model: String): String =
        when {
            provider.equals(ZAI, ignoreCase = true) -> ZaiCodingPlanModelCatalog.migrateLegacyModel(model)
            provider.equals(OPENCODE_GO, ignoreCase = true) -> OpenCodeGoModelCatalog.normalizedModelId(model)
            else -> model
        }

    fun remapRemovedProvider(provider: String): String = when (provider.uppercase()) {
        "GEMINI_AUTH" -> GEMINI
        "QWEN_CODE" -> OPENROUTER
        else -> provider.uppercase()
    }
}

enum class OpenCodeGoEndpointKind(val piApi: String) {
    CHAT_COMPLETIONS("openai-completions"),
    RESPONSES("openai-responses"),
    MESSAGES("anthropic-messages")
}

data class OpenCodeGoModel(
    val id: String,
    val displayName: String,
    val endpointKind: OpenCodeGoEndpointKind
)

data class SuperGrokModel(
    val id: String,
    val displayName: String,
    val supportsVision: Boolean,
    val supportsReasoning: Boolean,
    val description: String
)

object SuperGrokModelCatalog {
    const val defaultModel = "grok-4.5"

    val supportedModels = listOf(
        SuperGrokModel(
            id = "grok-build-0.1",
            displayName = "Grok Build 0.1",
            supportsVision = false,
            supportsReasoning = true,
            description = "xAI Grok Build coding model for SuperGrok OAuth."
        ),
        SuperGrokModel(
            id = "grok-4.5",
            displayName = "Grok 4.5",
            supportsVision = true,
            supportsReasoning = true,
            description = "Flagship Grok for code, chat, and agentic tool calling."
        ),
        SuperGrokModel(
            id = "grok-4.3",
            displayName = "Grok 4.3",
            supportsVision = true,
            supportsReasoning = true,
            description = "General-purpose Grok model."
        ),
        SuperGrokModel(
            id = "grok-4.20-0309-reasoning",
            displayName = "Grok 4.20 Reasoning",
            supportsVision = true,
            supportsReasoning = true,
            description = "Reasoning-heavy Grok variant."
        ),
        SuperGrokModel(
            id = "grok-4.20-0309-non-reasoning",
            displayName = "Grok 4.20 Non-Reasoning",
            supportsVision = true,
            supportsReasoning = false,
            description = "Faster non-reasoning Grok variant."
        ),
        SuperGrokModel(
            id = "grok-4.20-multi-agent-0309",
            displayName = "Grok 4.20 Multi-Agent",
            supportsVision = true,
            supportsReasoning = true,
            description = "Multi-agent oriented Grok variant."
        )
    )

    fun normalizedModelId(raw: String): String {
        val trimmed = raw.trim()
        val lower = trimmed.lowercase()
        return when {
            lower.startsWith("supergrok/") -> trimmed.drop("supergrok/".length)
            lower.startsWith("xai/") -> trimmed.drop("xai/".length)
            else -> trimmed
        }
    }

    fun modelFor(raw: String): SuperGrokModel? {
        val normalized = normalizedModelId(raw).lowercase()
        return supportedModels.firstOrNull { it.id.lowercase() == normalized }
    }
}

object OpenCodeGoModelCatalog {
    const val defaultModel = "glm-5.1"

    val supportedModels = listOf(
        OpenCodeGoModel("gpt-5.6-luna", "GPT-5.6 Luna", OpenCodeGoEndpointKind.RESPONSES),
        OpenCodeGoModel("glm-5.3", "GLM-5.3", OpenCodeGoEndpointKind.CHAT_COMPLETIONS),
        OpenCodeGoModel("glm-5.2", "GLM-5.2", OpenCodeGoEndpointKind.CHAT_COMPLETIONS),
        OpenCodeGoModel("glm-5.1", "GLM-5.1", OpenCodeGoEndpointKind.CHAT_COMPLETIONS),
        OpenCodeGoModel("grok-4.5", "Grok 4.5", OpenCodeGoEndpointKind.RESPONSES),
        OpenCodeGoModel("kimi-k3", "Kimi K3", OpenCodeGoEndpointKind.CHAT_COMPLETIONS),
        OpenCodeGoModel("kimi-k2.7-code", "Kimi K2.7 Code", OpenCodeGoEndpointKind.CHAT_COMPLETIONS),
        OpenCodeGoModel("kimi-k2.6", "Kimi K2.6", OpenCodeGoEndpointKind.CHAT_COMPLETIONS),
        OpenCodeGoModel("deepseek-v4-pro", "DeepSeek V4 Pro", OpenCodeGoEndpointKind.CHAT_COMPLETIONS),
        OpenCodeGoModel("deepseek-v4-flash", "DeepSeek V4 Flash", OpenCodeGoEndpointKind.CHAT_COMPLETIONS),
        OpenCodeGoModel("deepseek-v4-flash-vision-exp", "DeepSeek V4 Flash Vision Exp", OpenCodeGoEndpointKind.CHAT_COMPLETIONS),
        OpenCodeGoModel("ox-alpha-free", "Ox Alpha Free", OpenCodeGoEndpointKind.CHAT_COMPLETIONS),
        OpenCodeGoModel("mimo-v2.5-pro", "MiMo-V2.5-Pro", OpenCodeGoEndpointKind.CHAT_COMPLETIONS),
        OpenCodeGoModel("mimo-v2.5", "MiMo-V2.5", OpenCodeGoEndpointKind.CHAT_COMPLETIONS),
        OpenCodeGoModel("hy3", "HY 3", OpenCodeGoEndpointKind.CHAT_COMPLETIONS),
        OpenCodeGoModel("qwen3.8-max", "Qwen3.8 Max", OpenCodeGoEndpointKind.MESSAGES),
        OpenCodeGoModel("qwen3.7-max", "Qwen3.7 Max", OpenCodeGoEndpointKind.MESSAGES),
        OpenCodeGoModel("qwen3.7-plus", "Qwen3.7 Plus", OpenCodeGoEndpointKind.MESSAGES),
        OpenCodeGoModel("qwen3.6-plus", "Qwen3.6 Plus", OpenCodeGoEndpointKind.MESSAGES),
        OpenCodeGoModel("minimax-m3", "MiniMax M3", OpenCodeGoEndpointKind.MESSAGES),
        OpenCodeGoModel("minimax-m2.7", "MiniMax M2.7", OpenCodeGoEndpointKind.MESSAGES),
        OpenCodeGoModel("minimax-m2.5", "MiniMax M2.5", OpenCodeGoEndpointKind.MESSAGES),
        OpenCodeGoModel("muse-spark-1.2-contributor", "Muse Spark 1.2 Contributor", OpenCodeGoEndpointKind.RESPONSES)
    )

    fun normalizedModelId(raw: String): String {
        val trimmed = raw.trim()
        if (trimmed.startsWith("opencode-go/", ignoreCase = true)) {
            return normalizedModelId(trimmed.drop("opencode-go/".length))
        }
        return if (trimmed.equals("muse-spark-1.2", ignoreCase = true)) {
            "muse-spark-1.2-contributor"
        } else trimmed
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
        ClinePassModel("cline-pass/kimi-k3", "Kimi K3"),
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
        return if (trimmed.startsWith("cline-pass/", ignoreCase = true) || trimmed.isEmpty()) {
            trimmed
        } else {
            "cline-pass/$trimmed"
        }
    }

    fun modelFor(raw: String): ClinePassModel? {
        val normalized = normalizedModelId(raw).lowercase()
        return supportedModels.firstOrNull { it.id.lowercase() == normalized }
    }
}

object AlibabaCodingPlanModelCatalog {
    const val defaultModel = "qwen3.7-plus"

    val supportedModels = listOf(
        "qwen3.7-plus",
        "qwen3.6-plus",
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

object ZaiCodingPlanModelCatalog {
    const val defaultModel = "glm-5.2"

    val supportedModels = listOf(
        "glm-5.2",
        "glm-5-turbo",
        "glm-4.7"
    )

    fun isSupported(model: String): Boolean = supportedModels.any {
        it.equals(model.trim(), ignoreCase = true)
    }

    fun migrateLegacyModel(model: String): String =
        if (model.trim().equals("glm-5.1", ignoreCase = true)) defaultModel else model
}

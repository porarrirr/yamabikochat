package com.porarri.yamabikochat.data.modelsdev

import kotlinx.serialization.Serializable

const val MODELS_DEV_PROVIDER_PREFIX = "MODELS_DEV:"

@Serializable
data class ProviderReference(
    val persistedId: String
) {
    val modelsDevId: String?
        get() = persistedId
            .takeIf { it.startsWith(MODELS_DEV_PROVIDER_PREFIX, ignoreCase = true) }
            ?.substringAfter(':')
            ?.trim()
            ?.lowercase()
            ?.takeIf { it.isNotEmpty() }

    val isModelsDev: Boolean get() = modelsDevId != null

    companion object {
        fun modelsDev(providerId: String): ProviderReference =
            ProviderReference("$MODELS_DEV_PROVIDER_PREFIX${providerId.trim().lowercase()}")
    }
}

object ModelsDevMergedProvider {
    fun catalogIdFor(persistedId: String): String? = ProviderReference(persistedId).modelsDevId
        ?: mapOf(
            "GEMINI" to "google", "OPENAI" to "openai", "OPENCODE_GO" to "opencode",
            "ALIBABA_CODING_PLAN" to "alibaba-coding-plan", "ZAI" to "zai", "MINIMAX" to "minimax"
        )[persistedId.uppercase()]
}

@Serializable
data class CatalogCost(
    val inputPerMillion: Double? = null,
    val outputPerMillion: Double? = null,
    val reasoningPerMillion: Double? = null,
    val cacheReadPerMillion: Double? = null,
    val cacheWritePerMillion: Double? = null
)

@Serializable
data class CatalogLimits(
    val context: Long? = null,
    val input: Long? = null,
    val output: Long? = null
)

@Serializable
data class CatalogReasoningOption(
    val type: String,
    val values: List<String> = emptyList()
)

@Serializable
data class CatalogModel(
    val id: String,
    val name: String,
    val description: String? = null,
    val family: String? = null,
    val attachment: Boolean = false,
    val reasoning: Boolean = false,
    val reasoningOptions: List<CatalogReasoningOption> = emptyList(),
    val toolCall: Boolean = false,
    val structuredOutput: Boolean = false,
    val temperature: Boolean = true,
    val inputModalities: List<String> = emptyList(),
    val outputModalities: List<String> = emptyList(),
    val releaseDate: String? = null,
    val lastUpdated: String? = null,
    val limits: CatalogLimits = CatalogLimits(),
    val cost: CatalogCost = CatalogCost()
) {
    fun matches(query: String): Boolean {
        val normalized = query.trim().lowercase()
        if (normalized.isEmpty()) return true
        return listOf(id, name, family.orEmpty(), description.orEmpty())
            .any { it.lowercase().contains(normalized) }
    }
}

@Serializable
data class CatalogProvider(
    val id: String,
    val name: String,
    val npm: String,
    val api: String? = null,
    val env: List<String> = emptyList(),
    val documentationUrl: String? = null,
    val models: List<CatalogModel> = emptyList()
) {
    val reference: ProviderReference get() = ProviderReference.modelsDev(id)

    fun matches(query: String): Boolean {
        val normalized = query.trim().lowercase()
        return normalized.isEmpty() || id.lowercase().contains(normalized) || name.lowercase().contains(normalized)
    }
}

enum class ProviderAdapterKind {
    OPEN_AI_COMPATIBLE,
    OPEN_AI,
    ANTHROPIC,
    GEMINI,
    GOOGLE_VERTEX,
    GOOGLE_VERTEX_ANTHROPIC,
    AZURE_OPEN_AI,
    AMAZON_BEDROCK,
    COHERE,
    SAP_AI_CORE,
    GITLAB_DUO,
    VERCEL_AI,
    CLOUDFLARE_AI_GATEWAY,
    PROVIDER_SPECIFIC,
    UNVERIFIED_OPEN_AI_COMPATIBLE
}

data class ProviderExecutionProfile(
    val adapter: ProviderAdapterKind,
    val isVerifiedMapping: Boolean,
    val requiresManualBaseUrl: Boolean
)

object ModelsDevProviderAdapterRegistry {
    private val resolvedBaseUrlProviders = setOf(
        "openai", "anthropic", "xai", "groq", "mistral", "togetherai", "cerebras",
        "deepinfra", "perplexity", "cohere", "vercel", "v0", "venice", "aihubmix",
        "merge-gateway", "azure", "azure-cognitive-services", "cloudflare-ai-gateway"
    )
    private val openAIWirePackages = setOf(
        "@ai-sdk/openai-compatible", "@ai-sdk/openai", "@ai-sdk/xai", "@ai-sdk/groq",
        "@ai-sdk/cerebras", "@ai-sdk/deepinfra", "@ai-sdk/mistral", "@ai-sdk/perplexity",
        "@ai-sdk/togetherai", "venice-ai-sdk-provider", "@qvac/ai-sdk-provider",
        "@aihubmix/ai-sdk-provider", "merge-gateway-ai-sdk-provider"
    )

    fun profile(provider: CatalogProvider): ProviderExecutionProfile {
        val adapter = when (provider.npm) {
            "@ai-sdk/openai-compatible" -> ProviderAdapterKind.OPEN_AI_COMPATIBLE
            "@ai-sdk/openai" -> ProviderAdapterKind.OPEN_AI
            "@ai-sdk/anthropic" -> ProviderAdapterKind.ANTHROPIC
            "@ai-sdk/google" -> ProviderAdapterKind.GEMINI
            "@ai-sdk/google-vertex" -> ProviderAdapterKind.GOOGLE_VERTEX
            "@ai-sdk/google-vertex/anthropic" -> ProviderAdapterKind.GOOGLE_VERTEX_ANTHROPIC
            "@ai-sdk/azure" -> ProviderAdapterKind.AZURE_OPEN_AI
            "@ai-sdk/amazon-bedrock" -> ProviderAdapterKind.AMAZON_BEDROCK
            "@ai-sdk/cohere" -> ProviderAdapterKind.COHERE
            "@jerome-benoit/sap-ai-provider-v2" -> ProviderAdapterKind.SAP_AI_CORE
            "gitlab-ai-provider" -> ProviderAdapterKind.GITLAB_DUO
            "@ai-sdk/gateway", "@ai-sdk/vercel" -> ProviderAdapterKind.VERCEL_AI
            "ai-gateway-provider" -> ProviderAdapterKind.CLOUDFLARE_AI_GATEWAY
            in openAIWirePackages -> ProviderAdapterKind.PROVIDER_SPECIFIC
            else -> ProviderAdapterKind.UNVERIFIED_OPEN_AI_COMPATIBLE
        }
        return ProviderExecutionProfile(
            adapter = adapter,
            isVerifiedMapping = adapter != ProviderAdapterKind.UNVERIFIED_OPEN_AI_COMPATIBLE,
            requiresManualBaseUrl = provider.id !in resolvedBaseUrlProviders &&
                (provider.api.isNullOrBlank() || provider.api.contains("${'$'}{"))
        )
    }
}

enum class CatalogAvailability { IDLE, LOADING, READY, STALE, ERROR }

data class CatalogLoadState(
    val availability: CatalogAvailability = CatalogAvailability.IDLE,
    val providers: List<CatalogProvider> = emptyList(),
    val lastUpdatedEpochMs: Long? = null,
    val error: String? = null
)

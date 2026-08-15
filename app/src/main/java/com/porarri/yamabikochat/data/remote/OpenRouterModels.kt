package com.porarri.yamabikochat.data.remote

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.longOrNull

@Serializable
data class OpenRouterReasoningCapabilities(
    @SerialName("supported_efforts") val supportedEfforts: List<String>? = null,
    val exposesEffortSelection: Boolean = false,
    @SerialName("default_effort") val defaultEffort: String? = null,
    @SerialName("default_enabled") val defaultEnabled: Boolean? = null,
    @SerialName("supports_max_tokens") val supportsMaxTokens: Boolean = false,
    val mandatory: Boolean = false
) {
    val selectableEfforts: List<String>
        get() {
            if (!exposesEffortSelection) return emptyList()
            val source = supportedEfforts ?: GATEWAY_EFFORTS
            val seen = mutableSetOf<String>()
            return source
                .map { it.trim().lowercase() }
                .filter { effort ->
                    if (effort.isEmpty() || !seen.add(effort)) return@filter false
                    !mandatory || effort != "none"
                }
        }

    companion object {
        val GATEWAY_EFFORTS = listOf("max", "xhigh", "high", "medium", "low", "minimal", "none")
    }
}

@Serializable
data class OpenRouterModelsResponse(
    val data: List<OpenRouterModel>
)

@Serializable
data class OpenRouterModel(
    val id: String,
    val name: String,
    val description: String? = null,
    val pricing: ModelPricing,
    @SerialName("context_length") val contextLength: Int? = null,
    val architecture: ModelArchitecture? = null,
    @SerialName("top_provider") val topProvider: ModelProvider? = null,
    val created: Long? = null,
    val reasoning: OpenRouterReasoningCapabilities? = null
)

@Serializable
data class ModelPricing(
    val prompt: String? = null,
    val completion: String? = null,
    val request: String? = null,
    val image: String? = null,
    @SerialName("web_search") val webSearch: String? = null,
    @SerialName("internal_reasoning") val internalReasoning: String? = null
)

@Serializable
data class ModelArchitecture(
    val modality: String? = null,
    val tokenizer: String? = null,
    @SerialName("instruct_type") val instructType: String? = null
)

@Serializable
data class ModelProvider(
    @SerialName("max_completion_tokens") val maxCompletionTokens: Int? = null,
    @SerialName("is_moderated") val isModerated: Boolean? = null,
    @SerialName("supported_parameters") val supportedParameters: List<String>? = null,
    @SerialName("available_providers") val availableProviders: List<String>? = null,
    @SerialName("available_quantizations") val availableQuantizations: List<String>? = null
)

// UIで使用するためのシンプルなモデル情報
data class SimpleModel(
    val id: String,
    val name: String,
    val provider: String,
    val topProvider: String? = null,
    val contextLength: Int,
    // Stored in USD per 1M tokens for UI convenience
    val promptPricePerMillion: Double,
    val completionPricePerMillion: Double,
    val isFree: Boolean = false,
    val availableProviders: List<String> = emptyList(),
    val availableQuantizations: List<String> = emptyList(),
    val reasoning: OpenRouterReasoningCapabilities? = null
) {
    // 後方互換性のため、旧プロパティを維持（単位: USD/1 token）
    val promptPrice: Double
        get() = promptPricePerMillion / 1_000_000.0
    
    val completionPrice: Double
        get() = completionPricePerMillion / 1_000_000.0
    
    companion object {
        fun fromOpenRouterModel(model: OpenRouterModel): SimpleModel {
            // OpenRouter API pricing values are USD per 1 token (strings like "0.0000007")
            fun parsePrice(vararg candidates: String?): Double {
                return candidates
                    .asSequence()
                    .mapNotNull { it?.toDoubleOrNull() }
                    .firstOrNull() ?: 0.0
            }

            val promptPricePerToken = parsePrice(
                model.pricing.prompt,
                model.pricing.completion,
                model.pricing.request
            )
            val completionPricePerToken = parsePrice(
                model.pricing.completion,
                model.pricing.prompt,
                model.pricing.request
            )
            val provider = model.id.split("/").firstOrNull() ?: "unknown"
            // 1Mトークン単位に変換（×1,000,000）
            val promptPricePerMillion = promptPricePerToken * 1_000_000.0
            val completionPricePerMillion = completionPricePerToken * 1_000_000.0
            
            return SimpleModel(
                id = model.id,
                name = model.name,
                provider = provider,
                topProvider = model.topProvider?.availableProviders?.firstOrNull(),
                contextLength = model.contextLength ?: 0,
                promptPricePerMillion = promptPricePerMillion,
                completionPricePerMillion = completionPricePerMillion,
                isFree = promptPricePerToken == 0.0 && completionPricePerToken == 0.0,
                availableProviders = model.topProvider?.availableProviders ?: emptyList(),
                availableQuantizations = model.topProvider?.availableQuantizations ?: emptyList(),
                reasoning = model.reasoning
            )
        }
    }
}

@Serializable
data class ModelEndpointsEnvelope(
    val data: ModelEndpointsData
)

@Serializable
data class ModelEndpointsData(
    val id: String? = null,
    val name: String? = null,
    val description: String? = null,
    val architecture: ModelArchitecture? = null,
    val endpoints: List<ModelEndpoint> = emptyList()
)

@Serializable
data class ModelEndpoint(
    val name: String,
    @SerialName("context_length") val contextLength: Double? = null,
    val pricing: ModelPricing,
    @SerialName("provider_name") val providerName: String? = null,
    @SerialName("supported_parameters") val supportedParameters: List<String>? = null,
    val quantization: String? = null,
    @SerialName("max_completion_tokens") val maxCompletionTokens: Double? = null,
    @SerialName("max_prompt_tokens") val maxPromptTokens: Double? = null,
    val status: JsonElement? = null,
    @SerialName("uptime_last_30m") val uptimeLast30m: Double? = null,
    val tag: String? = null
)

// Providers directory response from /api/v1/providers
@Serializable
data class ProvidersResponse(
    val data: List<ProviderInfo>
)

@Serializable
data class ProviderInfo(
    val name: String,
    val slug: String
)

data class ProviderDirectory(
    val nameToSlug: Map<String, String>,
    val slugToName: Map<String, String>
) {
    companion object {
        fun fromList(list: List<ProviderInfo>): ProviderDirectory {
            val nameToSlug = list.associate { it.name.lowercase() to it.slug }
            val slugToName = list.associate { it.slug to it.name }
            return ProviderDirectory(nameToSlug, slugToName)
        }
        val EMPTY = ProviderDirectory(emptyMap(), emptyMap())
    }
    fun slugForName(name: String?): String? = name?.let { nameToSlug[it.lowercase()] }
    fun nameForSlug(slug: String?): String? = slug?.let { slugToName[it] }
}

// Helper to normalize status field (string | number | boolean → String?)
fun ModelEndpoint.statusText(): String? {
    val s = this.status
    if (s == null) return null
    return when (s) {
        is JsonPrimitive -> {
            when {
                s.isString -> s.content.ifBlank { null }
                s.booleanOrNull != null -> if (s.booleanOrNull == true) "up" else "down"
                s.longOrNull != null -> s.longOrNull?.toString()
                else -> s.toString()
            }
        }
        else -> s.toString()
    }
}

data class OpenRouterEndpointOption(
    val tag: String,
    val providerName: String,
    val quantization: String? = null,
    val supportedParameters: List<String> = emptyList(),
    val status: String? = null
) {
    val id: String get() = tag
}

data class OpenRouterModelEndpointOptions(
    val modelId: String,
    val endpoints: List<ModelEndpoint> = emptyList(),
    val providerEndpoints: List<OpenRouterEndpointOption> = emptyList(),
    val quantizations: List<String> = emptyList()
)

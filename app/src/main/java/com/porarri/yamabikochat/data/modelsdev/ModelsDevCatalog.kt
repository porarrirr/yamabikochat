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
            "GEMINI" to "google", "OPENAI" to "openai"
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
data class CatalogModelProviderContract(
    val npm: String? = null,
    val api: String? = null,
    val shape: String? = null,
    val provenance: String? = null
)

object ModelsDevReasoningPreference {
    private const val FIELD_PREFIX = "YAMABIKO_REASONING_EFFORT_"

    fun fieldName(modelId: String): String = FIELD_PREFIX + modelId
        .toByteArray(Charsets.UTF_8)
        .joinToString(separator = "") { byte -> "%02X".format(byte.toInt() and 0xFF) }

    fun fieldKey(providerId: String, fieldName: String): String {
        val provider = providerId.lowercase().replace(Regex("[^a-z0-9._-]+"), "_")
        val field = fieldName.uppercase().replace(Regex("[^A-Z0-9_]+"), "_")
        return "models_dev_${provider}_$field"
    }

    fun storageKey(providerId: String, modelId: String): String =
        fieldKey(providerId, fieldName(modelId))
}

@Serializable
data class CatalogModel(
    val id: String,
    val name: String,
    val description: String? = null,
    val family: String? = null,
    val attachment: Boolean? = null,
    val reasoning: Boolean? = null,
    val reasoningOptions: List<CatalogReasoningOption> = emptyList(),
    val toolCall: Boolean? = null,
    val structuredOutput: Boolean? = null,
    val temperature: Boolean? = null,
    val inputModalities: List<String> = emptyList(),
    val outputModalities: List<String> = emptyList(),
    val releaseDate: String? = null,
    val lastUpdated: String? = null,
    val limits: CatalogLimits = CatalogLimits(),
    val cost: CatalogCost = CatalogCost(),
    val providerContract: CatalogModelProviderContract? = null
) {
    val supportedReasoningEfforts: List<String>
        get() = reasoningOptions
            .asSequence()
            .filter { it.type.equals("effort", ignoreCase = true) }
            .flatMap { it.values.asSequence() }
            .map { it.trim().lowercase() }
            .filter { it.isNotEmpty() }
            .distinct()
            .toList()

    fun shouldShowReasoningEffortPreference(savedEffort: String): Boolean =
        supportedReasoningEfforts.isNotEmpty() || savedEffort.isNotBlank()

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

enum class CatalogAvailability { IDLE, LOADING, READY, STALE, ERROR }

data class CatalogLoadState(
    val availability: CatalogAvailability = CatalogAvailability.IDLE,
    val providers: List<CatalogProvider> = emptyList(),
    val lastUpdatedEpochMs: Long? = null,
    val error: String? = null
)

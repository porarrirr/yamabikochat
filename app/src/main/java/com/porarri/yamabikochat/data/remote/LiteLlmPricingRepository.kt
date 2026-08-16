package com.porarri.yamabikochat.data.remote

import android.util.Log
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.contentOrNull
import kotlin.math.max

class LiteLlmPricingRepository(
    private val apiService: LiteLlmPricingApiService
) {
    private val cacheMutex = Mutex()
    private var cachedCatalog: Map<String, LiteLlmModelCatalogEntry> = emptyMap()
    private var visionByBasename: Map<String, Boolean> = emptyMap()
    private var lastFetchedAtMs: Long = 0L
    private var catalogOverriddenForTests: Boolean = false

    suspend fun estimateCostUsd(
        provider: String,
        model: String,
        inputTokens: Int,
        outputTokens: Int,
        reasoningTokens: Int?
    ): Double? = withContext(Dispatchers.IO) {
        val price = resolvePrice(provider, model) ?: return@withContext null
        val inputRate = price.inputCostPerToken ?: 0.0
        val outputRate = price.outputCostPerToken ?: price.inputCostPerToken ?: 0.0
        val reasoningCount = max(0, reasoningTokens ?: 0)
        val nonReasoningOutput = max(0, outputTokens - reasoningCount)
        val reasoningRate = price.outputCostPerReasoningToken ?: outputRate
        val inputCost = inputRate * max(0, inputTokens)
        val outputCost = outputRate * nonReasoningOutput + reasoningRate * reasoningCount
        val total = inputCost + outputCost
        return@withContext if (total.isFinite() && total >= 0.0) total else null
    }

    suspend fun modelSupportsVision(provider: String, model: String): Boolean = withContext(Dispatchers.IO) {
        ensureCatalogLoaded()
        if (cachedCatalog.isEmpty()) return@withContext false

        val candidates = buildLookupCandidates(provider, model)
        for (candidate in candidates) {
            cachedCatalog[candidate]?.let { entry ->
                return@withContext entry.supportsVision == true
            }
        }

        if (provider.trim().uppercase() == "SUPERGROK") {
            SuperGrokModelCatalog.modelFor(model)?.let { catalogModel ->
                return@withContext catalogModel.supportsVision
            }
        }

        val basename = modelBasename(model)
        if (basename.isEmpty()) return@withContext false
        return@withContext visionByBasename[basename] == true
    }

    private suspend fun resolvePrice(provider: String, model: String): LiteLlmModelPrice? {
        ensureCatalogLoaded()
        if (cachedCatalog.isEmpty()) return null
        val candidates = buildLookupCandidates(provider, model)
        for (candidate in candidates) {
            val entry = cachedCatalog[candidate] ?: continue
            if (entry.hasPricing) return entry.price
        }
        return null
    }

    private suspend fun ensureCatalogLoaded(forceRefresh: Boolean = false) {
        if (catalogOverriddenForTests) return
        val now = System.currentTimeMillis()
        if (!forceRefresh && cachedCatalog.isNotEmpty() && (now - lastFetchedAtMs) < CACHE_TTL_MS) {
            return
        }
        cacheMutex.withLock {
            val freshNow = System.currentTimeMillis()
            if (!forceRefresh && cachedCatalog.isNotEmpty() && (freshNow - lastFetchedAtMs) < CACHE_TTL_MS) {
                return
            }
            runCatching {
                val response = apiService.getModelPriceCatalog()
                if (!response.isSuccessful) {
                    throw IllegalStateException("HTTP ${response.code()}")
                }
                response.body().orEmpty()
            }.onSuccess { json ->
                val parsed = parseCatalog(json)
                if (parsed.catalog.isNotEmpty()) {
                    cachedCatalog = parsed.catalog
                    visionByBasename = parsed.visionByBasename
                    lastFetchedAtMs = System.currentTimeMillis()
                }
            }.onFailure { err ->
                Log.w("LiteLlmPricingRepo", "Failed to fetch pricing catalog: ${err.message}")
            }
        }
    }

    internal fun parseCatalog(root: JsonObject): ParsedCatalog {
        val output = mutableMapOf<String, LiteLlmModelCatalogEntry>()
        val visionByBasename = mutableMapOf<String, Boolean>()
        root.forEach { (rawKey, rawValue) ->
            val key = rawKey.trim().lowercase()
            if (key == "sample_spec") return@forEach
            val obj = rawValue as? JsonObject ?: return@forEach
            val price = LiteLlmModelPrice(
                inputCostPerToken = obj.doubleValue("input_cost_per_token"),
                outputCostPerToken = obj.doubleValue("output_cost_per_token"),
                outputCostPerReasoningToken = obj.doubleValue("output_cost_per_reasoning_token")
            )
            val supportsVision = obj.boolValue("supports_vision")
            val hasPricing =
                price.inputCostPerToken != null ||
                    price.outputCostPerToken != null ||
                    price.outputCostPerReasoningToken != null
            if (!hasPricing && supportsVision == null) return@forEach

            output[key] = LiteLlmModelCatalogEntry(price = price, supportsVision = supportsVision)
            if (supportsVision == true) {
                val basename = modelBasename(key)
                if (basename.isNotEmpty()) {
                    visionByBasename[basename] = true
                }
            }
        }
        return ParsedCatalog(catalog = output, visionByBasename = visionByBasename)
    }

    internal fun replaceCatalogForTests(
        catalog: Map<String, LiteLlmModelCatalogEntry>,
        visionByBasename: Map<String, Boolean> = emptyMap()
    ) {
        cachedCatalog = catalog
        this.visionByBasename = visionByBasename
        lastFetchedAtMs = System.currentTimeMillis()
        catalogOverriddenForTests = true
    }

    private fun buildLookupCandidates(provider: String, model: String): List<String> {
        val cleanedModel = model.trim().removePrefix("/").lowercase()
        if (cleanedModel.isEmpty()) return emptyList()
        val providerKey = provider.trim().uppercase()
        val values = linkedSetOf<String>()
        val canonical = cleanedModel.substringBefore("@")
        values.add(canonical)
        values.add(canonical.substringBefore(":"))

        if (canonical.contains('/')) {
            val noVariant = canonical.substringBefore(":")
            values.add(noVariant)
            val afterFirstSlash = noVariant.substringAfter("/", "")
            if (afterFirstSlash.isNotEmpty()) values.add(afterFirstSlash)
            val afterSecondSlash = afterFirstSlash.substringAfter("/", "")
            if (afterSecondSlash.isNotEmpty()) values.add(afterSecondSlash)
            values.add("openrouter/$noVariant")
            values.add("openrouter/${afterFirstSlash.substringBefore(":")}")
        } else {
            val providerPrefix = inferProviderPrefix(canonical)
            providerPrefix?.let { values.add("$it/$canonical") }
            values.add("openrouter/$canonical")
            providerPrefix?.let { values.add("openrouter/$it/$canonical") }
        }

        when (providerKey) {
            "OPENROUTER" -> {
                val base = canonical.substringBefore(":")
                values.add("openrouter/$base")
                if (!base.startsWith("openrouter/")) {
                    values.add("openrouter/${base.substringAfter("/", base)}")
                }
            }
            "OPENAI", "CODEX_AUTH", "OPENAI_COMPAT", "OPENCODE_GO", "SUPERGROK", "CLINEPASS",
            "ALIBABA_CODING_PLAN", "MINIMAX", "ZAI" -> {
                values.add(canonical.removePrefix("openai/"))
                values.add(canonical.removePrefix("google/"))
                values.add(canonical.removePrefix("anthropic/"))
            }
            "GEMINI" -> {
                values.add(canonical.removePrefix("google/"))
                values.add("openrouter/google/${canonical.removePrefix("google/")}")
            }
        }
        return values.toList()
    }

    private fun inferProviderPrefix(model: String): String? {
        return when {
            model.startsWith("gpt") || model.startsWith("o1") || model.startsWith("o3") || model.startsWith("o4") -> "openai"
            model.startsWith("gemini") -> "google"
            model.startsWith("claude") -> "anthropic"
            model.startsWith("deepseek") -> "deepseek"
            model.startsWith("llama") -> "meta-llama"
            model.startsWith("qwen") -> "qwen"
            model.startsWith("mistral") || model.startsWith("mixtral") || model.startsWith("ministral") -> "mistralai"
            model.startsWith("minimax") || model.startsWith("abab") -> "minimax"
            else -> null
        }
    }

    private fun modelBasename(model: String): String {
        val cleaned = model.trim().removePrefix("/").lowercase()
        if (cleaned.isEmpty()) return ""
        val canonical = cleaned.substringBefore("@")
        val withoutVariant = canonical.substringBefore(":")
        return withoutVariant.substringAfterLast('/').ifEmpty { withoutVariant }
    }

    private fun JsonObject.doubleValue(key: String): Double? {
        val primitive = this[key] as? JsonPrimitive ?: return null
        return primitive.contentOrNull?.toDoubleOrNull()
    }

    private fun JsonObject.boolValue(key: String): Boolean? {
        val primitive = this[key] as? JsonPrimitive ?: return null
        primitive.booleanOrNull?.let { return it }
        return when (primitive.contentOrNull?.trim()?.lowercase()) {
            "true" -> true
            "false" -> false
            else -> null
        }
    }

    private fun JsonObject?.orEmpty(): JsonObject = this ?: JsonObject(emptyMap())

    companion object {
        private const val CACHE_TTL_MS = 12L * 60L * 60L * 1000L
    }
}

data class LiteLlmModelPrice(
    val inputCostPerToken: Double?,
    val outputCostPerToken: Double?,
    val outputCostPerReasoningToken: Double?
)

data class LiteLlmModelCatalogEntry(
    val price: LiteLlmModelPrice,
    val supportsVision: Boolean?
) {
    val hasPricing: Boolean
        get() = price.inputCostPerToken != null ||
            price.outputCostPerToken != null ||
            price.outputCostPerReasoningToken != null
}

data class ParsedCatalog(
    val catalog: Map<String, LiteLlmModelCatalogEntry>,
    val visionByBasename: Map<String, Boolean>
)

package com.porarri.yamabikochat.data.remote

import android.util.Log
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import kotlin.math.max

class LiteLlmPricingRepository(
    private val apiService: LiteLlmPricingApiService
) {
    private val cacheMutex = Mutex()
    private var cachedPrices: Map<String, LiteLlmModelPrice> = emptyMap()
    private var lastFetchedAtMs: Long = 0L

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

    private suspend fun resolvePrice(provider: String, model: String): LiteLlmModelPrice? {
        ensureCatalogLoaded()
        if (cachedPrices.isEmpty()) return null
        val candidates = buildLookupCandidates(provider, model)
        for (candidate in candidates) {
            cachedPrices[candidate]?.let { return it }
        }
        return null
    }

    private suspend fun ensureCatalogLoaded(forceRefresh: Boolean = false) {
        val now = System.currentTimeMillis()
        if (!forceRefresh && cachedPrices.isNotEmpty() && (now - lastFetchedAtMs) < CACHE_TTL_MS) {
            return
        }
        cacheMutex.withLock {
            val freshNow = System.currentTimeMillis()
            if (!forceRefresh && cachedPrices.isNotEmpty() && (freshNow - lastFetchedAtMs) < CACHE_TTL_MS) {
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
                if (parsed.isNotEmpty()) {
                    cachedPrices = parsed
                    lastFetchedAtMs = System.currentTimeMillis()
                }
            }.onFailure { err ->
                Log.w("LiteLlmPricingRepo", "Failed to fetch pricing catalog: ${err.message}")
            }
        }
    }

    private fun parseCatalog(root: JsonObject): Map<String, LiteLlmModelPrice> {
        val output = mutableMapOf<String, LiteLlmModelPrice>()
        root.forEach { (rawKey, rawValue) ->
            val key = rawKey.trim().lowercase()
            if (key == "sample_spec") return@forEach
            val obj = rawValue as? JsonObject ?: return@forEach
            val price = LiteLlmModelPrice(
                inputCostPerToken = obj.doubleValue("input_cost_per_token"),
                outputCostPerToken = obj.doubleValue("output_cost_per_token"),
                outputCostPerReasoningToken = obj.doubleValue("output_cost_per_reasoning_token")
            )
            if (price.inputCostPerToken != null || price.outputCostPerToken != null || price.outputCostPerReasoningToken != null) {
                output[key] = price
            }
        }
        return output
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
            "OPENAI", "CODEX_AUTH", "OPENAI_COMPAT", "MINIMAX", "ZAI" -> {
                values.add(canonical.removePrefix("openai/"))
                values.add(canonical.removePrefix("google/"))
                values.add(canonical.removePrefix("anthropic/"))
            }
            "GEMINI", "GEMINI_AUTH" -> {
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

    private fun JsonObject.doubleValue(key: String): Double? {
        val primitive = this[key] as? JsonPrimitive ?: return null
        return primitive.contentOrNull?.toDoubleOrNull()
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

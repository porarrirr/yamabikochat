package com.porarri.yamabikochat.data.modelsdev

import android.content.Context
import android.util.AtomicFile
import com.porarri.yamabikochat.utils.DiagnosticsLogger
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.longOrNull
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.File
import java.util.concurrent.TimeUnit

class ModelsDevCatalogRepository(
    context: Context,
    private val client: OkHttpClient = OkHttpClient.Builder()
        .connectTimeout(15, TimeUnit.SECONDS)
        .readTimeout(30, TimeUnit.SECONDS)
        .build(),
    private val now: () -> Long = System::currentTimeMillis
) {
    private val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }
    private val cacheFile = File(context.filesDir, "models_dev_catalog_cache.json")
    private val metadataPrefs = context.getSharedPreferences("models_dev_catalog_metadata", Context.MODE_PRIVATE)
    private val fetchMutex = Mutex()
    private val _state = MutableStateFlow(CatalogLoadState())
    val state: StateFlow<CatalogLoadState> = _state.asStateFlow()

    suspend fun load(forceRefresh: Boolean = false): CatalogLoadState = fetchMutex.withLock {
        val cached = readCache()
        val fetchedAt = metadataPrefs.getLong(KEY_FETCHED_AT, 0L).takeIf { it > 0 }
        val cacheFresh = cached.isNotEmpty() && fetchedAt != null && now() - fetchedAt < CACHE_TTL_MS
        if (!forceRefresh && cacheFresh) {
            return@withLock CatalogLoadState(CatalogAvailability.READY, cached, fetchedAt).also { _state.value = it }
        }

        _state.value = CatalogLoadState(CatalogAvailability.LOADING, cached, fetchedAt)
        val result = withContext(Dispatchers.IO) { fetchCatalog(cached, fetchedAt) }
        _state.value = result
        result
    }

    fun providers(): List<CatalogProvider> = state.value.providers

    fun provider(reference: ProviderReference): CatalogProvider? =
        reference.modelsDevId?.let { id -> providers().firstOrNull { it.id == id } }

    suspend fun providerOrLoad(reference: ProviderReference): CatalogProvider? {
        if (!reference.isModelsDev) return null
        provider(reference)?.let { return it }
        return load().providers.firstOrNull { it.id == reference.modelsDevId }
    }

    private fun fetchCatalog(cached: List<CatalogProvider>, fetchedAt: Long?): CatalogLoadState {
        return try {
            val requestBuilder = Request.Builder().url(CATALOG_URL).get()
            metadataPrefs.getString(KEY_ETAG, null)?.let { requestBuilder.header("If-None-Match", it) }
            client.newCall(requestBuilder.build()).execute().use { response ->
                if (response.code == 304 && cached.isNotEmpty()) {
                    val updatedAt = now()
                    metadataPrefs.edit().putLong(KEY_FETCHED_AT, updatedAt).apply()
                    return CatalogLoadState(CatalogAvailability.READY, cached, updatedAt)
                }
                if (!response.isSuccessful) error("models.dev returned HTTP ${response.code}")
                val body = response.body?.string().orEmpty()
                val parsed = parseCatalog(body)
                require(parsed.isNotEmpty()) { "models.dev catalog contains no usable providers" }
                writeCache(parsed)
                val updatedAt = now()
                metadataPrefs.edit()
                    .putLong(KEY_FETCHED_AT, updatedAt)
                    .putString(KEY_ETAG, response.header("ETag"))
                    .apply()
                DiagnosticsLogger.log("models.dev catalog updated providers=${parsed.size}")
                CatalogLoadState(CatalogAvailability.READY, parsed, updatedAt)
            }
        } catch (error: Exception) {
            DiagnosticsLogger.log("models.dev catalog update failed", error)
            CatalogLoadState(
                availability = if (cached.isEmpty()) CatalogAvailability.ERROR else CatalogAvailability.STALE,
                providers = cached,
                lastUpdatedEpochMs = fetchedAt,
                error = error.message ?: "models.dev catalog update failed"
            )
        }
    }

    internal fun parseCatalog(raw: String): List<CatalogProvider> {
        val root = json.parseToJsonElement(raw).jsonObject
        val providersObject = (root["providers"] ?: error("catalog.json is missing providers")).jsonObject
        return providersObject.entries.asSequence()
            .filter { (id, _) -> id.lowercase() != "openrouter" }
            .mapNotNull { (providerId, element) -> parseProvider(providerId, element.jsonObject) }
            .sortedBy { it.name.lowercase() }
            .toList()
    }

    private fun parseProvider(id: String, value: JsonObject): CatalogProvider? {
        val name = value.string("name") ?: return null
        val npm = value.string("npm") ?: return null
        val api = value.string("api")
        val models = value["models"]?.jsonObject?.entries.orEmpty().mapNotNull { (modelId, modelValue) ->
            parseModel(modelId, modelValue.jsonObject, npm, api)
        }.sortedBy { it.name.lowercase() }
        if (models.isEmpty()) return null
        return CatalogProvider(
            id = id.lowercase(),
            name = name,
            npm = npm,
            api = api,
            env = value.stringList("env"),
            documentationUrl = value.string("doc"),
            models = models
        )
    }

    private fun parseModel(id: String, value: JsonObject, providerNpm: String, providerApi: String?): CatalogModel? {
        if (value.string("status")?.lowercase() == "deprecated") return null
        val outputs = value["modalities"]?.jsonObject?.stringList("output").orEmpty()
        if (outputs.none { it.equals("text", ignoreCase = true) }) return null
        val reasoningOptions = value["reasoning_options"]?.jsonArray?.mapNotNull { option ->
            val objectValue = option.jsonObject
            objectValue.string("type")?.let { CatalogReasoningOption(it, objectValue.stringList("values")) }
        }.orEmpty()
        val limit = value["limit"]?.jsonObject
        val cost = value["cost"]?.jsonObject
        val modelProvider = value["provider"]?.jsonObject
        return CatalogModel(
            id = id,
            name = value.string("name") ?: id,
            description = value.string("description"),
            family = value.string("family"),
            attachment = value.optionalBool("attachment"),
            reasoning = value.optionalBool("reasoning"),
            reasoningOptions = reasoningOptions,
            toolCall = value.optionalBool("tool_call"),
            structuredOutput = value.optionalBool("structured_output"),
            temperature = value.optionalBool("temperature"),
            inputModalities = value["modalities"]?.jsonObject?.stringList("input").orEmpty(),
            outputModalities = outputs,
            releaseDate = value.string("release_date"),
            lastUpdated = value.string("last_updated"),
            limits = CatalogLimits(limit?.long("context"), limit?.long("input"), limit?.long("output")),
            cost = CatalogCost(
                cost?.double("input"), cost?.double("output"), cost?.double("reasoning"),
                cost?.double("cache_read"), cost?.double("cache_write")
            ),
            providerContract = CatalogModelProviderContract(
                npm = modelProvider?.string("npm") ?: providerNpm,
                api = modelProvider?.string("api") ?: providerApi,
                shape = modelProvider?.string("shape"),
                provenance = if (modelProvider == null) "provider" else "model"
            )
        )
    }

    private fun readCache(): List<CatalogProvider> = runCatching {
        if (!cacheFile.exists()) emptyList() else json.decodeFromString<List<CatalogProvider>>(cacheFile.readText())
    }.onFailure { DiagnosticsLogger.log("models.dev cache read failed", it) }.getOrDefault(emptyList())

    private fun writeCache(providers: List<CatalogProvider>) {
        val atomicFile = AtomicFile(cacheFile)
        val stream = atomicFile.startWrite()
        try {
            stream.write(json.encodeToString(providers).toByteArray(Charsets.UTF_8))
            atomicFile.finishWrite(stream)
        } catch (error: Exception) {
            atomicFile.failWrite(stream)
            throw error
        }
    }

    private fun JsonObject.string(key: String): String? = this[key]?.jsonPrimitive?.contentOrNull
    private fun JsonObject.optionalBool(key: String): Boolean? = this[key]?.jsonPrimitive?.booleanOrNull
    private fun JsonObject.long(key: String): Long? = this[key]?.jsonPrimitive?.longOrNull
    private fun JsonObject.double(key: String): Double? = this[key]?.jsonPrimitive?.doubleOrNull
    private fun JsonObject.stringList(key: String): List<String> =
        this[key]?.jsonArray?.mapNotNull { it.jsonPrimitive.contentOrNull }.orEmpty()

    private companion object {
        const val CATALOG_URL = "https://models.dev/catalog.json"
        const val KEY_FETCHED_AT = "fetched_at"
        const val KEY_ETAG = "etag"
        const val CACHE_TTL_MS = 24 * 60 * 60 * 1000L
    }
}

package com.porarri.yamabikochat.data.remote

import android.util.Log
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.withContext

class OpenRouterModelService(
    private val apiService: OpenRouterApiService
) {
    private var cachedModels: List<SimpleModel>? = null
    private var lastFetchTime = 0L
    private val cacheExpiry = 5 * 60 * 1000L // 5分キャッシュ
    
    private val _models = MutableStateFlow<List<SimpleModel>>(emptyList())
    val models: StateFlow<List<SimpleModel>> = _models.asStateFlow()
    
    private val _isLoading = MutableStateFlow(false)
    val isLoading: StateFlow<Boolean> = _isLoading.asStateFlow()
    
    private val _error = MutableStateFlow<String?>(null)
    val error: StateFlow<String?> = _error.asStateFlow()

    // Providers directory cache
    private var cachedProviders: ProviderDirectory = ProviderDirectory.EMPTY
    private var lastProvidersFetch = 0L
    private val providersCacheExpiry = 24 * 60 * 60 * 1000L // 24h

    private fun isProvidersCacheValid(): Boolean {
        return cachedProviders.nameToSlug.isNotEmpty() &&
               (System.currentTimeMillis() - lastProvidersFetch) < providersCacheExpiry
    }

    suspend fun getProvidersDirectory(forceRefresh: Boolean = false): ProviderDirectory = withContext(Dispatchers.IO) {
        if (!forceRefresh && isProvidersCacheValid()) return@withContext cachedProviders
        try {
            val res = apiService.getProviders()
            if (res.isSuccessful) {
                val body = res.body()
                if (body != null && body.data.isNotEmpty()) {
                    cachedProviders = ProviderDirectory.fromList(body.data)
                    lastProvidersFetch = System.currentTimeMillis()
                    return@withContext cachedProviders
                }
            }
        } catch (_: Exception) { }
        return@withContext cachedProviders
    }
    
    companion object {
        private const val TAG = "OpenRouterModelService"
        
        // フォールバック用の人気モデル一覧
        private val FALLBACK_MODELS = listOf(
            SimpleModel(
                id = "openai/gpt-4o",
                name = "GPT-4o",
                provider = "openai",
                contextLength = 128000,
                promptPricePerMillion = 5.0,
                completionPricePerMillion = 15.0
            ),
            SimpleModel(
                id = "anthropic/claude-3.5-sonnet",
                name = "Claude 3.5 Sonnet",
                provider = "anthropic",
                contextLength = 200000,
                promptPricePerMillion = 3.0,
                completionPricePerMillion = 15.0
            ),
            SimpleModel(
                id = "meta-llama/llama-3.1-8b-instruct:free",
                name = "Llama 3.1 8B Instruct (Free)",
                provider = "meta-llama",
                contextLength = 131072,
                promptPricePerMillion = 0.0,
                completionPricePerMillion = 0.0,
                isFree = true
            ),
            SimpleModel(
                id = "google/gemini-flash-1.5",
                name = "Gemini Flash 1.5",
                provider = "google",
                contextLength = 1000000,
                promptPricePerMillion = 0.75,
                completionPricePerMillion = 3.0
            )
        )
    }
    
    private fun isCacheValid(): Boolean {
        return cachedModels != null && 
               (System.currentTimeMillis() - lastFetchTime) < cacheExpiry
    }
    
    suspend fun getAvailableModels(forceRefresh: Boolean = false): List<SimpleModel> {
        // キャッシュが有効な場合はキャッシュを返す
        if (!forceRefresh && isCacheValid()) {
            Log.d(TAG, "返回缓存的模型列表")
            return cachedModels ?: FALLBACK_MODELS
        }
        
        return fetchModels()
    }
    
    private suspend fun fetchModels(): List<SimpleModel> = withContext(Dispatchers.IO) {
        try {
            _isLoading.value = true
            _error.value = null
            
            Log.d(TAG, "OpenRouterからモデル一覧を取得中...")
            
            val response = apiService.getModels()
            
            if (response.isSuccessful) {
                val modelsResponse = response.body()
                if (modelsResponse != null && modelsResponse.data.isNotEmpty()) {
                    val simpleModels = modelsResponse.data
                        .mapNotNull { model ->
                            try {
                                SimpleModel.fromOpenRouterModel(model)
                            } catch (e: Exception) {
                                Log.w(TAG, "モデル変換エラー: ${model.id}", e)
                                null
                            }
                        }
                        .sortedWith(compareBy<SimpleModel> { !it.isFree }.thenBy { it.promptPrice })
                    
                    cachedModels = simpleModels
                    lastFetchTime = System.currentTimeMillis()
                    _models.value = simpleModels
                    
                    Log.d(TAG, "モデル一覧取得成功: ${simpleModels.size}個のモデル")
                    simpleModels
                } else {
                    Log.w(TAG, "空のレスポンスを受信、フォールバックモデルを使用")
                    _error.value = "モデル一覧が空です"
                    getFallbackModels()
                }
            } else {
                Log.e(TAG, "API呼び出し失敗: ${response.code()}")
                _error.value = "APIエラー: ${response.code()}"
                getFallbackModels()
            }
        } catch (e: Exception) {
            Log.e(TAG, "モデル取得でエラーが発生", e)
            _error.value = "ネットワークエラー: ${e.message}"
            getFallbackModels()
        } finally {
            _isLoading.value = false
        }
    }
    
    private fun getFallbackModels(): List<SimpleModel> {
        cachedModels = FALLBACK_MODELS
        _models.value = FALLBACK_MODELS
        return FALLBACK_MODELS
    }
    
    fun getModelById(modelId: String): SimpleModel? {
        return _models.value.find { it.id == modelId }
    }
    
    fun searchModels(query: String): List<SimpleModel> {
        if (query.isBlank()) return _models.value
        
        val lowerQuery = query.lowercase()
        return _models.value.filter { model ->
            model.name.lowercase().contains(lowerQuery) ||
            model.id.lowercase().contains(lowerQuery) ||
            model.provider.lowercase().contains(lowerQuery)
        }
    }
    
    fun getModelsByProvider(provider: String): List<SimpleModel> {
        return _models.value.filter { it.provider.equals(provider, ignoreCase = true) }
    }
    
    fun getFreeModels(): List<SimpleModel> {
        return _models.value.filter { it.isFree }
    }
    
    fun clearCache() {
        cachedModels = null
        lastFetchTime = 0L
        _models.value = emptyList()
        _error.value = null
    }
    
    suspend fun getModelEndpoints(modelId: String): List<ModelEndpoint> = withContext(Dispatchers.IO) {
        try {
            val parts = modelId.split("/")
            if (parts.size < 2) {
                Log.w(TAG, "Invalid model ID format: $modelId")
                return@withContext emptyList()
            }
            
            val author = parts[0]
            // Drop variant suffix like ":free", ":beta", ":extended" when calling endpoints API
            val rawSlug = parts.drop(1).joinToString("/")
            val canonicalSlug = rawSlug.substringBefore(":")
            
            Log.d(TAG, "モデルエンドポイント取得中: $author/$canonicalSlug (from '$modelId')")
            
            val response = apiService.getModelEndpoints(author, canonicalSlug)
            
            if (response.isSuccessful) {
                val envelope = response.body()
                if (envelope != null) {
                    val endpoints = envelope.data.endpoints
                    Log.d(TAG, "エンドポイント情報取得成功: ${endpoints.size}個のエンドポイント")
                    endpoints
                } else {
                    Log.w(TAG, "エンドポイント情報が空です")
                    emptyList()
                }
            } else {
                Log.e(TAG, "エンドポイント取得失敗: ${response.code()}")
                emptyList()
            }
        } catch (e: Exception) {
            Log.e(TAG, "エンドポイント取得でエラーが発生", e)
            emptyList()
        }
    }
    
    suspend fun getAvailableProviders(modelId: String): List<String> {
        val endpoints = getModelEndpoints(modelId)
        val dir = getProvidersDirectory()
        // Return provider slugs
        return endpoints.mapNotNull { ep -> dir.slugForName(ep.providerName) ?: ep.providerName?.lowercase() }
            .distinct()
    }
    
    suspend fun getAvailableQuantizations(modelId: String): List<String> {
        val endpoints = getModelEndpoints(modelId)
        return endpoints.mapNotNull { it.quantization }.distinct()
    }

    suspend fun getModelEndpointOptions(modelId: String): OpenRouterModelEndpointOptions {
        val endpoints = getModelEndpoints(modelId)
        val dir = getProvidersDirectory()
        val providerEndpoints = endpoints.map { ep ->
            val tag = ep.tag ?: (dir.slugForName(ep.providerName) ?: ep.providerName?.lowercase() ?: "")
            OpenRouterEndpointOption(
                tag = tag,
                providerName = ep.providerName ?: tag,
                quantization = ep.quantization,
                supportedParameters = ep.supportedParameters ?: emptyList(),
                status = ep.statusText()
            )
        }.filter { it.tag.isNotBlank() }
        val quantizations = endpoints.mapNotNull { it.quantization }.distinct()
        return OpenRouterModelEndpointOptions(
            modelId = modelId,
            endpoints = endpoints,
            providerEndpoints = providerEndpoints,
            quantizations = quantizations
        )
    }
}

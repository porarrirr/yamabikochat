package com.porarri.yamabikochat.data.model

import com.porarri.yamabikochat.data.remote.ModelEndpoint
import com.porarri.yamabikochat.data.remote.OpenRouterModelService
import com.porarri.yamabikochat.data.remote.ProviderDirectory
import com.porarri.yamabikochat.data.remote.SimpleModel
import kotlinx.coroutines.flow.StateFlow

class ModelRepository(private val openRouterModelService: OpenRouterModelService) {

    suspend fun getOpenRouterModels(forceRefresh: Boolean = false): List<SimpleModel> {
        return openRouterModelService.getAvailableModels(forceRefresh)
    }

    fun getOpenRouterModelsFlow(): StateFlow<List<SimpleModel>> = openRouterModelService.models

    fun getOpenRouterModelsLoading(): StateFlow<Boolean> = openRouterModelService.isLoading

    fun getOpenRouterModelsError(): StateFlow<String?> = openRouterModelService.error

    fun searchOpenRouterModels(query: String): List<SimpleModel> {
        return openRouterModelService.searchModels(query)
    }

    fun getOpenRouterModelsByProvider(provider: String): List<SimpleModel> {
        return openRouterModelService.getModelsByProvider(provider)
    }

    fun getFreeOpenRouterModels(): List<SimpleModel> {
        return openRouterModelService.getFreeModels()
    }

    fun getOpenRouterModelById(modelId: String): SimpleModel? {
        return openRouterModelService.getModelById(modelId)
    }

    fun clearOpenRouterModelsCache() {
        openRouterModelService.clearCache()
    }

    suspend fun getAvailableProvidersForModel(modelId: String): List<String> {
        return openRouterModelService.getAvailableProviders(modelId)
    }

    suspend fun getAvailableQuantizationsForModel(modelId: String): List<String> {
        return openRouterModelService.getAvailableQuantizations(modelId)
    }

    suspend fun getModelEndpoints(modelId: String): List<ModelEndpoint> {
        return openRouterModelService.getModelEndpoints(modelId)
    }

    suspend fun getProvidersDirectory(): ProviderDirectory {
        return openRouterModelService.getProvidersDirectory()
    }
}

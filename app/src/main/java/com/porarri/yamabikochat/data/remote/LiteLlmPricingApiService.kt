package com.porarri.yamabikochat.data.remote

import kotlinx.serialization.json.JsonObject
import retrofit2.Response
import retrofit2.http.GET

interface LiteLlmPricingApiService {
    @GET("BerriAI/litellm/main/model_prices_and_context_window.json")
    suspend fun getModelPriceCatalog(): Response<JsonObject>
}

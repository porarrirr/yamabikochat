package com.porarri.yamabikochat.data.remote

import retrofit2.Response
import retrofit2.http.GET
import retrofit2.http.Path

interface OpenRouterApiService {
    @GET("v1/models")
    suspend fun getModels(): Response<OpenRouterModelsResponse>

    @GET("v1/providers")
    suspend fun getProviders(): Response<ProvidersResponse>

    @GET("v1/models/{author}/{slug}/endpoints")
    suspend fun getModelEndpoints(
        @Path("author") author: String,
        @Path("slug") slug: String
    ): Response<ModelEndpointsEnvelope>
}

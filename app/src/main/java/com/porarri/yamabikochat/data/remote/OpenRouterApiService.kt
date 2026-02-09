package com.porarri.yamabikochat.data.remote

import okhttp3.ResponseBody
import retrofit2.Response
import retrofit2.http.*

interface OpenRouterApiService {

    @POST("v1/chat/completions")
    suspend fun createChatCompletion(
        @Header("Authorization") authorization: String,
        @Header("Content-Type") contentType: String = "application/json",
        @Header("HTTP-Referer") referer: String = "https://github.com/porarri/yamabiko-chat",
        @Header("X-Title") title: String = "Yamabiko Chat",
        @Body request: OpenRouterRequest
    ): Response<OpenRouterResponse>

    @POST("v1/chat/completions")
    suspend fun createChatCompletionMultiModal(
        @Header("Authorization") authorization: String,
        @Header("Content-Type") contentType: String = "application/json",
        @Header("HTTP-Referer") referer: String = "https://github.com/porarri/yamabiko-chat",
        @Header("X-Title") title: String = "Yamabiko Chat",
        @Body request: OpenRouterMultiModalRequest
    ): Response<OpenRouterResponse>

    @Streaming
    @POST("v1/chat/completions")
    suspend fun createChatCompletionStream(
        @Header("Authorization") authorization: String,
        @Header("Content-Type") contentType: String = "application/json",
        @Header("HTTP-Referer") referer: String = "https://github.com/porarri/yamabiko-chat",
        @Header("X-Title") title: String = "Yamabiko Chat",
        @Body request: OpenRouterRequest
    ): Response<ResponseBody>

    @Streaming
    @POST("v1/chat/completions")
    suspend fun createChatCompletionMultiModalStream(
        @Header("Authorization") authorization: String,
        @Header("Content-Type") contentType: String = "application/json",
        @Header("HTTP-Referer") referer: String = "https://github.com/porarri/yamabiko-chat",
        @Header("X-Title") title: String = "Yamabiko Chat",
        @Body request: OpenRouterMultiModalRequest
    ): Response<ResponseBody>

    @GET("v1/models")
    suspend fun getModels(
        @Query("category") category: String? = null
    ): Response<OpenRouterModelsResponse>
    
    @GET("v1/models/{author}/{slug}/endpoints")
    suspend fun getModelEndpoints(
        @Path("author") author: String,
        @Path("slug") slug: String
    ): Response<ModelEndpointsEnvelope>

    @GET("v1/providers")
    suspend fun getProviders(): Response<ProvidersResponse>
}

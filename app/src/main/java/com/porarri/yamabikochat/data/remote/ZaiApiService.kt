package com.porarri.yamabikochat.data.remote

import okhttp3.ResponseBody
import retrofit2.Response
import retrofit2.http.Body
import retrofit2.http.GET
import retrofit2.http.Header
import retrofit2.http.POST
import retrofit2.http.Streaming

/**
 * Z.ai OpenAI-compatible API
 * Base URL is provided by RetrofitClient: https://api.z.ai/api/coding/paas/v4
 * Endpoints mirror OpenAI Chat Completions.
 */
interface ZaiApiService {

    @POST("chat/completions")
    suspend fun createChatCompletion(
        @Header("Authorization") authorization: String,
        @Header("Content-Type") contentType: String = "application/json",
        @Body request: OpenRouterRequest
    ): Response<OpenRouterResponse>

    @POST("chat/completions")
    suspend fun createChatCompletionMultiModal(
        @Header("Authorization") authorization: String,
        @Header("Content-Type") contentType: String = "application/json",
        @Body request: OpenRouterMultiModalRequest
    ): Response<OpenRouterResponse>

    @Streaming
    @POST("chat/completions")
    suspend fun createChatCompletionStream(
        @Header("Authorization") authorization: String,
        @Header("Content-Type") contentType: String = "application/json",
        @Body request: OpenRouterRequest
    ): Response<ResponseBody>

    @Streaming
    @POST("chat/completions")
    suspend fun createChatCompletionMultiModalStream(
        @Header("Authorization") authorization: String,
        @Header("Content-Type") contentType: String = "application/json",
        @Body request: OpenRouterMultiModalRequest
    ): Response<ResponseBody>
}


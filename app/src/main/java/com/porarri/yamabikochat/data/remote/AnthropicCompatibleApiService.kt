package com.porarri.yamabikochat.data.remote

import okhttp3.ResponseBody
import retrofit2.Response
import retrofit2.http.Body
import retrofit2.http.Header
import retrofit2.http.POST
import retrofit2.http.Streaming

interface AnthropicCompatibleApiService {
    @POST("messages")
    suspend fun createMessage(
        @Header("x-api-key") apiKey: String,
        @Header("anthropic-version") anthropicVersion: String,
        @Header("anthropic-beta") anthropicBeta: String? = null,
        @Header("Content-Type") contentType: String = "application/json",
        @Body request: AnthropicMessageRequest
    ): Response<AnthropicMessageResponse>

    @Streaming
    @POST("messages")
    suspend fun streamMessage(
        @Header("x-api-key") apiKey: String,
        @Header("anthropic-version") anthropicVersion: String,
        @Header("anthropic-beta") anthropicBeta: String? = null,
        @Header("Accept") accept: String = "text/event-stream",
        @Header("Content-Type") contentType: String = "application/json",
        @Body request: AnthropicMessageRequest
    ): Response<ResponseBody>
}

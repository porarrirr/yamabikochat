package com.porarri.yamabikochat.data.remote

import com.jakewharton.retrofit2.converter.kotlinx.serialization.asConverterFactory
import kotlinx.serialization.json.Json
import okhttp3.CertificatePinner
import okhttp3.ConnectionSpec
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.TlsVersion
import retrofit2.Retrofit
import java.util.concurrent.TimeUnit

object RetrofitClient {

    private const val GEMINI_BASE_URL = "https://generativelanguage.googleapis.com/"
    private const val OPENROUTER_BASE_URL = "https://openrouter.ai/api/"
    private const val ZAI_BASE_URL = "https://api.z.ai/api/coding/paas/v4/"
    private const val OPENAI_BASE_URL = "https://api.openai.com/v1/"

    private val json = Json {
        ignoreUnknownKeys = true
        coerceInputValues = true
        classDiscriminator = "type" // Ensure sealed content parts use 'type' discriminator
    }

    private val connectionSpec = ConnectionSpec.Builder(ConnectionSpec.MODERN_TLS)
        .tlsVersions(TlsVersion.TLS_1_2, TlsVersion.TLS_1_3)
        .build()

    private val okHttpClient = OkHttpClient.Builder()
        .connectTimeout(1, TimeUnit.MINUTES)
        .readTimeout(1, TimeUnit.MINUTES)
        .writeTimeout(1, TimeUnit.MINUTES)
        .connectionSpecs(listOf(connectionSpec))
        .retryOnConnectionFailure(true)
        .build()

    val geminiInstance: GeminiApiService by lazy {
        val retrofit = Retrofit.Builder()
            .baseUrl(GEMINI_BASE_URL)
            .client(okHttpClient)
            .addConverterFactory(json.asConverterFactory("application/json".toMediaType()))
            .build()
        retrofit.create(GeminiApiService::class.java)
    }

    val openRouterInstance: OpenRouterApiService by lazy {
        val retrofit = Retrofit.Builder()
            .baseUrl(OPENROUTER_BASE_URL)
            .client(okHttpClient)
            .addConverterFactory(json.asConverterFactory("application/json".toMediaType()))
            .build()
        retrofit.create(OpenRouterApiService::class.java)
    }

    val zaiInstance: ZaiApiService by lazy {
        val retrofit = Retrofit.Builder()
            .baseUrl(ZAI_BASE_URL)
            .client(okHttpClient)
            .addConverterFactory(json.asConverterFactory("application/json".toMediaType()))
            .build()
        retrofit.create(ZaiApiService::class.java)
    }

    /**
     * Static OpenAI service. Use when a global override is not required.
     */
    val openAiStaticInstance: OpenAiApiService by lazy {
        val retrofit = Retrofit.Builder()
            .baseUrl(OPENAI_BASE_URL)
            .client(okHttpClient)
            .addConverterFactory(json.asConverterFactory("application/json".toMediaType()))
            .build()
        retrofit.create(OpenAiApiService::class.java)
    }

    /**
     * Factory for dynamic OpenAI-compatible services with arbitrary base URLs.
     */
    fun makeOpenAiInstance(baseUrl: String): OpenAiApiService {
        val normalized = if (baseUrl.endsWith('/')) baseUrl else "$baseUrl/"
        val retrofit = Retrofit.Builder()
            .baseUrl(normalized)
            .client(okHttpClient)
            .addConverterFactory(json.asConverterFactory("application/json".toMediaType()))
            .build()
        return retrofit.create(OpenAiApiService::class.java)
    }

    // 互換性のために古いinstanceプロパティを保持
    @Deprecated("Use geminiInstance instead")
    val instance: GeminiApiService = geminiInstance
}

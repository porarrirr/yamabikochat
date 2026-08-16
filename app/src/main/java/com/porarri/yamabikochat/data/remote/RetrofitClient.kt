package com.porarri.yamabikochat.data.remote

import com.jakewharton.retrofit2.converter.kotlinx.serialization.asConverterFactory
import kotlinx.serialization.json.Json
import okhttp3.ConnectionSpec
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.TlsVersion
import retrofit2.Retrofit
import java.util.concurrent.TimeUnit

object RetrofitClient {

    private const val OPENROUTER_BASE_URL = "https://openrouter.ai/api/"
    private const val LITELLM_PRICING_BASE_URL = "https://raw.githubusercontent.com/"

    private val json = Json {
        ignoreUnknownKeys = true
        coerceInputValues = true
        classDiscriminator = "type" // Ensure sealed content parts use 'type' discriminator
    }

    private val connectionSpec = ConnectionSpec.Builder(ConnectionSpec.MODERN_TLS)
        .tlsVersions(TlsVersion.TLS_1_2, TlsVersion.TLS_1_3)
        .build()

    internal fun createHttpClient(): OkHttpClient = OkHttpClient.Builder()
        .connectTimeout(1, TimeUnit.MINUTES)
        // Model generation can legitimately remain silent for longer than one
        // minute. Zero is OkHttp's explicit no-timeout value.
        .readTimeout(0, TimeUnit.MILLISECONDS)
        .writeTimeout(0, TimeUnit.MILLISECONDS)
        .connectionSpecs(listOf(connectionSpec))
        .retryOnConnectionFailure(true)
        .build()

    private val okHttpClient = createHttpClient()

    val openRouterInstance: OpenRouterApiService by lazy {
        val retrofit = Retrofit.Builder()
            .baseUrl(OPENROUTER_BASE_URL)
            .client(okHttpClient)
            .addConverterFactory(json.asConverterFactory("application/json".toMediaType()))
            .build()
        retrofit.create(OpenRouterApiService::class.java)
    }

    val liteLlmPricingInstance: LiteLlmPricingApiService by lazy {
        val retrofit = Retrofit.Builder()
            .baseUrl(LITELLM_PRICING_BASE_URL)
            .client(okHttpClient)
            .addConverterFactory(json.asConverterFactory("application/json".toMediaType()))
            .build()
        retrofit.create(LiteLlmPricingApiService::class.java)
    }
}

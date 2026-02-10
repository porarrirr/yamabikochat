package com.porarri.yamabikochat.data.remote

import android.os.Build
import com.porarri.yamabikochat.BuildConfig
import com.porarri.yamabikochat.utils.DiagnosticsLogger
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.ResponseBody
import okhttp3.ResponseBody.Companion.toResponseBody
import retrofit2.Response
import java.util.UUID
import java.util.concurrent.TimeUnit

class GeminiCliProvider(
    private val httpClient: OkHttpClient = OkHttpClient()
) : ApiProvider {

    override val baseUrl: String = "https://cloudcode-pa.googleapis.com/v1internal"
    override val providerType: ProviderType = ProviderType.GEMINI

    private val json = Json {
        ignoreUnknownKeys = true
        encodeDefaults = true
        explicitNulls = false
    }

    private val streamClient: OkHttpClient = httpClient.newBuilder()
        .connectTimeout(1, TimeUnit.MINUTES)
        .writeTimeout(1, TimeUnit.MINUTES)
        .readTimeout(0, TimeUnit.MILLISECONDS)
        .callTimeout(0, TimeUnit.MILLISECONDS)
        .retryOnConnectionFailure(true)
        .build()

    private val requestClient: OkHttpClient = httpClient.newBuilder()
        .connectTimeout(1, TimeUnit.MINUTES)
        .writeTimeout(1, TimeUnit.MINUTES)
        .readTimeout(1, TimeUnit.MINUTES)
        .retryOnConnectionFailure(true)
        .build()

    override suspend fun generateContent(
        apiKey: String,
        model: String,
        request: GenerateContentRequest
    ): Response<GenerateContentResponse> =
        generateContent(apiKey, model, request, projectId = null, sessionId = null)

    suspend fun generateContent(
        apiKey: String,
        model: String,
        request: GenerateContentRequest,
        projectId: String?,
        sessionId: String?
    ): Response<GenerateContentResponse> = withContext(Dispatchers.IO) {
        try {
            val cleanedKey = apiKey.trim()
            if (cleanedKey.isEmpty()) {
                return@withContext Response.error(401, "Access token is empty".toResponseBody())
            }

            val payload = buildRequestPayload(model, request, projectId, sessionId)
            val body = json.encodeToString(GeminiCliGenerateContentRequest.serializer(), payload)
                .toRequestBody("application/json".toMediaType())

            val httpRequest = Request.Builder()
                .url("${baseUrl.trimEnd('/')}:generateContent")
                .header("Authorization", "Bearer $cleanedKey")
                .header("Content-Type", "application/json")
                .header("User-Agent", buildUserAgent(model))
                .post(body)
                .build()

            val response = requestClient.newCall(httpRequest).execute()
            response.use { resp ->
                val raw = resp.body?.string().orEmpty()
                if (!resp.isSuccessful) {
                    DiagnosticsLogger.log(
                        "GeminiCliProvider generateContent failed status=${resp.code} body=${raw.take(512)}"
                    )
                    return@withContext Response.error(resp.code, raw.toResponseBody("text/plain".toMediaType()))
                }

                val parsed = json.decodeFromString(GeminiCliGenerateContentResponse.serializer(), raw)
                return@withContext Response.success(toGeminiResponse(parsed))
            }
        } catch (e: Exception) {
            DiagnosticsLogger.log("GeminiCliProvider generateContent failed model=$model", e)
            Response.error(500, (e.message ?: "Unknown error").toResponseBody())
        }
    }

    override suspend fun streamGenerateContent(
        apiKey: String,
        model: String,
        request: GenerateContentRequest
    ): Response<ResponseBody> =
        streamGenerateContent(apiKey, model, request, projectId = null, sessionId = null)

    suspend fun streamGenerateContent(
        apiKey: String,
        model: String,
        request: GenerateContentRequest,
        projectId: String?,
        sessionId: String?
    ): Response<ResponseBody> = withContext(Dispatchers.IO) {
        try {
            val cleanedKey = apiKey.trim()
            if (cleanedKey.isEmpty()) {
                return@withContext Response.error(401, "Access token is empty".toResponseBody())
            }

            val payload = buildRequestPayload(model, request, projectId, sessionId)
            val body = json.encodeToString(GeminiCliGenerateContentRequest.serializer(), payload)
                .toRequestBody("application/json".toMediaType())

            val httpRequest = Request.Builder()
                .url("${baseUrl.trimEnd('/')}:streamGenerateContent?alt=sse")
                .header("Authorization", "Bearer $cleanedKey")
                .header("Content-Type", "application/json")
                .header("Accept", "text/event-stream")
                .header("User-Agent", buildUserAgent(model))
                .post(body)
                .build()

            val response = streamClient.newCall(httpRequest).execute()
            val responseBody = response.body
            if (!response.isSuccessful || responseBody == null) {
                val raw = responseBody?.string().orEmpty()
                response.close()
                DiagnosticsLogger.log(
                    "GeminiCliProvider streamGenerateContent failed status=${response.code} body=${raw.take(512)}"
                )
                return@withContext Response.error(response.code, raw.toResponseBody("text/plain".toMediaType()))
            }
            Response.success(responseBody)
        } catch (e: Exception) {
            DiagnosticsLogger.log("GeminiCliProvider streamGenerateContent failed model=$model", e)
            Response.error(500, (e.message ?: "Unknown error").toResponseBody())
        }
    }

    private fun buildRequestPayload(
        model: String,
        request: GenerateContentRequest,
        projectId: String?,
        sessionId: String?
    ): GeminiCliGenerateContentRequest {
        val systemInstruction = request.system_instruction?.let {
            Content(role = "system", parts = it.parts)
        }
        return GeminiCliGenerateContentRequest(
            model = model,
            project = projectId?.takeIf { it.isNotBlank() },
            userPromptId = UUID.randomUUID().toString(),
            request = GeminiCliRequest(
                contents = request.contents,
                systemInstruction = systemInstruction,
                tools = request.tools,
                toolConfig = request.toolConfig,
                generationConfig = request.generationConfig?.let { toCliGenerationConfig(it) },
                sessionId = sessionId
            )
        )
    }

    private fun toCliGenerationConfig(config: GenerationConfig): GeminiCliGenerationConfig =
        GeminiCliGenerationConfig(
            temperature = config.temperature,
            topK = config.topK,
            topP = config.topP,
            maxOutputTokens = config.maxOutputTokens,
            stopSequences = config.stopSequences,
            responseMimeType = config.responseMimeType,
            responseJsonSchema = config.responseJsonSchema,
            thinkingConfig = config.thinkingConfig
        )

    private fun toGeminiResponse(response: GeminiCliGenerateContentResponse): GenerateContentResponse {
        val candidates = response.response.candidates
        val text = candidates
            ?.firstOrNull()
            ?.content
            ?.parts
            ?.mapNotNull { it.text }
            ?.joinToString("")
            ?.takeIf { it.isNotBlank() }
        return GenerateContentResponse(
            candidates = candidates,
            promptFeedback = response.response.promptFeedback,
            text = text
        )
    }

    private fun buildUserAgent(model: String): String {
        val appVersion = BuildConfig.VERSION_NAME.takeIf { it.isNotBlank() } ?: "0.0.0"
        val osVersion = Build.VERSION.RELEASE?.takeIf { it.isNotBlank() } ?: "unknown"
        val abi = Build.SUPPORTED_ABIS.firstOrNull()?.takeIf { it.isNotBlank() } ?: "unknown"
        return "GeminiCLI/$appVersion/$model (Android $osVersion; $abi)"
    }
}

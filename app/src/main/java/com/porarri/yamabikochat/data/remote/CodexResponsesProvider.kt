@file:OptIn(kotlinx.serialization.ExperimentalSerializationApi::class)

package com.porarri.yamabikochat.data.remote

import android.content.Context
import android.os.Build
import com.porarri.yamabikochat.BuildConfig
import com.porarri.yamabikochat.utils.CodexUserAgentUtils
import com.porarri.yamabikochat.utils.DiagnosticsLogger
import com.porarri.yamabikochat.utils.SecurePreferencesManager
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.ResponseBody
import okhttp3.ResponseBody.Companion.toResponseBody
import retrofit2.Response
import java.util.concurrent.TimeUnit

class CodexResponsesProvider(
    private val context: Context,
    private val httpClient: OkHttpClient = OkHttpClient()
) : ApiProvider {

    override val baseUrl: String = "https://api.openai.com/v1"
    override val providerType: ProviderType = ProviderType.OPENAI
    private val originatorHeader = "codex_cli_rs"
    private val userAgentHeader: String
        get() = buildUserAgent()
    private val securePrefs = SecurePreferencesManager.getInstance(context)

    private val json = Json {
        ignoreUnknownKeys = true
        encodeDefaults = true
        explicitNulls = false
    }
    private val streamClient: OkHttpClient = httpClient.newBuilder()
        .connectTimeout(STREAM_CONNECT_TIMEOUT_SECONDS, TimeUnit.SECONDS)
        .writeTimeout(STREAM_WRITE_TIMEOUT_SECONDS, TimeUnit.SECONDS)
        .readTimeout(0, TimeUnit.MILLISECONDS)
        .callTimeout(0, TimeUnit.MILLISECONDS)
        .retryOnConnectionFailure(true)
        .build()
    private val requestClient: OkHttpClient = httpClient.newBuilder()
        .connectTimeout(REQUEST_CONNECT_TIMEOUT_SECONDS, TimeUnit.SECONDS)
        .writeTimeout(REQUEST_WRITE_TIMEOUT_SECONDS, TimeUnit.SECONDS)
        .readTimeout(REQUEST_READ_TIMEOUT_MINUTES, TimeUnit.MINUTES)
        .callTimeout(REQUEST_CALL_TIMEOUT_MINUTES, TimeUnit.MINUTES)
        .retryOnConnectionFailure(true)
        .build()

    override suspend fun generateContent(
        apiKey: String,
        model: String,
        request: GenerateContentRequest
    ): Response<GenerateContentResponse> =
        generateContent(apiKey, model, request, baseUrl)

    suspend fun generateContent(
        apiKey: String,
        model: String,
        request: GenerateContentRequest,
        baseUrl: String,
        accountId: String? = null,
        sessionId: String? = null
    ): Response<GenerateContentResponse> = withContext(Dispatchers.IO) {
        try {
            val cleanedKey = apiKey.trim()
            if (cleanedKey.isEmpty()) {
                return@withContext Response.error(401, "API Key is empty".toResponseBody())
            }

            val candidate = baseUrl.trimEnd('/')
            val safeAccountId = redactId(accountId)
            val safeSessionId = redactId(sessionId)
            val stream = false
            DiagnosticsLogger.log(
                "CodexResponsesProvider requesting url=${candidate}/responses stream=$stream " +
                    "model=$model originator=$originatorHeader ua=$userAgentHeader " +
                    "accountId=$safeAccountId sessionId=$safeSessionId"
            )

            when (val result = executeResponsesRequest(
                apiKey = cleanedKey,
                model = model,
                request = request,
                baseUrl = candidate,
                accountId = accountId,
                sessionId = sessionId
            )) {
                is ResponsesRequestResult.Success -> Response.success(parseResponsesToGemini(result.body))
                is ResponsesRequestResult.Error -> errorResponse(result.code, result.body)
            }
        } catch (e: Exception) {
            DiagnosticsLogger.log("CodexResponsesProvider generateContent failed model=$model", e)
            Response.error(500, (e.message ?: "Unknown error").toResponseBody())
        }
    }

    override suspend fun streamGenerateContent(
        apiKey: String,
        model: String,
        request: GenerateContentRequest
    ): Response<ResponseBody> =
        streamGenerateContent(apiKey, model, request, baseUrl)

    suspend fun streamGenerateContent(
        apiKey: String,
        model: String,
        request: GenerateContentRequest,
        baseUrl: String,
        accountId: String? = null,
        sessionId: String? = null
    ): Response<ResponseBody> = withContext(Dispatchers.IO) {
        try {
            val cleanedKey = apiKey.trim()
            if (cleanedKey.isEmpty()) {
                return@withContext Response.error(401, "API Key is empty".toResponseBody())
            }

            val candidate = baseUrl.trimEnd('/')
            val safeAccountId = redactId(accountId)
            val safeSessionId = redactId(sessionId)
            val stream = true
            DiagnosticsLogger.log(
                "CodexResponsesProvider requesting url=${candidate}/responses stream=$stream " +
                    "model=$model originator=$originatorHeader ua=$userAgentHeader " +
                    "accountId=$safeAccountId sessionId=$safeSessionId"
            )

            when (
                val result = executeResponsesStream(
                    apiKey = cleanedKey,
                    model = model,
                    request = request,
                    baseUrl = candidate,
                    stream = true,
                    accountId = accountId,
                    sessionId = sessionId
                )
            ) {
                is ResponsesStreamResult.Success -> Response.success(result.body)
                is ResponsesStreamResult.Error -> errorStreamResponse(result.code, result.body)
            }
        } catch (e: Exception) {
            DiagnosticsLogger.log("CodexResponsesProvider streamGenerateContent failed model=$model", e)
            Response.error(500, (e.message ?: "Unknown error").toResponseBody())
        }
    }

    private sealed interface ResponsesStreamResult {
        data class Success(val body: ResponseBody) : ResponsesStreamResult
        data class Error(val code: Int, val body: String) : ResponsesStreamResult
    }

    private sealed interface ResponsesRequestResult {
        data class Success(val body: String) : ResponsesRequestResult
        data class Error(val code: Int, val body: String) : ResponsesRequestResult
    }

    private fun executeResponsesStream(
        apiKey: String,
        model: String,
        request: GenerateContentRequest,
        baseUrl: String,
        stream: Boolean,
        accountId: String?,
        sessionId: String?
    ): ResponsesStreamResult {
        val requestBody = buildRequestBody(request, model, stream)
        val httpRequest = buildHttpRequest(baseUrl, apiKey, requestBody, accountId, sessionId, stream)
        logRequestHeaders(httpRequest)
        val response = streamClient.newCall(httpRequest).execute()
        val body = response.body
        if (!response.isSuccessful || body == null) {
            val err = body?.string().orEmpty()
            response.close()
            return ResponsesStreamResult.Error(response.code, err)
        }
        return ResponsesStreamResult.Success(body)
    }

    private fun executeResponsesRequest(
        apiKey: String,
        model: String,
        request: GenerateContentRequest,
        baseUrl: String,
        accountId: String?,
        sessionId: String?
    ): ResponsesRequestResult {
        val requestBody = buildRequestBody(request, model, false)
        val httpRequest = buildHttpRequest(baseUrl, apiKey, requestBody, accountId, sessionId, false)
        logRequestHeaders(httpRequest)
        val response = requestClient.newCall(httpRequest).execute()
        response.use { resp ->
            val body = resp.body?.string().orEmpty()
            return if (!resp.isSuccessful) {
                ResponsesRequestResult.Error(resp.code, body)
            } else {
                ResponsesRequestResult.Success(body)
            }
        }
    }

    private fun buildRequestBody(
        request: GenerateContentRequest,
        model: String,
        stream: Boolean
    ): okhttp3.RequestBody {
        val payload = json.encodeToString(
            ResponsesRequest.serializer(),
            RequestConverter.geminiToResponses(
                geminiRequest = request,
                model = model,
                stream = stream
            )
        )
        logRequestPayload(payload)
        val bodyBytes = payload.toByteArray(Charsets.UTF_8)
        return bodyBytes.toRequestBody("application/json".toMediaType())
    }

    private fun buildHttpRequest(
        baseUrl: String,
        apiKey: String,
        requestBody: okhttp3.RequestBody,
        accountId: String?,
        sessionId: String?,
        stream: Boolean
    ): Request = Request.Builder()
        .url("${baseUrl.trimEnd('/')}/responses")
        .header("Authorization", "Bearer $apiKey")
        .header("Content-Type", "application/json")
        .header("originator", originatorHeader)
        .header("User-Agent", userAgentHeader)
        .apply {
            if (stream) {
                header("Accept", "text/event-stream")
            }
            val cleanedAccount = accountId?.trim().orEmpty()
            if (cleanedAccount.isNotEmpty()) {
                header("ChatGPT-Account-ID", cleanedAccount)
            }
            val cleanedSession = sessionId?.trim().orEmpty()
            if (cleanedSession.isNotEmpty()) {
                header("session-id", cleanedSession)
            }
        }
        .post(requestBody)
        .build()

    private fun logRequestHeaders(request: Request) {
        if (!DiagnosticsLogger.isEnabled()) return
        val headersToLog = listOf(
            "Content-Type",
            "Accept",
            "originator",
            "User-Agent",
            "ChatGPT-Account-ID",
            "session-id"
        )
        val headerSummary = headersToLog.joinToString(separator = " ") { name ->
            val value = request.header(name)?.trim().orEmpty().ifBlank { "-" }
            "$name=$value"
        }
        val bodyType = request.body?.contentType()?.toString().orEmpty().ifBlank { "-" }
        DiagnosticsLogger.log("CodexResponsesProvider request headers: $headerSummary bodyContentType=$bodyType")
    }

    private fun logRequestPayload(payload: String) {
        if (!DiagnosticsLogger.isEnabled()) return
        val sanitized = sanitizePayload(payload)
        val maxChars = 8000
        val trimmed = if (sanitized.length > maxChars) {
            sanitized.take(maxChars) + "..."
        } else {
            sanitized
        }
        DiagnosticsLogger.log("CodexResponsesProvider request payload=$trimmed")
    }

    private fun sanitizePayload(payload: String): String {
        val element = runCatching { json.parseToJsonElement(payload) }.getOrNull() ?: return payload
        val sanitized = sanitizeElement(element)
        return runCatching { json.encodeToString(JsonElement.serializer(), sanitized) }.getOrDefault(payload)
    }

    private fun sanitizeElement(element: JsonElement): JsonElement {
        val redactedKeys = setOf("text", "image_url", "instructions", "prompt_cache_key")
        return when (element) {
            is JsonObject -> {
                val updated = element.mapValues { (key, value) ->
                    if (key in redactedKeys) {
                        val replacement = if (value is JsonPrimitive && value.isString) {
                            "<redacted:${value.content.length}>"
                        } else {
                            "<redacted>"
                        }
                        JsonPrimitive(replacement)
                    } else {
                        sanitizeElement(value)
                    }
                }
                JsonObject(updated)
            }
            is JsonArray -> JsonArray(element.map { sanitizeElement(it) })
            else -> element
        }
    }

    private fun errorResponse(code: Int, body: String): Response<GenerateContentResponse> {
        return Response.error(code, body.toResponseBody("application/json".toMediaType()))
    }

    private fun errorStreamResponse(code: Int, body: String): Response<ResponseBody> {
        return Response.error(code, body.toResponseBody("application/json".toMediaType()))
    }

    private fun redactId(value: String?): String {
        val cleaned = value?.trim().orEmpty()
        if (cleaned.isBlank()) return "-"
        val prefix = 6
        val suffix = 4
        if (cleaned.length <= prefix + suffix) return cleaned
        return cleaned.take(prefix) + "…" + cleaned.takeLast(suffix)
    }

    private fun buildUserAgent(): String {
        val appVersion = BuildConfig.VERSION_NAME.takeIf { it.isNotBlank() } ?: "0.0.0"
        val cliVersion = securePrefs.getCodexUserAgentCliVersion()
            ?.trim()
            ?.takeIf { it.isNotBlank() }
            ?: CodexUserAgentUtils.DEFAULT_CODEX_CLI_VERSION
        val osVersion = Build.VERSION.RELEASE?.takeIf { it.isNotBlank() } ?: "unknown"
        val abi = Build.SUPPORTED_ABIS.firstOrNull()?.takeIf { it.isNotBlank() } ?: "unknown"
        val preset = securePrefs.getCodexUserAgentPreset()
        val candidate = CodexUserAgentUtils.buildUserAgent(
            originator = originatorHeader,
            cliVersion = cliVersion,
            preset = preset,
            androidOsVersion = osVersion,
            androidAbi = abi,
            androidAppId = BuildConfig.APPLICATION_ID,
            androidAppVersion = appVersion
        )
        return sanitizeUserAgent(candidate, "${originatorHeader}/${cliVersion}")
    }

    private fun sanitizeUserAgent(candidate: String, fallback: String): String {
        val sanitized = candidate.map { ch ->
            if (ch.code in 32..126) ch else '_'
        }.joinToString("")
        return if (sanitized.isNotBlank()) sanitized else fallback
    }

    private fun parseResponsesToGemini(payload: String): GenerateContentResponse {
        if (payload.isBlank()) return GenerateContentResponse(text = "")
        val root = json.parseToJsonElement(payload).jsonObject
        val output = root["output"] as? JsonArray
        val textBuilder = StringBuilder()
        val thinkingBuilder = StringBuilder()
        val tokenUsage = parseResponsesUsage(root)

        output?.forEach { item ->
            val obj = item.jsonObject
            val type = obj["type"]?.jsonPrimitive?.contentOrNull
            if (type == "message") {
                val role = obj["role"]?.jsonPrimitive?.contentOrNull
                if (role == "assistant") {
                    val content = obj["content"] as? JsonArray
                    content?.forEach { block ->
                        val blockObj = block.jsonObject
                        when (blockObj["type"]?.jsonPrimitive?.contentOrNull) {
                            "output_text" -> textBuilder.append(blockObj["text"]?.jsonPrimitive?.contentOrNull.orEmpty())
                            "reasoning_text" -> thinkingBuilder.append(blockObj["text"]?.jsonPrimitive?.contentOrNull.orEmpty())
                        }
                    }
                }
            } else if (type == "reasoning") {
                val summary = obj["summary"]?.jsonPrimitive?.contentOrNull
                if (!summary.isNullOrBlank()) thinkingBuilder.append(summary)
            }
        }

        val parts = buildList {
            val thinking = thinkingBuilder.toString().trim()
            if (thinking.isNotBlank()) {
                add(ResponsePart(text = thinking, thought = true))
            }
            add(ResponsePart(text = textBuilder.toString()))
        }

        return GenerateContentResponse(
            candidates = listOf(
                Candidate(
                    content = ResponseContent(parts = parts, role = "model")
                )
            ),
            text = textBuilder.toString(),
            tokenUsage = tokenUsage
        )
    }

    private fun parseResponsesSseToGemini(body: ResponseBody): GenerateContentResponse {
        body.use {
            val reader = body.byteStream().bufferedReader(Charsets.UTF_8)
            reader.use { buffered ->
                val textBuilder = StringBuilder()
                val thinkingBuilder = StringBuilder()
                val rawFallback = StringBuilder()
                var sawSseData = false
                val eventBuffer = StringBuilder()

                fun incrementalDelta(buffer: String, incoming: String): String {
                    if (incoming.isEmpty()) return ""
                    if (incoming.length > buffer.length && incoming.startsWith(buffer)) {
                        return incoming.substring(buffer.length)
                    }
                    return incoming
                }

                fun extractOutputTextFromItem(item: JsonObject?): String {
                    if (item == null) return ""
                    val type = item["type"]?.jsonPrimitive?.contentOrNull
                    if (type != "message") return ""
                    val role = item["role"]?.jsonPrimitive?.contentOrNull
                    if (role != "assistant") return ""
                    val content = item["content"] as? JsonArray ?: return ""
                    val builder = StringBuilder()
                    content.forEach { block ->
                        val blockObj = block.jsonObject
                        if (blockObj["type"]?.jsonPrimitive?.contentOrNull == "output_text") {
                            builder.append(blockObj["text"]?.jsonPrimitive?.contentOrNull.orEmpty())
                        }
                    }
                    return builder.toString()
                }

                fun applyPayload(payload: String) {
                    val element = runCatching { json.parseToJsonElement(payload) }.getOrNull() ?: return
                    val obj = element.jsonObject
                    val type = obj["type"]?.jsonPrimitive?.contentOrNull ?: return
                    val delta = obj["delta"]?.jsonPrimitive?.contentOrNull.orEmpty()
                    when (type) {
                        "response.output_text.delta" -> textBuilder.append(delta)
                        "response.reasoning_text.delta", "response.reasoning_summary_text.delta" -> thinkingBuilder.append(delta)
                        "response.output_item.done" -> {
                            val fullText = extractOutputTextFromItem(obj["item"]?.jsonObject)
                            val append = incrementalDelta(textBuilder.toString(), fullText)
                            textBuilder.append(append)
                        }
                    }
                }

                fun flushEvent() {
                    val payload = eventBuffer.toString().trim()
                    eventBuffer.setLength(0)
                    if (payload.isEmpty() || payload == "[DONE]") return
                    sawSseData = true
                    applyPayload(payload)
                }

                while (true) {
                    val rawLine = buffered.readLine() ?: break
                    if (!sawSseData) {
                        rawFallback.append(rawLine)
                        rawFallback.append('\n')
                    }
                    if (rawLine.startsWith(":")) continue
                    if (rawLine.isEmpty()) {
                        if (eventBuffer.isNotEmpty()) flushEvent()
                        continue
                    }
                    if (rawLine.startsWith("data:")) {
                        val payload = rawLine.substringAfter("data:").trimStart()
                        if (eventBuffer.isNotEmpty()) eventBuffer.append('\n')
                        eventBuffer.append(payload)
                    }
                }

                if (eventBuffer.isNotEmpty()) flushEvent()

                if (!sawSseData) {
                    return parseResponsesToGemini(rawFallback.toString())
                }

                val parts = buildList {
                    val thinking = thinkingBuilder.toString().trim()
                    if (thinking.isNotBlank()) add(ResponsePart(text = thinking, thought = true))
                    add(ResponsePart(text = textBuilder.toString()))
                }

                return GenerateContentResponse(
                    candidates = listOf(
                        Candidate(
                            content = ResponseContent(parts = parts, role = "model")
                        )
                    ),
                    text = textBuilder.toString(),
                    tokenUsage = parseResponsesUsageFromSse(rawFallback.toString())
                )
            }
        }
    }

    private fun parseResponsesUsage(root: JsonObject): TokenUsageSnapshot? {
        val usage = root["usage"]?.jsonObject ?: return null
        return usageToSnapshot(usage)
    }

    private fun parseResponsesUsageFromSse(payload: String): TokenUsageSnapshot? {
        if (payload.isBlank()) return null
        var usageObj: JsonObject? = null
        payload.lineSequence().forEach { line ->
            if (!line.startsWith("data:")) return@forEach
            val body = line.substringAfter("data:").trim()
            if (body.isEmpty() || body == "[DONE]") return@forEach
            runCatching { json.parseToJsonElement(body).jsonObject }.getOrNull()?.let { obj ->
                val type = obj["type"]?.jsonPrimitive?.contentOrNull
                if (type == "response.completed") {
                    val usage = obj["response"]?.jsonObject
                        ?.get("usage")
                        ?.jsonObject
                    if (usage != null) {
                        usageObj = usage
                    }
                }
            }
        }
        return usageObj?.let { usageToSnapshot(it) }
    }

    private fun usageToSnapshot(usageObj: JsonObject): TokenUsageSnapshot? {
        val inputTokens = usageObj["input_tokens"]?.jsonPrimitive?.contentOrNull?.toIntOrNull() ?: 0
        val outputTokens = usageObj["output_tokens"]?.jsonPrimitive?.contentOrNull?.toIntOrNull() ?: 0
        val totalTokens = usageObj["total_tokens"]?.jsonPrimitive?.contentOrNull?.toIntOrNull()
            ?: (inputTokens + outputTokens)
        val reasoningTokens = runCatching {
            usageObj["output_tokens_details"]?.jsonObject
                ?.get("reasoning_tokens")
                ?.jsonPrimitive
                ?.contentOrNull
                ?.toIntOrNull()
        }.getOrNull()
        val cachedInputTokens = runCatching {
            usageObj["input_tokens_details"]?.jsonObject
                ?.get("cached_tokens")
                ?.jsonPrimitive
                ?.contentOrNull
                ?.toIntOrNull()
        }.getOrNull()
        val snapshot = TokenUsageSnapshot(
            inputTokens = inputTokens,
            outputTokens = outputTokens,
            totalTokens = totalTokens,
            reasoningTokens = reasoningTokens,
            cachedInputTokens = cachedInputTokens
        ).normalized()
        return snapshot.takeUnless { it.isEmpty() }
    }

    companion object {
        private const val STREAM_CONNECT_TIMEOUT_SECONDS = 60L
        private const val STREAM_WRITE_TIMEOUT_SECONDS = 60L
        private const val REQUEST_CONNECT_TIMEOUT_SECONDS = 60L
        private const val REQUEST_WRITE_TIMEOUT_SECONDS = 60L
        private const val REQUEST_READ_TIMEOUT_MINUTES = 10L
        private const val REQUEST_CALL_TIMEOUT_MINUTES = 10L
    }
}

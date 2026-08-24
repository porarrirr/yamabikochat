package com.porarri.yamabikochat.pi

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.webkit.MimeTypeMap
import com.porarri.yamabikochat.data.model.ProviderClientError
import com.porarri.yamabikochat.data.model.ProviderRequest
import com.porarri.yamabikochat.data.model.ProviderResponse
import com.porarri.yamabikochat.data.model.ProviderStreamEvent
import com.porarri.yamabikochat.data.model.ToolActivityEvent
import com.porarri.yamabikochat.data.model.ToolCall
import com.porarri.yamabikochat.data.tools.editor.StrReplaceEditorTool
import com.porarri.yamabikochat.data.model.ToolResult
import com.porarri.yamabikochat.data.tools.LocalToolRegistry
import com.porarri.yamabikochat.utils.DiagnosticsLogger
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.channelFlow
import kotlinx.coroutines.flow.flowOn
import kotlinx.coroutines.joinAll
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonPrimitive
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.io.BufferedReader
import java.io.File
import java.io.FileOutputStream
import java.io.InputStreamReader
import java.util.Base64
import java.util.UUID
import java.util.concurrent.TimeUnit
import kotlin.random.Random

class PiAgentRuntime private constructor(private val context: Context) {
    companion object {
        private const val MAX_ATTACHMENT_SIZE_BYTES = 10 * 1024 * 1024L // 10 MB

        @Volatile
        private var instance: PiAgentRuntime? = null

        fun getInstance(context: Context): PiAgentRuntime {
            return instance ?: synchronized(this) {
                instance ?: PiAgentRuntime(context.applicationContext).also { instance = it }
            }
        }

        fun credentialJSONString(element: kotlinx.serialization.json.JsonElement): String {
            return Json.encodeToString(element)
        }
    }

    private val json = Json {
        ignoreUnknownKeys = true
        isLenient = true
        encodeDefaults = true
    }

    private val httpClient = OkHttpClient.Builder()
        .connectTimeout(30, TimeUnit.SECONDS)
        .readTimeout(10, TimeUnit.MINUTES)
        .writeTimeout(60, TimeUnit.SECONDS)
        .build()

    private val mutex = Mutex()
    private var endpointUrl: String? = null
    private var authToken: String? = null

    suspend fun verifyReady() {
        startIfNeeded()
    }

    suspend fun startIfNeeded(): Pair<String, String> = mutex.withLock {
        val existingEndpoint = endpointUrl
        val existingToken = authToken
        if (existingEndpoint != null && existingToken != null) {
            return Pair(existingEndpoint, existingToken)
        }

        withContext(Dispatchers.IO) {
            val scriptFile = extractBundledScript()
            val port = Random.nextInt(49152, 60000)
            val token = UUID.randomUUID().toString().replace("-", "")
            val endpoint = "http://127.0.0.1:$port/"

            DiagnosticsLogger.log("Pi runtime engine starting port=$port script=${scriptFile.name}")
            PiNodeRunner.startEngine(listOf("node", scriptFile.absolutePath, port.toString(), token))

            val healthRequest = Request.Builder()
                .url("${endpoint}health")
                .header("Authorization", "Bearer $token")
                .get()
                .build()

            var ready = false
            for (attempt in 1..100) {
                try {
                    httpClient.newCall(healthRequest).execute().use { response ->
                        if (response.isSuccessful) {
                            val health = response.body?.string()?.let { body ->
                                runCatching { json.decodeFromString<PiHealthResponse>(body) }.getOrNull()
                            }
                            if (health?.ok == true && health.contractVersion == 2) {
                                DiagnosticsLogger.log("Pi runtime health check succeeded attempt=$attempt port=$port contractVersion=2")
                                ready = true
                            }
                        }
                    }
                } catch (_: Exception) {}

                if (ready) break
                delay(100)
            }

            if (!ready) {
                val error = ProviderClientError.ParseFailure("Pi agent runtime did not start")
                DiagnosticsLogger.log("Pi runtime health check timed out port=$port", error)
                throw error
            }

            endpointUrl = endpoint
            authToken = token
            Pair(endpoint, token)
        }
    }

    suspend fun resolveModels(configurations: List<PiAgentConfiguration>): List<PiModelResolution> =
        withContext(Dispatchers.IO) {
            val (endpoint, token) = startIfNeeded()
            val envelope = PiModelResolutionEnvelope(configurations)
            val request = Request.Builder()
                .url("${endpoint}v1/models/resolve")
                .header("Authorization", "Bearer $token")
                .header("Content-Type", "application/json")
                .post(json.encodeToString(envelope).toRequestBody("application/json".toMediaType()))
                .build()
            httpClient.newCall(request).execute().use { response ->
                if (!response.isSuccessful) throw ProviderClientError.InvalidResponse
                val value = json.decodeFromString<PiModelResolutionResponse>(response.body?.string().orEmpty())
                if (value.contractVersion != 2) {
                    throw ProviderClientError.ParseFailure("Pi runtime contract mismatch")
                }
                value.models.forEach { model ->
                    DiagnosticsLogger.log(
                        "Pi model contract resolved contractVersion=${value.contractVersion} " +
                            "supported=${model.supported} provider=${model.provider ?: "unknown"} " +
                            "model=${model.model ?: "unknown"} api=${model.api ?: "none"} " +
                            "source=${model.source ?: "none"} reason=${model.reason ?: "none"}"
                    )
                }
                value.models
            }
        }

    private fun extractBundledScript(): File {
        val runtimeDir = File(context.filesDir, "pi-runtime")
        if (!runtimeDir.exists()) runtimeDir.mkdirs()
        val scriptFile = File(runtimeDir, "main.js")

        context.assets.open("pi-runtime/main.js").use { input ->
            FileOutputStream(scriptFile).use { output ->
                input.copyTo(output)
            }
        }
        return scriptFile
    }

    fun stream(
        request: ProviderRequest,
        configuration: PiAgentConfiguration,
        tools: LocalToolRegistry
    ): Flow<ProviderStreamEvent> = channelFlow {
        DiagnosticsLogger.log(
            "Pi runtime stream requested provider=${configuration.provider} model=${configuration.model} contractVersion=${configuration.contractVersion}"
        )
        val (endpoint, token) = startIfNeeded()
        val runId = UUID.randomUUID().toString()
        val piRequest = makeRequest(request)
        val envelope = PiRunEnvelope(runId = runId, request = piRequest, config = configuration)
        val bodyJson = json.encodeToString(envelope)
        val requestBody = bodyJson.toRequestBody("application/json".toMediaType())

        val urlRequest = Request.Builder()
            .url("${endpoint}v1/run")
            .header("Authorization", "Bearer $token")
            .header("Content-Type", "application/json")
            .post(requestBody)
            .build()

        DiagnosticsLogger.log(
            "Pi runtime bridge request starting runId=$runId provider=${configuration.provider} model=${configuration.model} messages=${request.messages.size}"
        )

        val call = httpClient.newCall(urlRequest)

        try {
            val response = call.execute()
            if (!response.isSuccessful) {
                throw ProviderClientError.InvalidResponse
            }

            val source = response.body?.byteStream() ?: throw ProviderClientError.InvalidResponse
            val reader = BufferedReader(InputStreamReader(source, Charsets.UTF_8))

            val toolJobs = mutableListOf<kotlinx.coroutines.Job>()
            var line: String?
            while (reader.readLine().also { line = it } != null) {
                val currentLine = line?.trim().orEmpty()
                if (currentLine.isEmpty()) continue

                val event = try {
                    json.decodeFromString<PiRuntimeEvent>(currentLine)
                } catch (e: Exception) {
                    DiagnosticsLogger.log("Failed to parse Pi event: $currentLine", e)
                    continue
                }

                when (event.type) {
                    "diagnostic" -> {
                        DiagnosticsLogger.log(
                            event.message ?: "Pi runtime diagnostic",
                            null
                        )
                    }
                    "text_delta" -> {
                        send(ProviderStreamEvent.TextDelta(event.delta.orEmpty()))
                    }
                    "reasoning_delta" -> {
                        send(ProviderStreamEvent.ReasoningDelta(event.delta.orEmpty()))
                    }
                    "answer_start" -> {
                        send(ProviderStreamEvent.AnswerStart)
                    }
                    "tool_request" -> {
                        val reqId = event.requestId
                        val callId = event.toolCallId
                        val toolName = event.name
                        if (reqId != null && callId != null && toolName != null) {
                            val argumentsString = event.arguments?.let { json.encodeToString(it) } ?: "{}"
                            val providerMetadata = if (toolName == StrReplaceEditorTool.NAME) {
                                mapOf(
                                    "editorSessionId" to request.metadata["editorSessionId"].orEmpty(),
                                    "editorAttachmentsJSON" to json.encodeToString(request.messages.flatMap { it.attachments })
                                )
                            } else null
                            val toolCall = ToolCall(id = callId, name = toolName, argumentsJSON = argumentsString, providerMetadata = providerMetadata)
                            val createdAtMs = event.timeMs ?: System.currentTimeMillis()
                            val reportsActivity = toolName == "web_search" || toolName == "fetch_url" || toolName == StrReplaceEditorTool.NAME
                            if (reportsActivity) {
                                send(ProviderStreamEvent.ToolActivity(ToolActivityEvent(
                                    phase = ToolActivityEvent.Phase.started,
                                    call = toolCall,
                                    createdAtMs = createdAtMs
                                )))
                            }
                            toolJobs += launch {
                                try {
                                    val toolResult = tools.execute(toolCall)
                                    if (reportsActivity) {
                                        send(ProviderStreamEvent.ToolActivity(ToolActivityEvent(
                                            phase = ToolActivityEvent.Phase.finished,
                                            call = toolCall,
                                            result = toolResult,
                                            createdAtMs = createdAtMs
                                        )))
                                    }
                                    submitToolResult(toolResult, reqId, endpoint, token)
                                } catch (error: Exception) {
                                    abortRun(runId, endpoint, token)
                                    call.cancel()
                                    throw error
                                }
                            }
                        }
                    }
                    "completed" -> {
                        toolJobs.joinAll()
                        val completedResponse = event.response
                            ?: throw ProviderClientError.ParseFailure("Pi completed without a response")
                        DiagnosticsLogger.log(
                            "Pi runtime request completed runId=$runId provider=${configuration.provider} model=${configuration.model}"
                        )
                        send(ProviderStreamEvent.Completed(completedResponse))
                    }
                    "error" -> {
                        val error = ProviderClientError.ParseFailure(event.message ?: "Pi agent failed")
                        DiagnosticsLogger.log("Pi runtime reported an error runId=$runId", error)
                        throw error
                    }
                }
            }
        } catch (e: CancellationException) {
            DiagnosticsLogger.log("Pi runtime request cancelled runId=$runId")
            abortRun(runId, endpoint, token)
            throw e
        } catch (e: Exception) {
            DiagnosticsLogger.log("Pi runtime bridge failed runId=$runId", e)
            throw e
        }
    }.flowOn(Dispatchers.IO)

    private suspend fun submitToolResult(
        result: ToolResult,
        requestId: String,
        endpoint: String,
        token: String
    ) = withContext(Dispatchers.IO) {
        val envelope = PiToolResultEnvelope(
            requestId = requestId,
            content = result.content,
            isError = result.isError,
            sources = result.sources
        )
        val bodyJson = json.encodeToString(envelope)
        val request = Request.Builder()
            .url("${endpoint}v1/tool-result")
            .header("Authorization", "Bearer $token")
            .header("Content-Type", "application/json")
            .post(bodyJson.toRequestBody("application/json".toMediaType()))
            .build()

        httpClient.newCall(request).execute().use { response ->
            if (!response.isSuccessful) {
                throw ProviderClientError.InvalidResponse
            }
        }
    }

    private suspend fun abortRun(runId: String, endpoint: String, token: String) = withContext(Dispatchers.IO) {
        val jsonBody = """{"runId":"$runId"}"""
        val request = Request.Builder()
            .url("${endpoint}v1/abort")
            .header("Authorization", "Bearer $token")
            .header("Content-Type", "application/json")
            .post(jsonBody.toRequestBody("application/json".toMediaType()))
            .build()

        runCatching {
            httpClient.newCall(request).execute().close()
        }
    }

    suspend fun loginOAuth(
        provider: PiOAuthProvider,
        method: PiOAuthLoginMethod,
        onDeviceCode: (suspend (SuperGrokDeviceCodeChallenge) -> Unit)? = null
    ): PiOAuthResolution = withContext(Dispatchers.IO) {
        val (endpoint, token) = startIfNeeded()
        val envelope = PiOAuthLoginRequest(provider = provider, method = method)
        val request = Request.Builder()
            .url("${endpoint}v1/auth/login")
            .header("Authorization", "Bearer $token")
            .header("Content-Type", "application/json")
            .post(json.encodeToString(envelope).toRequestBody("application/json".toMediaType()))
            .build()

        val response = httpClient.newCall(request).execute()
        if (!response.isSuccessful) {
            throw ProviderClientError.InvalidResponse
        }

        val source = response.body?.byteStream() ?: throw ProviderClientError.InvalidResponse
        val reader = BufferedReader(InputStreamReader(source, Charsets.UTF_8))

        var line: String?
        while (reader.readLine().also { line = it } != null) {
            val currentLine = line?.trim().orEmpty()
            if (currentLine.isEmpty()) continue

            val event = json.decodeFromString<PiRuntimeEvent>(currentLine)
            when (event.type) {
                "auth_url" -> {
                    val urlStr = event.url ?: throw ProviderClientError.ParseFailure("Pi OAuth returned invalid URL")
                    openBrowser(urlStr)
                }
                "device_code" -> {
                    val verificationUri = event.verificationUri
                        ?: throw ProviderClientError.ParseFailure("Pi OAuth returned invalid device code")
                    val userCode = event.userCode.orEmpty()
                    onDeviceCode?.invoke(
                        SuperGrokDeviceCodeChallenge(
                            verificationURI = verificationUri,
                            userCode = userCode,
                            browserURL = verificationUri
                        )
                    )
                    openBrowser(verificationUri)
                }
                "auth_completed" -> {
                    val cred = event.credential
                        ?: throw ProviderClientError.ParseFailure("Pi OAuth completed without credentials")
                    val profile = event.profile ?: PiOAuthProfile()
                    val access = (cred as? JsonObject)?.get("access")?.jsonPrimitive?.content
                        ?: throw ProviderClientError.ParseFailure("Pi OAuth credential missing access token")
                    val accountId = (cred as? JsonObject)?.get("accountId")?.jsonPrimitive?.content ?: profile.accountId

                    return@withContext PiOAuthResolution(
                        credential = cred,
                        accessToken = access,
                        accountId = accountId,
                        profile = profile
                    )
                }
                "error" -> {
                    throw ProviderClientError.ParseFailure(event.message ?: "Pi OAuth login failed")
                }
            }
        }
        throw ProviderClientError.ParseFailure("Pi OAuth login ended without credentials")
    }

    suspend fun resolveOAuth(
        provider: PiOAuthProvider,
        credentialJSON: String,
        force: Boolean
    ): PiOAuthResolution = withContext(Dispatchers.IO) {
        val (endpoint, token) = startIfNeeded()
        val parsedCred = json.parseToJsonElement(credentialJSON)
        val envelope = PiOAuthResolveRequest(provider = provider, credential = parsedCred, force = force)

        val request = Request.Builder()
            .url("${endpoint}v1/auth/resolve")
            .header("Authorization", "Bearer $token")
            .header("Content-Type", "application/json")
            .post(json.encodeToString(envelope).toRequestBody("application/json".toMediaType()))
            .build()

        val response = httpClient.newCall(request).execute()
        val responseBody = response.body?.string().orEmpty()
        if (!response.isSuccessful) {
            throw ProviderClientError.ParseFailure("Pi OAuth refresh failed: $responseBody")
        }

        json.decodeFromString<PiOAuthResolution>(responseBody)
    }

    private fun openBrowser(url: String) {
        try {
            val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url)).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(intent)
        } catch (e: Exception) {
            DiagnosticsLogger.log("Failed to launch browser for URL: $url", e)
        }
    }

    private fun makeRequest(request: ProviderRequest): PiRequest {
        return PiRequest(
            messages = request.messages.map { msg ->
                PiMessage(
                    role = msg.role,
                    content = msg.content,
                    attachments = msg.attachments.mapNotNull { path -> loadImageAttachment(path) },
                    reasoningContent = msg.reasoningContent,
                    toolCalls = msg.toolCalls,
                    toolCallId = msg.toolCallId,
                    toolName = msg.toolName,
                    toolResultIsError = msg.toolResultIsError
                )
            },
            systemPrompt = request.systemPrompt,
            tools = request.tools,
            thinking = request.thinking,
            provider = request.provider,
            metadata = request.metadata,
            timeoutInterval = request.timeoutInterval
        )
    }

    private fun loadImageAttachment(path: String): PiAttachment? {
        return try {
            val file = File(path)
            if (!file.exists() || file.length() > MAX_ATTACHMENT_SIZE_BYTES) return null
            val bytes = file.readBytes()
            val ext = file.extension.lowercase()
            val mimeType = MimeTypeMap.getSingleton().getMimeTypeFromExtension(ext) ?: "image/jpeg"
            val base64 = Base64.getEncoder().encodeToString(bytes)
            PiAttachment(data = base64, mimeType = mimeType)
        } catch (_: Exception) {
            null
        }
    }
}

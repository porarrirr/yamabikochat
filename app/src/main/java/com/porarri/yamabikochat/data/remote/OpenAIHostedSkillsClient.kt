package com.porarri.yamabikochat.data.remote

import android.content.Context
import com.porarri.yamabikochat.data.skills.AgentSkillRepository
import com.porarri.yamabikochat.data.skills.SkillRequestContext
import com.porarri.yamabikochat.utils.DiagnosticsLogger
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.ResponseBody
import okhttp3.ResponseBody.Companion.toResponseBody
import okio.buffer
import okio.source
import org.json.JSONArray
import org.json.JSONObject
import retrofit2.Response
import java.io.File
import java.io.FileOutputStream
import java.io.PipedInputStream
import java.io.PipedOutputStream
import java.net.URI
import java.security.MessageDigest
import java.util.UUID
import java.util.concurrent.TimeUnit
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

object OpenAIHostedSkillsPolicy {
    private val supportedModelPatterns = listOf(
        Regex("^gpt-5\\.4(?:-(?:mini|nano))?(?:-\\d{4}-\\d{2}-\\d{2})?$"),
        Regex("^gpt-5\\.5(?:-\\d{4}-\\d{2}-\\d{2})?$"),
        Regex("^gpt-5\\.6$"),
        Regex("^gpt-5\\.6-(?:sol|terra|luna)(?:-\\d{4}-\\d{2}-\\d{2})?$")
    )

    fun validationError(model: String, baseUrl: String): String? {
        if (!isOfficialBaseUrl(baseUrl)) {
            return "OpenAI hosted Skill実行には公式エンドポイント https://api.openai.com/v1/ が必要です。"
        }
        if (!supportsModel(model)) {
            return "モデル '$model' はOpenAI hosted shell/Skillsに対応していません。対応モデルを選択してください。"
        }
        return null
    }

    fun supportsModel(model: String): Boolean {
        val normalized = model.trim().lowercase()
        return supportedModelPatterns.any { it.matches(normalized) }
    }

    fun isOfficialBaseUrl(baseUrl: String): Boolean = runCatching {
        val uri = URI(baseUrl.trim())
        val path = uri.path.orEmpty()
        uri.scheme.equals("https", ignoreCase = true) &&
            uri.host.equals("api.openai.com", ignoreCase = true) &&
            uri.port == -1 &&
            uri.userInfo == null &&
            uri.rawQuery == null &&
            uri.rawFragment == null &&
            path in setOf("", "/", "/v1", "/v1/")
    }.getOrDefault(false)

    fun cacheKey(context: SkillRequestContext, apiKey: String): String {
        val conversation = context.conversationId ?: UUID.randomUUID().toString()
        return "$conversation:${context.enabledSkillSetHash}:${credentialFingerprint(apiKey)}"
    }

    private fun credentialFingerprint(apiKey: String): String = MessageDigest
        .getInstance("SHA-256")
        .digest(apiKey.toByteArray(Charsets.UTF_8))
        .take(16)
        .joinToString("") { "%02x".format(it.toInt() and 0xff) }
}

class OpenAIHostedSkillsClient(
    private val context: Context,
    private val skills: AgentSkillRepository,
    private val http: OkHttpClient = OkHttpClient.Builder().readTimeout(10, TimeUnit.MINUTES).build()
) {
    private data class Cached(val id: String, var lastActive: Long)
    private val cached = mutableMapOf<String, Cached>()
    private val jsonMedia = "application/json".toMediaType()

    @Synchronized
    private fun containerId(requestContext: SkillRequestContext, apiKey: String): String {
        val key = OpenAIHostedSkillsPolicy.cacheKey(requestContext, apiKey)
        cached[key]?.takeIf { System.currentTimeMillis() - it.lastActive < 19 * 60_000 }
            ?.let { it.lastActive = System.currentTimeMillis(); return it.id }
        val inlineSkills = JSONArray()
        skills.enabledSkills.forEach { skill ->
            inlineSkills.put(JSONObject().put("type", "inline").put("name", skill.manifest.name).put("description", skill.manifest.description).put(
                "source", JSONObject().put("type", "base64").put("media_type", "application/zip").put("data", android.util.Base64.encodeToString(zipSkill(skill.manifest.name), android.util.Base64.NO_WRAP))
            ))
        }
        val body = JSONObject().put("name", "YamabikoChat Agent Skills").put("expires_after", JSONObject().put("anchor", "last_active_at").put("minutes", 20)).put("skills", inlineSkills)
        val response = execute("https://api.openai.com/v1/containers", apiKey, body, false)
        response.use {
            val text = it.body?.string().orEmpty()
            if (!it.isSuccessful) throw IllegalStateException("OpenAI container error ${it.code}: $text")
            val id = JSONObject(text).optString("id").takeIf(String::isNotBlank) ?: throw IllegalStateException("OpenAI container response did not include an id")
            cached.entries.removeAll { System.currentTimeMillis() - it.value.lastActive >= 20 * 60_000 }
            cached[key] = Cached(id, System.currentTimeMillis())
            DiagnosticsLogger.log("OpenAI temporary Skill container created container=$id skills=${inlineSkills.length()} expires=20m")
            return id
        }
    }

    fun generate(apiKey: String, model: String, request: GenerateContentRequest): Response<GenerateContentResponse> {
        val skillContext = request.skillContext ?: return Response.error(400, "Hosted Skill context is missing".toResponseBody())
        return try {
            val container = containerId(skillContext, apiKey)
            execute("https://api.openai.com/v1/responses", apiKey, responseBody(model, request, container, false), false).use { raw ->
                val text = raw.body?.string().orEmpty()
                if (!raw.isSuccessful) return Response.error(raw.code, text.toResponseBody())
                Response.success(parseResponse(JSONObject(text), apiKey))
            }
        } catch (error: Exception) { Response.error(500, (error.message ?: "Hosted Skill execution failed").toResponseBody()) }
    }

    fun stream(apiKey: String, model: String, request: GenerateContentRequest): Response<ResponseBody> {
        val skillContext = request.skillContext ?: return Response.error(400, "Hosted Skill context is missing".toResponseBody())
        return try {
            val container = containerId(skillContext, apiKey)
            val raw = execute("https://api.openai.com/v1/responses", apiKey, responseBody(model, request, container, true), true)
            if (!raw.isSuccessful) {
                val code = raw.code; val body = raw.body?.string().orEmpty(); raw.close(); Response.error(code, body.toResponseBody())
            } else {
                val body = raw.body ?: return Response.error(500, "Empty Responses stream".toResponseBody())
                Response.success(wrapHostedStream(raw, body, apiKey))
            }
        } catch (error: Exception) { Response.error(500, (error.message ?: "Hosted Skill streaming failed").toResponseBody()) }
    }

    private fun responseBody(model: String, request: GenerateContentRequest, container: String, stream: Boolean): JSONObject {
        val input = JSONArray()
        request.contents.forEach { content ->
            val role = if (content.role == "model") "assistant" else (content.role ?: "user")
            val blocks = JSONArray()
            content.parts.forEach { part ->
                part.text?.takeIf { it.isNotEmpty() }?.let {
                    blocks.put(JSONObject().put("type", if (role == "assistant") "output_text" else "input_text").put("text", it))
                }
                if (role != "assistant") {
                    part.inlineData?.let { inline ->
                        val dataUrl = "data:${inline.mimeType};base64,${inline.data}"
                        blocks.put(if (inline.mimeType.startsWith("image/")) {
                            JSONObject().put("type", "input_image").put("image_url", dataUrl)
                        } else {
                            JSONObject().put("type", "input_file").put("filename", "attachment").put("file_data", dataUrl)
                        })
                    }
                    part.fileData?.let { file -> localInputFile(file)?.let(blocks::put) }
                }
            }
            if (blocks.length() > 0) input.put(JSONObject().put("role", role).put("content", blocks))
            var callIndex = 0
            content.parts.mapNotNull { it.functionCall }.forEach { call ->
                input.put(JSONObject().put("type", "function_call").put("call_id", "call-${callIndex++}-${call.name}").put("name", call.name).put("arguments", call.args?.toString() ?: "{}"))
            }
            content.parts.mapNotNull { it.functionResponse }.forEach { response ->
                input.put(JSONObject().put("type", "function_call_output").put("call_id", response.id ?: "call-0-${response.name}").put("output", response.response?.toString() ?: "{}"))
            }
        }
        val tools = JSONArray()
        request.tools.orEmpty().flatMap { it.function_declarations.orEmpty() }.forEach { declaration ->
            tools.put(JSONObject().put("type", "function").put("name", declaration.name).put("description", declaration.description ?: "").put("parameters", declaration.parameters?.let { JSONObject(it.toString()) } ?: JSONObject().put("type", "object")))
        }
        tools.put(JSONObject().put("type", "shell").put("environment", JSONObject().put("type", "container_reference").put("container_id", container)))
        return JSONObject().put("model", model).put("input", input).put("tools", tools).put("stream", stream).also { body ->
            request.system_instruction?.parts?.mapNotNull { it.text }?.joinToString("\n")?.takeIf { it.isNotBlank() }?.let { body.put("instructions", it) }
            request.generationConfig?.thinkingConfig?.effort?.let { body.put("reasoning", JSONObject().put("effort", it).put("summary", "auto")) }
        }
    }

    private fun parseResponse(root: JSONObject, apiKey: String): GenerateContentResponse {
        val parts = mutableListOf<ResponsePart>()
        val output = root.optJSONArray("output") ?: JSONArray()
        for (index in 0 until output.length()) {
            val item = output.optJSONObject(index) ?: continue
            when (item.optString("type")) {
                "message" -> item.optJSONArray("content")?.let { content -> for (i in 0 until content.length()) content.optJSONObject(i)?.optString("text")?.takeIf { it.isNotBlank() }?.let { parts += ResponsePart(text = it) } }
                "reasoning" -> item.optJSONArray("summary")?.let { summary -> for (i in 0 until summary.length()) summary.optJSONObject(i)?.optString("text")?.takeIf { it.isNotBlank() }?.let { parts += ResponsePart(text = it, thought = true) } }
                "function_call" -> parts += ResponsePart(functionCall = FunctionCall(item.optString("name"), kotlinx.serialization.json.Json.parseToJsonElement(item.optString("arguments", "{}"))))
                "shell_call", "shell_call_output" -> DiagnosticsLogger.log("OpenAI hosted shell activity type=${item.optString("type")} exit=${item.optInt("exit_code", 0)} timedOut=${item.optBoolean("timed_out", false)}")
            }
        }
        collectFileCitations(root).forEach { citation ->
            runCatching {
                val url = "https://api.openai.com/v1/containers/${citation.first}/files/${citation.second}/content"
                execute(url, apiKey, null, false, "GET").use { response ->
                    if (!response.isSuccessful) error("Container Files error ${response.code}")
                    val target = persistGeneratedFile(response, citation.third)
                    parts += ResponsePart(fileData = FileData(displayName = citation.third, fileUri = target.absolutePath))
                    DiagnosticsLogger.log("OpenAI generated file saved file=${citation.second}")
                }
            }.onFailure { DiagnosticsLogger.log("OpenAI generated file download failed file=${citation.second}", it) }
        }
        val usage = root.optJSONObject("usage")
        return GenerateContentResponse(candidates = listOf(Candidate(ResponseContent(parts, "model"))), tokenUsage = usage?.let { TokenUsageSnapshot(it.optInt("input_tokens"), it.optInt("output_tokens"), it.optInt("total_tokens")) })
    }

    private fun collectFileCitations(root: Any): List<Triple<String, String, String>> {
        val found = linkedSetOf<Triple<String, String, String>>()
        fun walk(value: Any?) { when (value) {
            is JSONObject -> { if (value.optString("type") == "container_file_citation") found += Triple(value.optString("container_id"), value.optString("file_id"), value.optString("filename", "generated-file")); value.keys().forEach { walk(value.opt(it)) } }
            is JSONArray -> for (i in 0 until value.length()) walk(value.opt(i))
        } }
        walk(root); return found.filter { it.first.isNotBlank() && it.second.isNotBlank() }
    }

    private fun localInputFile(file: FileData): JSONObject? {
        val raw = file.fileUri ?: return null
        val source = when {
            raw.startsWith("file:") -> runCatching { File(java.net.URI(raw)) }.getOrNull()
            else -> File(raw)
        }?.takeIf { it.isFile } ?: return null
        val mime = file.mimeType ?: "application/octet-stream"
        val data = android.util.Base64.encodeToString(source.readBytes(), android.util.Base64.NO_WRAP)
        return JSONObject().put("type", "input_file")
            .put("filename", file.displayName ?: source.name)
            .put("file_data", "data:$mime;base64,$data")
    }

    private fun wrapHostedStream(raw: okhttp3.Response, body: ResponseBody, apiKey: String): ResponseBody {
        val input = PipedInputStream(64 * 1024)
        val output = PipedOutputStream(input)
        Thread({
            val seenFiles = mutableSetOf<String>()
            try {
                body.byteStream().bufferedReader(Charsets.UTF_8).useLines { lines ->
                    lines.forEach { line ->
                        output.write((line + "\n").toByteArray(Charsets.UTF_8))
                        if (!line.startsWith("data:")) return@forEach
                        val payload = line.substringAfter("data:").trim()
                        if (payload.isEmpty() || payload == "[DONE]") return@forEach
                        val root = runCatching { JSONObject(payload) }.getOrNull() ?: return@forEach
                        collectFileCitations(root).filter { seenFiles.add("${it.first}:${it.second}") }.forEach { citation ->
                            runCatching { downloadGeneratedFile(citation, apiKey) }.onSuccess { file ->
                                val synthetic = JSONObject()
                                    .put("type", "yamabiko.generated_file")
                                    .put("path", file.absolutePath)
                                    .put("filename", citation.third)
                                output.write(("data: $synthetic\n\n").toByteArray(Charsets.UTF_8))
                            }.onFailure {
                                val synthetic = JSONObject()
                                    .put("type", "yamabiko.generated_file_error")
                                    .put("filename", citation.third)
                                    .put("message", it.message ?: "Container file download failed")
                                output.write(("data: $synthetic\n\n").toByteArray(Charsets.UTF_8))
                                DiagnosticsLogger.log("OpenAI generated file download failed file=${citation.second}", it)
                            }
                        }
                    }
                }
            } finally {
                runCatching { output.close() }
                raw.close()
            }
        }, "yamabiko-hosted-skill-stream").apply { isDaemon = true; start() }
        return object : ResponseBody() {
            override fun contentType() = "text/event-stream".toMediaType()
            override fun contentLength() = -1L
            override fun source() = input.source().buffer()
        }
    }

    private fun downloadGeneratedFile(citation: Triple<String, String, String>, apiKey: String): File {
        val url = "https://api.openai.com/v1/containers/${citation.first}/files/${citation.second}/content"
        execute(url, apiKey, null, false, "GET").use { response ->
            if (!response.isSuccessful) error("Container Files error ${response.code}")
            return persistGeneratedFile(response, citation.third)
        }
    }

    private fun persistGeneratedFile(response: okhttp3.Response, filename: String): File {
        val safe = filename.replace(Regex("[^A-Za-z0-9._-]+"), "_").ifBlank { "generated-file" }
        val target = File(context.filesDir, "${UUID.randomUUID()}_$safe")
        response.body?.byteStream()?.use { source -> FileOutputStream(target).use(source::copyTo) }
            ?: error("Container file response was empty")
        return target
    }

    private fun execute(url: String, key: String, body: JSONObject?, streaming: Boolean, method: String = "POST"): okhttp3.Response {
        val builder = Request.Builder().url(url).header("Authorization", "Bearer $key")
        if (method == "GET") builder.get() else builder.post((body ?: JSONObject()).toString().toRequestBody(jsonMedia))
        return http.newCall(builder.build()).execute()
    }

    private fun zipSkill(name: String): ByteArray {
        val root = skills.enabledSkillRoot(name)
        val output = java.io.ByteArrayOutputStream()
        ZipOutputStream(output).use { zip -> root.walkTopDown().filter { it.isFile && it.name != "state.json" }.forEach { file -> zip.putNextEntry(ZipEntry("$name/${file.relativeTo(root).invariantSeparatorsPath}")); file.inputStream().use { it.copyTo(zip) }; zip.closeEntry() } }
        return output.toByteArray()
    }

    private fun String.toResponseBody(): ResponseBody = toResponseBody("text/plain".toMediaType())
}

package com.porarri.yamabikochat.data.tools.editor

import android.content.Context
import com.porarri.yamabikochat.data.attachments.AttachmentStorage
import com.porarri.yamabikochat.data.model.ToolArtifact
import com.porarri.yamabikochat.data.model.ToolCall
import com.porarri.yamabikochat.data.model.ToolDefinition
import com.porarri.yamabikochat.data.model.ToolResult
import com.porarri.yamabikochat.data.tools.LocalToolExecutor
import java.io.File
import java.io.IOException
import java.nio.charset.CharacterCodingException
import java.nio.charset.CodingErrorAction
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.security.MessageDigest
import java.net.URLConnection
import java.util.UUID
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

class EditorWorkspaceStore(
    private val root: File
) {
    private val mutex = Mutex()

    suspend fun <T> withWorkspace(sessionId: String, operation: suspend (File) -> T): T = mutex.withLock {
        require(sessionId.isNotEmpty()) { "str_replace_editor requires a valid conversation session." }
        val workspace = File(root, sha256(sessionId.toByteArray()))
        if (!workspace.exists() && !workspace.mkdirs()) throw IOException("Could not create editor workspace.")
        operation(workspace)
    }

    suspend fun delete(sessionId: String) = mutex.withLock {
        val workspace = File(root, sha256(sessionId.toByteArray()))
        if (workspace.exists() && !workspace.deleteRecursively()) throw IOException("Could not delete editor workspace.")
    }

    suspend fun deleteOrphans(validSessionIds: List<String>) = mutex.withLock {
        if (!root.exists()) return@withLock
        val validNames = validSessionIds.mapTo(mutableSetOf()) { sha256(it.toByteArray()) }
        root.listFiles().orEmpty().filterNot { it.name in validNames }.forEach { orphan ->
            if (!orphan.deleteRecursively()) throw IOException("Could not delete orphaned editor workspace.")
        }
    }

    companion object {
        fun forContext(context: Context) = EditorWorkspaceStore(File(context.filesDir, "EditorWorkspaces"))

        internal fun sha256(bytes: ByteArray): String = MessageDigest.getInstance("SHA-256")
            .digest(bytes).joinToString("") { "%02x".format(it) }
    }
}

class StrReplaceEditorTool(
    private val workspaces: EditorWorkspaceStore,
    private val attachments: AttachmentStorage
) : LocalToolExecutor {
    override val definition = ToolDefinition(
        name = NAME,
        description = "Custom editing tool for viewing, creating and editing files in the persistent conversation workspace at /workspace. File views contain numbered lines, directory views list visible entries up to 2 levels deep, create never overwrites, and str_replace requires exactly one literal match. Long view output is marked with <response clipped>.",
        parametersJSON = """{"type":"object","properties":{"command":{"type":"string","description":"The command to run.","enum":["view","create","str_replace","insert"]},"path":{"type":"string","description":"Absolute virtual path under /workspace."},"file_text":{"type":"string","description":"Required content for create."},"insert_line":{"type":"integer","description":"Required for insert; new_str is inserted after this line (0 inserts before line 1)."},"new_str":{"type":"string","description":"Replacement or insertion text. Omission deletes old_str for str_replace."},"old_str":{"type":"string","description":"Required unique literal text for str_replace."},"view_range":{"type":"array","items":{"type":"integer"},"description":"Optional inclusive 1-based [start,end] range; end -1 means EOF."}},"required":["command","path"]}"""
    )

    override suspend fun execute(call: ToolCall): ToolResult {
        val sessionId = call.providerMetadata?.get("editorSessionId")?.trim().orEmpty()
        require(sessionId.isNotEmpty()) { "str_replace_editor requires a valid conversation session." }
        val args = decodeArguments(call.argumentsJSON)
        return workspaces.withWorkspace(sessionId) { workspace ->
            stageAttachments(call.providerMetadata?.get("editorAttachmentsJSON"), workspace)
            val target = resolve(args.path, workspace)
            val execution = execute(args, target, workspace, sessionId)
            ToolResult(
                callId = call.id,
                name = call.name,
                content = execution.content,
                artifacts = execution.artifact?.let(::listOf).orEmpty()
            )
        }
    }

    private data class Arguments(
        val command: String,
        val path: String,
        val fileText: String?,
        val oldString: String?,
        val newString: String?,
        val insertLine: Int?,
        val viewRange: List<Int>?
    )

    private data class Execution(val content: String, val artifact: ToolArtifact? = null)

    private fun decodeArguments(raw: String): Arguments {
        val objectValue = editorJson.parseToJsonElement(raw).jsonObject
        val command = objectValue["command"]?.jsonPrimitive?.contentOrNull
        val path = objectValue["path"]?.jsonPrimitive?.contentOrNull
        require(command != null && path != null) { "Parameters `command` and `path` are required." }
        val insertLine = objectValue["insert_line"]?.let {
            require(it.jsonPrimitive.intOrNull != null) { "Parameter `insert_line` must be an integer." }
            it.jsonPrimitive.intOrNull
        }
        val viewRange = objectValue["view_range"]?.jsonArray?.map { value ->
            require(value.jsonPrimitive.intOrNull != null) { "Invalid `view_range`. It should be a list of two integers." }
            value.jsonPrimitive.intOrNull!!
        }
        fun optional(name: String): String? = objectValue[name]?.jsonPrimitive?.contentOrNull
        return Arguments(
            command = command,
            path = path,
            fileText = optional("file_text"),
            oldString = optional("old_str"),
            newString = optional("new_str"),
            insertLine = insertLine,
            viewRange = viewRange
        )
    }

    private fun decodeAttachmentPaths(raw: String): List<String> =
        editorJson.parseToJsonElement(raw).jsonArray.mapNotNull { it.jsonPrimitive.contentOrNull }

    private suspend fun execute(args: Arguments, target: File, workspace: File, sessionId: String): Execution = when (args.command) {
        "view" -> Execution(view(target, args.path, args.viewRange))
        "create" -> {
            val text = args.fileText ?: error("Parameter `file_text` is required for command: create")
            require(!target.exists()) { "File already exists at: ${args.path}. Cannot overwrite files using command `create`." }
            require(target.parentFile?.isDirectory == true) { "The parent directory does not exist: ${args.path}" }
            mutate(target, args.path, workspace, text, create = true, sessionId)
        }
        "str_replace" -> {
            val old = required(args.oldString, "old_str", "str_replace", allowEmpty = false)
            val before = readRegularFile(target, args.path)
            val matches = literalOffsets(before, old)
            require(matches.isNotEmpty()) { "No replacement was performed, old_str `$old` did not appear verbatim in ${args.path}." }
            require(matches.size == 1) {
                val lines = matches.map { lineNumber(before, it) }
                "No replacement was performed. Multiple occurrences of old_str `$old` in lines [${lines.joinToString(", ")}]. Please ensure it is unique"
            }
            val offset = matches.single()
            mutate(target, args.path, workspace, before.substring(0, offset) + (args.newString ?: "") + before.substring(offset + old.length), false, sessionId)
        }
        "insert" -> {
            val insertLine = args.insertLine ?: error("Parameter `insert_line` is required for command: insert")
            val value = required(args.newString, "new_str", "insert")
            val before = readRegularFile(target, args.path)
            val separator = if (before.contains("\r\n")) "\r\n" else "\n"
            val lines = if (before.isEmpty()) emptyList() else before.split(separator)
            require(insertLine in 0..lines.size) { "Invalid `insert_line` parameter: $insertLine. It should be within the range of lines of the file: [0, ${lines.size}]" }
            val insertedLines = value.replace("\r\n", "\n").split('\n')
            val after = (lines.take(insertLine) + insertedLines + lines.drop(insertLine)).joinToString(separator)
            mutate(target, args.path, workspace, after, false, sessionId)
        }
        else -> error("Unsupported command: ${args.command}")
    }

    private fun resolve(virtualPath: String, workspace: File): File {
        require(virtualPath == "/workspace" || virtualPath.startsWith("/workspace/")) {
            "The path $virtualPath must be an absolute virtual path under `/workspace`."
        }
        val components = virtualPath.removePrefix("/workspace").split('/').filter { it.isNotEmpty() }
        require(components.size <= MAXIMUM_PATH_DEPTH && components.none { it == "." || it == ".." }) {
            "The path $virtualPath is outside the allowed workspace."
        }
        var current = workspace.canonicalFile
        components.forEach { component ->
            current = File(current, component)
            if (Files.isSymbolicLink(current.toPath())) error("Symbolic links are not allowed in the editor workspace: $virtualPath")
        }
        require(current.canonicalPath == workspace.canonicalPath || current.canonicalPath.startsWith(workspace.canonicalPath + File.separator)) {
            "The path $virtualPath is outside the allowed workspace."
        }
        return current
    }

    private fun view(target: File, virtualPath: String, range: List<Int>?): String {
        require(target.exists()) { "The path $virtualPath does not exist. Please provide a valid path." }
        if (target.isDirectory) {
            require(range == null) { "The `view_range` parameter is not allowed when `path` points to a directory." }
            return listDirectory(target, virtualPath)
        }
        val content = readRegularFile(target, virtualPath)
        val lines = content.split('\n')
        var start = 1
        var end = lines.size
        var suffix = ""
        if (range != null) {
            require(range.size == 2) { "Invalid `view_range`. It should be a list of two integers." }
            start = range[0]
            end = if (range[1] == -1) lines.size else range[1]
            require(start in 1..lines.size && end in start..lines.size) { "Invalid `view_range`: [${range.joinToString(", ")}] for a file with ${lines.size} lines." }
            suffix = " with view_range=[${range[0]}, ${range[1]}]"
        }
        val numbered = lines.subList(start - 1, end).mapIndexed { index, line -> "%6d  %s".format(start + index, line) }.joinToString("\n")
        return clip("Here's the content of $virtualPath with line numbers (which has a total of ${lines.size} lines)$suffix:\n$numbered\n")
    }

    private fun listDirectory(directory: File, virtualPath: String): String {
        val rows = mutableListOf("d\t$virtualPath")
        fun visit(current: File, virtual: String, depth: Int) {
            current.listFiles().orEmpty()
                .filter { !it.name.startsWith('.') && it.name != "node_modules" && it.name != "__pycache__" && !Files.isSymbolicLink(it.toPath()) }
                .forEach { entry ->
                    val child = "$virtual/${entry.name}"
                    rows += "${if (entry.isDirectory) "d" else if (entry.isFile) "f" else "?"}\t$child"
                    if (entry.isDirectory && depth < 2) visit(entry, child, depth + 1)
                }
        }
        visit(directory, virtualPath, 1)
        rows.sortBy { it.substringAfter('\t') }
        return clip("Here're the files and directories up to 2 levels deep in $virtualPath, excluding hidden items, node_modules, and Python cache directories:\n${rows.joinToString("\n")}\n")
    }

    private fun readRegularFile(target: File, virtualPath: String): String {
        require(target.isFile) { "The path $virtualPath is not a regular file." }
        require(target.length() <= MAXIMUM_FILE_BYTES) { "The file exceeds the $MAXIMUM_FILE_BYTES-byte limit." }
        val bytes = target.readBytes()
        return try {
            Charsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT).onUnmappableCharacter(CodingErrorAction.REPORT)
                .decode(java.nio.ByteBuffer.wrap(bytes)).toString()
        } catch (_: CharacterCodingException) {
            error("The file is not valid UTF-8 text: $virtualPath")
        }
    }

    private suspend fun mutate(target: File, virtualPath: String, workspace: File, content: String, create: Boolean, sessionId: String): Execution {
        val data = content.toByteArray(Charsets.UTF_8)
        validateQuota(workspace, target, data.size.toLong(), create)
        val mime = URLConnection.guessContentTypeFromName(target.name) ?: "application/octet-stream"
        val temporary = File(target.parentFile, ".yamabiko-editor-${UUID.randomUUID()}")
        try {
            Files.write(temporary.toPath(), data)
            if (create) {
                Files.move(temporary.toPath(), target.toPath(), StandardCopyOption.ATOMIC_MOVE)
            } else {
                Files.move(temporary.toPath(), target.toPath(), StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING)
            }
        } catch (error: Exception) {
            temporary.delete()
            throw error
        }
        val snapshot = attachments.persistGeneratedFileReplacingExisting(
            data,
            target.name,
            "Editor $sessionId",
            MAXIMUM_FILE_BYTES.toInt(),
        )
        return Execution(
            if (create) "New file created successfully at: $virtualPath" else "The file $virtualPath has been edited successfully.",
            ToolArtifact(snapshot.absolutePath, target.name, mime, data.size.toLong())
        )
    }

    private fun validateQuota(workspace: File, target: File, newSize: Long, create: Boolean) {
        require(newSize <= MAXIMUM_FILE_BYTES) { "The file exceeds the $MAXIMUM_FILE_BYTES-byte limit." }
        val files = workspace.walkTopDown().filter { it.isFile }.toList()
        val bytes = files.filterNot { it.canonicalFile == target.canonicalFile }.sumOf { it.length() }
        require((if (create) files.size + 1 else files.size) <= MAXIMUM_WORKSPACE_FILES && bytes + newSize <= MAXIMUM_WORKSPACE_BYTES) {
            "The editor workspace resource limit would be exceeded."
        }
    }

    private fun stageAttachments(raw: String?, workspace: File) {
        if (raw.isNullOrBlank()) return
        val paths = runCatching { decodeAttachmentPaths(raw) }.getOrNull() ?: return
        val root = File(workspace, "attachments")
        if (!root.exists() && !root.mkdirs()) throw IOException("Could not create attachment workspace.")
        for (path in paths) {
            val source = File(path)
            if (!source.isFile) continue
            val bytes = source.readBytes()
            require(bytes.size.toLong() <= MAXIMUM_FILE_BYTES) { "An attachment exceeds the editor file limit: ${source.name}" }
            val directory = File(root, EditorWorkspaceStore.sha256(bytes))
            if (!directory.exists() && !directory.mkdirs()) throw IOException("Could not stage editor attachment.")
            val safeName = source.name.replace(Regex("[^A-Za-z0-9._-]+"), "_").ifEmpty { "attachment" }
            val destination = File(directory, safeName)
            if (!destination.exists()) {
                validateQuota(workspace, destination, bytes.size.toLong(), create = true)
                val temporary = File(directory, ".yamabiko-editor-${UUID.randomUUID()}")
                try {
                    Files.write(temporary.toPath(), bytes)
                    Files.move(temporary.toPath(), destination.toPath(), StandardCopyOption.ATOMIC_MOVE)
                } catch (error: Exception) {
                    temporary.delete()
                    throw error
                }
            }
        }
    }

    private fun required(value: String?, name: String, command: String, allowEmpty: Boolean = true): String {
        require(value != null) { "Parameter `$name` is required for command: $command" }
        require(allowEmpty || value.isNotEmpty()) { "Parameter `$name` is empty for command: $command" }
        return value
    }

    private fun literalOffsets(content: String, search: String): List<Int> {
        val offsets = mutableListOf<Int>()
        var offset = 0
        while (true) {
            val match = content.indexOf(search, offset)
            if (match < 0) return offsets
            offsets += match
            offset = match + search.length
        }
    }

    private fun lineNumber(content: String, offset: Int) = 1 + content.substring(0, offset).count { it == '\n' }

    private fun clip(value: String): String = if (value.length <= MAXIMUM_OUTPUT_CHARACTERS) value
        else value.take(MAXIMUM_OUTPUT_CHARACTERS) + "<response clipped><NOTE>To save on context only part of this output has been shown.</NOTE>"

    companion object {
        private val editorJson = Json { ignoreUnknownKeys = true; isLenient = false }
        const val NAME = "str_replace_editor"
        const val MAXIMUM_OUTPUT_CHARACTERS = 16_000
        const val MAXIMUM_FILE_BYTES = 25L * 1_024 * 1_024
        const val MAXIMUM_WORKSPACE_BYTES = 100L * 1_024 * 1_024
        const val MAXIMUM_WORKSPACE_FILES = 1_024
        const val MAXIMUM_PATH_DEPTH = 16
    }
}

package com.porarri.yamabikochat.data.skills

import android.content.Context
import android.net.Uri
import androidx.documentfile.provider.DocumentFile
import com.porarri.yamabikochat.utils.DiagnosticsLogger
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import org.snakeyaml.engine.v2.api.Load
import org.snakeyaml.engine.v2.api.LoadSettings
import java.io.BufferedInputStream
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.RandomAccessFile
import java.nio.charset.CodingErrorAction
import java.nio.charset.Charset
import java.nio.charset.StandardCharsets
import java.security.MessageDigest
import java.util.UUID
import java.util.zip.ZipInputStream

class AgentSkillRepository(private val context: Context, private val root: File = File(context.filesDir, "AgentSkills")) {
    @Serializable
    private data class PersistedState(val isEnabled: Boolean, val installedAtEpochMs: Long, val contentHash: String)

    private val json = Json { prettyPrint = true; ignoreUnknownKeys = true }
    private val _installedSkills = MutableStateFlow<List<InstalledAgentSkill>>(emptyList())
    val installedSkills: StateFlow<List<InstalledAgentSkill>> = _installedSkills.asStateFlow()
    val enabledSkills: List<InstalledAgentSkill> get() = _installedSkills.value.filter { it.isEnabled }
    private val preferences = context.getSharedPreferences("agent_skills", Context.MODE_PRIVATE)

    var openAIHostedExecutionEnabled: Boolean
        get() = preferences.getBoolean("openai_hosted_execution", false)
        set(value) { preferences.edit().putBoolean("openai_hosted_execution", value).apply() }

    init { root.mkdirs(); reload() }

    @Synchronized
    fun inspect(uri: Uri): AgentSkillInstallPreview {
        val staging = File(context.cacheDir, "agent-skill-${UUID.randomUUID()}").apply { mkdirs() }
        val extracted = File(staging, "extracted").apply { mkdirs() }
        try {
            val document = DocumentFile.fromSingleUri(context, uri) ?: DocumentFile.fromTreeUri(context, uri)
                ?: throw AgentSkillException("選択したSkillを読み込めません。")
            if (document.isDirectory) copyDocumentFolder(document, extracted) else {
                val zip = File(staging, "source.zip")
                context.contentResolver.openInputStream(uri)?.use { input ->
                    FileOutputStream(zip).use { output -> input.copyToLimited(output, AgentSkillLimits.ARCHIVE_BYTES) }
                } ?: throw AgentSkillException("ZIPを開けません。")
                extractZip(zip, extracted)
            }
            val skillRoot = locateSkillRoot(extracted)
            val parsed = parseAndInventory(skillRoot)
            val canonical = File(staging, "skill")
            if (!skillRoot.renameTo(canonical)) {
                skillRoot.copyRecursively(canonical, overwrite = false)
                skillRoot.deleteRecursively()
            }
            return AgentSkillInstallPreview(
                parsed.manifest, parsed.files, parsed.files.any { it.isScript }, parsed.hash,
                parsed.externalUrls, File(root, parsed.manifest.name).exists(), canonical
            )
        } catch (error: Exception) {
            staging.deleteRecursively()
            throw error
        }
    }

    @Synchronized
    fun inspect(file: File): AgentSkillInstallPreview {
        if (file.isDirectory) {
            val staging = File(context.cacheDir, "agent-skill-${UUID.randomUUID()}").apply { mkdirs() }
            val extracted = File(staging, "extracted").apply { mkdirs() }
            try {
                copyFolder(file, extracted)
                val skillRoot = locateSkillRoot(extracted)
                val parsed = parseAndInventory(skillRoot)
                val canonical = File(staging, "skill")
                check(skillRoot.renameTo(canonical) || skillRoot.copyRecursively(canonical))
                return AgentSkillInstallPreview(parsed.manifest, parsed.files, parsed.files.any { it.isScript }, parsed.hash, parsed.externalUrls, File(root, parsed.manifest.name).exists(), canonical)
            } catch (error: Exception) { staging.deleteRecursively(); throw error }
        }
        val staging = File(context.cacheDir, "agent-skill-${UUID.randomUUID()}").apply { mkdirs() }
        val extracted = File(staging, "extracted").apply { mkdirs() }
        try {
            extractZip(file, extracted)
            val skillRoot = locateSkillRoot(extracted)
            val parsed = parseAndInventory(skillRoot)
            val canonical = File(staging, "skill")
            check(skillRoot.renameTo(canonical) || skillRoot.copyRecursively(canonical))
            return AgentSkillInstallPreview(parsed.manifest, parsed.files, parsed.files.any { it.isScript }, parsed.hash, parsed.externalUrls, File(root, parsed.manifest.name).exists(), canonical)
        } catch (error: Exception) { staging.deleteRecursively(); throw error }
    }

    @Synchronized
    fun install(preview: AgentSkillInstallPreview, trusted: Boolean, allowReplacement: Boolean): InstalledAgentSkill {
        if (!trusted) throw AgentSkillException("Skillの内容と危険性を確認し、信頼する操作が必要です。")
        val destination = File(root, preview.manifest.name)
        val existing = _installedSkills.value.firstOrNull { it.manifest.name == preview.manifest.name }
        if (existing != null && !allowReplacement) throw AgentSkillException("同名のSkillがあります。置換の確認が必要です。")
        val state = PersistedState(existing?.isEnabled ?: true, System.currentTimeMillis(), preview.contentHash)
        File(preview.stagedRoot, "state.json").writeText(json.encodeToString(state), Charsets.UTF_8)
        val backup = File(root, ".${preview.manifest.name}.backup-${UUID.randomUUID()}")
        if (destination.exists() && !destination.renameTo(backup)) throw AgentSkillException("既存Skillを安全に退避できません。")
        try {
            if (!preview.stagedRoot.renameTo(destination)) throw AgentSkillException("Skillを原子的に配置できません。")
            backup.deleteRecursively()
        } catch (error: Exception) {
            destination.deleteRecursively()
            if (backup.exists()) backup.renameTo(destination)
            throw error
        } finally { preview.stagedRoot.parentFile?.deleteRecursively() }
        reload()
        DiagnosticsLogger.log("Agent Skill installed skill=${preview.manifest.name}")
        return _installedSkills.value.first { it.manifest.name == preview.manifest.name }
    }

    fun discard(preview: AgentSkillInstallPreview) { preview.stagedRoot.parentFile?.deleteRecursively() }

    @Synchronized
    fun setEnabled(name: String, enabled: Boolean) {
        val skill = _installedSkills.value.firstOrNull { it.manifest.name == name } ?: throw AgentSkillException("Skillが見つかりません: $name")
        File(root, name).resolve("state.json").writeText(json.encodeToString(PersistedState(enabled, skill.installedAtEpochMs, skill.contentHash)))
        reload()
        DiagnosticsLogger.log("Agent Skill enabled state changed skill=$name enabled=$enabled")
    }

    @Synchronized
    fun delete(name: String) {
        val directory = File(root, name)
        if (!directory.exists()) throw AgentSkillException("Skillが見つかりません: $name")
        if (!directory.deleteRecursively()) throw AgentSkillException("Skillを削除できません: $name")
        reload()
        DiagnosticsLogger.log("Agent Skill deleted skill=$name")
    }

    fun requestContext(text: String, conversationId: String?): SkillRequestContext? {
        val enabled = enabledSkills
        if (enabled.isEmpty()) return null
        val names = explicitSkillNames(text, enabled.map { it.manifest.name }.toSet())
        return SkillRequestContext(
            catalog = enabled.map { AgentSkillCatalogEntry(it.manifest.name, it.manifest.description) },
            explicitlyRequestedNames = names,
            explicitInstructions = names.map(::skillInstructions),
            resourceLists = names.map { resourcePaths(it).joinToString("\n") },
            conversationId = conversationId,
            enabledSkillSetHash = sha256(enabled.map { "${it.manifest.name}:${it.contentHash}" }.sorted().joinToString("\n").toByteArray()),
            hostedExecutionEnabled = openAIHostedExecutionEnabled
        )
    }

    fun skillInstructions(name: String): String {
        requireEnabled(name)
        return readUtf8(File(root, name).resolve("SKILL.md"), AgentSkillLimits.SKILL_FILE_BYTES)
    }

    fun resourcePaths(name: String): List<String> = requireEnabled(name).files.map { it.path }.filter { it != "SKILL.md" && it != "state.json" }

    fun readResource(name: String, rawPath: String): String {
        requireEnabled(name)
        val path = normalizedPath(rawPath)
        if (path == "SKILL.md" || path == "state.json") throw AgentSkillException("このファイルは資料APIから読み込めません。")
        val skillRoot = File(root, name).canonicalFile
        val target = File(skillRoot, path).canonicalFile
        if (!target.path.startsWith(skillRoot.path + File.separator)) throw AgentSkillException("Skill外のパスは読み込めません。")
        return readUtf8(target, AgentSkillLimits.TEXT_RESOURCE_BYTES)
    }

    fun enabledSkillRoot(name: String): File { requireEnabled(name); return File(root, name) }

    @Synchronized
    private fun reload() {
        _installedSkills.value = root.listFiles()?.filter { it.isDirectory && !it.name.startsWith(".") }?.mapNotNull { directory ->
            runCatching {
                val parsed = parseAndInventory(directory)
                val state = json.decodeFromString<PersistedState>(File(directory, "state.json").readText())
                if (state.contentHash != parsed.hash) return@runCatching null
                InstalledAgentSkill(parsed.manifest, parsed.files, parsed.files.any { it.isScript }, parsed.hash, state.isEnabled, state.installedAtEpochMs)
            }.getOrNull()
        }?.filterNotNull()?.sortedBy { it.manifest.name }.orEmpty()
    }

    private data class Parsed(val manifest: AgentSkillManifest, val files: List<AgentSkillFile>, val hash: String, val externalUrls: List<String>)

    private fun parseAndInventory(directory: File): Parsed {
        val markdown = readUtf8(File(directory, "SKILL.md"), AgentSkillLimits.SKILL_FILE_BYTES)
        val manifest = parseManifest(markdown)
        val urls = linkedSetOf<String>()
        val entries = directory.walkTopDown().drop(1).onEach { file ->
            if (isSymbolicLink(file)) throw AgentSkillException("シンボリックリンクは使用できません: ${file.name}")
        }
        val files = entries.filter { it.isFile && it.name != "state.json" }.map { file ->
            val relative = file.relativeTo(directory).invariantSeparatorsPath
            if (file.length() <= AgentSkillLimits.TEXT_RESOURCE_BYTES) runCatching { readUtf8(file, AgentSkillLimits.TEXT_RESOURCE_BYTES) }.getOrNull()?.let { text ->
                Regex("https?://[^\\s)\\]>\"']+").findAll(text).forEach { urls += it.value }
            }
            AgentSkillFile(relative, file.length(), isScript(relative, file))
        }.toList().sortedBy { it.path }
        val hash = sha256(files.joinToString("\n") { file -> "${file.path}:${sha256(File(directory, file.path).readBytes())}" }.toByteArray())
        return Parsed(manifest, files, hash, urls.sorted())
    }

    @Suppress("UNCHECKED_CAST")
    private fun parseManifest(markdown: String): AgentSkillManifest {
        val lines = markdown.lines()
        if (lines.firstOrNull()?.trim() != "---") throw AgentSkillException("SKILL.mdのYAMLフロントマターがありません。")
        val end = lines.drop(1).indexOfFirst { it.trim() == "---" }.takeIf { it >= 0 }?.plus(1)
            ?: throw AgentSkillException("SKILL.mdのYAMLフロントマターが閉じられていません。")
        val raw = runCatching { Load(LoadSettings.builder().build()).loadFromString(lines.subList(1, end).joinToString("\n")) as? Map<*, *> }
            .getOrElse { throw AgentSkillException("YAMLを解析できません: ${it.message}") }
            ?: throw AgentSkillException("フロントマターはマップ形式で記述してください。")
        val name = raw["name"] as? String
        if (name == null || !Regex("^[a-z0-9][a-z0-9-]{0,63}$").matches(name)) throw AgentSkillException("nameは小文字英数字とハイフンで1〜64文字にしてください。")
        val description = (raw["description"] as? String)?.trim().orEmpty()
        if (description.isEmpty()) throw AgentSkillException("descriptionは必須です。")
        val metadata = (raw["metadata"] as? Map<*, *>)?.entries?.associate { it.key.toString() to it.value.toString() }.orEmpty()
        val allowed = when (val value = raw["allowed-tools"]) {
            is List<*> -> value.map { it.toString() }
            is String -> value.split(Regex("\\s+")).filter { it.isNotBlank() }
            else -> emptyList()
        }
        return AgentSkillManifest(name, description, raw["license"]?.toString(), raw["compatibility"]?.toString(), metadata, allowed)
    }

    private fun extractZip(zip: File, destination: File) {
        if (zip.length() > AgentSkillLimits.ARCHIVE_BYTES) throw AgentSkillException("ZIPは50 MB以下にしてください。")
        val centralPaths = validateZipCentralDirectory(zip).toMutableSet()
        val seen = mutableSetOf<String>()
        var count = 0
        var total = 0L
        ZipInputStream(BufferedInputStream(FileInputStream(zip))).use { input ->
            while (true) {
                val entry = input.nextEntry ?: break
                val path = normalizedPath(entry.name)
                if (!centralPaths.remove(path)) throw AgentSkillException("ZIPの中央ディレクトリと展開エントリが一致しません: $path")
                if (!seen.add(path)) throw AgentSkillException("重複パスがあります: $path")
                val target = File(destination, path)
                if (!target.canonicalPath.startsWith(destination.canonicalPath + File.separator)) throw AgentSkillException("安全でないパスです: $path")
                if (entry.isDirectory) target.mkdirs() else {
                    count++
                    if (count > AgentSkillLimits.FILE_COUNT) throw AgentSkillException("ファイル数は500以下にしてください。")
                    target.parentFile?.mkdirs()
                    FileOutputStream(target).use { output ->
                        val written = input.copyToLimited(output, AgentSkillLimits.SINGLE_FILE_BYTES)
                        total += written
                        if (total > AgentSkillLimits.EXPANDED_BYTES) throw AgentSkillException("展開後合計は200 MB以下にしてください。")
                    }
                }
                input.closeEntry()
            }
        }
        if (centralPaths.isNotEmpty()) throw AgentSkillException("ZIPの全エントリを安全に展開できませんでした。")
    }

    private fun validateZipCentralDirectory(zip: File): Set<String> {
        RandomAccessFile(zip, "r").use { file ->
            val length = file.length()
            if (length < 22) throw AgentSkillException("ZIPが壊れています。")
            val tailLength = minOf(length, 65_557L).toInt()
            val tail = ByteArray(tailLength)
            file.seek(length - tailLength)
            file.readFully(tail)
            var eocd = tail.size - 22
            while (eocd >= 0 && littleUInt(tail, eocd) != 0x06054b50L) eocd--
            if (eocd < 0) throw AgentSkillException("ZIPの終端レコードが見つかりません。")
            val disk = littleUShort(tail, eocd + 4)
            val centralDisk = littleUShort(tail, eocd + 6)
            val diskEntries = littleUShort(tail, eocd + 8)
            val totalEntries = littleUShort(tail, eocd + 10)
            val centralSize = littleUInt(tail, eocd + 12)
            val centralOffset = littleUInt(tail, eocd + 16)
            if (disk != 0 || centralDisk != 0 || diskEntries != totalEntries) throw AgentSkillException("分割ZIPは使用できません。")
            if (totalEntries == 0xffff || centralSize == 0xffffffffL || centralOffset == 0xffffffffL) throw AgentSkillException("ZIP64形式は使用できません。")
            if (centralOffset + centralSize > length) throw AgentSkillException("ZIPの中央ディレクトリが壊れています。")

            val paths = linkedSetOf<String>()
            file.seek(centralOffset)
            repeat(totalEntries) {
                val fixed = ByteArray(46)
                file.readFully(fixed)
                if (littleUInt(fixed, 0) != 0x02014b50L) throw AgentSkillException("ZIPの中央ディレクトリが壊れています。")
                val versionMadeBy = littleUShort(fixed, 4)
                val flags = littleUShort(fixed, 8)
                if ((flags and 1) != 0) throw AgentSkillException("暗号化ZIPは使用できません。")
                val nameLength = littleUShort(fixed, 28)
                val extraLength = littleUShort(fixed, 30)
                val commentLength = littleUShort(fixed, 32)
                val externalAttributes = littleUInt(fixed, 38)
                val nameBytes = ByteArray(nameLength)
                file.readFully(nameBytes)
                val charset = if ((flags and (1 shl 11)) != 0) Charsets.UTF_8 else Charset.forName("CP437")
                val path = normalizedPath(String(nameBytes, charset))
                if (!paths.add(path)) throw AgentSkillException("重複パスがあります: $path")
                val hostSystem = versionMadeBy ushr 8
                if (hostSystem == 3) {
                    val mode = (externalAttributes ushr 16).toInt()
                    val fileType = mode and 0xF000
                    if (fileType == 0xA000) throw AgentSkillException("シンボリックリンクは使用できません: $path")
                    if (fileType != 0 && fileType != 0x8000 && fileType != 0x4000) throw AgentSkillException("特殊ファイルは使用できません: $path")
                }
                file.seek(file.filePointer + extraLength + commentLength)
            }
            return paths
        }
    }

    private fun littleUShort(bytes: ByteArray, offset: Int): Int =
        (bytes[offset].toInt() and 0xff) or ((bytes[offset + 1].toInt() and 0xff) shl 8)

    private fun littleUInt(bytes: ByteArray, offset: Int): Long =
        littleUShort(bytes, offset).toLong() or (littleUShort(bytes, offset + 2).toLong() shl 16)

    private fun copyDocumentFolder(source: DocumentFile, destination: File) {
        var count = 0; var total = 0L
        fun visit(document: DocumentFile, directory: File) {
            document.listFiles().forEach { child ->
                val name = normalizedPath(child.name ?: throw AgentSkillException("名前のないファイルは取り込めません。"))
                val target = File(directory, name)
                if (child.isDirectory) { target.mkdirs(); visit(child, target) }
                else {
                    count++; if (count > AgentSkillLimits.FILE_COUNT) throw AgentSkillException("ファイル数は500以下にしてください。")
                    target.parentFile?.mkdirs()
                    context.contentResolver.openInputStream(child.uri)?.use { input -> FileOutputStream(target).use { total += input.copyToLimited(it, AgentSkillLimits.SINGLE_FILE_BYTES) } }
                        ?: throw AgentSkillException("ファイルを読み込めません: $name")
                    if (total > AgentSkillLimits.EXPANDED_BYTES) throw AgentSkillException("合計は200 MB以下にしてください。")
                }
            }
        }
        visit(source, destination)
    }

    private fun copyFolder(source: File, destination: File) {
        var count = 0; var total = 0L
        source.walkTopDown().drop(1).forEach { file ->
            if (isSymbolicLink(file)) throw AgentSkillException("シンボリックリンクは使用できません。")
            val target = File(destination, file.relativeTo(source).invariantSeparatorsPath)
            if (file.isDirectory) target.mkdirs() else {
                count++; total += file.length()
                if (count > AgentSkillLimits.FILE_COUNT || file.length() > AgentSkillLimits.SINGLE_FILE_BYTES || total > AgentSkillLimits.EXPANDED_BYTES) throw AgentSkillException("Skillがサイズ上限を超えています。")
                target.parentFile?.mkdirs(); file.copyTo(target)
            }
        }
    }

    /**
     * java.nio.file.Files.isSymbolicLink is API 26+, while the app supports API 24.
     * Comparing the lexical entry with its canonical target detects a link without
     * following it into the copied or inventoried Skill tree.
     */
    private fun isSymbolicLink(file: File): Boolean {
        val lexicalEntry = file.parentFile?.canonicalFile?.let { File(it, file.name) } ?: file.absoluteFile
        return lexicalEntry.absoluteFile != lexicalEntry.canonicalFile
    }

    private fun locateSkillRoot(extracted: File): File {
        val matches = extracted.walkTopDown().filter { it.isFile && it.name == "SKILL.md" }.take(2).toList()
        if (matches.size != 1) throw AgentSkillException(if (matches.isEmpty()) "SKILL.mdがありません。" else "複数のSKILL.mdはインストールできません。")
        return matches.single().parentFile!!
    }

    private fun requireEnabled(name: String) = enabledSkills.firstOrNull { it.manifest.name == name } ?: throw AgentSkillException("有効なSkillが見つかりません: $name")

    private fun readUtf8(file: File, limit: Long): String {
        if (!file.exists()) throw AgentSkillException("ファイルが見つかりません: ${file.name}")
        if (file.length() > limit) throw AgentSkillException("ファイルが読込上限を超えています: ${file.name}")
        val bytes = file.readBytes()
        if (bytes.any { it == 0.toByte() }) throw AgentSkillException("UTF-8テキスト資料だけを読み込めます: ${file.name}")
        return try { StandardCharsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT).onUnmappableCharacter(CodingErrorAction.REPORT).decode(java.nio.ByteBuffer.wrap(bytes)).toString() }
        catch (_: Exception) { throw AgentSkillException("UTF-8テキスト資料だけを読み込めます: ${file.name}") }
    }

    private fun normalizedPath(raw: String): String {
        val value = raw.replace('\\', '/')
        if (value.isBlank() || value.startsWith('/') || value.startsWith('~') || Regex("^[A-Za-z]:/").containsMatchIn(value)) throw AgentSkillException("絶対パスは使用できません: $raw")
        val parts = value.split('/').filter { it.isNotEmpty() }
        if (parts.isEmpty() || parts.any { it == "." || it == ".." }) throw AgentSkillException("安全でないパスです: $raw")
        return parts.joinToString("/")
    }

    private fun isScript(path: String, file: File): Boolean = path.substringAfterLast('.', "").lowercase() in setOf("sh", "bash", "zsh", "fish", "py", "rb", "pl", "js", "mjs", "cjs", "ts", "ps1", "bat", "cmd", "exe") || file.inputStream().bufferedReader().use { it.readLine()?.startsWith("#!") == true }

    companion object {
        fun explicitSkillNames(text: String, allowed: Set<String>): List<String> {
            val seen = linkedSetOf<String>()
            Regex("(?<![A-Za-z0-9_-])\\$([a-z0-9][a-z0-9-]{0,63})(?![A-Za-z0-9_-])").findAll(text).forEach { match ->
                match.groupValues[1].takeIf { it in allowed }?.let(seen::add)
            }
            return seen.toList()
        }

        private fun sha256(bytes: ByteArray): String = MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }

        private fun java.io.InputStream.copyToLimited(output: java.io.OutputStream, limit: Long): Long {
            val buffer = ByteArray(DEFAULT_BUFFER_SIZE); var total = 0L
            while (true) { val read = read(buffer); if (read < 0) break; total += read; if (total > limit) throw AgentSkillException("ファイルがサイズ上限を超えています。"); output.write(buffer, 0, read) }
            return total
        }
    }
}

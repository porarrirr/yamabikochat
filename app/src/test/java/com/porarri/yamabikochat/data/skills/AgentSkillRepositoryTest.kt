package com.porarri.yamabikochat.data.skills

import android.content.Context
import android.content.SharedPreferences
import com.porarri.yamabikochat.data.fusion.FusionPhase
import com.porarri.yamabikochat.data.fusion.FusionService
import com.porarri.yamabikochat.data.fusion.PanelModelConfig
import com.porarri.yamabikochat.data.local.Settings
import io.mockk.every
import io.mockk.mockk
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.assertThrows
import org.junit.Before
import org.junit.Test
import java.io.File
import java.nio.file.Files
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

class AgentSkillRepositoryTest {
    private lateinit var temporaryRoot: File
    private lateinit var repository: AgentSkillRepository

    @Before
    fun setUp() {
        temporaryRoot = Files.createTempDirectory("agent-skill-tests").toFile()
        val preferences = mockk<SharedPreferences>(relaxed = true)
        every { preferences.getBoolean(any(), any()) } returns false
        val context = mockk<Context>(relaxed = true)
        every { context.filesDir } returns File(temporaryRoot, "files").apply { mkdirs() }
        every { context.cacheDir } returns File(temporaryRoot, "cache").apply { mkdirs() }
        every { context.getSharedPreferences(any(), any()) } returns preferences
        repository = AgentSkillRepository(context, File(temporaryRoot, "installed"))
    }

    @After
    fun tearDown() {
        temporaryRoot.deleteRecursively()
    }

    @Test
    fun manifestInventoryInstallAndExplicitOrder() {
        val source = makeSkill(
            name = "review-helper",
            descriptionYaml = ">\n  Review changes carefully\n  and report risks.",
            extraFrontMatter = """
                license: MIT
                compatibility: Requires git
                allowed-tools:
                  - shell
                  - read
                metadata:
                  author: Example
            """.trimIndent(),
            extraFiles = mapOf(
                "references/checklist.md" to "Check every edge case.",
                "scripts/audit.py" to "#!/usr/bin/env python3\nprint('never run locally')"
            )
        )

        val preview = repository.inspect(source)
        assertEquals("review-helper", preview.manifest.name)
        assertTrue(preview.manifest.description.contains("Review changes carefully"))
        assertEquals(listOf("shell", "read"), preview.manifest.allowedTools)
        assertEquals("Example", preview.manifest.metadata["author"])
        assertTrue(preview.hasScripts)
        assertEquals(listOf("SKILL.md", "references/checklist.md", "scripts/audit.py"), preview.files.map { it.path })
        assertThrows(AgentSkillException::class.java) {
            repository.install(preview, trusted = false, allowReplacement = false)
        }

        repository.install(preview, trusted = true, allowReplacement = false)
        val context = requireNotNull(repository.requestContext(
            "${'$'}review-helper then ${'$'}review-helper and ${'$'}unknown",
            "conversation-42"
        ))
        assertEquals(listOf("review-helper"), context.explicitlyRequestedNames)
        assertEquals(listOf("review-helper"), context.catalog.map { it.name })
        assertTrue(context.explicitInstructions.single().contains("Follow these instructions"))
        assertEquals("Check every edge case.", repository.readResource("review-helper", "references/checklist.md"))
        assertThrows(AgentSkillException::class.java) {
            repository.readResource("review-helper", "../outside.txt")
        }
    }

    @Test
    fun enabledStatePersistsAcrossReplacementAndReload() {
        repository.install(repository.inspect(makeSkill("stable-skill")), trusted = true, allowReplacement = false)
        repository.setEnabled("stable-skill", false)
        val replacement = repository.inspect(makeSkill("stable-skill", extraFiles = mapOf("new.md" to "replacement")))
        assertTrue(replacement.replacesExisting)
        repository.install(replacement, trusted = true, allowReplacement = true)
        assertFalse(repository.installedSkills.value.single().isEnabled)

        val reloaded = AgentSkillRepository(
            context = mockContext(),
            root = File(temporaryRoot, "installed")
        )
        assertFalse(reloaded.installedSkills.value.single().isEnabled)
        reloaded.delete("stable-skill")
        assertTrue(reloaded.installedSkills.value.isEmpty())
    }

    @Test
    fun rejectsMultipleSkillFilesSymlinksAndInvalidNames() {
        val multiple = makeSkill("multiple")
        File(multiple, "nested").mkdirs()
        File(multiple, "nested/SKILL.md").writeText("---\nname: nested\ndescription: nested\n---\n")
        assertThrows(AgentSkillException::class.java) { repository.inspect(multiple) }

        val linked = makeSkill("linked")
        val outside = File(temporaryRoot, "outside.txt").apply { writeText("outside") }
        Files.createSymbolicLink(File(linked, "escape.txt").toPath(), outside.toPath())
        assertThrows(AgentSkillException::class.java) { repository.inspect(linked) }

        assertThrows(AgentSkillException::class.java) { repository.inspect(makeSkill("Invalid_Name")) }
    }

    @Test
    fun validatesZipCentralDirectoryAndRejectsZipSlipAndSymlinkEntries() {
        val valid = makeZip("valid.zip", mapOf(
            "zip-skill/SKILL.md" to "---\nname: zip-skill\ndescription: zip import\n---\nUse zip.",
            "zip-skill/reference.md" to "reference"
        ))
        assertEquals("zip-skill", repository.inspect(valid).manifest.name)

        val slip = makeZip("slip.zip", mapOf(
            "../escape/SKILL.md" to "---\nname: escape\ndescription: bad\n---\n"
        ))
        assertThrows(AgentSkillException::class.java) { repository.inspect(slip) }

        val link = makeZip("link.zip", mapOf(
            "linked-zip/SKILL.md" to "---\nname: linked-zip\ndescription: linked\n---\n",
            "linked-zip/escape" to "../../outside"
        ))
        markCentralEntryAsUnixSymlink(link, "linked-zip/escape")
        assertThrows(AgentSkillException::class.java) { repository.inspect(link) }
    }

    @Test
    fun fusionOnlyInjectsSkillsIntoPanelRequests() = runBlocking {
        repository.install(repository.inspect(makeSkill("fusion-skill")), trusted = true, allowReplacement = false)
        val resolver = com.porarri.yamabikochat.data.repositories.ProviderRequestSettingsResolver(
            modelService = mockk(relaxed = true),
            skillRepository = repository
        )
        val service = FusionService(
            settingsProvider = { Settings() },
            providerGateway = mockk(relaxed = true),
            requestSettingsResolver = resolver,
            skillRepository = repository
        )
        val model = PanelModelConfig(modelId = "gpt-5.6", provider = "OPENAI")
        val panel = service.buildProviderRequest(
            model = model,
            systemPrompt = "panel",
            phase = FusionPhase.panel,
            allowTools = false,
            settings = Settings(),
            fusionDepth = 0,
            userPrompt = "Use \$fusion-skill",
            conversationHistory = emptyList(),
            conversationId = "42"
        )
        val judge = service.buildProviderRequest(
            model = model,
            systemPrompt = "judge",
            phase = FusionPhase.judge,
            allowTools = false,
            settings = Settings(),
            fusionDepth = 0,
            userPrompt = "Use \$fusion-skill",
            conversationHistory = emptyList(),
            conversationId = "42"
        )

        assertTrue(panel.messages.single().content.contains("<available_agent_skills>"))
        assertTrue(panel.tools.any { it.payload["name"] == AgentSkillTools.ACTIVATE })
        assertFalse(judge.messages.any { it.content.contains("<available_agent_skills>") })
        assertTrue(judge.tools.none { it.payload["name"] == AgentSkillTools.ACTIVATE })
    }

    private fun mockContext(): Context {
        val preferences = mockk<SharedPreferences>(relaxed = true)
        every { preferences.getBoolean(any(), any()) } returns false
        return mockk<Context>(relaxed = true).also { context ->
            every { context.filesDir } returns File(temporaryRoot, "files").apply { mkdirs() }
            every { context.cacheDir } returns File(temporaryRoot, "cache").apply { mkdirs() }
            every { context.getSharedPreferences(any(), any()) } returns preferences
        }
    }

    private fun makeSkill(
        name: String,
        descriptionYaml: String = "A test skill",
        extraFrontMatter: String = "",
        extraFiles: Map<String, String> = emptyMap()
    ): File {
        val source = File(temporaryRoot, "source-${java.util.UUID.randomUUID()}").apply { mkdirs() }
        File(source, "SKILL.md").writeText(
            "---\nname: $name\ndescription: $descriptionYaml\n" +
                extraFrontMatter +
                "\n---\nFollow these instructions for $name.\n"
        )
        extraFiles.forEach { (path, content) ->
            File(source, path).apply { parentFile?.mkdirs(); writeText(content) }
        }
        return source
    }

    private fun makeZip(filename: String, entries: Map<String, String>): File {
        val zipFile = File(temporaryRoot, filename)
        ZipOutputStream(zipFile.outputStream()).use { zip ->
            entries.forEach { (path, content) ->
                zip.putNextEntry(ZipEntry(path))
                zip.write(content.toByteArray())
                zip.closeEntry()
            }
        }
        return zipFile
    }

    private fun markCentralEntryAsUnixSymlink(zip: File, targetName: String) {
        val bytes = zip.readBytes()
        var offset = 0
        while (offset <= bytes.size - 46) {
            if (u32(bytes, offset) != 0x02014b50L) {
                offset++
                continue
            }
            val nameLength = u16(bytes, offset + 28)
            val extraLength = u16(bytes, offset + 30)
            val commentLength = u16(bytes, offset + 32)
            val name = String(bytes, offset + 46, nameLength, Charsets.UTF_8)
            if (name == targetName) {
                bytes[offset + 4] = 20
                bytes[offset + 5] = 3
                val attributes = 0xA1FF0000L
                repeat(4) { index -> bytes[offset + 38 + index] = ((attributes ushr (index * 8)) and 0xff).toByte() }
                zip.writeBytes(bytes)
                return
            }
            offset += 46 + nameLength + extraLength + commentLength
        }
        error("Central directory entry not found: $targetName")
    }

    private fun u16(bytes: ByteArray, offset: Int): Int =
        (bytes[offset].toInt() and 0xff) or ((bytes[offset + 1].toInt() and 0xff) shl 8)

    private fun u32(bytes: ByteArray, offset: Int): Long =
        u16(bytes, offset).toLong() or (u16(bytes, offset + 2).toLong() shl 16)
}

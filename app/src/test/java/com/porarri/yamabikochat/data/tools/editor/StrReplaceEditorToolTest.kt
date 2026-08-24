package com.porarri.yamabikochat.data.tools.editor

import com.porarri.yamabikochat.data.attachments.AttachmentStorage
import com.porarri.yamabikochat.data.model.ToolCall
import io.mockk.coEvery
import io.mockk.mockk
import java.io.File
import java.nio.file.Files
import java.util.UUID
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.Json
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Before
import org.junit.Test

class StrReplaceEditorToolTest {
    private lateinit var root: File
    private lateinit var artifacts: File
    private lateinit var storage: AttachmentStorage
    private lateinit var tool: StrReplaceEditorTool

    @Before
    fun setUp() {
        root = Files.createTempDirectory("editor-workspaces-").toFile()
        artifacts = Files.createTempDirectory("editor-artifacts-").toFile()
        storage = mockk()
        coEvery { storage.persistGeneratedFileReplacingExisting(any(), any(), any(), any()) } coAnswers {
            val destination = File(artifacts, secondArg<String>())
            destination.writeBytes(firstArg())
            destination
        }
        coEvery { storage.deleteGeneratedFile(any()) } coAnswers {
            firstArg<File>().delete()
            Unit
        }
        tool = StrReplaceEditorTool(EditorWorkspaceStore(root), storage)
    }

    @After
    fun tearDown() {
        root.deleteRecursively()
        artifacts.deleteRecursively()
    }

    @Test
    fun `schema exposes the DSh commands and required parameters`() {
        val schema = Json.parseToJsonElement(tool.definition.parametersJSON).jsonObject
        assertEquals(listOf("command", "path"), schema.getValue("required").jsonArray.map { it.jsonPrimitive.content })
        assertEquals(
            listOf("view", "create", "str_replace", "insert"),
            schema.getValue("properties").jsonObject.getValue("command").jsonObject.getValue("enum").jsonArray.map { it.jsonPrimitive.content }
        )
    }

    @Test
    fun `create range view unique replacement deletion and insert persist artifacts`() = runBlocking {
        val created = call("""{"command":"create","path":"/workspace/sample.txt","file_text":"one\ntwo\nthree"}""")
        assertEquals(listOf("sample.txt"), created.artifacts.map { it.name })
        assertTrue(call("""{"command":"view","path":"/workspace/sample.txt","view_range":[2,-1]}""").content.contains("     2  two"))
        val replaced = call("""{"command":"str_replace","path":"/workspace/sample.txt","old_str":"two","new_str":"TWO"}""")
        call("""{"command":"str_replace","path":"/workspace/sample.txt","old_str":"three"}""")
        val inserted = call("""{"command":"insert","path":"/workspace/sample.txt","insert_line":1,"new_str":"between"}""")
        val final = call("""{"command":"view","path":"/workspace/sample.txt"}""").content
        assertTrue(final.contains("     2  between"))
        assertTrue(final.contains("     3  TWO"))
        assertFalse(final.contains("three"))
        assertEquals(created.artifacts.single().path, replaced.artifacts.single().path)
        assertEquals(created.artifacts.single().path, inserted.artifacts.single().path)
        assertEquals(listOf("sample.txt"), artifacts.list()?.toList())
        assertEquals("one\nbetween\nTWO\n", File(artifacts, "sample.txt").readText())
    }

    @Test
    fun `empty file and CRLF insertion preserve expected line semantics`() = runBlocking {
        call("""{"command":"create","path":"/workspace/empty.txt","file_text":""}""")
        call("""{"command":"insert","path":"/workspace/empty.txt","insert_line":0,"new_str":"first"}""")
        assertTrue(call("""{"command":"view","path":"/workspace/empty.txt"}""").content.contains("     1  first"))

        call("""{"command":"create","path":"/workspace/crlf.txt","file_text":"a\r\nb"}""")
        call("""{"command":"insert","path":"/workspace/crlf.txt","insert_line":1,"new_str":"x\ny"}""")
        val workspace = workspace("session-one")
        assertEquals("a\r\nx\r\ny\r\nb", File(workspace, "crlf.txt").readText())
    }

    @Test
    fun `directory view is sorted filtered two levels and output is clipped`() = runBlocking {
        val workspace = workspace("session-one").apply { mkdirs() }
        File(workspace, "b/sub/deep").mkdirs()
        File(workspace, "a").mkdirs()
        File(workspace, ".hidden").writeText("hidden")
        File(workspace, "node_modules").mkdirs()
        File(workspace, "b/visible.txt").writeText("ok")
        File(workspace, "b/sub/second.txt").writeText("too deep")
        val listing = call("""{"command":"view","path":"/workspace"}""").content
        assertTrue(listing.indexOf("/workspace/a") < listing.indexOf("/workspace/b"))
        assertTrue(listing.contains("/workspace/b/visible.txt"))
        assertFalse(listing.contains("second.txt"))
        assertFalse(listing.contains(".hidden"))
        assertFalse(listing.contains("\t/workspace/node_modules"))

        call("""{"command":"create","path":"/workspace/long.txt","file_text":"${"z".repeat(17_000)}"}""")
        assertTrue(call("""{"command":"view","path":"/workspace/long.txt"}""").content.contains("<response clipped>"))
    }

    @Test
    fun `invalid edits paths utf8 and symlinks do not mutate files`() = runBlocking {
        call("""{"command":"create","path":"/workspace/repeated.txt","file_text":"same\nsame"}""")
        assertFails { call("""{"command":"str_replace","path":"/workspace/repeated.txt","old_str":"same","new_str":"changed"}""") }
        assertFails { call("""{"command":"create","path":"/workspace/repeated.txt","file_text":"overwrite"}""") }
        assertFails { call("""{"command":"insert","path":"/workspace/repeated.txt","insert_line":4,"new_str":"bad"}""") }
        assertFails { call("""{"command":"view","path":"/workspace/../outside"}""") }
        val workspace = workspace("session-one")
        File(workspace, "invalid.bin").writeBytes(byteArrayOf(0xC3.toByte(), 0x28))
        assertFails { call("""{"command":"view","path":"/workspace/invalid.bin"}""") }
        val link = File(workspace, "link")
        runCatching { Files.createSymbolicLink(link.toPath(), artifacts.toPath()) }.onSuccess {
            assertFails { call("""{"command":"view","path":"/workspace/link"}""") }
        }
        assertEquals("same\nsame", File(workspace, "repeated.txt").readText())
    }

    @Test
    fun `sessions are isolated and persisted across tool instances`() = runBlocking {
        call("""{"command":"create","path":"/workspace/owned.txt","file_text":"one"}""")
        val second = StrReplaceEditorTool(EditorWorkspaceStore(root), storage)
        assertTrue(second.execute(toolCall("""{"command":"view","path":"/workspace/owned.txt"}""", "session-one")).content.contains("one"))
        assertFails { second.execute(toolCall("""{"command":"view","path":"/workspace/owned.txt"}""", "session-two")) }
        workspace("orphan").apply { mkdirs(); resolve("old.txt").writeText("old") }
        EditorWorkspaceStore(root).deleteOrphans(listOf("session-one"))
        assertTrue(workspace("session-one").isDirectory)
        assertFalse(workspace("orphan").exists())
    }

    @Test
    fun `request attachments are staged under a hashed discoverable path`() = runBlocking {
        val source = File(artifacts, "input notes.txt").apply { writeText("attached") }
        val result = tool.execute(
            toolCall("""{"command":"view","path":"/workspace"}""", "session-one").copy(
                providerMetadata = mapOf(
                    "editorSessionId" to "session-one",
                    "editorAttachmentsJSON" to Json.encodeToString(listOf(source.absolutePath))
                )
            )
        )
        val digest = EditorWorkspaceStore.sha256(source.readBytes())
        assertTrue(result.content.contains("/workspace/attachments/$digest"))
        assertTrue(call("""{"command":"view","path":"/workspace/attachments/$digest"}""").content.contains("input_notes.txt"))
        assertTrue(call("""{"command":"view","path":"/workspace/attachments/$digest/input_notes.txt"}""").content.contains("attached"))
    }

    private suspend fun call(arguments: String) = tool.execute(toolCall(arguments, "session-one"))

    private fun toolCall(arguments: String, session: String) = ToolCall(
        id = UUID.randomUUID().toString(),
        name = StrReplaceEditorTool.NAME,
        argumentsJSON = arguments,
        providerMetadata = mapOf("editorSessionId" to session)
    )

    private fun workspace(session: String) = File(root, EditorWorkspaceStore.sha256(session.toByteArray()))

    private suspend fun assertFails(block: suspend () -> Unit) {
        try {
            block()
            fail("Expected an exception")
        } catch (_: Exception) {}
    }
}

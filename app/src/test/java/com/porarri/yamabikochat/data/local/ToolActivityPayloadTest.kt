package com.porarri.yamabikochat.data.local

import com.porarri.yamabikochat.data.model.ProviderStreamEvent
import com.porarri.yamabikochat.data.model.ToolActivityEvent
import com.porarri.yamabikochat.data.model.ToolCall
import com.porarri.yamabikochat.data.model.ToolResult
import com.porarri.yamabikochat.data.model.ToolSource
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test

class ToolActivityPayloadTest {
    @Test
    fun `start and finish update one step and create replay transcript`() {
        val call = ToolCall("call-1", "web_search", """{"query":"Compose"}""")
        var payload = ToolActivityPayload().applying(
            ToolActivityEvent(ToolActivityEvent.Phase.started, call, createdAtMs = 1)
        )
        assertEquals(ToolActivityStep.Status.running, payload.steps.single().status)
        assertEquals("Compose", payload.steps.single().detail)

        payload = payload.applying(
            ToolActivityEvent(
                ToolActivityEvent.Phase.finished,
                call,
                ToolResult(
                    callId = call.id,
                    name = call.name,
                    content = """{"results":[{},{}]}""",
                    sources = listOf(
                        ToolSource("A", "https://example.com"),
                        ToolSource("Duplicate", "https://example.com")
                    )
                ),
                createdAtMs = 1
            )
        )

        assertEquals(1, payload.steps.size)
        assertEquals(ToolActivityStep.Status.completed, payload.steps.single().status)
        assertEquals(2, payload.steps.single().resultCount)
        assertEquals(1, payload.steps.single().sources.size)
        assertEquals(listOf("assistant", "tool"), payload.providerTranscript.map { it.role })
    }

    @Test
    fun `tool activity is not answer text`() {
        val call = ToolCall("call-1", "web_search", """{"query":"q"}""")
        val event = ProviderStreamEvent.ToolActivity(
            ToolActivityEvent(ToolActivityEvent.Phase.started, call, createdAtMs = 1)
        )
        assertFalse(event.includesNonEmptyAnswerText)
    }

    @Test
    fun `execution order is stable and running steps finalize on failure`() {
        val first = ToolCall("search-1", "web_search", """{"query":"first"}""")
        val second = ToolCall("fetch-1", "fetch_url", """{"url":"https://developer.android.com"}""")
        var payload = ToolActivityPayload()
            .applying(ToolActivityEvent(ToolActivityEvent.Phase.started, first, createdAtMs = 1))
            .applying(ToolActivityEvent(ToolActivityEvent.Phase.started, second, createdAtMs = 1))
        payload = payload.applying(
            ToolActivityEvent(
                ToolActivityEvent.Phase.finished,
                first,
                ToolResult(first.id, first.name, """{"error":"offline"}""", isError = true),
                createdAtMs = 2
            )
        )

        assertEquals(listOf(first.id, second.id), payload.steps.map { it.id })
        assertEquals(listOf(1, 2), payload.steps.map { it.round })
        assertEquals(ToolActivityStep.Status.failed, payload.steps.first().status)
        payload = payload.failRunning("cancelled")
        assertEquals(ToolActivityStep.Status.failed, payload.steps.last().status)
    }
}

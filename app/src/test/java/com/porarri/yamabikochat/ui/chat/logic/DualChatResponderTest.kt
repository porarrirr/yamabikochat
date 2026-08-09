package com.porarri.yamabikochat.ui.chat.logic

import com.porarri.yamabikochat.data.ChatRepository
import com.porarri.yamabikochat.data.remote.Candidate
import com.porarri.yamabikochat.data.remote.Content
import com.porarri.yamabikochat.data.remote.FunctionDeclaration
import com.porarri.yamabikochat.data.remote.GenerateContentRequest
import com.porarri.yamabikochat.data.remote.GenerateContentResponse
import com.porarri.yamabikochat.data.remote.Part
import com.porarri.yamabikochat.data.remote.ResponseContent
import com.porarri.yamabikochat.data.remote.ResponsePart
import com.porarri.yamabikochat.data.remote.Tool
import com.porarri.yamabikochat.data.skills.AgentSkillTools
import com.porarri.yamabikochat.data.tools.ClientToolCallingRunner
import com.porarri.yamabikochat.data.tools.LocalToolRegistry
import io.mockk.coVerify
import io.mockk.mockk
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import retrofit2.Response
import java.util.concurrent.atomic.AtomicInteger

class DualChatResponderTest {
    @Test
    fun agentSkillRequestsUsePerSideToolRunnerInsteadOfDirectDualApi() = runTest {
        val repository = mockk<ChatRepository>(relaxed = true)
        val calls = AtomicInteger(0)
        val runner = ClientToolCallingRunner(
            generate = { _, model, _ ->
                calls.incrementAndGet()
                Response.success(
                    GenerateContentResponse(
                        candidates = listOf(
                            Candidate(
                                content = ResponseContent(
                                    parts = listOf(ResponsePart(text = "answer-$model")),
                                    role = "model"
                                )
                            )
                        )
                    )
                )
            },
            registry = LocalToolRegistry(emptyList())
        )
        val responder = DualChatResponder(repository, runner)
        val request = GenerateContentRequest(
            contents = listOf(Content(role = "user", parts = listOf(Part(text = "hello")))),
            tools = listOf(
                Tool(
                    function_declarations = listOf(
                        FunctionDeclaration(
                            name = AgentSkillTools.ACTIVATE,
                            parameters = buildJsonObject { put("type", "object") }
                        )
                    )
                )
            )
        )

        val result = responder.generateResponses(
            conversationId = 1,
            modelA = "model-a",
            modelB = "model-b",
            providerA = "OPENAI",
            providerB = "OPENAI",
            requestA = request,
            requestB = request
        )

        assertTrue(result is DualChatResponder.DualResponseResult.Success)
        result as DualChatResponder.DualResponseResult.Success
        assertEquals("answer-model-a", result.textA)
        assertEquals("answer-model-b", result.textB)
        assertEquals(2, calls.get())
        coVerify(exactly = 0) {
            repository.generateDualContent(any(), any(), any(), any(), any(), any())
        }
    }
}

package com.porarri.yamabikochat.ui.chat.logic

import com.porarri.yamabikochat.data.ChatRepository
import com.porarri.yamabikochat.data.model.ProviderRequest
import com.porarri.yamabikochat.data.model.ProviderRequestMessage
import com.porarri.yamabikochat.data.model.ProviderResponse
import io.mockk.coEvery
import io.mockk.coVerify
import io.mockk.mockk
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class DualChatResponderTest {
    @Test
    fun dualChatResponderRunsBothSidesConcurrently() = runTest {
        val repository = mockk<ChatRepository>(relaxed = true)
        val requestA = ProviderRequest(
            model = "model-a",
            messages = listOf(ProviderRequestMessage(role = "user", content = "hello"))
        )
        val requestB = ProviderRequest(
            model = "model-b",
            messages = listOf(ProviderRequestMessage(role = "user", content = "hello"))
        )

        coEvery { repository.generateProviderRequest(requestA, "OPENAI") } returns ProviderResponse(
            text = "answer-model-a",
            toolCalls = emptyList()
        )
        coEvery { repository.generateProviderRequest(requestB, "ANTHROPIC") } returns ProviderResponse(
            text = "answer-model-b",
            toolCalls = emptyList()
        )

        val responder = DualChatResponder(repository)
        val result = responder.generateResponses(
            conversationId = 1,
            modelA = "model-a",
            modelB = "model-b",
            providerA = "OPENAI",
            providerB = "ANTHROPIC",
            requestA = requestA,
            requestB = requestB
        )

        assertTrue(result is DualChatResponder.DualResponseResult.Success)
        result as DualChatResponder.DualResponseResult.Success
        assertEquals("answer-model-a", result.textA)
        assertEquals("answer-model-b", result.textB)

        coVerify(exactly = 1) { repository.generateProviderRequest(requestA, "OPENAI") }
        coVerify(exactly = 1) { repository.generateProviderRequest(requestB, "ANTHROPIC") }
    }
}

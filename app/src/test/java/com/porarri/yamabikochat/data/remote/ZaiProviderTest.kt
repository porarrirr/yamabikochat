package com.porarri.yamabikochat.data.remote

import io.mockk.mockk
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Test

class ZaiProviderTest {
    @Test
    fun rejectsModelOutsideCodingPlanBeforeApiCall() = runTest {
        val provider = ZaiProvider(mockk(relaxed = true))
        val request = GenerateContentRequest(
            contents = listOf(Content(role = "user", parts = listOf(Part(text = "hello"))))
        )

        val response = provider.generateContent("zai-key", "glm-5.1", request)

        assertEquals(400, response.code())
        assertEquals(
            "Unsupported Z.ai Coding Plan model: glm-5.1",
            response.errorBody()?.string()
        )
    }
}

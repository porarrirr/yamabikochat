package com.porarri.yamabikochat.data.fusion

import com.porarri.yamabikochat.data.model.ProviderRequest
import com.porarri.yamabikochat.data.model.ProviderRequestMessage
import com.porarri.yamabikochat.data.model.ProviderResponse
import kotlinx.coroutines.delay
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class FusionPanelRunnerTest {
    @Test
    fun panelRunsPastLegacyConfiguredTimeout() = runTest {
        val panel = PanelModelConfig(
            modelId = "slow-model",
            provider = "GEMINI",
            timeoutMs = 1
        )
        val request = FusionRequest(
            userPrompt = "test",
            panelModels = listOf(panel),
            judgeModel = panel,
            synthesizerModel = panel,
            preset = "custom",
            maxPanelTokens = 1,
            maxJudgeTokens = 1,
            maxSynthesizerTokens = 1,
            timeoutMs = 1,
            allowWebSearch = false,
            taskType = FusionTaskType.research
        )

        val results = FusionPanelRunner.runAll(
            request = request,
            panelSystemPrompt = "panel",
            buildPanelRequest = { model, _ ->
                FusionPanelRunner.GenerateRequestBundle(
                    model = model.modelId,
                    provider = model.provider,
                    request = ProviderRequest(
                        model = model.modelId,
                        messages = listOf(ProviderRequestMessage(role = "user", content = "test"))
                    )
                )
            },
            invoke = { _, _, _ ->
                delay(100)
                ProviderResponse(text = "completed")
            },
            estimateCost = { _, _, _ -> null }
        )

        assertEquals("completed", results.single().content)
        assertTrue(results.single().success)
    }
}

package com.porarri.yamabikochat.data.fusion

import com.porarri.yamabikochat.data.local.Settings
import com.porarri.yamabikochat.data.model.ProviderRequest
import com.porarri.yamabikochat.data.model.ProviderRequestMessage
import com.porarri.yamabikochat.data.repositories.ProviderGateway
import com.porarri.yamabikochat.data.repositories.ProviderRequestResolvedSettings
import com.porarri.yamabikochat.data.repositories.ProviderRequestSettingsResolver
import io.mockk.coEvery
import io.mockk.mockk
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Before
import org.junit.Test

class FusionServiceTest {
    private val requestSettingsResolver = mockk<ProviderRequestSettingsResolver>(relaxed = true)

    @Before
    fun setUp() {
        val resolved = ProviderRequestResolvedSettings(
            tools = emptyList(),
            thinking = null,
            routing = null,
            metadata = emptyMap()
        )
        coEvery { requestSettingsResolver.resolve(any(), any(), any(), any()) } returns resolved
        coEvery { requestSettingsResolver.resolve(any(), any(), any(), any(), any()) } returns resolved
    }

    @Test
    fun buildProviderRequestSetsSupportsVisionMetadataForPanelPhase() = runBlocking {
        val service = makeService()
        val history = listOf(
            ProviderRequestMessage(role = "user", content = "Hello", attachments = listOf("file:///img.png"))
        )

        val request = service.buildProviderRequest(
            model = PanelModelConfig(modelId = "m1", provider = "OPENAI"),
            systemPrompt = "panel",
            phase = FusionPhase.panel,
            allowTools = false,
            settings = Settings(),
            fusionDepth = 0,
            userPrompt = "Hello",
            conversationHistory = history,
            userAttachments = listOf("file:///img.png"),
            supportsVision = true,
            conversationId = "42"
        )

        assertEquals(1, request.messages.size)
        assertEquals("Hello", request.messages[0].content)
        assertEquals(listOf("file:///img.png"), request.messages[0].attachments)
        assertEquals("true", request.metadata["supportsVision"])
        assertEquals("fusion-42", request.metadata["promptCacheKey"])
    }

    @Test
    fun runThroughJudgePassesPerPanelVisionIntoPanelRequests() = runBlocking {
        val visionPanel = PanelModelConfig(modelId = "vision-model", provider = "OPENAI")
        val textPanel = PanelModelConfig(modelId = "text-model", provider = "GEMINI")
        val orchestrator = mockk<FusionOrchestrator>()
        var visionRequest: ProviderRequest? = null
        var textRequest: ProviderRequest? = null
        var judgeRequest: ProviderRequest? = null

        coEvery {
            orchestrator.runThroughJudge(any(), any(), any(), any(), any(), any())
        } coAnswers {
            val builder = arg<FusionOrchestratorRequestBuilder>(2)
            visionRequest = builder(visionPanel, "panel", FusionPhase.panel, false, 4096)
            textRequest = builder(textPanel, "panel", FusionPhase.panel, false, 4096)
            judgeRequest = builder(textPanel, "judge", FusionPhase.judge, false, 2048)
            mockk(relaxed = true)
        }

        val service = makeService(
            orchestrator = orchestrator,
            modelSupportsVision = { _, model -> model == "vision-model" }
        )

        service.runThroughJudge(
            request = FusionRequest(
                userPrompt = "look at this",
                panelModels = listOf(visionPanel, textPanel),
                judgeModel = textPanel,
                synthesizerModel = textPanel,
                allowWebSearch = false
            ),
            context = FusionContext(conversationId = 42L),
            conversationHistory = emptyList(),
            userAttachments = listOf("file:///img.png")
        )

        assertEquals("true", visionRequest?.metadata?.get("supportsVision"))
        assertEquals("false", textRequest?.metadata?.get("supportsVision"))
        assertNull(judgeRequest?.metadata?.get("supportsVision"))
        assertEquals("fusion-42", visionRequest?.metadata?.get("promptCacheKey"))
    }

    private fun makeService(
        orchestrator: FusionOrchestrator = FusionOrchestrator(),
        modelSupportsVision: suspend (String, String) -> Boolean = { _, _ -> false }
    ): FusionService {
        return FusionService(
            settingsProvider = { Settings() },
            providerGateway = mockk(relaxed = true),
            modelSupportsVision = modelSupportsVision,
            requestSettingsResolver = requestSettingsResolver,
            orchestrator = orchestrator
        )
    }
}

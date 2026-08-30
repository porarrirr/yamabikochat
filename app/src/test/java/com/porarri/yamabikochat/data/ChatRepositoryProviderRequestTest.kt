package com.porarri.yamabikochat.data

import com.porarri.yamabikochat.data.database.DatabaseRepository
import com.porarri.yamabikochat.data.local.Conversation
import com.porarri.yamabikochat.data.local.Settings
import com.porarri.yamabikochat.data.model.ProviderRequest
import com.porarri.yamabikochat.data.model.ProviderRequestMessage
import com.porarri.yamabikochat.data.model.ProviderResponse
import com.porarri.yamabikochat.data.remote.LiteLlmPricingRepository
import com.porarri.yamabikochat.data.repositories.ProviderGateway
import com.porarri.yamabikochat.data.repositories.ProviderRequestResolvedSettings
import com.porarri.yamabikochat.data.repositories.ProviderRequestSettingsResolver
import com.porarri.yamabikochat.data.skills.AgentSkillRepository
import io.mockk.coEvery
import io.mockk.every
import io.mockk.mockk
import io.mockk.slot
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Before
import org.junit.Test

class ChatRepositoryProviderRequestTest {
    private val databaseRepository = mockk<DatabaseRepository>(relaxed = true)
    private val providerGateway = mockk<ProviderGateway>(relaxed = true)
    private val requestSettingsResolver = mockk<ProviderRequestSettingsResolver>(relaxed = true)
    private val pricingRepository = mockk<LiteLlmPricingRepository>(relaxed = true)
    private val agentSkillRepository = mockk<AgentSkillRepository>(relaxed = true)
    private lateinit var repository: ChatRepository

    @Before
    fun setUp() {
        every { agentSkillRepository.requestContext(any(), any(), any()) } returns null
        every { agentSkillRepository.requestContext(any(), any()) } returns null
        coEvery { requestSettingsResolver.resolve(any(), any(), any(), any()) } returns
            ProviderRequestResolvedSettings(
                tools = emptyList(),
                thinking = null,
                routing = null,
                metadata = emptyMap()
            )
        coEvery { requestSettingsResolver.resolve(any(), any(), any(), any(), any()) } returns
            ProviderRequestResolvedSettings(
                tools = emptyList(),
                thinking = null,
                routing = null,
                metadata = emptyMap()
            )
        repository = ChatRepository(
            databaseRepository = databaseRepository,
            providerGateway = providerGateway,
            requestSettingsResolver = requestSettingsResolver,
            fileProcessingRepository = mockk(relaxed = true),
            modelRepository = mockk(relaxed = true),
            codexAuthRepository = mockk(relaxed = true),
            superGrokAuthRepository = mockk(relaxed = true),
            pricingRepository = pricingRepository,
            modelsDevCatalogRepository = mockk(relaxed = true),
            agentSkillRepository = agentSkillRepository,
            securePreferences = mockk(relaxed = true),
            editorWorkspaceStore = mockk(relaxed = true)
        )
    }

    @Test
    fun buildProviderRequestSetsVisionProviderCacheAndCodexSession() = runBlocking {
        coEvery { pricingRepository.modelSupportsVision("CODEX_AUTH", "gpt-5.3-codex") } returns true
        coEvery { databaseRepository.getOrCreateCodexSessionId(42L) } returns "session-uuid"

        val request = repository.buildProviderRequest(
            conversation = Conversation(
                id = 42L,
                title = "Chat",
                model = "gpt-5.3-codex",
                apiProvider = "CODEX_AUTH"
            ),
            settings = Settings(),
            provider = "CODEX_AUTH",
            model = "gpt-5.3-codex",
            messages = listOf(ProviderRequestMessage(role = "user", content = "hi")),
            systemPrompt = null
        )

        assertEquals("true", request.metadata["supportsVision"])
        assertEquals("CODEX_AUTH", request.metadata["provider"])
        assertEquals("conversation-42", request.metadata["promptCacheKey"])
        assertEquals("42", request.metadata["editorSessionId"])
        assertEquals("session-uuid", request.metadata["codexSessionId"])
    }

    @Test
    fun buildProviderRequestUsesExplicitPromptCacheKeyWithoutCodexSession() = runBlocking {
        coEvery { pricingRepository.modelSupportsVision("GEMINI", "gemini-2.5-flash") } returns false

        val request = repository.buildProviderRequest(
            conversation = Conversation(id = 7L, title = "Dual", model = "gemini-2.5-flash"),
            settings = Settings(),
            provider = "GEMINI",
            model = "gemini-2.5-flash",
            messages = listOf(ProviderRequestMessage(role = "user", content = "hi")),
            systemPrompt = null,
            promptCacheKey = "conversation-7-dual-a"
        )

        assertEquals("false", request.metadata["supportsVision"])
        assertEquals("GEMINI", request.metadata["provider"])
        assertEquals("conversation-7-dual-a", request.metadata["promptCacheKey"])
        assertEquals("7", request.metadata["editorSessionId"])
        assertNull(request.metadata["codexSessionId"])
    }

    @Test
    fun buildProviderRequestRejectsAttachmentsForSecretConversation() {
        assertThrows(IllegalArgumentException::class.java) {
            runBlocking {
                repository.buildProviderRequest(
                    conversation = Conversation(
                        id = 8L,
                        title = "Secret",
                        model = "gpt-5.6",
                        isSecret = true
                    ),
                    settings = Settings(),
                    provider = "OPENAI",
                    model = "gpt-5.6",
                    messages = listOf(
                        ProviderRequestMessage(
                            role = "user",
                            content = "secret",
                            attachments = listOf("/tmp/plaintext.txt")
                        )
                    ),
                    systemPrompt = null
                )
            }
        }
    }

    @Test
    fun generateAutoConversationResponseSetsPromptCacheKeyAndProvider() = runBlocking {
        coEvery { pricingRepository.modelSupportsVision("OPENROUTER", "deepseek/deepseek-chat") } returns false
        coEvery { databaseRepository.getLatestSettings() } returns Settings()
        val captured = slot<ProviderRequest>()
        coEvery { providerGateway.generate(capture(captured), "OPENROUTER") } returns ProviderResponse(text = "ok")

        repository.generateAutoConversationResponse(
            model = "deepseek/deepseek-chat",
            provider = "OPENROUTER",
            systemPrompt = "sys",
            conversationHistory = listOf(ProviderRequestMessage(role = "user", content = "go")),
            reasoningContext = Settings.ReasoningContext.AUTO_A,
            promptCacheKey = "auto-conversation-9-A"
        )

        assertEquals("OPENROUTER", captured.captured.metadata["provider"])
        assertEquals("auto-conversation-9-A", captured.captured.metadata["promptCacheKey"])
        assertEquals("false", captured.captured.metadata["supportsVision"])
    }
}

package com.porarri.yamabikochat.ui.settings

import com.porarri.yamabikochat.TestLogUtils
import com.porarri.yamabikochat.data.ChatRepository
import com.porarri.yamabikochat.data.local.Settings
import com.porarri.yamabikochat.data.remote.SimpleModel
import io.mockk.coEvery
import io.mockk.coVerify
import io.mockk.every
import io.mockk.just
import io.mockk.mockk
import io.mockk.runs
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import kotlinx.coroutines.test.resetMain
import org.junit.After
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class SettingsViewModelTest {

    private val testDispatcher = StandardTestDispatcher()

    private lateinit var repository: ChatRepository
    private lateinit var settingsFlow: MutableStateFlow<Settings?>
    private lateinit var viewModel: SettingsViewModel

    @Before
    fun setup() {
        TestLogUtils.setup()
        Dispatchers.setMain(testDispatcher)

        repository = mockk(relaxed = true)
        settingsFlow = MutableStateFlow(Settings(apiProvider = "GEMINI", defaultModel = "gemini-2.5-flash"))

        every { repository.getSettings() } returns settingsFlow
        every { repository.getAllModelPresets() } returns flowOf(emptyList())
        every { repository.getOpenRouterModelsFlow() } returns MutableStateFlow(emptyList<SimpleModel>())
        every { repository.getOpenRouterModelsLoading() } returns MutableStateFlow(false)
        every { repository.getOpenRouterModelsError() } returns MutableStateFlow(null)

        coEvery { repository.saveSettings(any()) } just runs

        // Default: no keys stored.
        every { repository.hasApiKey(any()) } returns false
        coEvery { repository.saveApiKey(any(), any()) } returns true
        coEvery { repository.saveOpenAiCompatApiKey(any(), any()) } returns true
        every { repository.saveCodexUserAgentPreset(any()) } returns true

        viewModel = SettingsViewModel(repository)
    }

    @After
    fun tearDown() {
        Dispatchers.resetMain()
        TestLogUtils.tearDown()
    }

    @Test
    fun `saveSettings updates apiKeyStatus after saving`() = runTest {
        var hasGeminiKey = false
        every { repository.hasApiKey("GEMINI") } answers { hasGeminiKey }
        coEvery { repository.saveApiKey("GEMINI", "abc") } answers { hasGeminiKey = true; true }

        viewModel.saveSettings(
            SettingsUpdateRequest(
                apiKey = "abc",
                model = "gemini-2.5-flash",
                googleSearchEnabled = false,
                codeExecutionEnabled = false,
                thinkingEnabled = false,
                thinkingBudget = 0,
                thinkingLevel = "",
                systemPrompt = null,
                isStreamingEnabled = false,
                apiProvider = "GEMINI",
                openRouterApiKey = "",
                openAiApiKey = "",
                zaiApiKey = "",
                openAiCompatApiKey = "",
                geminiApiKeyAction = ApiKeyAction.Update,
                openRouterApiKeyAction = ApiKeyAction.NoChange,
                openAiApiKeyAction = ApiKeyAction.NoChange,
                zaiApiKeyAction = ApiKeyAction.NoChange,
                openAiCompatApiKeyAction = ApiKeyAction.NoChange,
                isDualModeEnabled = false,
                dualModelA = "",
                dualModelB = "",
                dualProviderA = "GEMINI",
                dualProviderB = "GEMINI",
                dualSplitLayout = "VERTICAL",
                dualSplitRatio = 0.5f,
                isAutoConversationEnabled = false,
                autoModelA = "",
                autoModelB = "",
                autoProviderA = "GEMINI",
                autoProviderB = "GEMINI",
                autoSystemPromptA = "",
                autoSystemPromptB = "",
                autoMaxTurns = 0,
                mathRenderingEnabled = false
            )
        )

        advanceUntilIdle()

        assertTrue(viewModel.apiKeyStatus.value.hasGeminiKey)
    }

    @Test
    fun `saveSettings persists OpenAI compatible key when requested`() = runTest {
        viewModel.saveSettings(
            SettingsUpdateRequest(
                apiKey = "",
                model = "gpt-4o-mini",
                googleSearchEnabled = false,
                codeExecutionEnabled = false,
                thinkingEnabled = false,
                thinkingBudget = 0,
                thinkingLevel = "",
                systemPrompt = null,
                isStreamingEnabled = false,
                apiProvider = "OPENAI_COMPAT",
                openRouterApiKey = "",
                openAiApiKey = "",
                zaiApiKey = "",
                openAiCompatApiKey = "compat-key",
                geminiApiKeyAction = ApiKeyAction.NoChange,
                openRouterApiKeyAction = ApiKeyAction.NoChange,
                openAiApiKeyAction = ApiKeyAction.NoChange,
                zaiApiKeyAction = ApiKeyAction.NoChange,
                openAiCompatApiKeyAction = ApiKeyAction.Update,
                isDualModeEnabled = false,
                dualModelA = "",
                dualModelB = "",
                dualProviderA = "GEMINI",
                dualProviderB = "GEMINI",
                dualSplitLayout = "VERTICAL",
                dualSplitRatio = 0.5f,
                isAutoConversationEnabled = false,
                autoModelA = "",
                autoModelB = "",
                autoProviderA = "GEMINI",
                autoProviderB = "GEMINI",
                autoSystemPromptA = "",
                autoSystemPromptB = "",
                autoMaxTurns = 0,
                mathRenderingEnabled = false,
                selectedOpenAiCompatPreset = "MyPreset"
            )
        )

        advanceUntilIdle()

        coVerify(exactly = 1) { repository.saveOpenAiCompatApiKey("MyPreset", "compat-key") }
    }
}

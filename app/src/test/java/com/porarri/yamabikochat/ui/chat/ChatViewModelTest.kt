package com.porarri.yamabikochat.ui.chat

import android.net.Uri
import androidx.lifecycle.SavedStateHandle
import com.porarri.yamabikochat.data.ChatRepository
import com.porarri.yamabikochat.data.local.ChatMessage
import com.porarri.yamabikochat.data.local.Settings
import com.porarri.yamabikochat.data.local.ModelPreset
import com.porarri.yamabikochat.data.local.DualChatSettings
import com.porarri.yamabikochat.data.local.SplitLayoutType
import com.porarri.yamabikochat.data.local.Conversation
import com.porarri.yamabikochat.TestLogUtils
import com.porarri.yamabikochat.utils.FileValidationUtils
import io.mockk.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.test.*
import org.junit.After
import org.junit.Before
import org.junit.Test
import org.junit.Assert.*
@ExperimentalCoroutinesApi
class ChatViewModelTest {

    private lateinit var repository: ChatRepository
    private lateinit var savedStateHandle: SavedStateHandle
    private lateinit var viewModel: ChatViewModel
    private lateinit var settingsFlow: MutableStateFlow<Settings?>
    
    private val testDispatcher = StandardTestDispatcher()
    
    @Before
    fun setup() {
        TestLogUtils.setup()
        Dispatchers.setMain(testDispatcher)
        
        repository = mockk(relaxed = true)
        savedStateHandle = mockk(relaxed = true)
        
        // デフォルトのモック設定
        every { savedStateHandle.get<String>("conversationId") } returns "1"
        settingsFlow = MutableStateFlow(createDefaultSettings())
        every { repository.getSettings() } returns settingsFlow
        every { repository.getMessagesForConversation(any()) } returns flowOf(emptyList())
        every { repository.getDualMessagesForConversation(any()) } returns flowOf(emptyList())
        coEvery { repository.upsertConversation(any()) } returns 1L
        coEvery { repository.getConversationById(any()) } returns createDefaultConversation()
        coEvery { repository.saveSettings(any()) } just runs
        coEvery { repository.resolveCanAttachImages(any(), any(), any()) } returns true

        viewModel = ChatViewModel(repository, savedStateHandle)
    }
    
    @After
    fun tearDown() {
        Dispatchers.resetMain()
        viewModel.triggerOnClearedForTest()
        TestLogUtils.tearDown()
    }
    
    private fun createDefaultSettings() = Settings(
        defaultModel = "gemini-2.5-flash",
        apiProvider = "GEMINI",
        thinkingEnabled = false,
        thinkingBudget = 1000,
        geminiStreamingEnabled = true,
        geminiThinkingEnabled = false,
        geminiThinkingBudget = 1000,
        isDualModeEnabled = false,
        isAutoConversationEnabled = false
    )
    
    private fun createDefaultConversation() = Conversation(
        id = 1L,
        title = "Test Chat",
        model = "gemini-2.5-flash",
        apiProvider = "GEMINI"
    )

    // 添付ファイル管理のテスト
    @Test
    fun `addAttachment with valid file should add to attachments`() = runTest {
        // Given
        val uri = mockk<Uri>()
        val validResult = FileValidationUtils.FileValidationResult.Valid("image/jpeg", 1024L)
        coEvery { repository.validateFile(uri) } returns validResult
        
        // When
        viewModel.addAttachment(uri)
        advanceUntilIdle()
        
        // Then
        assertTrue("Should contain the added attachment", viewModel.attachments.value.contains(uri))
        assertNull("Error message should be null", viewModel.errorMessage.value)
    }
    
    @Test
    fun `addAttachment with invalid file should set error message`() = runTest {
        // Given
        val uri = mockk<Uri>()
        val invalidResult = FileValidationUtils.FileValidationResult.TooLarge(15 * 1024 * 1024L)
        coEvery { repository.validateFile(uri) } returns invalidResult
        
        // When
        viewModel.addAttachment(uri)
        advanceUntilIdle()
        
        // Then
        assertFalse("Should not contain the invalid attachment", viewModel.attachments.value.contains(uri))
        assertNotNull("Error message should be set", viewModel.errorMessage.value)
        assertTrue("Error message should mention file size",
            viewModel.errorMessage.value?.contains("10MB制限を超えています") == true)
    }
    
    @Test
    fun `addAttachment with dangerous file should set security error`() = runTest {
        // Given
        val uri = mockk<Uri>()
        val dangerousResult = FileValidationUtils.FileValidationResult.DangerousFile
        coEvery { repository.validateFile(uri) } returns dangerousResult
        
        // When
        viewModel.addAttachment(uri)
        advanceUntilIdle()
        
        // Then
        assertFalse("Should not contain dangerous file", viewModel.attachments.value.contains(uri))
        assertEquals("Should set security error message", 
            "危険なファイル形式です。このファイルはアップロードできません。", 
            viewModel.errorMessage.value)
    }
    
    @Test
    fun `removeAttachment should remove from attachments and clear error`() = runTest {
        // Given
        val uri = mockk<Uri>()
        val validResult = FileValidationUtils.FileValidationResult.Valid("image/jpeg", 1024L)
        coEvery { repository.validateFile(uri) } returns validResult
        
        viewModel.addAttachment(uri)
        advanceUntilIdle()
        
        // When
        viewModel.removeAttachment(uri)
        
        // Then
        assertFalse("Should not contain removed attachment", viewModel.attachments.value.contains(uri))
        assertNull("Error message should be cleared", viewModel.errorMessage.value)
    }
    
    @Test
    fun `clearErrorMessage should clear error state`() = runTest {
        // Given
        val uri = mockk<Uri>()
        val invalidResult = FileValidationUtils.FileValidationResult.UnsupportedType
        coEvery { repository.validateFile(uri) } returns invalidResult
        
        viewModel.addAttachment(uri)
        advanceUntilIdle()
        
        // When
        viewModel.clearErrorMessage()
        
        // Then
        assertNull("Error message should be cleared", viewModel.errorMessage.value)
    }

    // メッセージ編集のテスト
    @Test
    fun `startEditing should set editing message`() = runTest {
        // Given
        val message = ChatMessage(id = 1L, conversationId = 1L, role = "user", text = "Test message")
        
        // When
        viewModel.startEditing(message)
        
        // Then
        assertEquals("Should set editing message", message, viewModel.editingMessage.value)
    }
    
    @Test
    fun `updateMessage should call repository and refresh full message`() = runTest {
        // Given
        val message = ChatMessage(id = 1L, conversationId = 1L, role = "user", text = "Updated message")
        coEvery { repository.getFullMessageById(1L) } returns null
        
        // When
        viewModel.updateMessage(message)
        advanceUntilIdle()
        
        // Then
        coVerify { repository.updateMessage(message) }
        coVerify { repository.getFullMessageById(1L) }
    }

    @Test
    fun `sendMessage while editing updates existing message without inserting a new one`() = runTest {
        // Given
        val original = ChatMessage(id = 10L, conversationId = 1L, role = "user", text = "Before")
        viewModel.startEditing(original)
        clearMocks(repository, answers = false, recordedCalls = true, verificationMarks = true)

        // When
        viewModel.sendMessage("After")
        advanceUntilIdle()

        // Then
        coVerify(exactly = 1) { repository.updateMessage(original.copy(text = "After")) }
        coVerify(exactly = 0) { repository.insertMessage(any()) }
        assertNull("Editing state should be cleared", viewModel.editingMessage.value)
    }

    // プリセット適用のテスト
    @Test
    fun `applyPreset should update conversation and settings`() = runTest {
        // Given
        val preset = ModelPreset(
            id = 1L,
            name = "Test Preset",
            model = "gemini-2.5-pro",
            apiProvider = "GEMINI",
            systemPrompt = "Test system prompt",
            thinkingEnabled = true,
            thinkingBudget = 2000
        )
        
        val conversation = createDefaultConversation()
        coEvery { repository.getConversationById(1L) } returns conversation
        
        // When
        viewModel.applyPreset(preset)
        advanceUntilIdle()
        
        // Then
        coVerify { 
            repository.upsertConversation(
                conversation.copy(
                    model = preset.model,
                    systemPrompt = preset.systemPrompt
                )
            )
        }
        
        coVerify { 
            repository.saveSettings(
                match { settings ->
                    settings.thinkingEnabled == preset.thinkingEnabled &&
                    settings.thinkingBudget == preset.thinkingBudget &&
                    settings.apiProvider == preset.apiProvider
                }
            )
        }
    }

    @Test
    fun `applyPreset should resolve named system prompt preset before inline prompt`() = runTest {
        // Given
        settingsFlow.value = createDefaultSettings().copy(
            systemPromptPresets = """[{"name":"Architect","prompt":"Preset prompt"}]"""
        )
        val preset = ModelPreset(
            id = 3L,
            name = "Named Prompt Preset",
            model = "gemini-2.5-pro",
            apiProvider = "GEMINI",
            systemPrompt = "Inline prompt",
            systemPromptPresetName = "architect"
        )
        val conversation = createDefaultConversation().copy(systemPrompt = "Existing prompt")
        coEvery { repository.getConversationById(1L) } returns conversation

        // When
        viewModel.applyPreset(preset)
        advanceUntilIdle()

        // Then
        coVerify {
            repository.upsertConversation(
                conversation.copy(
                    model = "gemini-2.5-pro",
                    systemPrompt = "Preset prompt",
                    apiProvider = "GEMINI"
                )
            )
        }
    }

    @Test
    fun `applyPreset should not overwrite conversation system prompt when preset has none`() = runTest {
        // Given
        val preset = ModelPreset(
            id = 2L,
            name = "API Only Preset",
            model = "deepseek/deepseek-chat",
            apiProvider = "OPENROUTER",
            systemPrompt = null
        )

        val conversation = createDefaultConversation().copy(
            apiProvider = "GEMINI",
            systemPrompt = "Existing system prompt"
        )
        coEvery { repository.getConversationById(1L) } returns conversation

        // When
        viewModel.applyPreset(preset)
        advanceUntilIdle()

        // Then
        coVerify {
            repository.upsertConversation(
                conversation.copy(
                    model = preset.model,
                    systemPrompt = "Existing system prompt",
                    apiProvider = preset.apiProvider.uppercase()
                )
            )
        }
    }

    // デュアルモード切り替えのテスト
    @Test
    fun `toggleDualMode should enable dual mode and disable auto conversation`() = runTest {
        // Given
        val settingsWithAutoConv = createDefaultSettings().copy(
            isDualModeEnabled = false,
            isAutoConversationEnabled = true
        )
        settingsFlow.value = settingsWithAutoConv
        advanceUntilIdle()

        // When
        viewModel.toggleDualMode()
        advanceUntilIdle()

        // Then
        coVerify(exactly = 1) { 
            repository.saveSettings(
                match { settings ->
                    settings.isDualModeEnabled == true &&
                    settings.isAutoConversationEnabled == false
                }
            )
        }
        assertTrue(viewModel.isDualModeActive.value)
        assertTrue(viewModel.dualChatSettings.value.isDualModeEnabled)
    }

    @Test
    fun `toggleDualMode should only toggle dual mode when auto conversation is disabled`() = runTest {
        // Given
        val settingsWithoutAutoConv = createDefaultSettings().copy(
            isDualModeEnabled = false,
            isAutoConversationEnabled = false
        )
        settingsFlow.value = settingsWithoutAutoConv
        advanceUntilIdle()

        // When
        viewModel.toggleDualMode()
        advanceUntilIdle()

        // Then
        coVerify(exactly = 1) { 
            repository.saveSettings(
                match { settings ->
                    settings.isDualModeEnabled == true &&
                    settings.isAutoConversationEnabled == false  // remains false
                }
            )
        }
        assertTrue(viewModel.isDualModeActive.value)
        assertTrue(viewModel.dualChatSettings.value.isDualModeEnabled)
    }

    @Test
    fun `toggleAutoConversation should enable auto conversation and disable dual mode`() = runTest {
        // Given
        val settingsWithDualMode = createDefaultSettings().copy(
            isDualModeEnabled = true,
            isAutoConversationEnabled = false
        )
        settingsFlow.value = settingsWithDualMode
        advanceUntilIdle()

        // When
        viewModel.toggleAutoConversation()
        advanceUntilIdle()

        // Then
        coVerify(exactly = 1) { 
            repository.saveSettings(
                match { settings ->
                    settings.isAutoConversationEnabled == true &&
                    settings.isDualModeEnabled == false
                }
            )
        }
        assertFalse(viewModel.isDualModeActive.value)
        assertFalse(viewModel.dualChatSettings.value.isDualModeEnabled)
    }

    // デュアルチャット設定のテスト
    @Test
    fun `updateDualChatSettings should update repository and local state`() = runTest {
        // Given
        val newSettings = DualChatSettings(
            isDualModeEnabled = true,
            modelA = "gemini-2.5-pro",
            modelB = "gemini-2.5-flash",
            providerA = "GEMINI",
            providerB = "GEMINI",
            splitLayout = SplitLayoutType.HORIZONTAL,
            splitRatio = 0.6f
        )
        
        // When
        viewModel.updateDualChatSettings(newSettings)
        advanceUntilIdle()
        
        // Then
        coVerify { 
            repository.saveSettings(
                match { settings ->
                    settings.isDualModeEnabled == true &&
                    settings.dualModelA == "gemini-2.5-pro" &&
                    settings.dualModelB == "gemini-2.5-flash" &&
                    settings.dualSplitLayout == "HORIZONTAL" &&
                    settings.dualSplitRatio == 0.6f
                }
            )
        }
        
        assertEquals("Should update local dual chat settings", newSettings, viewModel.dualChatSettings.value)
        assertTrue("Should update dual mode active state", viewModel.isDualModeActive.value)
    }

    // エッジケースのテスト
    @Test
    fun `addAttachment with multiple files should maintain all valid attachments`() = runTest {
        // Given
        val uri1 = mockk<Uri>()
        val uri2 = mockk<Uri>()
        val uri3 = mockk<Uri>() // Invalid file
        
        val validResult = FileValidationUtils.FileValidationResult.Valid("image/jpeg", 1024L)
        val invalidResult = FileValidationUtils.FileValidationResult.TooLarge(15 * 1024 * 1024L)
        
        coEvery { repository.validateFile(uri1) } returns validResult
        coEvery { repository.validateFile(uri2) } returns validResult
        coEvery { repository.validateFile(uri3) } returns invalidResult
        
        // When
        viewModel.addAttachment(uri1)
        viewModel.addAttachment(uri2)
        viewModel.addAttachment(uri3)
        advanceUntilIdle()
        
        // Then
        val attachments = viewModel.attachments.value
        assertTrue("Should contain first valid attachment", attachments.contains(uri1))
        assertTrue("Should contain second valid attachment", attachments.contains(uri2))
        assertFalse("Should not contain invalid attachment", attachments.contains(uri3))
        assertEquals("Should have exactly 2 valid attachments", 2, attachments.size)
    }

    @Test
    fun `addAttachment rejects images when model does not support vision`() = runTest {
        coEvery { repository.resolveCanAttachImages(any(), any(), any()) } returns false
        settingsFlow.value = createDefaultSettings().copy(defaultModel = "text-only")
        advanceUntilIdle()

        val imageUri = mockk<Uri>()
        val fileUri = mockk<Uri>()
        coEvery { repository.validateFile(imageUri) } returns
            FileValidationUtils.FileValidationResult.Valid("image/png", 512L)
        coEvery { repository.validateFile(fileUri) } returns
            FileValidationUtils.FileValidationResult.Valid("application/pdf", 2048L)

        viewModel.addAttachment(imageUri)
        advanceUntilIdle()
        assertFalse(viewModel.attachments.value.contains(imageUri))
        assertEquals("このモデルは画像入力に対応していません。", viewModel.errorMessage.value)

        viewModel.addAttachment(fileUri)
        advanceUntilIdle()
        assertTrue(viewModel.attachments.value.contains(fileUri))
    }
    
    @Test
    fun `toggleAutoConversation should keep dual mode disabled when enabling from normal mode`() = runTest {
        // Given
        settingsFlow.value = createDefaultSettings().copy(
            isDualModeEnabled = false,
            isAutoConversationEnabled = false
        )
        advanceUntilIdle()
        clearMocks(repository, answers = false, recordedCalls = true, verificationMarks = true)
        
        // When
        viewModel.toggleAutoConversation()
        advanceUntilIdle()

        // Then
        coVerify(exactly = 1) {
            repository.saveSettings(
                match { settings ->
                    settings.isAutoConversationEnabled &&
                        !settings.isDualModeEnabled
                }
            )
        }
        assertFalse(viewModel.isDualModeActive.value)
        assertFalse(viewModel.dualChatSettings.value.isDualModeEnabled)
    }
}


private fun ChatViewModel.triggerOnClearedForTest() {
    val method = ChatViewModel::class.java.getDeclaredMethod("onCleared")
    method.isAccessible = true
    method.invoke(this)
}

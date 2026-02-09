package com.porarri.yamabikochat.ui.chat

import android.net.Uri
import android.util.Log
import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.porarri.yamabikochat.data.ChatRepository
import com.porarri.yamabikochat.data.local.ChatMessage
import com.porarri.yamabikochat.utils.FileValidationUtils
import com.porarri.yamabikochat.data.local.ChatMessageSummary
import com.porarri.yamabikochat.data.local.FullChatMessage
import com.porarri.yamabikochat.data.remote.Content
import com.porarri.yamabikochat.data.local.Settings
import com.porarri.yamabikochat.data.local.Conversation
import com.porarri.yamabikochat.data.local.DualChatMessage
import com.porarri.yamabikochat.data.local.SplitLayoutType
import com.porarri.yamabikochat.data.local.DualChatSettings
import com.porarri.yamabikochat.data.AutoConversationManager
import com.porarri.yamabikochat.data.local.AutoConversationConfig
import com.porarri.yamabikochat.data.local.AutoConversationMessage
import com.porarri.yamabikochat.data.displayContent
import com.porarri.yamabikochat.ui.chat.logic.ChatInteractionCoordinator
import com.porarri.yamabikochat.ui.chat.logic.ChatResponseStreamer
import com.porarri.yamabikochat.ui.chat.logic.DualChatResponder
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.filterNotNull
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.serialization.json.Json
import kotlinx.coroutines.withContext

class ChatViewModel(
    private val repository: ChatRepository,
    private val savedStateHandle: SavedStateHandle
) : ViewModel() {
    // --- Helpers to keep reasoning (CoT) out of final content when models inline it ---
    private fun splitReasoningBlocks(input: String): Pair<String, String> {
        if (input.isEmpty()) return input to ""
        var working = input
        val extracted = StringBuilder()

        // <think> ... </think>
        val thinkRegex = Regex("(?is)<think>(.*?)</think>")
        thinkRegex.findAll(working).forEach { m ->
            extracted.append(m.groups[1]?.value ?: "")
        }
        working = thinkRegex.replace(working, "")

        // ```thinking ... ``` fenced block
        val fencedRegex = Regex("""(?is)```\s*thinking\s*\n(.*?)```""")
        fencedRegex.findAll(working).forEach { m ->
            extracted.append(m.groups[1]?.value ?: "")
        }
        working = fencedRegex.replace(working, "")

        return working to extracted.toString()
    }

    private fun buildBranchTitle(baseTitle: String, messageText: String?): String {
        val normalized = messageText
            ?.replace(Regex("\\s+"), " ")
            ?.trim()
            .orEmpty()
        val snippet = when {
            normalized.length > 32 -> normalized.take(32).trimEnd() + "..."
            else -> normalized
        }
        return if (baseTitle.isBlank() || baseTitle == "New Chat") {
            if (snippet.isNotBlank()) "ブランチ: $snippet" else "ブランチ"
        } else {
            "ブランチ: $baseTitle"
        }
    }
    
    // AutoConversationManager
    private val autoConversationManager = AutoConversationManager(repository, viewModelScope)

    private val historyBuilder = ConversationHistoryBuilder(repository)
    private val jsonAdapter = Json { ignoreUnknownKeys = true }
    private val responseStreamer = ChatResponseStreamer(repository, ::splitReasoningBlocks, jsonAdapter)
    private val dualChatResponder = DualChatResponder(repository)
    private val interactionCoordinator = ChatInteractionCoordinator(
        repository,
        historyBuilder,
        responseStreamer,
        dualChatResponder
    )

    private var conversationId: Long = savedStateHandle.get<String>("conversationId")?.toLongOrNull() ?: 0
    private val conversationIdFlow = MutableStateFlow<Long?>(conversationId.takeIf { it != 0L })
    private var autoConversationObservationJob: Job? = null
    private var autoConversationTargetConversationId: Long? = conversationId.takeIf { it != 0L }

    private val _messages = MutableStateFlow<List<ChatMessageSummary>>(emptyList())
    val messages: StateFlow<List<ChatMessageSummary>> = _messages.asStateFlow()

    private val _fullMessages = MutableStateFlow<Map<Long, FullChatMessage>>(emptyMap())
    val fullMessages: StateFlow<Map<Long, FullChatMessage>> = _fullMessages.asStateFlow()

    // デュアルモード関連のStateFlow
    private val _dualMessages = MutableStateFlow<List<DualChatMessage>>(emptyList())
    val dualMessages: StateFlow<List<DualChatMessage>> = _dualMessages.asStateFlow()

    private val _dualChatSettings = MutableStateFlow(DualChatSettings())
    val dualChatSettings: StateFlow<DualChatSettings> = _dualChatSettings.asStateFlow()

    private val _isDualModeActive = MutableStateFlow(false)
    val isDualModeActive: StateFlow<Boolean> = _isDualModeActive.asStateFlow()
    
    // 自動会話関連のStateFlow
    private val _isAutoConversationRunning = MutableStateFlow(false)
    val isAutoConversationRunning: StateFlow<Boolean> = _isAutoConversationRunning.asStateFlow()
    
    private val _autoConversationStatus = MutableStateFlow<String?>(null)
    val autoConversationStatus: StateFlow<String?> = _autoConversationStatus.asStateFlow()

    private fun fetchFullMessage(messageId: Long) {
        viewModelScope.launch {
            val fullMessage = repository.getFullMessageById(messageId)
            if (fullMessage != null) {
                _fullMessages.update { it + (messageId to fullMessage) }
            }
        }
    }

    private val _editingMessage = MutableStateFlow<ChatMessage?>(null)
    val editingMessage: StateFlow<ChatMessage?> = _editingMessage.asStateFlow()

    private val _attachments = MutableStateFlow<List<Uri>>(emptyList())
    val attachments: StateFlow<List<Uri>> = _attachments.asStateFlow()

    private val _errorMessage = MutableStateFlow<String?>(null)
    val errorMessage: StateFlow<String?> = _errorMessage.asStateFlow()

    // 現在の会話（モデル/プロバイダー表示用）
    private val _conversation = MutableStateFlow<com.porarri.yamabikochat.data.local.Conversation?>(null)
    val conversation: StateFlow<com.porarri.yamabikochat.data.local.Conversation?> = _conversation.asStateFlow()

    private val settings: StateFlow<Settings?> = repository.getSettings()
        .stateIn(viewModelScope, SharingStarted.Eagerly, null)

    private var lastSettingsSnapshot: Settings? = null

    private suspend fun syncNewChatWithSettingsIfEmpty(settings: Settings) {
        val previous = lastSettingsSnapshot
        lastSettingsSnapshot = settings
        val currentId = conversationId
        if (currentId == 0L) return
        val conversation = repository.getConversationById(currentId) ?: return
        if (conversation.title != "New Chat") return
        if (_messages.value.isNotEmpty() || _dualMessages.value.isNotEmpty()) return

        val shouldSync = previous == null || (
            conversation.apiProvider.equals(previous.apiProvider, ignoreCase = true) &&
                conversation.model.ifBlank { previous.getCurrentModel() } ==
                previous.getCurrentModel() &&
                conversation.systemPrompt.orEmpty() == previous.systemPrompt.orEmpty()
            )
        if (!shouldSync) return

        val newProvider = settings.apiProvider
        val newModel = settings.getCurrentModel()
        val newPrompt = settings.systemPrompt
        if (conversation.apiProvider != newProvider ||
            conversation.model != newModel ||
            conversation.systemPrompt != newPrompt
        ) {
            repository.upsertConversation(
                conversation.copy(
                    apiProvider = newProvider,
                    model = newModel,
                    systemPrompt = newPrompt
                )
            )
            _conversation.value = repository.getConversationById(currentId)
        }
    }

    init {
        // AutoConversationManagerのコールバックを設定
        autoConversationManager.onNewMessage = { speakerModel, content, targetConversationId ->
            viewModelScope.launch {
                try {
                    val messageText = "**[$speakerModel]**\n\n$content"
                    val chatMessage = ChatMessage(
                        conversationId = targetConversationId,
                        role = "model",
                        text = messageText,
                        attachments = emptyList()
                    )
                    repository.insertMessage(chatMessage)
                } catch (e: Exception) {
                    android.util.Log.e("ChatViewModel", "Error integrating auto conversation message", e)
                }
            }
        }
        
        viewModelScope.launch {
            if (conversationId == 0L) {
                val existingConversation =
                    repository.findLatestEmptyConversationByTitle("New Chat")
                val resolvedConversationId = existingConversation?.id ?: run {
                    val currentSettings = repository.getSettings().first() ?: Settings()
                    repository.upsertConversation(
                        com.porarri.yamabikochat.data.local.Conversation(
                            title = "New Chat",
                            systemPrompt = currentSettings.systemPrompt,
                            model = currentSettings.getCurrentModel(),
                            apiProvider = currentSettings.apiProvider
                        )
                    )
                }

                savedStateHandle["conversationId"] = resolvedConversationId.toString()
                conversationId = resolvedConversationId
                conversationIdFlow.value = resolvedConversationId
                autoConversationTargetConversationId = resolvedConversationId
                // 生成した会話をロード
                _conversation.value = repository.getConversationById(resolvedConversationId)
                val currentSettings = repository.getSettings().first() ?: Settings()
                syncNewChatWithSettingsIfEmpty(currentSettings)
            } else {
                conversationIdFlow.value = conversationId
                autoConversationTargetConversationId = conversationId
                // 既存会話をロード
                _conversation.value = repository.getConversationById(conversationId)
                val currentSettings = repository.getSettings().first() ?: Settings()
                syncNewChatWithSettingsIfEmpty(currentSettings)
            }
        }

        // 通常メッセージを監視（conversationIdが設定された後）
        viewModelScope.launch {
            conversationIdFlow
                .filterNotNull()
                .flatMapLatest { id -> repository.getMessagesForConversation(id) }
                .collectLatest { summaries ->
                    _messages.value = summaries
                    summaries.forEach { summary ->
                        if (!_fullMessages.value.containsKey(summary.id)) {
                            fetchFullMessage(summary.id)
                        }
                    }
                }
        }

        // デュアルメッセージを監視（conversationIdが設定された後）
        viewModelScope.launch {
            conversationIdFlow
                .filterNotNull()
                .flatMapLatest { id -> repository.getDualMessagesForConversation(id) }
                .collectLatest { duals ->
                    _dualMessages.value = duals
                }
        }

        // 設定を監視してデュアルモード設定を更新
        viewModelScope.launch {
            repository.getSettings().collect { settings ->
                if (settings != null) {
                    _dualChatSettings.value = DualChatSettings(
                        isDualModeEnabled = settings.isDualModeEnabled,
                        modelA = settings.dualModelA,
                        modelB = settings.dualModelB,
                        providerA = settings.dualProviderA,
                        providerB = settings.dualProviderB,
                        splitLayout = when (settings.dualSplitLayout) {
                            "HORIZONTAL" -> SplitLayoutType.HORIZONTAL
                            else -> SplitLayoutType.VERTICAL
                        },
                        splitRatio = settings.dualSplitRatio
                    )
                    _isDualModeActive.value = settings.isDualModeEnabled
                    syncNewChatWithSettingsIfEmpty(settings)
                }
            }
        }

        viewModelScope.launch {
            var wasRunning = false
            autoConversationManager.isRunning.collect { running ->
                if (!running && wasRunning) {
                    integrateAutoConversationResults()
                    if (_autoConversationStatus.value?.contains("停止") != true) {
                        _autoConversationStatus.value = "自動会話が完了しました"
                    }
                    autoConversationTargetConversationId = null
                }
                wasRunning = running
                _isAutoConversationRunning.value = running
                if (!running) {
                    autoConversationObservationJob?.cancel()
                    autoConversationObservationJob = null
                }
            }
        }
    }

    fun addAttachment(uri: Uri) {
        viewModelScope.launch {
            when (val result = repository.validateFile(uri)) {
                is FileValidationUtils.FileValidationResult.Valid -> {
                    _attachments.update { it + uri }
                    _errorMessage.value = null
                }
                is FileValidationUtils.FileValidationResult.TooLarge -> {
                    val sizeMB = result.fileSize / (1024 * 1024)
                    _errorMessage.value = "ファイルサイズが${sizeMB}MBで、10MB制限を超えています。より小さなファイルを選択してください。"
                }
                is FileValidationUtils.FileValidationResult.TooSmall -> {
                    _errorMessage.value = "ファイルサイズが小さすぎます。"
                }
                is FileValidationUtils.FileValidationResult.UnsupportedType -> {
                    _errorMessage.value = "サポートされていないファイル形式です。"
                }
                is FileValidationUtils.FileValidationResult.DangerousFile -> {
                    _errorMessage.value = "危険なファイル形式です。このファイルはアップロードできません。"
                }
                is FileValidationUtils.FileValidationResult.CorruptedFile -> {
                    _errorMessage.value = "ファイルが破損しているか、形式が正しくありません。"
                }
                is FileValidationUtils.FileValidationResult.Error -> {
                    _errorMessage.value = "ファイルの読み込みに失敗しました: ${result.message}"
                }
            }
        }
    }

    fun removeAttachment(uri: Uri) {
        _attachments.update { it - uri }
        _errorMessage.value = null
    }

    fun clearErrorMessage() {
        _errorMessage.value = null
    }

    private fun clearAttachments() {
        _attachments.value = emptyList()
        _errorMessage.value = null
    }

    fun sendMessage(text: String) {
        val attachmentsToSend = _attachments.value
        viewModelScope.launch {
            val editing = _editingMessage.value
            if (editing != null) {
                repository.updateMessage(editing.copy(text = text))
                _editingMessage.value = null
                return@launch
            }

            val conversation = withContext(Dispatchers.IO) { repository.getConversationById(conversationId) }
            _conversation.value = conversation
            val currentSettings = settings.value ?: Settings()

            if (currentSettings.isDualModeEnabled) {
                clearAttachments()
                interactionCoordinator.sendDualMessage(
                    conversationId = conversationId,
                    text = text,
                    attachments = attachmentsToSend,
                    dualMessages = _dualMessages.value,
                    settings = currentSettings
                )
                return@launch
            }

            if (conversation == null) {
                Log.e("ChatViewModel", "No conversation found for id: $conversationId")
                return@launch
            }

            val isAutoConvEnabled = currentSettings.isAutoConversationEnabled
            val isTriggerMessage = isAutoConversationTrigger(text)

            interactionCoordinator.sendSingleMessage(
                ChatInteractionCoordinator.SingleMessageContext(
                    conversation = conversation,
                    settings = currentSettings,
                    text = text,
                    attachments = attachmentsToSend,
                    messageSummaries = _messages.value,
                    fullMessagesState = _fullMessages,
                    fetchFullMessage = { fetchFullMessage(it) },
                    scope = viewModelScope,
                    skipModelResponse = isAutoConvEnabled && isTriggerMessage
                )
            )

            clearAttachments()

            if (isAutoConvEnabled && isTriggerMessage) {
                startAutoConversation(text)
            }
        }
    }

    suspend fun createSecretConversation(): Long? {
        return withContext(Dispatchers.IO) {
            try {
                val currentSettings = settings.value ?: repository.getSettings().first() ?: Settings()
                repository.upsertConversation(
                    Conversation(
                        title = "シークレットチャット",
                        systemPrompt = currentSettings.systemPrompt,
                        model = currentSettings.getCurrentModel(),
                        apiProvider = currentSettings.apiProvider,
                        isSecret = true
                    )
                )
            } catch (e: Exception) {
                Log.e("ChatViewModel", "Failed to create secret conversation", e)
                _errorMessage.value = "シークレットチャットの作成に失敗しました: ${e.message}"
                null
            }
        }
    }

    fun setSecretMode(enabled: Boolean) {
        viewModelScope.launch {
            val conversation = repository.getConversationById(conversationId)
            if (conversation == null) {
                _errorMessage.value = "会話が見つかりませんでした"
                return@launch
            }
            val hasChatMessages = repository.getMessagesForConversation(conversationId).first().isNotEmpty()
            val hasDualMessages = repository.getDualMessagesForConversation(conversationId).first().isNotEmpty()
            if (hasChatMessages || hasDualMessages) {
                _errorMessage.value = "送信後はシークレット切替できません"
                return@launch
            }
            if (conversation.isSecret == enabled) return@launch
            repository.upsertConversation(conversation.copy(isSecret = enabled))
            _conversation.value = repository.getConversationById(conversationId)
        }
    }

    fun startEditing(message: ChatMessage) {
        _editingMessage.value = message
    }

    fun fetchMessageForEditing(messageId: Long) {
        viewModelScope.launch {
            _editingMessage.value = repository.getFullMessageById(messageId)?.chatMessage
        }
    }

    suspend fun getFullMessageById(id: Long): com.porarri.yamabikochat.data.local.FullChatMessage? {
        return repository.getFullMessageById(id)
    }
    
    fun updateMessage(message: ChatMessage) {
        viewModelScope.launch {
            repository.updateMessage(message)
            // UI状態を更新するために、更新されたメッセージを再取得
            fetchFullMessage(message.id)
        }
    }

    suspend fun branchConversationFromMessage(messageId: Long): Long? {
        return withContext(Dispatchers.IO) {
            try {
                val currentConversation =
                    repository.getConversationById(conversationId)
                        ?: run {
                            _errorMessage.value = "会話が見つかりませんでした"
                            return@withContext null
                        }
                val summaries = repository.getMessagesForConversation(conversationId).first()
                if (summaries.isEmpty()) {
                    _errorMessage.value = "メッセージがありません"
                    return@withContext null
                }
                val targetIndex = summaries.indexOfFirst { it.id == messageId }
                if (targetIndex == -1) {
                    _errorMessage.value = "指定メッセージが見つかりませんでした"
                    return@withContext null
                }
                val selectedSummaries = summaries.take(targetIndex + 1)
                val fullMap =
                    repository.getFullMessagesByIds(selectedSummaries.map { it.id })
                val branchSourceText =
                    fullMap[messageId]?.chatMessage?.text ?: selectedSummaries.last().textPreview
                val branchTitle = buildBranchTitle(currentConversation.title, branchSourceText)
                val newConversationId = repository.upsertConversation(
                    currentConversation.copy(
                        id = 0,
                        title = branchTitle,
                        timestamp = System.currentTimeMillis()
                    )
                )
                selectedSummaries.forEach { summary ->
                    val full = fullMap[summary.id] ?: return@forEach
                    val original = full.chatMessage
                    val newMessageId = repository.insertMessage(
                        original.copy(
                            id = 0,
                            conversationId = newConversationId
                        )
                    )
                    if (!full.thinkingStream.isNullOrBlank()) {
                        repository.insertThinking(newMessageId, full.thinkingStream)
                    }
                }
                newConversationId
            } catch (e: Exception) {
                Log.e("ChatViewModel", "Error branching conversation", e)
                _errorMessage.value = "ブランチの作成に失敗しました: ${e.message}"
                null
            }
        }
    }

    fun applyPreset(preset: com.porarri.yamabikochat.data.local.ModelPreset) {
        viewModelScope.launch {
            val conversation = repository.getConversationById(conversationId)
            if (conversation != null) {
                val currentSettings = settings.value ?: Settings()
                val presetPrompt = preset.systemPromptPresetName
                    ?.takeIf { it.isNotBlank() }
                    ?.let { name ->
                        currentSettings.getSystemPromptPresetsList()
                            .firstOrNull { it.name.equals(name, ignoreCase = true) }
                            ?.prompt
                    }
                val resolvedSystemPrompt = presetPrompt ?: preset.systemPrompt ?: conversation.systemPrompt
                repository.upsertConversation(
                    conversation.copy(
                        model = preset.model,
                        systemPrompt = resolvedSystemPrompt,
                        apiProvider = preset.apiProvider.uppercase()
                    )
                )
                _conversation.value = repository.getConversationById(conversationId)
                val baseThinkingUpdate = currentSettings.copy(
                    thinkingEnabled = preset.thinkingEnabled,
                    thinkingBudget = preset.thinkingBudget,
                    geminiThinkingLevel = preset.thinkingLevel,
                    geminiThinkingEnabled = preset.thinkingEnabled,
                    geminiThinkingBudget = preset.thinkingBudget
                )
                val updatedSettings = when (preset.apiProvider.uppercase()) {
                    "OPENROUTER" -> currentSettings.copy(
                        thinkingEnabled = preset.thinkingEnabled,
                        thinkingBudget = preset.thinkingBudget,
                        openRouterThinkingEnabled = preset.thinkingEnabled,
                        openRouterThinkingBudget = preset.thinkingBudget,
                        openRouterReasoningMode = preset.reasoningMode,
                        openRouterReasoningEffort = preset.reasoningEffort,
                        openRouterReasoningExclude = preset.reasoningExclude,
                        openRouterGoogleSearchEnabled = preset.googleSearchEnabled,
                        openRouterCodeExecutionEnabled = preset.codeExecutionEnabled
                    )
                    "CODEX_AUTH" -> currentSettings.copy(
                        thinkingEnabled = preset.thinkingEnabled,
                        thinkingBudget = preset.thinkingBudget,
                        codexReasoningEnabled = preset.thinkingEnabled,
                        codexReasoningEffort = preset.reasoningEffort.ifBlank { currentSettings.codexReasoningEffort },
                        codexReasoningSummary = preset.codexReasoningSummary,
                        codexVerbosity = preset.codexVerbosity,
                        codexSupportsReasoningSummaries = preset.codexSupportsReasoningSummaries,
                        codexShowReasoningSummary = preset.codexShowReasoningSummary,
                        codexWebSearchEnabled = preset.codexWebSearchEnabled,
                        codexWebSearchContextSize = preset.codexWebSearchContextSize,
                        codexPromptCacheEnabled = preset.codexPromptCacheEnabled,
                        codexPromptCacheMinLength = preset.codexPromptCacheMinLength,
                        codexPromptCacheType = preset.codexPromptCacheType
                    )
                    "GEMINI", "GEMINI_AUTH" -> currentSettings.copy(
                        thinkingEnabled = preset.thinkingEnabled,
                        thinkingBudget = preset.thinkingBudget,
                        geminiThinkingLevel = preset.thinkingLevel,
                        geminiThinkingEnabled = preset.thinkingEnabled,
                        geminiThinkingBudget = preset.thinkingBudget,
                        geminiGoogleSearchEnabled = preset.googleSearchEnabled,
                        geminiCodeExecutionEnabled = preset.codeExecutionEnabled,
                        geminiUrlContextEnabled = preset.urlContextEnabled,
                        geminiGoogleMapsEnabled = preset.googleMapsEnabled,
                        geminiComputerUseEnabled = preset.computerUseEnabled,
                        geminiResponseMimeType = preset.responseMimeType,
                        geminiResponseJsonSchema = preset.responseJsonSchema,
                        geminiFunctionDeclarations = preset.functionDeclarations
                    )
                    "OPENAI_COMPAT" -> {
                        val compatName = preset.openAiCompatPresetName?.takeIf { it.isNotBlank() }
                        if (compatName == null) {
                            baseThinkingUpdate
                        } else {
                            baseThinkingUpdate.copy(selectedOpenAiCompatPreset = compatName)
                        }
                    }
                    else -> baseThinkingUpdate
                }
                repository.saveSettings(updatedSettings)
            }
        }
    }

    fun regenerateMessage(messageId: Long) {
        viewModelScope.launch {
            val conversation = repository.getConversationById(conversationId)
            if (conversation == null) {
                _errorMessage.value = "会話が見つかりませんでした"
                return@launch
            }

            val currentSettings = settings.value ?: Settings()
            if (currentSettings.isDualModeEnabled) {
                _errorMessage.value = "デュアルモードでは再生成できません"
                return@launch
            }

            val summaries = repository.getMessagesForConversation(conversationId).first()
            if (summaries.isEmpty()) {
                _errorMessage.value = "メッセージがありません"
                return@launch
            }

            val targetIndex = summaries.indexOfFirst { it.id == messageId }
            if (targetIndex == -1) {
                _errorMessage.value = "指定メッセージが見つかりませんでした"
                return@launch
            }

            val targetSummary = summaries[targetIndex]
            if (targetSummary.role != "model") {
                _errorMessage.value = "再生成はAIメッセージのみ対応しています"
                return@launch
            }

            if (targetIndex != summaries.lastIndex) {
                _errorMessage.value = "最後の応答のみ再生成できます。過去の応答は「ここからブランチ」を使用してください。"
                return@launch
            }

            val userIndex = targetIndex - 1
            if (userIndex < 0 || summaries[userIndex].role != "user") {
                _errorMessage.value = "このメッセージは再生成できません"
                return@launch
            }

            val userMessage = repository.getFullMessageById(summaries[userIndex].id)
            if (userMessage == null) {
                _errorMessage.value = "元のユーザーメッセージが見つかりませんでした"
                return@launch
            }

            interactionCoordinator.regenerateMessage(
                ChatInteractionCoordinator.RegenerateMessageContext(
                    conversation = conversation,
                    settings = currentSettings,
                    userMessage = userMessage.chatMessage,
                    messageSummariesBefore = summaries.take(userIndex),
                    fullMessagesState = _fullMessages,
                    fetchFullMessage = { fetchFullMessage(it) },
                    scope = viewModelScope,
                    targetMessageId = messageId
                )
            )
        }
    }

    // デュアルモード設定を更新
    fun updateDualChatSettings(settings: DualChatSettings) {
        viewModelScope.launch {
            val currentSettings = this@ChatViewModel.settings.value ?: Settings()
            val updatedSettings = currentSettings.copy(
                isDualModeEnabled = settings.isDualModeEnabled,
                dualModelA = settings.modelA,
                dualModelB = settings.modelB,
                dualProviderA = settings.providerA,
                dualProviderB = settings.providerB,
                dualSplitLayout = when (settings.splitLayout) {
                    SplitLayoutType.HORIZONTAL -> "HORIZONTAL"
                    SplitLayoutType.VERTICAL -> "VERTICAL"
                },
                dualSplitRatio = settings.splitRatio
            )
            repository.saveSettings(updatedSettings)
            _dualChatSettings.value = settings
            _isDualModeActive.value = settings.isDualModeEnabled
        }
    }
    
    // 排他制御付きデュアルモード切り替え
    fun toggleDualMode() {
        viewModelScope.launch {
            val currentSettings = settings.value ?: return@launch
            val newDualModeState = !currentSettings.isDualModeEnabled
            
            // デュアルモードをオンにする場合、自動会話を無効化
            if (newDualModeState && currentSettings.isAutoConversationEnabled) {
                // 実行中の自動会話があれば停止
                if (_isAutoConversationRunning.value) {
                    stopAutoConversation()
                }
                // 設定を更新（自動会話を無効化）
                repository.saveSettings(currentSettings.copy(
                    isDualModeEnabled = newDualModeState,
                    isAutoConversationEnabled = false
                ))
            } else {
                // 通常のデュアルモード切り替え
                repository.saveSettings(currentSettings.copy(isDualModeEnabled = newDualModeState))
            }
            
            // ローカル状態も更新
            _dualChatSettings.update { it.copy(isDualModeEnabled = newDualModeState) }
            _isDualModeActive.value = newDualModeState
        }
    }
    
    // 排他制御付き自動会話切り替え
    fun toggleAutoConversation() {
        viewModelScope.launch {
            val currentSettings = settings.value ?: return@launch
            val newAutoConversationState = !currentSettings.isAutoConversationEnabled
            
            // 自動会話をオンにする場合、デュアルモードを無効化
            if (newAutoConversationState && currentSettings.isDualModeEnabled) {
                // 設定を更新（デュアルモードを無効化）
                val newSettings = currentSettings.copy(
                    isAutoConversationEnabled = newAutoConversationState,
                    isDualModeEnabled = false
                )
                repository.saveSettings(newSettings)
                // ローカル状態も更新
                _dualChatSettings.update { it.copy(isDualModeEnabled = false) }
                _isDualModeActive.value = false
            } else if (!newAutoConversationState && _isAutoConversationRunning.value) {
                // 自動会話をオフにする場合、実行中であれば停止
                stopAutoConversation()
                val newSettings = currentSettings.copy(isAutoConversationEnabled = newAutoConversationState)
                repository.saveSettings(newSettings)
            } else {
                // 通常の自動会話切り替え
                val newSettings = currentSettings.copy(isAutoConversationEnabled = newAutoConversationState)
                repository.saveSettings(newSettings)
            }
        }
    }
    
    // 自動会話関連のメソッド
    
    /**
     * 自動会話のトリガーとなるメッセージかどうかを判定
     * 自動会話がオンの時は、意味のあるメッセージなら開始する
     */
    private fun isAutoConversationTrigger(text: String): Boolean {
        val trimmedText = text.trim()
        
        // 空のメッセージや明らかにテスト目的の短いメッセージは除外
        if (trimmedText.length < 2) return false
        
        val lowerText = trimmedText.lowercase()
        
        // 明らかにテスト目的のメッセージを除外
        val testPatterns = listOf(
            "a", "test", "テスト", "t", "1", "2", "3", "4", "5", "6", "7", "8", "9", "0",
            "aa", "aaa", "bb", "cc", "dd", "ee", "ff", "gg", "hh", "ii", "jj", "kk"
        )
        
        if (testPatterns.contains(lowerText)) return false
        
        // 特定のトリガーワードがある場合は確実に開始
        val strongTriggers = listOf(
            "こんにちは", "会話", "話", "議論", "ディスカッション", "チャット",
            "について", "どう思う", "考える", "語る", "相談", "質問"
        )
        
        if (strongTriggers.any { trigger -> lowerText.contains(trigger) }) {
            return true
        }
        
        // 3文字以上で疑問符や感嘆符を含む場合も開始
        if (trimmedText.length >= 3 && (lowerText.contains("？") || lowerText.contains("?") || lowerText.contains("！") || lowerText.contains("!"))) {
            return true
        }
        
        // 5文字以上の意味のありそうなメッセージは開始
        if (trimmedText.length >= 5) {
            // ひらがな、カタカナ、漢字、アルファベットの組み合わせをチェック
            val hasJapanese = lowerText.any { it in 'あ'..'ん' || it in 'ア'..'ン' || it.code > 0x3000 }
            val hasAlphabet = lowerText.any { it in 'a'..'z' }
            
            if (hasJapanese || hasAlphabet) {
                return true
            }
        }
        
        return false
    }
    
    /**
     * 自動会話を開始
     */
    private fun startAutoConversation(initialMessage: String) {
        viewModelScope.launch {
            try {
                _isAutoConversationRunning.value = true
                _autoConversationStatus.value = "自動会話を開始しています..."
                
                val currentSettings = settings.value
                if (currentSettings == null) {
                    _autoConversationStatus.value = null
                    _isAutoConversationRunning.value = false
                    return@launch
                }
                
                // AutoConversationConfigを作成
                val config = AutoConversationConfig(
                    title = "自動会話: ${initialMessage.take(20)}...",
                    modelA = currentSettings.autoModelA,
                    modelB = currentSettings.autoModelB,
                    providerA = currentSettings.autoProviderA,
                    providerB = currentSettings.autoProviderB,
                    systemPromptA = currentSettings.autoSystemPromptA,
                    systemPromptB = currentSettings.autoSystemPromptB,
                    maxTurns = currentSettings.autoMaxTurns
                )
                
                
                // AutoConversationManagerで自動会話を開始
                val targetConversationId = conversationId
                autoConversationTargetConversationId = targetConversationId
                val result = autoConversationManager.startConversation(
                    config,
                    initialMessage,
                    targetConversationId
                )

                if (result.isSuccess) {
                    _autoConversationStatus.value = "自動会話が進行中です..."

                    // 自動会話の進行を監視（少し遅延を入れる）
                    autoConversationObservationJob?.cancel()
                    kotlinx.coroutines.delay(500) // AutoConversationManagerの初期化を待つ
                    observeAutoConversation()

                } else {
                    val error = result.exceptionOrNull()
                    android.util.Log.e("ChatViewModel", "Failed to start auto conversation", error)
                    _errorMessage.value = "自動会話の開始に失敗しました: ${error?.message}"
                    _autoConversationStatus.value = null
                    _isAutoConversationRunning.value = false
                    autoConversationTargetConversationId = null
                }
                
            } catch (e: Exception) {
                android.util.Log.e("ChatViewModel", "Error starting auto conversation", e)
                _errorMessage.value = "自動会話でエラーが発生しました: ${e.message}"
                _autoConversationStatus.value = null
                _isAutoConversationRunning.value = false
            }
        }
    }
    
    /**
     * 自動会話の進行を監視（簡素化版）
     */
    private fun observeAutoConversation() {
        autoConversationObservationJob?.cancel()
        autoConversationObservationJob = viewModelScope.launch {
            try {
                autoConversationManager.currentConversationId
                    .filterNotNull()
                    .flatMapLatest { id -> repository.getAutoConversationMessages(id) }
                    .collectLatest { messages ->
                        val messageCount = messages.count { it.speakerModel != "USER" }
                        val isRunning = autoConversationManager.isRunning.value
                        _autoConversationStatus.value = if (isRunning) {
                            "自動会話進行中 (${messageCount}件のメッセージ)"
                        } else {
                            "自動会話完了 (合計${messageCount}件のメッセージ)"
                        }
                    }
            } catch (e: Exception) {
                android.util.Log.e("ChatViewModel", "Fatal error in observeAutoConversation", e)
                _autoConversationStatus.value = "自動会話でエラーが発生しました: ${e.message}"
            }
        }
    }
    
    /**
     * 自動会話の進行状況をリアルタイムで更新
     */
    private suspend fun updateAutoConversationProgress() {
        try {
            val currentConversationId = autoConversationManager.currentConversationId.value
            if (currentConversationId != null) {
                val targetConversationId = autoConversationTargetConversationId ?: conversationId
                // 自動会話のメッセージを一度だけ取得
                val autoMessages = repository.getAutoConversationMessages(currentConversationId).first()

                var addedCount = 0
                // 新しいメッセージのみを統合
                autoMessages.forEach { autoMessage: AutoConversationMessage ->
                    if (autoMessage.speakerModel != "USER") {
                        val speakerName = if (autoMessage.speakerModel == "A") "AI-A" else "AI-B"
                        val displayContent = autoMessage.displayContent()
                        if (displayContent.isBlank()) {
                            return@forEach
                        }
                        val messageText = "**[$speakerName]**\n\n$displayContent"
                        
                        // 同じ内容のメッセージが既に存在するかチェック
                        val isDuplicate = _messages.value.any { summary -> 
                            val fullMessage = _fullMessages.value[summary.id]
                            fullMessage?.chatMessage?.text == messageText
                        }
                        if (!isDuplicate) {
                            val chatMessage = ChatMessage(
                                conversationId = targetConversationId,
                                role = "model",
                                text = messageText,
                                attachments = emptyList()
                            )
                            repository.insertMessage(chatMessage)
                            addedCount++
                        }
                    }
                }
                
                
                // ステータス更新
                val messageCount = autoMessages.count { it.speakerModel != "USER" }
                _autoConversationStatus.value = "自動会話進行中 (${messageCount}件のメッセージ)"
            }
        } catch (e: Exception) {
            android.util.Log.e("ChatViewModel", "Error updating auto conversation progress", e)
        }
    }
    
    /**
     * 自動会話の結果を通常の会話履歴に統合
     */
    private suspend fun integrateAutoConversationResults() {
        try {
            val currentConversationId = autoConversationManager.currentConversationId.value
            if (currentConversationId != null) {
                val targetConversationId = autoConversationTargetConversationId ?: conversationId
                // 自動会話のメッセージを一度だけ取得
                val autoMessages = repository.getAutoConversationMessages(currentConversationId).first()
                
                // 最終的な統合処理 - 残っているメッセージがあれば追加
                var addedCount = 0
                autoMessages.forEach { autoMessage: AutoConversationMessage ->
                    if (autoMessage.speakerModel != "USER") {
                        val speakerName = if (autoMessage.speakerModel == "A") "AI-A" else "AI-B"
                        val displayContent = autoMessage.displayContent()
                        if (displayContent.isBlank()) {
                            return@forEach
                        }
                        val messageText = "**[$speakerName]**\n\n$displayContent"
                        
                        // 同じ内容のメッセージが既に存在するかチェック
                        val isDuplicate = _messages.value.any { summary -> 
                            val fullMessage = _fullMessages.value[summary.id]
                            fullMessage?.chatMessage?.text == messageText
                        }
                        if (!isDuplicate) {
                            val chatMessage = ChatMessage(
                                conversationId = targetConversationId,
                                role = "model",
                                text = messageText,
                                attachments = emptyList()
                            )
                            repository.insertMessage(chatMessage)
                            addedCount++
                        }
                    }
                }
                
                if (_autoConversationStatus.value?.contains("停止") != true) {
                    _autoConversationStatus.value = "自動会話完了 (合計${autoMessages.count { it.speakerModel != "USER" }}件のメッセージ)"
                }
            }
        } catch (e: Exception) {
            android.util.Log.e("ChatViewModel", "Error integrating auto conversation results", e)
            _errorMessage.value = "自動会話結果の統合でエラーが発生しました"
        }
    }
    
    /**
     * 自動会話を停止
     */
    fun stopAutoConversation() {
        viewModelScope.launch {
            try {
                autoConversationManager.stopConversation("ユーザーによる停止")
                _autoConversationStatus.value = "自動会話が停止されました"
                autoConversationTargetConversationId = null
            } catch (e: Exception) {
                android.util.Log.e("ChatViewModel", "Error stopping auto conversation", e)
                _errorMessage.value = "自動会話の停止でエラーが発生しました"
            }
        }
    }

    override fun onCleared() {
        super.onCleared()
        autoConversationObservationJob?.cancel()
        autoConversationObservationJob = null
        // AutoConversationManagerのリソースを解放
        autoConversationManager.cleanup()
    }
}

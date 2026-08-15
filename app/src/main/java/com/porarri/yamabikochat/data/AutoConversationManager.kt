package com.porarri.yamabikochat.data

import android.util.Log
import com.porarri.yamabikochat.data.local.*
import com.porarri.yamabikochat.data.model.ProviderRequestMessage
import com.porarri.yamabikochat.data.model.ProviderResponse
import com.porarri.yamabikochat.data.formatAutoConversationDisplay
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.first
import kotlin.coroutines.coroutineContext

class AutoConversationManager(
    private val repository: ChatRepository,
    private val scope: CoroutineScope
) {
    private val _isRunning = MutableStateFlow(false)
    val isRunning: StateFlow<Boolean> = _isRunning.asStateFlow()

    private val _currentConversationId = MutableStateFlow<Long?>(null)
    val currentConversationId: StateFlow<Long?> = _currentConversationId.asStateFlow()

    private var currentJob: Job? = null
    private var boundChatConversationId: Long? = null
    
    var onNewMessage: ((speakerModel: String, content: String, chatConversationId: Long) -> Unit)? = null
    
    companion object {
        private const val TAG = "AutoConversationManager"
        private const val DEFAULT_END_SIGNAL = "[END]"
        private const val MAX_RETRY_ATTEMPTS = 3
        private const val TURN_DELAY_MS = 2000L
        private val CONVERSATION_END_REGEXES = listOf(
            Regex("(?:会話|議論|討論|対話)(?:を)?(?:(?:ここ|これ|以上)で)?終(?:了|わ)り(?:に)?(?:いたします|ます|ましょう|とします)", RegexOption.IGNORE_CASE),
            Regex("これ(?:にて|で)(?:終(?:了|わ)り|終了)とさせていただきます", RegexOption.IGNORE_CASE),
            Regex("(?:ここ|これ|以上|本件)(?:で|にて)(?:終(?:了|わ)り|終了)(?:とします|です)", RegexOption.IGNORE_CASE),
            Regex("\\bend of (?:this )?(?:conversation|discussion)\\b", RegexOption.IGNORE_CASE),
            Regex("\\bthis concludes (?:our )?(?:conversation|discussion)\\b", RegexOption.IGNORE_CASE),
            Regex("\\blet'?s end (?:the )?(?:conversation|discussion)\\b", RegexOption.IGNORE_CASE),
        )
    }
    
    suspend fun startConversation(
        config: AutoConversationConfig,
        initialMessage: String,
        boundChatConversationId: Long? = null
    ): Result<Long> {
        return try {
            if (_isRunning.value) {
                return Result.failure(IllegalStateException("別の会話が既に進行中です"))
            }

            val conversationId = repository.createAutoConversation(
                config = config,
                boundChatConversationId = boundChatConversationId
            )
            
            _currentConversationId.value = conversationId
            this.boundChatConversationId = boundChatConversationId

            startAutoConversationLoop(conversationId, config, initialMessage)
            
            Result.success(conversationId)
        } catch (e: Exception) {
            Log.e(TAG, "自動会話の開始に失敗", e)
            Result.failure(e)
        }
    }
    
    suspend fun stopConversation(reason: String = "ユーザーによる停止") {
        val job = currentJob
        val callerJob = coroutineContext[Job]

        _isRunning.value = false

        withContext(NonCancellable) {
            _currentConversationId.value?.let { conversationId ->
                try {
                    val current = repository.getAutoConversationById(conversationId)
                    if (current != null && current.status == AutoConversationStatus.ACTIVE) {
                        val updated = current.copy(
                            status = AutoConversationStatus.PAUSED,
                            endReason = reason,
                            lastActiveAt = System.currentTimeMillis()
                        )
                        repository.updateAutoConversation(updated)
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "会話停止処理エラー", e)
                }
            }
            _currentConversationId.value = null
            boundChatConversationId = null
        }

        if (job != null && job !== callerJob) {
            job.cancelAndJoin()
        }
        currentJob = null
    }
    
    suspend fun restartConversation(conversationId: Long): Result<Unit> {
        return try {
            if (_isRunning.value) {
                return Result.failure(IllegalStateException("別の会話が既に進行中です"))
            }

            val conversation = repository.getAutoConversationById(conversationId)
                ?: return Result.failure(IllegalArgumentException("会話が見つかりません"))

            if (conversation.status != AutoConversationStatus.PAUSED && 
                conversation.status != AutoConversationStatus.ENDED) {
                return Result.failure(IllegalStateException("停止またはエラー状態の会話のみ再開できます"))
            }

            val messages = repository.getAutoConversationMessages(conversationId).first()
            val initialMessage = messages.find { it.speakerModel == "USER" }?.content ?: ""

            _currentConversationId.value = conversationId
            boundChatConversationId = conversation.boundChatConversationId

            val updated = conversation.copy(
                status = AutoConversationStatus.ACTIVE,
                endReason = null,
                lastActiveAt = System.currentTimeMillis()
            )
            repository.updateAutoConversation(updated)

            val config = AutoConversationConfig(
                title = conversation.title,
                modelA = conversation.modelA,
                providerA = conversation.providerA,
                systemPromptA = conversation.systemPromptA,
                modelB = conversation.modelB,
                providerB = conversation.providerB,
                systemPromptB = conversation.systemPromptB,
                maxTurns = conversation.maxTurns,
                endSignal = conversation.endSignal
            )

            startAutoConversationLoop(conversationId, config, initialMessage, updated)
            
            Result.success(Unit)
        } catch (e: Exception) {
            Log.e(TAG, "会話再開エラー", e)
            Result.failure(e)
        }
    }
    
    private fun startAutoConversationLoop(
        conversationId: Long,
        config: AutoConversationConfig,
        initialMessage: String,
        initialConversation: AutoConversation? = null
    ) {
        currentJob = scope.launch(Dispatchers.IO) {
            _isRunning.value = true
            
            try {
                val existingMessages = repository.getAutoConversationMessages(conversationId).first()
                val conversationMessages = mutableListOf<AutoConversationMessage>()
                conversationMessages.addAll(existingMessages)
                
                var currentTurn = (existingMessages.maxOfOrNull { it.turnNumber } ?: 0) + 1
                var currentSpeaker = if (existingMessages.isNotEmpty()) {
                    val lastSpeaker = existingMessages.last().speakerModel
                    if (lastSpeaker == "A") "B" else "A"
                } else {
                    "A"
                }

                var conversationSnapshot = initialConversation ?: repository.getAutoConversationById(conversationId)

                while (isActive && _isRunning.value && (config.maxTurns <= 0 || currentTurn <= config.maxTurns)) {
                    ensureActive()

                    val conversationHistory = buildConversationHistory(conversationMessages, currentSpeaker)
                    val (model, provider, systemPrompt) = if (currentSpeaker == "A") {
                        Triple(config.modelA, config.providerA, config.systemPromptA)
                    } else {
                        Triple(config.modelB, config.providerB, config.systemPromptB)
                    }
                    
                    val response = try {
                        repository.generateAutoConversationResponse(
                            model,
                            provider,
                            systemPrompt,
                            conversationHistory,
                            if (currentSpeaker == "A") Settings.ReasoningContext.AUTO_A else Settings.ReasoningContext.AUTO_B
                        )
                    } catch (e: Exception) {
                        Log.e(TAG, "API呼び出しエラー", e)
                        null
                    }
                    
                    ensureActive()
                    
                    if (response != null) {
                        response.usage?.let { usage ->
                            runCatching {
                                repository.recordTokenUsage(
                                    provider = provider,
                                    model = model,
                                    usage = usage,
                                    conversationId = boundChatConversationId,
                                    requestType = "auto_conversation"
                                )
                            }
                        }
                        val responseText = response.text
                        val reasoningText = response.reasoningSummary.orEmpty()

                        if (responseText.isNotBlank() || reasoningText.isNotBlank()) {
                            val hasEndSignal = containsEndSignal(responseText, config.endSignal)

                            val message = AutoConversationMessage(
                                autoConversationId = conversationId,
                                turnNumber = currentTurn,
                                speakerModel = currentSpeaker,
                                content = responseText,
                                reasoning = reasoningText.ifBlank { null },
                                isEndSignal = hasEndSignal
                            )
                            repository.insertAutoConversationMessage(message)
                            conversationMessages.add(message)

                            try {
                                val speakerName = if (currentSpeaker == "A") "AI-A" else "AI-B"
                                val display = formatAutoConversationDisplay(responseText, reasoningText)
                                val chatConversationId = boundChatConversationId
                                if (chatConversationId != null) {
                                    onNewMessage?.invoke(speakerName, display, chatConversationId)
                                }
                            } catch (e: Exception) {
                                Log.e(TAG, "Error notifying ChatViewModel", e)
                            }
                            
                            val now = System.currentTimeMillis()
                            val nextSnapshot = conversationSnapshot ?: repository.getAutoConversationById(conversationId)
                            if (nextSnapshot != null) {
                                val updated = nextSnapshot.copy(
                                    currentTurn = currentTurn,
                                    lastActiveAt = now
                                )
                                repository.updateAutoConversation(updated)
                                conversationSnapshot = updated
                            }

                            if (hasEndSignal) {
                                val nextEndSnapshot = conversationSnapshot ?: repository.getAutoConversationById(conversationId)
                                if (nextEndSnapshot != null) {
                                    val completed = nextEndSnapshot.copy(
                                        status = AutoConversationStatus.ENDED,
                                        endReason = "end_signal",
                                        lastActiveAt = System.currentTimeMillis()
                                    )
                                    repository.updateAutoConversation(completed)
                                    conversationSnapshot = completed
                                }
                                break
                            }

                            currentTurn++
                            currentSpeaker = if (currentSpeaker == "A") "B" else "A"
                            
                            delay(TURN_DELAY_MS)
                        } else {
                            handleTurnError(conversationId, "空の応答を受信しました", conversationSnapshot)
                            break
                        }
                    } else {
                        handleTurnError(conversationId, "API呼び出しに失敗しました", conversationSnapshot)
                        break
                    }
                }

                if (_isRunning.value && config.maxTurns > 0 && currentTurn > config.maxTurns) {
                    val current = conversationSnapshot ?: repository.getAutoConversationById(conversationId)
                    if (current != null && current.status == AutoConversationStatus.ACTIVE) {
                        val completed = current.copy(
                            status = AutoConversationStatus.ENDED,
                            endReason = "max_turns",
                            lastActiveAt = System.currentTimeMillis()
                        )
                        repository.updateAutoConversation(completed)
                    }
                }
                
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                Log.e(TAG, "自動会話ループエラー", e)
                handleTurnError(conversationId, e.message ?: "不明なエラー")
            } finally {
                _isRunning.value = false
            }
        }
    }
    
    private suspend fun handleTurnError(
        conversationId: Long,
        errorMessage: String,
        cachedConversation: AutoConversation? = null
    ) {
        try {
            val current = cachedConversation ?: repository.getAutoConversationById(conversationId)
            if (current != null) {
                val updated = current.copy(
                    status = AutoConversationStatus.ENDED,
                    endReason = errorMessage,
                    lastActiveAt = System.currentTimeMillis()
                )
                repository.updateAutoConversation(updated)
            }
        } catch (e: Exception) {
            Log.e(TAG, "エラー状態の保存に失敗", e)
        }
    }
    
    fun cleanup() {
        currentJob?.cancel()
        currentJob = null
        _isRunning.value = false
        _currentConversationId.value = null
    }
    
    private fun buildConversationHistory(
        messages: List<AutoConversationMessage>,
        currentSpeaker: String
    ): List<ProviderRequestMessage> {
        val history = mutableListOf<ProviderRequestMessage>()
        
        for (message in messages) {
            when (message.speakerModel) {
                "USER" -> {
                    history.add(ProviderRequestMessage(role = "user", content = message.content))
                }
                "A", "B" -> {
                    val role = if (message.speakerModel == currentSpeaker) "assistant" else "user"
                    history.add(
                        ProviderRequestMessage(
                            role = role,
                            content = message.content,
                            reasoningContent = if (role == "assistant") message.reasoning else null
                        )
                    )
                }
            }
        }

        return history
    }

    private fun containsEndSignal(text: String, endSignal: String?): Boolean {
        val normalizedEndSignal = endSignal?.takeIf { it.isNotBlank() } ?: DEFAULT_END_SIGNAL
        if (text.contains(normalizedEndSignal, ignoreCase = true)) {
            return true
        }
        
        val normalizedText = text.trim()
        if (normalizedText.isEmpty()) {
            return false
        }

        return CONVERSATION_END_REGEXES.any { regex -> regex.containsMatchIn(normalizedText) }
    }
}

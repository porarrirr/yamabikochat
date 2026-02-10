package com.porarri.yamabikochat.data

import android.util.Log
import com.porarri.yamabikochat.data.local.*
import com.porarri.yamabikochat.data.remote.Content
import com.porarri.yamabikochat.data.remote.Part
import com.porarri.yamabikochat.data.remote.GenerateContentResponse
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
    
    // メッセージ統合のためのコールバック
    var onNewMessage: ((speakerModel: String, content: String, chatConversationId: Long) -> Unit)? = null
    
    companion object {
        private const val TAG = "AutoConversationManager"
        private const val DEFAULT_END_SIGNAL = "[END]"
        private const val MAX_RETRY_ATTEMPTS = 3
        private const val TURN_DELAY_MS = 2000L // 2秒の間隔
        private val CONVERSATION_END_REGEXES = listOf(
            Regex("(?:会話|議論|討論|対話)(?:を)?(?:(?:ここ|これ|以上)で)?終(?:了|わ)り(?:に)?(?:いたします|ます|ましょう|とします)", RegexOption.IGNORE_CASE),
            Regex("これ(?:にて|で)(?:終(?:了|わ)り|終了)とさせていただきます", RegexOption.IGNORE_CASE),
            Regex("(?:ここ|これ|以上|本件)(?:で|にて)(?:終(?:了|わ)り|終了)(?:とします|です)", RegexOption.IGNORE_CASE),
            Regex("\\bend of (?:this )?(?:conversation|discussion)\\b", RegexOption.IGNORE_CASE),
            Regex("\\bthis concludes (?:our )?(?:conversation|discussion)\\b", RegexOption.IGNORE_CASE),
            Regex("\\blet'?s end (?:the )?(?:conversation|discussion)\\b", RegexOption.IGNORE_CASE),
            Regex("\\bconversation (?:has )?(?:ended|is over)\\b", RegexOption.IGNORE_CASE)
        )
    }
    
    /**
     * 自動会話を開始する
     */
    suspend fun startConversation(
        config: AutoConversationConfig,
        initialMessage: String,
        chatConversationId: Long
    ): Result<Long> {
        return try {
            if (_isRunning.value) {
                return Result.failure(IllegalStateException("会話が既に進行中です"))
            }

            // 会話を作成
            val conversationId = repository.createAutoConversation(config, chatConversationId)
            _currentConversationId.value = conversationId
            boundChatConversationId = chatConversationId

            val conversationRecord = repository.getAutoConversationById(conversationId)

            // 初期メッセージを保存（ユーザーメッセージとして）
            val initialMsg = AutoConversationMessage(
                autoConversationId = conversationId,
                turnNumber = 0,
                speakerModel = "USER", // ユーザーの初期メッセージ
                content = initialMessage
            )
            repository.insertAutoConversationMessage(initialMsg)

            // 自動会話を開始
            startAutoConversationLoop(conversationId, config, initialMessage, conversationRecord)
            
            Result.success(conversationId)
        } catch (e: Exception) {
            Log.e(TAG, "会話開始エラー", e)
            Result.failure(e)
        }
    }
    
    /**
     * 自動会話を停止する
     */
    suspend fun stopConversation(reason: String = AutoConversationEndReason.USER_STOP) {
        val job = currentJob
        val callerJob = coroutineContext[Job]

        // 状態を先に更新してループを停止
        _isRunning.value = false

        withContext(NonCancellable) {
            _currentConversationId.value?.let { conversationId ->
                try {
                    val conversation = repository.getAutoConversationById(conversationId)
                    if (conversation != null) {
                        repository.updateAutoConversation(
                            conversation.copy(
                                status = AutoConversationStatus.ENDED,
                                endReason = reason,
                                lastActiveAt = System.currentTimeMillis(),
                                boundChatConversationId = null
                            )
                        )
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "会話状態更新エラー", e)
                }
            }

            if (job != null && job == callerJob) {
                currentJob = null
            }

            _currentConversationId.value = null
            boundChatConversationId = null
        }

        if (job != null && job != callerJob) {
            job.cancel()
            currentJob = null
        }
    }
    
    /**
     * 自動会話の一時停止
     */
    suspend fun pauseConversation() {
        currentJob?.cancel()
        _isRunning.value = false
        
        _currentConversationId.value?.let { conversationId ->
            val conversation = repository.getAutoConversationById(conversationId)
            if (conversation != null) {
                repository.updateAutoConversation(
                    conversation.copy(
                        status = AutoConversationStatus.PAUSED,
                        lastActiveAt = System.currentTimeMillis()
                    )
                )
            }
        }
        
    }
    
    /**
     * 一時停止中の会話を再開
     */
    suspend fun resumeConversation(chatConversationId: Long? = null) {
        val conversationId = _currentConversationId.value ?: return
        val conversation = repository.getAutoConversationById(conversationId) ?: return

        if (conversation.status != AutoConversationStatus.PAUSED) {
            return
        }

        val restoredBinding = chatConversationId ?: conversation.boundChatConversationId
        boundChatConversationId = restoredBinding
        val bindingAdjustedConversation = if (restoredBinding != conversation.boundChatConversationId) {
            val updated = conversation.copy(boundChatConversationId = restoredBinding)
            repository.updateAutoConversation(updated)
            updated
        } else {
            conversation
        }

        // 設定を再構築
        val config = AutoConversationConfig(
            title = bindingAdjustedConversation.title,
            modelA = bindingAdjustedConversation.modelA,
            modelB = bindingAdjustedConversation.modelB,
            providerA = bindingAdjustedConversation.providerA,
            providerB = bindingAdjustedConversation.providerB,
            systemPromptA = bindingAdjustedConversation.systemPromptA,
            systemPromptB = bindingAdjustedConversation.systemPromptB,
            maxTurns = bindingAdjustedConversation.maxTurns,
            endSignal = bindingAdjustedConversation.endSignal
        )
        
        // 最後のメッセージを取得
        val lastMessage = repository.getLastAutoConversationMessage(conversationId)
        val lastContent = lastMessage?.content ?: ""
        
        // 会話を再開
        repository.updateAutoConversation(bindingAdjustedConversation.copy(status = AutoConversationStatus.ACTIVE))
        continueAutoConversationLoop(conversationId, config)
        
    }
    
    /**
     * 自動会話のメインループ
     */
    private fun startAutoConversationLoop(
        conversationId: Long,
        config: AutoConversationConfig,
        initialMessage: String,
        initialConversation: AutoConversation?
    ) {
        // 既存のJobをキャンセル
        currentJob?.cancel()

        initialConversation?.boundChatConversationId?.let { storedBinding ->
            boundChatConversationId = storedBinding
        }

        // ViewModelスコープを使用してエラー処理を改善
        currentJob = scope.launch(Dispatchers.IO) {
            try {
                _isRunning.value = true

                val conversationMessages = repository.getAutoConversationMessages(conversationId)
                    .first()
                    .sortedBy { it.turnNumber }
                    .toMutableList()

                val (initialTurn, initialSpeaker) = determineNextTurnAndSpeaker(conversationMessages)
                var currentTurn = initialTurn
                var currentSpeaker = initialSpeaker

                if (config.maxTurns > 0 && currentTurn > config.maxTurns) {
                    stopConversation(AutoConversationEndReason.MAX_TURNS)
                    return@launch
                }

                var conversationSnapshot = initialConversation ?: repository.getAutoConversationById(conversationId)

                while (isActive && _isRunning.value && (config.maxTurns <= 0 || currentTurn <= config.maxTurns)) {

                    // キャンセレーションをチェック
                    ensureActive()

                    // 会話履歴を構築
                    val conversationHistory = buildConversationHistory(conversationMessages, currentSpeaker)
                    
                    // 現在のモデル情報を取得
                    val (model, provider, systemPrompt) = if (currentSpeaker == "A") {
                        Triple(config.modelA, config.providerA, config.systemPromptA)
                    } else {
                        Triple(config.modelB, config.providerB, config.systemPromptB)
                    }
                    
                    // API呼び出し
                    val response = repository.generateAutoConversationResponse(
                        model,
                        provider,
                        systemPrompt,
                        conversationHistory,
                        if (currentSpeaker == "A") Settings.ReasoningContext.AUTO_A else Settings.ReasoningContext.AUTO_B
                    )
                    
                    // キャンセレーションをチェック
                    ensureActive()
                    
                    if (response.isSuccessful) {
                        val responseBody = response.body()
                        val (responseText, reasoningText) = extractResponseSegments(responseBody)

                        if (responseText.isNotBlank() || reasoningText.isNotBlank()) {
                            // 終了シグナルをチェック
                            val hasEndSignal = containsEndSignal(responseText, config.endSignal)

                            // メッセージを保存
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

                            // 追加：コールバックでChatViewModelに通知
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
                            
                            // 会話の状態を更新
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
                            
                            
                            // 終了シグナルがあれば停止
                            if (hasEndSignal) {
                                // 終了通知メッセージを挿入
                                try {
                                    val endMessage = "**[SYSTEM]**\n\n🏁 自動会話が終了しました\n\n" +
                                        "• 実行ターン数: $currentTurn/${config.maxTurns}ターン\n" +
                                        "• 参加モデル: ${config.modelA} vs ${config.modelB}\n" +
                                        "• 終了理由: AIモデルが会話終了を宣言\n\n" +
                                        "自然な形で会話が終了しました 🤝"
                                    boundChatConversationId?.let { chatConversationId ->
                                        onNewMessage?.invoke("SYSTEM", endMessage, chatConversationId)
                                    }
                                } catch (e: Exception) {
                                    Log.e(TAG, "終了シグナル通知メッセージの送信に失敗", e)
                                }
                                
                                stopConversation(AutoConversationEndReason.END_SIGNAL)
                                break
                            }
                            
                            // 次のターンへ
                            currentSpeaker = if (currentSpeaker == "A") "B" else "A"
                            currentTurn++
                            // 少し待機（キャンセレーション対応）
                            try {
                                delay(TURN_DELAY_MS)
                            } catch (e: CancellationException) {
                                throw e
                            }
                        } else {
                            Log.e(TAG, "空の応答を受信")
                            stopConversation(AutoConversationEndReason.ERROR)
                            break
                        }
                    } else {
                        Log.e(TAG, "API エラー: ${response.code()} ${response.message()}")
                        stopConversation(AutoConversationEndReason.API_ERROR)
                        break
                    }
                }
                
                // 最大ターン数に達した場合（0以下は無制限として扱う）
                if (config.maxTurns > 0 && currentTurn > config.maxTurns && _isRunning.value) {
                    // 終了通知メッセージを挿入
                    try {
                        val endMessage = "**[SYSTEM]**\n\n🎯 自動会話が完了しました！\n\n" +
                            "• 実行ターン数: ${currentTurn - 1}/${config.maxTurns}ターン\n" +
                            "• 参加モデル: ${config.modelA} vs ${config.modelB}\n" +
                            "• 終了理由: 最大ターン数に達したため\n\n" +
                            "会話をお疲れ様でした！ 💪"
                        boundChatConversationId?.let { chatConversationId ->
                            onNewMessage?.invoke("SYSTEM", endMessage, chatConversationId)
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "終了通知メッセージの送信に失敗", e)
                    }
                    
                    stopConversation(AutoConversationEndReason.MAX_TURNS)
                }
                
            } catch (e: CancellationException) {
                _isRunning.value = false
                throw e
            } catch (e: Exception) {
                Log.e(TAG, "会話エラー", e)
                stopConversation(AutoConversationEndReason.ERROR)
            } finally {
                if (_isRunning.value) {
                    _isRunning.value = false
                }
            }
        }
    }
    
    /**
     * 一時停止からの継続用ループ
     */
    private fun continueAutoConversationLoop(conversationId: Long, config: AutoConversationConfig) {
        // 既存のJobをキャンセル
        currentJob?.cancel()

        currentJob = scope.launch(Dispatchers.IO) {
            try {
                _isRunning.value = true
                val conversation = repository.getAutoConversationById(conversationId) ?: return@launch
                val messages = repository.getAutoConversationMessages(conversationId).first()

                if (messages.isNotEmpty()) {
                    val orderedMessages = messages.sortedBy { it.turnNumber }
                    val lastMessage = orderedMessages.last()

                    if (lastMessage.isEndSignal) {
                        stopConversation(AutoConversationEndReason.END_SIGNAL)
                        return@launch
                    }

                    val (nextTurn, _) = determineNextTurnAndSpeaker(orderedMessages)
                    if (config.maxTurns > 0 && nextTurn > config.maxTurns) {
                        stopConversation(AutoConversationEndReason.MAX_TURNS)
                        return@launch
                    }

                    val initialMessage = orderedMessages
                        .firstOrNull { it.speakerModel == "USER" }
                        ?.content
                        .orEmpty()
                    startAutoConversationLoop(conversationId, config, initialMessage, conversation)
                } else {
                    Log.w(TAG, "継続するメッセージがありません")
                    stopConversation(AutoConversationEndReason.ERROR)
                }
                
            } catch (e: Exception) {
                Log.e(TAG, "会話継続エラー", e)
                stopConversation(AutoConversationEndReason.ERROR)
            }
        }
    }

    private fun determineNextTurnAndSpeaker(
        messages: List<AutoConversationMessage>
    ): Pair<Int, String> {
        val lastModelMessage = messages
            .lastOrNull { it.speakerModel == "A" || it.speakerModel == "B" }

        return if (lastModelMessage == null) {
            1 to "A"
        } else {
            val nextSpeaker = if (lastModelMessage.speakerModel == "A") "B" else "A"
            (lastModelMessage.turnNumber + 1) to nextSpeaker
        }
    }

    /**
     * リソースを解放する（ViewModelが破棄される際に呼び出し）
     */
    fun cleanup() {
        currentJob?.cancel()
        currentJob = null
        _isRunning.value = false
        _currentConversationId.value = null
    }
    
    /**
     * 各モデル用の会話履歴を構築
     * 重要: 各モデルにとって自分の発言は"model"、相手の発言は"user"として扱う
     */
    private fun buildConversationHistory(
        messages: List<AutoConversationMessage>,
        currentSpeaker: String
    ): List<Content> {
        val history = mutableListOf<Content>()
        
        for (message in messages) {
            when (message.speakerModel) {
                "USER" -> {
                    // 初期のユーザーメッセージは常に"user"として扱う
                    history.add(Content(
                        role = "user",
                        parts = listOf(Part(text = message.content))
                    ))
                }
                "A", "B" -> {
                    // 現在話しているモデルの視点でroleを決定
                    val role = if (message.speakerModel == currentSpeaker) {
                        "model" // 自分の発言
                    } else {
                        "user" // 相手の発言
                    }

                    history.add(Content(
                        role = role,
                        parts = listOf(Part(text = message.content))
                    ))
                }
            }
        }

        return history
    }

    private fun extractResponseSegments(response: GenerateContentResponse?): Pair<String, String> {
        if (response == null) {
            return "" to ""
        }

        val parts = response.candidates?.firstOrNull()?.content?.parts.orEmpty()
        val textBuilder = StringBuilder()
        val reasoningBuilder = StringBuilder()

        var hasExplicitTextPart = false
        for (part in parts) {
            if (part.thought == true) {
                reasoningBuilder.append(part.text.orEmpty())
            } else {
                textBuilder.append(part.text.orEmpty())
                hasExplicitTextPart = true
            }
        }

        if (!hasExplicitTextPart) {
            response.text?.let { textBuilder.append(it) }
        }

        return textBuilder.toString() to reasoningBuilder.toString()
    }
    
    /**
     * 終了シグナルの検出
     * 明確な会話終了の意図を示すフレーズのみを検出し、誤判定を防ぐ
     */
    private fun containsEndSignal(text: String, endSignal: String?): Boolean {
        val normalizedEndSignal = endSignal?.takeIf { it.isNotBlank() } ?: DEFAULT_END_SIGNAL
        // 明示的な終了シグナル
        if (text.contains(normalizedEndSignal, ignoreCase = true)) {
            return true
        }
        
        // 明確な会話終了意図のパターンを検出
        val normalizedText = text.trim()
        if (normalizedText.isEmpty()) {
            return false
        }

        return CONVERSATION_END_REGEXES.any { regex -> regex.containsMatchIn(normalizedText) }
    }
}

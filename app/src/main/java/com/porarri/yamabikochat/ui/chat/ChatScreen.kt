package com.porarri.yamabikochat.ui.chat

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material.icons.automirrored.filled.CallSplit
import androidx.compose.material.icons.filled.*
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.scale
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.window.Dialog
import com.porarri.yamabikochat.MyApplication
import com.porarri.yamabikochat.data.local.ChatMessage
import com.porarri.yamabikochat.data.local.ChatMessageSummary
import com.porarri.yamabikochat.data.local.FullChatMessage
import com.porarri.yamabikochat.data.local.DualChatMessage
import com.porarri.yamabikochat.data.local.SplitLayoutType
import com.porarri.yamabikochat.ui.components.YamabikoOption
import com.porarri.yamabikochat.ui.components.YamabikoOptionBottomSheet   
import com.porarri.yamabikochat.ui.components.YamabikoTextField
import com.porarri.yamabikochat.ui.preview.YamabikoPreview
import com.porarri.yamabikochat.ui.settings.SettingsViewModel
import com.porarri.yamabikochat.ui.components.DualResponseDisplay
import com.porarri.yamabikochat.ui.chat.MarkdownText
import com.porarri.yamabikochat.ui.chat.components.ChatMessageInputBar
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import android.graphics.BitmapFactory
import android.net.Uri
import java.io.File

// 自動会話メッセージの判定とパース用ヘルパー関数
data class AutoConversationInfo(
    val isAutoConversation: Boolean,
    val speaker: String? = null, // "AI-A" or "AI-B"
    val cleanContent: String
)

private data class ThinkingSheetData(
    val messageId: Long,
    val thinkingText: String
)

fun parseAutoConversationMessage(text: String): AutoConversationInfo {
    val autoConversationPattern = Regex("^\\*\\*\\[(.+?)\\]\\*\\*\\n\\n(.*)$", RegexOption.DOT_MATCHES_ALL)
    val match = autoConversationPattern.find(text)
    
    return if (match != null) {
        val speaker = match.groupValues[1]
        val content = match.groupValues[2]
        AutoConversationInfo(
            isAutoConversation = true,
            speaker = speaker,
            cleanContent = content
        )
    } else {
        AutoConversationInfo(
            isAutoConversation = false,
            cleanContent = text
        )
    }
}

private fun resolveThinkingText(
    message: FullChatMessage,
    preferSummary: Boolean,
    allowSummary: Boolean
): String? {
    val summary = message.chatMessage.thinkingSummary?.takeIf { it.isNotBlank() }
    val stream = message.thinkingStream?.takeIf { it.isNotBlank() }
    if (preferSummary && summary != null) return summary
    if (stream != null) return stream
    return if (allowSummary) summary else null
}

private sealed interface ChatTimelineItem {
    val timestamp: Long
    val key: String

    data class Chat(val summary: ChatMessageSummary) : ChatTimelineItem {
        override val timestamp: Long = summary.timestamp
        override val key: String = "c-${summary.id}"
    }

    data class Dual(val message: DualChatMessage) : ChatTimelineItem {
        override val timestamp: Long = message.timestamp
        override val key: String = "d-${message.id}"
    }
}

private fun buildTimeline(
    chatMessages: List<ChatMessageSummary>,
    dualMessages: List<DualChatMessage>
): List<ChatTimelineItem> =
    (chatMessages.map { ChatTimelineItem.Chat(it) } + dualMessages.map { ChatTimelineItem.Dual(it) })
        .sortedBy { it.timestamp }

@OptIn(ExperimentalMaterial3Api::class, ExperimentalFoundationApi::class)       
@Composable
fun ChatScreen(
    onMenuClick: () -> Unit = {},
    viewModel: ChatViewModel = viewModel(
        factory = (LocalContext.current.applicationContext as MyApplication).viewModelFactory
    ),
    initialPrompt: String? = null,
    onInitialPromptConsumed: () -> Unit = {},
    focusMessageId: Long? = null,
    focusDualMessageId: Long? = null,
    showCloseButton: Boolean = false,
    onClose: () -> Unit = {},
    onNavigateToConversation: (Long) -> Unit = {}
) {
    val messages by viewModel.messages.collectAsState()
    val fullMessages by viewModel.fullMessages.collectAsState()
    val dualMessages by viewModel.dualMessages.collectAsState()
    val dualChatSettings by viewModel.dualChatSettings.collectAsState()
    val isDualModeActive by viewModel.isDualModeActive.collectAsState()
    val editingMessage by viewModel.editingMessage.collectAsState()
    val attachments by viewModel.attachments.collectAsState()
    val errorMessage by viewModel.errorMessage.collectAsState()
    val isAutoConversationRunning by viewModel.isAutoConversationRunning.collectAsState()
    val autoConversationStatus by viewModel.autoConversationStatus.collectAsState()
    var text by rememberSaveable { mutableStateOf(initialPrompt ?: "") }
    val snackbarHostState = remember { SnackbarHostState() }
    val scope = rememberCoroutineScope()

    val imagePicker = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.GetMultipleContents(),
        onResult = { uris -> uris.forEach { viewModel.addAttachment(it) } }
    )
    val filePicker = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.GetMultipleContents(),
        onResult = { uris -> uris.forEach { viewModel.addAttachment(it) } }
    )

    LaunchedEffect(editingMessage) {
        editingMessage?.let {
            text = it.text
        }
    }
    LaunchedEffect(initialPrompt) {
        if (!initialPrompt.isNullOrBlank()) {
            text = initialPrompt
            onInitialPromptConsumed()
        }
    }

    // エラーメッセージ表示用のSnackbar
    LaunchedEffect(errorMessage) {
        errorMessage?.let { message ->
            snackbarHostState.showSnackbar(
                message = message,
                actionLabel = "閉じる"
            )
            viewModel.clearErrorMessage()
        }
    }

    val settingsViewModel: SettingsViewModel = viewModel(
        factory = (LocalContext.current.applicationContext as MyApplication).viewModelFactory
    )
    val presets by settingsViewModel.modelPresets.collectAsState()
    val settings by settingsViewModel.settings.collectAsState()
    val globalPresets = settings?.buildGlobalProviderPresets().orEmpty()        
    val globalPresetsInChat = settings?.let { currentSettings ->
        globalPresets.filter { currentSettings.shouldShowGlobalProviderPresetInChat(it.apiProvider) }
    }.orEmpty()
    val presetOptions = globalPresetsInChat + presets
    val currentConversation by viewModel.conversation.collectAsState()
    val isSecretChat = currentConversation?.isSecret == true
    val canToggleSecret = messages.isEmpty() && dualMessages.isEmpty()
    var showPresetMenu by remember { mutableStateOf(false) }
    var showOverflowMenu by remember { mutableStateOf(false) }
    var selectedPreset by remember { mutableStateOf<com.porarri.yamabikochat.data.local.ModelPreset?>(null) }
    val thinkingSheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    var thinkingSheet by remember { mutableStateOf<ThinkingSheetData?>(null) }

    val dismissThinkingSheet: () -> Unit = {
        scope.launch {
            try {
                thinkingSheetState.hide()
            } finally {
                thinkingSheet = null
            }
        }
    }
    val toggleThinkingSheet: (Long, String) -> Unit = { messageId, thinkingText ->
        if (thinkingSheet?.messageId == messageId) {
            dismissThinkingSheet()
        } else {
            thinkingSheet = ThinkingSheetData(messageId = messageId, thinkingText = thinkingText)
        }
    }
    val isPristineNewChat =
        (currentConversation?.title ?: "New Chat") == "New Chat" &&      
            messages.isEmpty() &&
            dualMessages.isEmpty()

    Scaffold(
        modifier = Modifier.fillMaxSize(),
        containerColor = MaterialTheme.colorScheme.surface,
        topBar = {
            TopAppBar(
                title = {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,   
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Column(modifier = Modifier.weight(1f)) {
                            Text(
                                text = when {
                                    isSecretChat -> "シークレットチャット"
                                    isDualModeActive -> "Dual Chat"
                                    settings?.isAutoConversationEnabled == true -> "Auto Conversation"
                                    else -> "Chat"
                                },
                                style = MaterialTheme.typography.titleMedium
                            )
                            when {
                                isDualModeActive -> {
                                    Text(
                                        text = "${dualChatSettings.providerA} ${dualChatSettings.modelA} vs ${dualChatSettings.providerB} ${dualChatSettings.modelB}",
                                        style = MaterialTheme.typography.bodySmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant
                                    )
                                }
                                settings?.isAutoConversationEnabled == true -> {
                                    Column {
                                        Row(
                                            verticalAlignment = Alignment.CenterVertically
                                        ) {
                                            Icon(
                                                Icons.Default.AutoAwesome,
                                                contentDescription = "Auto Conversation",
                                                modifier = Modifier.size(12.dp),
                                                tint = if (isAutoConversationRunning)
                                                    MaterialTheme.colorScheme.secondary
                                                else
                                                    MaterialTheme.colorScheme.onSurfaceVariant
                                            )
                                            Spacer(modifier = Modifier.width(4.dp))
                                            Text(
                                                text = if (isAutoConversationRunning) "実行中" else "待機中",
                                                style = MaterialTheme.typography.bodySmall,
                                                color = if (isAutoConversationRunning)
                                                    MaterialTheme.colorScheme.secondary
                                                else
                                                    MaterialTheme.colorScheme.onSurfaceVariant
                                            )
                                        }
                                        val a = settings
                                        if (a != null) {
                                            Text(
                                                text = "${a.autoProviderA} ${a.autoModelA} ⇄ ${a.autoProviderB} ${a.autoModelB}",
                                                style = MaterialTheme.typography.bodySmall,
                                                color = MaterialTheme.colorScheme.onSurfaceVariant
                                            )
                                        }
                                    }
                                }
                                else -> {
                                    val provider = (currentConversation?.apiProvider ?: settings?.apiProvider)?.uppercase() ?: "GEMINI"
                                    val model = currentConversation?.model ?: settings?.getCurrentModel() ?: ""
                                    Text(
                                        text = listOf(provider, model).filter { it.isNotBlank() }.joinToString(" · "),
                                        style = MaterialTheme.typography.bodySmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant
                                    )
                                }
                            }
                        }
                        
                        // レイアウト切替ボタン（デュアルモードのときのみ表示）
                        if (isDualModeActive) {
                            IconButton(
                                onClick = {
                                    val newLayoutType = when (dualChatSettings.splitLayout) {
                                        SplitLayoutType.VERTICAL -> SplitLayoutType.HORIZONTAL
                                        SplitLayoutType.HORIZONTAL -> SplitLayoutType.VERTICAL
                                    }
                                    viewModel.updateDualChatSettings(
                                        dualChatSettings.copy(splitLayout = newLayoutType)
                                    )
                                }
                            ) {
                                Icon(
                                    when (dualChatSettings.splitLayout) {
                                        SplitLayoutType.VERTICAL -> Icons.Default.ViewColumn
                                        SplitLayoutType.HORIZONTAL -> Icons.Default.ViewArray
                                    },
                                    contentDescription = "Toggle layout"
                                )
                            }
                        }
                        
                        IconButton(
                            onClick = { onNavigateToConversation(0L) },
                            enabled = !isPristineNewChat
                        ) {
                            Icon(
                                imageVector = Icons.Default.Edit,
                                contentDescription = "New Chat"
                            )
                        }

                        IconButton(
                            onClick = { viewModel.setSecretMode(!isSecretChat) },
                            enabled = canToggleSecret
                        ) {
                            Icon(
                                imageVector = if (isSecretChat) Icons.Default.Lock else Icons.Default.LockOpen,
                                contentDescription = "Secret Chat",
                                tint = if (isSecretChat) {
                                    MaterialTheme.colorScheme.primary
                                } else {
                                    MaterialTheme.colorScheme.onSurfaceVariant
                                }
                            )
                        }

                        IconButton(
                            onClick = { showPresetMenu = true }
                        ) {
                            Icon(
                                imageVector = Icons.Default.Tune,
                                contentDescription = "Model"
                            )
                        }

                        Box {
                            IconButton(onClick = { showOverflowMenu = true }) {
                                Icon(
                                    imageVector = Icons.Default.MoreVert,
                                    contentDescription = "More"
                                )
                            }
                            DropdownMenu(
                                expanded = showOverflowMenu,
                                onDismissRequest = { showOverflowMenu = false }
                            ) {
                                DropdownMenuItem(
                                    text = { Text("Dual mode") },
                                    leadingIcon = { Icon(Icons.Default.Compare, contentDescription = null) },
                                    trailingIcon = {
                                        Switch(
                                            checked = isDualModeActive,
                                            onCheckedChange = {
                                                viewModel.toggleDualMode()
                                                showOverflowMenu = false
                                            }
                                        )
                                    },
                                    onClick = {
                                        viewModel.toggleDualMode()
                                        showOverflowMenu = false
                                    }
                                )
                                DropdownMenuItem(
                                    text = { Text("Auto conversation") },
                                    leadingIcon = { Icon(Icons.Default.AutoAwesome, contentDescription = null) },
                                    trailingIcon = {
                                        Switch(
                                            checked = settings?.isAutoConversationEnabled == true,
                                            onCheckedChange = {
                                                viewModel.toggleAutoConversation()
                                                showOverflowMenu = false
                                            }
                                        )
                                    },
                                    onClick = {
                                        viewModel.toggleAutoConversation()
                                        showOverflowMenu = false
                                    }
                                )
                            }
                        }

                        if (showPresetMenu) {
                            YamabikoOptionBottomSheet(
                                title = "プリセット",
                                options = presetOptions.map { preset ->
                                    val providerLabel = when (preset.apiProvider.uppercase()) {
                                        "GEMINI" -> "Google Gemini"
                                        "OPENROUTER" -> "OpenRouter"
                                        "MINIMAX" -> "MiniMax"
                                        "OPENAI" -> "OpenAI"
                                        "CODEX_AUTH" -> "Codex Auth"
                                        "OPENAI_COMPAT" -> "OpenAI (Custom)"
                                        "ZAI" -> "Z.ai"
                                        else -> preset.apiProvider
                                    }
                                    val thinkingSuffix = if (preset.thinkingEnabled) " · Thinking" else ""
                                    YamabikoOption(
                                        key = preset.id.toString(),
                                        title = preset.name,
                                        subtitle = "$providerLabel · ${preset.model}$thinkingSuffix"
                                    )
                                },
                                selectedKey = selectedPreset?.id?.toString(),
                                onOptionSelected = { option ->
                                    val preset = presetOptions.firstOrNull { it.id.toString() == option.key }
                                        ?: return@YamabikoOptionBottomSheet
                                    viewModel.applyPreset(preset)
                                    selectedPreset = preset
                                },
                                onDismissRequest = { showPresetMenu = false }
                            )
                        }
                    }
                },
                navigationIcon = {
                    if (showCloseButton) {
                        IconButton(onClick = onClose) {
                            Icon(Icons.Default.Close, contentDescription = "Close Overlay")
                        }
                    } else {
                        IconButton(onClick = onMenuClick) {
                            Icon(Icons.Default.Menu, contentDescription = "Menu")
                        }
                    }
                }
            )
        },
        snackbarHost = {
            SnackbarHost(hostState = snackbarHostState)
        },
        bottomBar = {
            Column(
                modifier = Modifier.imePadding()
            ) {
                // 自動会話状態表示（実行中のみ表示）
                if (isAutoConversationRunning || autoConversationStatus != null) {
                    Card(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 16.dp, vertical = 4.dp),
                        colors = CardDefaults.cardColors(
                            containerColor = if (isAutoConversationRunning) 
                                MaterialTheme.colorScheme.secondaryContainer 
                            else 
                                MaterialTheme.colorScheme.surfaceVariant
                        )
                    ) {
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(12.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            if (isAutoConversationRunning) {
                                CircularProgressIndicator(
                                    modifier = Modifier.size(16.dp),
                                    strokeWidth = 2.dp,
                                    color = MaterialTheme.colorScheme.secondary
                                )
                            } else {
                                Icon(
                                    Icons.Default.CheckCircle,
                                    contentDescription = "Complete",
                                    modifier = Modifier.size(16.dp),
                                    tint = MaterialTheme.colorScheme.secondary
                                )
                            }
                            
                            Spacer(modifier = Modifier.width(8.dp))
                            
                            Text(
                                text = autoConversationStatus ?: "自動会話状態不明",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                modifier = Modifier.weight(1f)
                            )
                            
                            if (isAutoConversationRunning) {
                                TextButton(
                                    onClick = { viewModel.stopAutoConversation() },
                                    modifier = Modifier.padding(start = 8.dp)
                                ) {
                                    Text(
                                        text = "停止",
                                        style = MaterialTheme.typography.labelSmall,
                                        color = MaterialTheme.colorScheme.error
                                    )
                                }
                            }
                        }
                    }
                }
                
        AttachmentPreview(
            attachments = attachments,
            onRemoveAttachment = { viewModel.removeAttachment(it) }
        )
        // 入力欄の右上にプロバイダー/モデルのラベルを表示
        val shorten: (String) -> String = { s ->
            val core = s.substringAfterLast('/')
            if (core.length > 32) core.take(31) + "…" else core
        }
        val baseContextLabel = when {
            isDualModeActive ->
                "DUAL · ${dualChatSettings.providerA} ${shorten(dualChatSettings.modelA)} vs ${dualChatSettings.providerB} ${shorten(dualChatSettings.modelB)}"
            (settings?.isAutoConversationEnabled == true) -> {
                val a = settings!!
                "AUTO · ${a.autoProviderA} ${shorten(a.autoModelA)} ⇄ ${a.autoProviderB} ${shorten(a.autoModelB)}"
            }
            else -> {
                val provider = (currentConversation?.apiProvider ?: settings?.apiProvider)?.uppercase() ?: "GEMINI"
                val model = currentConversation?.model ?: settings?.getCurrentModel() ?: ""
                listOf(provider, shorten(model)).filter { it.isNotBlank() }.joinToString(" · ")
            }
        }
        val inputContextLabel =
            if (isSecretChat && baseContextLabel.isNotBlank()) {
                "シークレット · $baseContextLabel"
            } else if (isSecretChat) {
                "シークレット"
            } else {
                baseContextLabel
            }

        ChatMessageInputBar(
            value = text,
            onValueChange = { text = it },
            attachments = attachments,
            onSendClick = {
                viewModel.sendMessage(text)
                text = ""
            },
            onImagePick = { imagePicker.launch("image/*") },
            onFilePick = { filePicker.launch("*/*") },
            isAutoConversationEnabled = settings?.isAutoConversationEnabled ?: false,
            contextLabel = inputContextLabel,
            isSecretMode = isSecretChat
        )
            }
        }
    ) { padding ->
        val timeline = remember(messages, dualMessages) { buildTimeline(messages, dualMessages) }
        val timelineReversed = remember(timeline) { timeline.asReversed() }
        val listState = rememberLazyListState()
        val lastMessageId = remember(messages) { messages.lastOrNull()?.id }

        val focusKey = focusMessageId?.let { "c-$it" } ?: focusDualMessageId?.let { "d-$it" }
        var focusHandled by rememberSaveable(focusKey) { mutableStateOf(false) }
        var highlightedKey by remember { mutableStateOf<String?>(null) }

        LaunchedEffect(focusKey, timelineReversed) {
            if (focusKey == null || focusHandled) return@LaunchedEffect
            val index = timelineReversed.indexOfFirst { it.key == focusKey }
            if (index >= 0) {
                listState.scrollToItem(index)
                highlightedKey = focusKey
                focusHandled = true
                delay(2_000)
                highlightedKey = null
            }
        }

        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .padding(horizontal = 0.dp),
            reverseLayout = true,
            state = listState
        ) {
            items(items = timelineReversed, key = { it.key }) { item ->
                when (item) {
                    is ChatTimelineItem.Chat -> {
                        val summary = item.summary
                        val fullMessage = fullMessages[summary.id]
                        if (fullMessage != null) {
                            val activeProvider =
                                (currentConversation?.apiProvider ?: settings?.apiProvider)?.uppercase() ?: "GEMINI"
                            val allowSummary = if (activeProvider == "CODEX_AUTH") {
                                settings?.codexShowReasoningSummary ?: true
                            } else {
                                true
                            }
                            val preferSummary = activeProvider == "CODEX_AUTH" && allowSummary
                            ChatMessageItem(
                                message = fullMessage,
                                viewModel = viewModel,
                                highlighted = item.key == highlightedKey,
                                canRegenerate = summary.role == "model" && summary.id == lastMessageId,
                                onEdit = { viewModel.fetchMessageForEditing(summary.id) },
                                onBranch = { targetMessageId ->
                                    scope.launch {
                                        val newConversationId =
                                            viewModel.branchConversationFromMessage(targetMessageId)
                                        if (newConversationId != null) {
                                            onNavigateToConversation(newConversationId)
                                        }
                                    }
                                },
                                thinkingExpanded = thinkingSheet?.messageId == fullMessage.chatMessage.id,
                                onThinkingToggle = toggleThinkingSheet,
                                preferSummary = preferSummary,
                                allowSummary = allowSummary
                            )
                        } else {
                            ChatMessageSummaryItem(
                                summary = summary,
                                highlighted = item.key == highlightedKey
                            )
                        }
                    }

                    is ChatTimelineItem.Dual -> {
                        DualChatMessageItem(
                            dualMessage = item.message,
                            dualChatSettings = dualChatSettings,
                            highlighted = item.key == highlightedKey,
                            onSplitRatioChanged = { newRatio ->
                                viewModel.updateDualChatSettings(
                                    dualChatSettings.copy(splitRatio = newRatio)
                                )
                            }
                        )
                    }
                }
            }
        }

        thinkingSheet?.let { sheet ->
            ThinkingBottomSheet(
                thinkingText = sheet.thinkingText,
                sheetState = thinkingSheetState,
                onDismissRequest = dismissThinkingSheet
            )
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ThinkingBottomSheet(
    thinkingText: String,
    sheetState: SheetState,
    onDismissRequest: () -> Unit,
) {
    val scrollState = rememberScrollState()
    LaunchedEffect(thinkingText) {
        scrollState.scrollTo(0)
    }

    ModalBottomSheet(
        sheetState = sheetState,
        onDismissRequest = onDismissRequest,
        dragHandle = { BottomSheetDefaults.DragHandle() },
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .fillMaxHeight(0.85f)
                .padding(horizontal = 16.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Icon(
                    Icons.Default.Psychology,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.primary
                )
                Spacer(modifier = Modifier.width(10.dp))
                Text(
                    text = "Thinking",
                    style = MaterialTheme.typography.titleMedium
                )
                Spacer(modifier = Modifier.weight(1f))
                IconButton(onClick = onDismissRequest) {
                    Icon(
                        Icons.Default.Close,
                        contentDescription = "Close",
                    )
                }
            }

            Spacer(modifier = Modifier.height(8.dp))
            HorizontalDivider(
                color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.7f)
            )
            Spacer(modifier = Modifier.height(12.dp))

            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .weight(1f)
                    .verticalScroll(scrollState)
            ) {
                MarkdownText(
                    markdown = thinkingText,
                    modifier = Modifier.fillMaxWidth()
                )
            }

            Spacer(modifier = Modifier.height(16.dp))
        }
    }
}

@Composable
fun DualChatMessageItem(
    dualMessage: DualChatMessage,
    dualChatSettings: com.porarri.yamabikochat.data.local.DualChatSettings,
    highlighted: Boolean = false,
    onSplitRatioChanged: (Float) -> Unit
) {
    val configuration = LocalConfiguration.current
    val density = LocalDensity.current
    
    // 画面サイズの取得
    val screenHeight = configuration.screenHeightDp.dp
    val screenWidth = configuration.screenWidthDp.dp
    val orientation = configuration.orientation
    
    // デバイスタイプの判定（画面の向きを考慮）
    val isTablet = screenWidth >= 600.dp
    val isLargeTablet = screenWidth >= 840.dp
    val isCompact = screenHeight < 600.dp
    val isLandscape = orientation == android.content.res.Configuration.ORIENTATION_LANDSCAPE
    
    // キーボード表示状態の検出
    val ime = WindowInsets.ime
    val imeHeight = ime.getBottom(density)
    val isKeyboardVisible = imeHeight > 0
    
    // 適応的な高さ計算（画面の向きを考慮）
    val baseHeight = remember(screenHeight, screenWidth, isTablet, isLargeTablet, isCompact, isLandscape) {
        when {
            isLargeTablet -> {
                val ratio = if (isLandscape) 0.8f else 0.75f
                val minHeight = if (isLandscape) 500.dp else 600.dp
                val maxHeight = if (isLandscape) 800.dp else 1000.dp
                (screenHeight * ratio).coerceIn(minHeight, maxHeight)
            }
            isTablet -> {
                val ratio = if (isLandscape) 0.75f else 0.7f
                val minHeight = if (isLandscape) 400.dp else 500.dp
                val maxHeight = if (isLandscape) 600.dp else 800.dp
                (screenHeight * ratio).coerceIn(minHeight, maxHeight)
            }
            isCompact -> {
                val ratio = if (isLandscape) 0.6f else 0.5f
                val minHeight = if (isLandscape) 250.dp else 300.dp
                val maxHeight = if (isLandscape) 400.dp else 450.dp
                (screenHeight * ratio).coerceIn(minHeight, maxHeight)
            }
            else -> {
                val ratio = if (isLandscape) 0.7f else 0.6f
                val minHeight = if (isLandscape) 300.dp else 400.dp
                val maxHeight = if (isLandscape) 500.dp else 600.dp
                (screenHeight * ratio).coerceIn(minHeight, maxHeight)
            }
        }
    }
    
    // キーボード表示時の最終高さ調整
    val adaptiveHeight = remember(baseHeight, isKeyboardVisible, isLandscape) {
        if (isKeyboardVisible) {
            // キーボード表示時は高さを20%削減、最小高さを保証
            val reducedHeight = baseHeight * 0.8f
            when {
                isLargeTablet -> reducedHeight.coerceAtLeast(if (isLandscape) 350.dp else 400.dp)
                isTablet -> reducedHeight.coerceAtLeast(if (isLandscape) 300.dp else 350.dp)
                isCompact -> reducedHeight.coerceAtLeast(if (isLandscape) 180.dp else 200.dp)
                else -> reducedHeight.coerceAtLeast(if (isLandscape) 200.dp else 250.dp)
            }
        } else {
            baseHeight
        }
    }
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 6.dp)
            .then(
                if (highlighted) {
                    Modifier.border(
                        width = 1.dp,
                        color = MaterialTheme.colorScheme.secondary,
                        shape = MaterialTheme.shapes.medium
                    )
                } else {
                    Modifier
                }
            )
    ) {
        if (dualMessage.role == "user") {
            // ユーザーメッセージ
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.End
            ) {
                Surface(
                    modifier = Modifier.widthIn(max = 420.dp),
                    shape = RoundedCornerShape(topStart = 18.dp, topEnd = 18.dp, bottomStart = 18.dp, bottomEnd = 6.dp),
                    color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.6f)
                ) {
                    Text(
                        text = dualMessage.userText,
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurface,
                        modifier = Modifier.padding(horizontal = 14.dp, vertical = 10.dp)
                    )
                }
            }
        } else if (dualMessage.role == "dual_model") {
            // デュアルモデル応答
            DualResponseDisplay(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(adaptiveHeight), // 適応的高さを使用
                layoutType = dualChatSettings.splitLayout,
                splitRatio = dualChatSettings.splitRatio,
                onSplitRatioChanged = onSplitRatioChanged,
                modelAName = dualMessage.modelAName,
                modelBName = dualMessage.modelBName,
                modelAContent = dualMessage.modelAText,
                modelBContent = dualMessage.modelBText,
                modelAProvider = dualMessage.modelAProvider,
                modelBProvider = dualMessage.modelBProvider
            )
        }
    }
}

@Composable
private fun ChatMessageSummaryItem(
    summary: ChatMessageSummary,
    highlighted: Boolean
) {
    val isUserMessage = summary.role == "user"
    val pillShape = RoundedCornerShape(999.dp)
    val userBubbleShape =
        RoundedCornerShape(topStart = 18.dp, topEnd = 18.dp, bottomStart = 18.dp, bottomEnd = 6.dp)
    val blockShape = RoundedCornerShape(12.dp)
    val highlightBorder = if (highlighted) {
        BorderStroke(1.dp, MaterialTheme.colorScheme.secondary.copy(alpha = 0.8f))
    } else {
        null
    }

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 8.dp)
    ) {
        if (isUserMessage) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.End
            ) {
                Surface(
                    modifier = Modifier.widthIn(max = 420.dp),
                    shape = userBubbleShape,
                    color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.6f),
                    border = highlightBorder,
                    shadowElevation = 0.dp
                ) {
                    Text(
                        text = summary.textPreview,
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurface,
                        modifier = Modifier.padding(horizontal = 14.dp, vertical = 10.dp)
                    )
                }
            }
        } else {
            Surface(
                modifier = Modifier.fillMaxWidth(),
                shape = blockShape,
                color = Color.Transparent,
                border = highlightBorder,
                shadowElevation = 0.dp
            ) {
                Text(
                    text = summary.textPreview,
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurface,
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(vertical = 2.dp)
                )
            }
        }
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
fun ChatMessageItemLegacy(
    message: FullChatMessage,
    viewModel: ChatViewModel,
    highlighted: Boolean = false,
    preferSummary: Boolean = false,
    allowSummary: Boolean = true,
    thinkingExpanded: Boolean = false,
    onThinkingToggle: (Long, String) -> Unit = { _, _ -> },
    onEdit: () -> Unit,
    onBranch: (Long) -> Unit
) {
    var showMenu by remember { mutableStateOf(false) }
    var isEditing by remember { mutableStateOf(false) }
    var editText by remember { mutableStateOf(message.chatMessage.text) }
    val clipboardManager = LocalClipboardManager.current
    val context = LocalContext.current

    // 自動会話メッセージの解析
    val autoConvInfo = if (message.chatMessage.role == "model") {
        parseAutoConversationMessage(message.chatMessage.text)
    } else {
        AutoConversationInfo(false, null, message.chatMessage.text)
    }
    
    // 表示位置の決定（自動会話の場合はモデルBを右側に、SYSTEMは中央）
    val isRightAligned = when {
        message.chatMessage.role == "user" -> true
        autoConvInfo.isAutoConversation && autoConvInfo.speaker == "AI-B" -> true
        autoConvInfo.isAutoConversation && autoConvInfo.speaker == "SYSTEM" -> false // システムメッセージは左寄せ
        else -> false
    }
    
    val isCenteredSystemMessage = autoConvInfo.isAutoConversation && autoConvInfo.speaker == "SYSTEM"

    Box(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 6.dp)
            .padding(horizontal = 16.dp)
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = when {
                isCenteredSystemMessage -> Arrangement.Center
                isRightAligned -> Arrangement.End
                else -> Arrangement.Start
            }
        ) {
            // Left avatar for AI-A or normal model messages (not for SYSTEM messages)
            if (!isRightAligned && message.chatMessage.role == "model" && !isCenteredSystemMessage) {
                Box(
                    modifier = Modifier
                        .size(32.dp)
                        .background(
                            if (autoConvInfo.isAutoConversation) {
                                when (autoConvInfo.speaker) {
                                    "AI-A" -> MaterialTheme.colorScheme.primary
                                    else -> MaterialTheme.colorScheme.primary
                                }
                            } else {
                                MaterialTheme.colorScheme.primary
                            },
                            shape = MaterialTheme.shapes.small
                        ),
                    contentAlignment = Alignment.Center
                ) {
                    Text(
                        text = if (autoConvInfo.isAutoConversation) {
                            when (autoConvInfo.speaker) {
                                "AI-A" -> "A"
                                "AI-B" -> "B"
                                "SYSTEM" -> "ℹ"
                                else -> "AI"
                            }
                        } else {
                            "AI"
                        },
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onPrimary
                    )
                }
                Spacer(modifier = Modifier.width(12.dp))
            }
            
            Surface(
                modifier = Modifier
                    .widthIn(max = when {
                        isCenteredSystemMessage -> 400.dp
                        isRightAligned -> 300.dp
                        else -> 600.dp
                    }),
                shape = MaterialTheme.shapes.medium,
                color = when {
                    message.chatMessage.role == "user" -> MaterialTheme.colorScheme.primaryContainer
                    autoConvInfo.isAutoConversation && autoConvInfo.speaker == "SYSTEM" ->
                        MaterialTheme.colorScheme.tertiaryContainer
                    else -> MaterialTheme.colorScheme.surfaceContainerHighest
                },
                shadowElevation = if (isRightAligned) 2.dp else 0.dp,
                border = if (highlighted) {
                    BorderStroke(1.dp, MaterialTheme.colorScheme.secondary)
                } else {
                    null
                }
            ) {
                Column(
                    modifier = Modifier.padding(16.dp)
                ) {
                    val thinkingText = resolveThinkingText(message, preferSummary, allowSummary)
                    if (!thinkingText.isNullOrBlank()) {
                        Surface(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clickable { onThinkingToggle(message.chatMessage.id, thinkingText) },
                            color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.3f),
                            shape = MaterialTheme.shapes.small
                        ) {
                            Row(
                                modifier = Modifier.padding(8.dp),
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                Icon(
                                    Icons.Default.Psychology,
                                    contentDescription = "Thinking",
                                    modifier = Modifier.size(16.dp),
                                    tint = MaterialTheme.colorScheme.primary
                                )
                                Spacer(modifier = Modifier.width(8.dp))
                                Text(
                                    text = "Thinking",
                                    style = MaterialTheme.typography.labelMedium,
                                    color = MaterialTheme.colorScheme.primary
                                )
                                Spacer(modifier = Modifier.weight(1f))
                                Icon(
                                    if (thinkingExpanded) Icons.Default.KeyboardArrowUp else Icons.Default.KeyboardArrowDown,
                                    contentDescription = if (thinkingExpanded) "Collapse" else "Expand",
                                    modifier = Modifier.size(16.dp),
                                    tint = MaterialTheme.colorScheme.primary
                                )
                            }
                        }
                        Spacer(modifier = Modifier.height(12.dp))
                    }
                    if (message.chatMessage.attachments.isNotEmpty()) {
                        Spacer(modifier = Modifier.height(8.dp))
                        MessageAttachmentList(attachments = message.chatMessage.attachments)
                        Spacer(modifier = Modifier.height(4.dp))
                    }
                    if (isEditing) {
                        Column {
                            YamabikoTextField(
                                value = editText,
                                onValueChange = { editText = it },
                                modifier = Modifier.fillMaxWidth(),
                                minLines = 3,
                                maxLines = 20,
                                placeholder = { Text("Edit message...") }       
                            )
                            Row(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(top = 8.dp),
                                horizontalArrangement = Arrangement.End
                            ) {
                                TextButton(
                                    onClick = {
                                        isEditing = false
                                        editText = message.chatMessage.text
                                    }
                                ) {
                                    Text("Cancel")
                                }
                                Spacer(modifier = Modifier.width(8.dp))
                                Button(
                                    onClick = {
                                        viewModel.updateMessage(message.chatMessage.copy(text = editText))
                                        isEditing = false
                                    }
                                ) {
                                    Text("Save")
                                }
                            }
                        }
                    } else {
                        Box(
                            modifier = Modifier.fillMaxWidth()
                        ) {
                            MarkdownText(
                                markdown = if (autoConvInfo.isAutoConversation) {
                                    autoConvInfo.cleanContent
                                } else {
                                    message.chatMessage.text
                                },
                                modifier = Modifier.fillMaxWidth()
                            )
                            // メニュー表示用のオーバーレイ（右上に小さなボタン）
                            IconButton(
                                onClick = { showMenu = true },
                                modifier = Modifier
                                    .align(Alignment.TopEnd)
                                    .size(24.dp)
                            ) {
                                Icon(
                                    Icons.Default.MoreVert,
                                    contentDescription = "More options",
                                    modifier = Modifier.size(16.dp),
                                    tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.6f)
                                )
                            }
                        }
                    }
                }

                DropdownMenu(
                    expanded = showMenu,
                    onDismissRequest = { showMenu = false }
                ) {
                    DropdownMenuItem(
                        text = { Text("Copy") },
                        onClick = {
                            clipboardManager.setText(AnnotatedString(message.chatMessage.text))
                            showMenu = false
                        }
                    )
                    DropdownMenuItem(
                        text = { Text("ここからブランチ") },
                        onClick = {
                            onBranch(message.chatMessage.id)
                            showMenu = false
                        }
                    )
                    DropdownMenuItem(
                        text = { Text("Edit") },
                        onClick = {
                            isEditing = true
                            editText = message.chatMessage.text
                            showMenu = false
                        }
                    )
                    if (message.chatMessage.role == "model") {
                        DropdownMenuItem(
                            text = { Text("Regenerate") },
                            onClick = {
                                viewModel.regenerateMessage(message.chatMessage.id)
                                showMenu = false
                            }
                        )
                    }
                }
            }
            
    // Right avatar for AI-B when displayed on right side
    if (isRightAligned && autoConvInfo.isAutoConversation && autoConvInfo.speaker == "AI-B") {
        Spacer(modifier = Modifier.width(12.dp))
        Box(
                    modifier = Modifier
                        .size(32.dp)
                        .background(
                            MaterialTheme.colorScheme.secondary,
                            shape = MaterialTheme.shapes.small
                        ),
                    contentAlignment = Alignment.Center
                ) {
                    Text(
                        text = "B",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSecondary
                    )
                }
            }
        }
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
fun ChatMessageItem(
    message: FullChatMessage,
    viewModel: ChatViewModel,
    highlighted: Boolean = false,
    canRegenerate: Boolean = false,
    thinkingExpanded: Boolean = false,
    preferSummary: Boolean = false,
    allowSummary: Boolean = true,
    onThinkingToggle: (Long, String) -> Unit = { _, _ -> },
    onEdit: () -> Unit,
    onBranch: (Long) -> Unit
) {
    var showMenu by remember { mutableStateOf(false) }
    var isEditing by remember { mutableStateOf(false) }
    var editText by remember { mutableStateOf(message.chatMessage.text) }
    val clipboardManager = LocalClipboardManager.current

    val autoConvInfo = if (message.chatMessage.role == "model") {
        parseAutoConversationMessage(message.chatMessage.text)
    } else {
        AutoConversationInfo(false, null, message.chatMessage.text)
    }

    val isUserMessage = message.chatMessage.role == "user"
    val isSystemMessage = autoConvInfo.isAutoConversation && autoConvInfo.speaker == "SYSTEM"

    val pillShape = RoundedCornerShape(999.dp)
    val userBubbleShape =
        RoundedCornerShape(topStart = 18.dp, topEnd = 18.dp, bottomStart = 18.dp, bottomEnd = 6.dp)
    val blockShape = RoundedCornerShape(12.dp)
    val highlightBorder = if (highlighted) {
        BorderStroke(1.dp, MaterialTheme.colorScheme.secondary.copy(alpha = 0.8f))
    } else {
        null
    }

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 8.dp)
    ) {
        when {
            isSystemMessage -> {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.Center
                ) {
                    Box {
                        Surface(
                            modifier = Modifier
                                .combinedClickable(
                                    enabled = !isEditing,
                                    onClick = {},
                                    onLongClick = { showMenu = true }
                                )
                                .widthIn(max = 520.dp),
                            shape = pillShape,
                            color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.04f),
                            border = highlightBorder,
                            shadowElevation = 0.dp
                        ) {
                            Text(
                                text = autoConvInfo.cleanContent,
                                style = MaterialTheme.typography.labelSmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                modifier = Modifier.padding(horizontal = 12.dp, vertical = 6.dp)
                            )
                        }

                        DropdownMenu(
                            expanded = showMenu,
                            onDismissRequest = { showMenu = false }
                        ) {
                            DropdownMenuItem(
                                text = { Text("Copy") },
                                onClick = {
                                    clipboardManager.setText(AnnotatedString(message.chatMessage.text))
                                    showMenu = false
                                }
                            )
                            DropdownMenuItem(
                                text = { Text("ここからブランチ") },
                                onClick = {
                                    onBranch(message.chatMessage.id)
                                    showMenu = false
                                }
                            )
                        }
                    }
                }
            }

            isUserMessage -> {
                if (message.chatMessage.attachments.isNotEmpty()) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.End
                    ) {
                        Box(modifier = Modifier.widthIn(max = 420.dp)) {
                            MessageAttachmentList(attachments = message.chatMessage.attachments)
                        }
                    }
                    Spacer(modifier = Modifier.height(12.dp))
                }

                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.End
                ) {
                    Box(
                        modifier = Modifier.widthIn(max = 420.dp)
                    ) {
                        Surface(
                            modifier = Modifier.combinedClickable(
                                enabled = !isEditing,
                                onClick = {},
                                onLongClick = { showMenu = true }
                            ),
                            shape = userBubbleShape,
                            color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.6f),
                            border = highlightBorder,
                            shadowElevation = 0.dp
                        ) {
                            Text(
                                text = message.chatMessage.text,
                                style = MaterialTheme.typography.bodyMedium,
                                color = MaterialTheme.colorScheme.onSurface,
                                modifier = Modifier.padding(horizontal = 14.dp, vertical = 10.dp)
                            )
                        }

                        DropdownMenu(
                            expanded = showMenu,
                            onDismissRequest = { showMenu = false }
                        ) {
                            DropdownMenuItem(
                                text = { Text("Copy") },
                                onClick = {
                                    clipboardManager.setText(AnnotatedString(message.chatMessage.text))
                                    showMenu = false
                                }
                            )
                            DropdownMenuItem(
                                text = { Text("ここからブランチ") },
                                onClick = {
                                    onBranch(message.chatMessage.id)
                                    showMenu = false
                                }
                            )
                            DropdownMenuItem(
                                text = { Text("Edit") },
                                onClick = {
                                    onEdit()
                                    isEditing = true
                                    editText = message.chatMessage.text
                                    showMenu = false
                                }
                            )
                        }
                    }
                }

                if (isEditing) {
                    Spacer(modifier = Modifier.height(10.dp))
                    YamabikoTextField(
                        value = editText,
                        onValueChange = { editText = it },
                        modifier = Modifier.fillMaxWidth(),
                        minLines = 3,
                        maxLines = 20,
                        placeholder = { Text("Edit message...") }
                    )
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(top = 8.dp),
                        horizontalArrangement = Arrangement.End
                    ) {
                        TextButton(
                            onClick = {
                                isEditing = false
                                editText = message.chatMessage.text
                            }
                        ) {
                            Text("Cancel")
                        }
                        Spacer(modifier = Modifier.width(8.dp))
                        Button(
                            onClick = {
                                viewModel.updateMessage(message.chatMessage.copy(text = editText))
                                isEditing = false
                            }
                        ) {
                            Text("Save")
                        }
                    }
                }
            }

            else -> {
                Box {
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .combinedClickable(
                                enabled = !isEditing,
                                onClick = {},
                                onLongClick = { showMenu = true }
                            )
                    ) {
                        if (autoConvInfo.isAutoConversation && !autoConvInfo.speaker.isNullOrBlank()) {
                            Text(
                                text = autoConvInfo.speaker,
                                style = MaterialTheme.typography.labelSmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                modifier = Modifier.padding(bottom = 6.dp)
                            )
                        }

                        val thinkingText = resolveThinkingText(message, preferSummary, allowSummary)
                        if (!thinkingText.isNullOrBlank()) {
                            Column {
                                Row(
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .clickable { onThinkingToggle(message.chatMessage.id, thinkingText) }
                                        .padding(vertical = 6.dp),
                                    verticalAlignment = Alignment.CenterVertically
                                ) {
                                    Icon(
                                        Icons.Default.Psychology,
                                        contentDescription = "Thinking",
                                        modifier = Modifier.size(16.dp),
                                        tint = MaterialTheme.colorScheme.onSurfaceVariant
                                    )
                                    Spacer(modifier = Modifier.width(8.dp))
                                    Text(
                                        text = "Thinking",
                                        style = MaterialTheme.typography.labelMedium,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant
                                    )
                                    Spacer(modifier = Modifier.weight(1f))
                                    Icon(
                                        if (thinkingExpanded) Icons.Default.KeyboardArrowUp else Icons.Default.KeyboardArrowDown,
                                        contentDescription = if (thinkingExpanded) "Collapse" else "Expand",
                                        modifier = Modifier.size(18.dp),
                                        tint = MaterialTheme.colorScheme.onSurfaceVariant
                                    )
                                }

                                HorizontalDivider(
                                    color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.7f)
                                )
                                Spacer(modifier = Modifier.height(10.dp))
                            }
                        }

                        if (message.chatMessage.attachments.isNotEmpty()) {
                            MessageAttachmentList(attachments = message.chatMessage.attachments)
                            Spacer(modifier = Modifier.height(10.dp))
                        }

                        val contentText = if (autoConvInfo.isAutoConversation) {
                            autoConvInfo.cleanContent
                        } else {
                            message.chatMessage.text
                        }

                        Surface(
                            modifier = Modifier.fillMaxWidth(),
                            shape = blockShape,
                            color = Color.Transparent,
                            border = highlightBorder,
                            shadowElevation = 0.dp
                        ) {
                            Column(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(vertical = 2.dp)
                            ) {
                                if (isEditing) {
                                    YamabikoTextField(
                                        value = editText,
                                        onValueChange = { editText = it },
                                        modifier = Modifier.fillMaxWidth(),
                                        minLines = 3,
                                        maxLines = 20,
                                        placeholder = { Text("Edit message...") }
                                    )
                                    Row(
                                        modifier = Modifier
                                            .fillMaxWidth()
                                            .padding(top = 8.dp),
                                        horizontalArrangement = Arrangement.End
                                    ) {
                                        TextButton(
                                            onClick = {
                                                isEditing = false
                                                editText = message.chatMessage.text
                                            }
                                        ) {
                                            Text("Cancel")
                                        }
                                        Spacer(modifier = Modifier.width(8.dp))
                                        Button(
                                            onClick = {
                                                viewModel.updateMessage(message.chatMessage.copy(text = editText))
                                                isEditing = false
                                            }
                                        ) {
                                            Text("Save")
                                        }
                                    }
                                } else {
                                    MarkdownText(
                                        markdown = contentText,
                                        modifier = Modifier.fillMaxWidth()
                                    )
                                }
                            }
                        }

                        if (!isEditing) {
                            Row(
                                modifier = Modifier.padding(top = 6.dp),
                                horizontalArrangement = Arrangement.Start,
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                val actionIconTint = MaterialTheme.colorScheme.onSurfaceVariant

                                Box(
                                    modifier = Modifier
                                        .size(32.dp)
                                        .clickable { onBranch(message.chatMessage.id) },
                                    contentAlignment = Alignment.Center
                                ) {
                                    Icon(
                                        imageVector = Icons.AutoMirrored.Filled.CallSplit,
                                        contentDescription = "ここからブランチ",
                                        modifier = Modifier.size(18.dp),
                                        tint = actionIconTint
                                    )
                                }
                                Spacer(modifier = Modifier.width(4.dp))
                                Box(
                                    modifier = Modifier
                                        .size(32.dp)
                                        .clickable(
                                            enabled = canRegenerate,
                                            onClick = { viewModel.regenerateMessage(message.chatMessage.id) }
                                        ),
                                    contentAlignment = Alignment.Center
                                ) {
                                    Icon(
                                        imageVector = Icons.Default.Refresh,
                                        contentDescription = "再生成",
                                        modifier = Modifier.size(18.dp),
                                        tint = actionIconTint.copy(alpha = if (canRegenerate) 1f else 0.38f)
                                    )
                                }
                                Spacer(modifier = Modifier.width(4.dp))
                                Box(
                                    modifier = Modifier
                                        .size(32.dp)
                                        .clickable {
                                            clipboardManager.setText(AnnotatedString(message.chatMessage.text))
                                        },
                                    contentAlignment = Alignment.Center
                                ) {
                                    Icon(
                                        imageVector = Icons.Default.ContentCopy,
                                        contentDescription = "全文コピー",
                                        modifier = Modifier.size(18.dp),
                                        tint = actionIconTint
                                    )
                                }
                            }
                        }
                    }

                    DropdownMenu(
                        expanded = showMenu,
                        onDismissRequest = { showMenu = false }
                    ) {
                        DropdownMenuItem(
                            text = { Text("Copy") },
                            onClick = {
                                clipboardManager.setText(AnnotatedString(message.chatMessage.text))
                                showMenu = false
                            }
                        )
                        DropdownMenuItem(
                            text = { Text("ここからブランチ") },
                            onClick = {
                                onBranch(message.chatMessage.id)
                                showMenu = false
                            }
                        )
                        DropdownMenuItem(
                            text = { Text("Edit") },
                            onClick = {
                                onEdit()
                                isEditing = true
                                editText = message.chatMessage.text
                                showMenu = false
                            }
                        )
                        if (message.chatMessage.role == "model") {
                            DropdownMenuItem(
                                text = { Text("Regenerate") },
                                onClick = {
                                    viewModel.regenerateMessage(message.chatMessage.id)
                                    showMenu = false
                                }
                            )
                        }
                    }
                }
            }
        }
    }
}

@Composable
fun AttachmentPreview(
    attachments: List<android.net.Uri>,
    onRemoveAttachment: (android.net.Uri) -> Unit
) {
    val context = LocalContext.current
    LazyRow(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 8.dp)
    ) {
        items(attachments) { uri ->
            Box(
                modifier = Modifier
                    .padding(end = 8.dp)
            ) {
                val isImage = remember(uri) { isImageUri(context, uri) }
                val thumbnail = rememberImageThumbnail(
                    key = uri.toString(),
                    loader = { decodeThumbnailFromUri(context, uri, 240) }
                )
                if (isImage && thumbnail != null) {
                    var showPreview by remember { mutableStateOf(false) }
                    if (showPreview) {
                        ImagePreviewDialog(
                            title = uri.lastPathSegment,
                            image = thumbnail,
                            onDismiss = { showPreview = false }
                        )
                    }
                    Card(
                        modifier = Modifier
                            .size(96.dp)
                            .clickable { showPreview = true },
                        shape = MaterialTheme.shapes.small
                    ) {
                        Image(
                            bitmap = thumbnail,
                            contentDescription = uri.lastPathSegment,
                            contentScale = ContentScale.Crop,
                            modifier = Modifier.fillMaxSize()
                        )
                    }
                } else {
                    Text(
                        text = uri.lastPathSegment ?: "Attached File",
                        modifier = Modifier
                            .background(
                                MaterialTheme.colorScheme.secondaryContainer,
                                shape = MaterialTheme.shapes.small
                            )
                            .padding(8.dp)
                    )
                }
                IconButton(
                    onClick = { onRemoveAttachment(uri) },
                    modifier = Modifier
                        .align(Alignment.TopEnd)
                        .size(16.dp)
                ) {
                    Icon(Icons.Default.Close, contentDescription = "Remove Attachment")
                }
            }
        }
    }
}

@Composable
fun MessageAttachmentList(attachments: List<String>) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        attachments.forEach { path ->
            val fileName = runCatching { File(path).name }.getOrNull().orEmpty()
            val isImage = remember(path) { isImagePath(path) }
            val thumbnail = rememberImageThumbnail(
                key = path,
                loader = { decodeThumbnailFromFile(path, 320) }
            )
            if (isImage && thumbnail != null) {
                var showPreview by remember { mutableStateOf(false) }
                if (showPreview) {
                    ImagePreviewDialog(
                        title = fileName.ifBlank { path },
                        image = thumbnail,
                        onDismiss = { showPreview = false }
                    )
                }
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .background(
                            MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.2f),
                            shape = MaterialTheme.shapes.small
                        )
                        .padding(6.dp)
                ) {
                    Card(
                        modifier = Modifier
                            .size(120.dp)
                            .clickable { showPreview = true },
                        shape = MaterialTheme.shapes.small
                    ) {
                        Image(
                            bitmap = thumbnail,
                            contentDescription = fileName.ifBlank { path },
                            contentScale = ContentScale.Crop,
                            modifier = Modifier.fillMaxSize()
                        )
                    }
                    if (fileName.isNotBlank()) {
                        Spacer(modifier = Modifier.height(6.dp))
                        Text(
                            text = fileName,
                            style = MaterialTheme.typography.labelSmall,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                }
            } else {
                Text(
                    text = if (fileName.isNotBlank()) fileName else path,
                    style = MaterialTheme.typography.bodySmall,
                    modifier = Modifier
                        .fillMaxWidth()
                        .background(
                            MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.6f),
                            shape = MaterialTheme.shapes.small
                        )
                        .padding(horizontal = 8.dp, vertical = 6.dp)
                )
            }
        }
    }
}

@Composable
private fun ImagePreviewDialog(
    title: String?,
    image: androidx.compose.ui.graphics.ImageBitmap,
    onDismiss: () -> Unit
) {
    Dialog(onDismissRequest = onDismiss) {
        Surface(
            shape = MaterialTheme.shapes.medium,
            tonalElevation = 6.dp,
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp)
        ) {
            Column(modifier = Modifier.padding(12.dp)) {
                if (!title.isNullOrBlank()) {
                    Text(
                        text = title,
                        style = MaterialTheme.typography.labelMedium,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                    Spacer(modifier = Modifier.height(8.dp))
                }
                Image(
                    bitmap = image,
                    contentDescription = title,
                    contentScale = ContentScale.Fit,
                    modifier = Modifier
                        .fillMaxWidth()
                        .heightIn(max = 420.dp)
                )
                Spacer(modifier = Modifier.height(8.dp))
                TextButton(
                    onClick = onDismiss,
                    modifier = Modifier.align(Alignment.End)
                ) {
                    Text("閉じる")
                }
            }
        }
    }
}

@Composable
private fun rememberImageThumbnail(
    key: String,
    loader: suspend () -> android.graphics.Bitmap?
): androidx.compose.ui.graphics.ImageBitmap? {
    val bitmap by produceState<android.graphics.Bitmap?>(initialValue = null, key1 = key) {
        value = withContext(Dispatchers.IO) { loader() }
    }
    return bitmap?.asImageBitmap()
}

private fun isImagePath(path: String): Boolean {
    val extension = path.substringAfterLast('.', "").lowercase()
    return extension in setOf(
        "jpg", "jpeg", "png", "gif", "webp", "bmp", "heic", "heif"
    )
}

private fun isImageUri(context: android.content.Context, uri: Uri): Boolean {
    val type = runCatching { context.contentResolver.getType(uri) }.getOrNull()
    if (type?.startsWith("image/") == true) return true
    val extension = uri.lastPathSegment?.substringAfterLast('.', "")?.lowercase().orEmpty()
    return extension in setOf(
        "jpg", "jpeg", "png", "gif", "webp", "bmp", "heic", "heif"
    )
}

private fun decodeThumbnailFromFile(path: String, targetPx: Int): android.graphics.Bitmap? {
    val options = BitmapFactory.Options().apply { inJustDecodeBounds = true }
    BitmapFactory.decodeFile(path, options)
    if (options.outWidth <= 0 || options.outHeight <= 0) return null
    options.inSampleSize = calculateInSampleSize(options, targetPx, targetPx)
    options.inJustDecodeBounds = false
    return BitmapFactory.decodeFile(path, options)
}

private fun decodeThumbnailFromUri(
    context: android.content.Context,
    uri: Uri,
    targetPx: Int
): android.graphics.Bitmap? {
    val resolver = context.contentResolver
    val options = BitmapFactory.Options().apply { inJustDecodeBounds = true }
    resolver.openInputStream(uri)?.use { stream ->
        BitmapFactory.decodeStream(stream, null, options)
    }
    if (options.outWidth <= 0 || options.outHeight <= 0) return null
    options.inSampleSize = calculateInSampleSize(options, targetPx, targetPx)
    options.inJustDecodeBounds = false
    resolver.openInputStream(uri)?.use { stream ->
        return BitmapFactory.decodeStream(stream, null, options)
    }
    return null
}

private fun calculateInSampleSize(
    options: BitmapFactory.Options,
    reqWidth: Int,
    reqHeight: Int
): Int {
    val height = options.outHeight
    val width = options.outWidth
    var inSampleSize = 1
    if (height > reqHeight || width > reqWidth) {
        var halfHeight = height / 2
        var halfWidth = width / 2
        while ((halfHeight / inSampleSize) >= reqHeight && (halfWidth / inSampleSize) >= reqWidth) {
            inSampleSize *= 2
        }
    }
    return inSampleSize
}

@Composable
fun MessageInput(
    value: String,
    onValueChange: (String) -> Unit,
    attachments: List<android.net.Uri>,
    onSendClick: () -> Unit,
    onImagePick: () -> Unit,
    onFilePick: () -> Unit,
    isDualModeActive: Boolean,
    isAutoConversationEnabled: Boolean,
    contextLabel: String? = null,
    onDualModeToggle: () -> Unit,
    onAutoConversationToggle: () -> Unit
) {
    var showAttachmentMenu by remember { mutableStateOf(false) }
    var showModeMenu by remember { mutableStateOf(false) }

    Surface(
        modifier = Modifier
            .fillMaxWidth()
            .padding(16.dp),
        shape = MaterialTheme.shapes.extraLarge,
        color = MaterialTheme.colorScheme.surfaceContainerHigh,
        tonalElevation = 0.dp,
        shadowElevation = 0.dp
    ) {
        Box(modifier = Modifier.fillMaxWidth()) {
            // メイン行
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(12.dp),
                verticalAlignment = Alignment.Bottom
            ) {
                // Attachment button
                Box {
                IconButton(
                    onClick = { showAttachmentMenu = true },
                    modifier = Modifier.size(40.dp)
                ) {
                    Icon(
                        Icons.Default.AttachFile,
                        contentDescription = "Add Attachment",
                        tint = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
                DropdownMenu(
                    expanded = showAttachmentMenu,
                    onDismissRequest = { showAttachmentMenu = false }
                ) {
                    DropdownMenuItem(
                        text = { Text("Image") },
                        leadingIcon = { Icon(Icons.Default.Image, null) },
                        onClick = {
                            showAttachmentMenu = false
                            onImagePick()
                        }
                    )
                    DropdownMenuItem(
                        text = { Text("File") },
                        leadingIcon = { Icon(Icons.Default.Description, null) },
                        onClick = {
                            showAttachmentMenu = false
                            onFilePick()
                        }
                    )
                }
            }
            
            // Text input field
            TextField(
                value = value,
                onValueChange = onValueChange,
                modifier = Modifier.weight(1f),
                placeholder = {
                    Text(
                        text = if (isAutoConversationEnabled) {
                            "AI同士の会話を開始するメッセージを入力..."
                        } else {
                            "Message..."
                        },
                        color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.6f)
                    ) 
                },
                colors = TextFieldDefaults.colors(
                    focusedContainerColor = Color.Transparent,
                    unfocusedContainerColor = Color.Transparent,
                    disabledContainerColor = Color.Transparent,
                    focusedIndicatorColor = Color.Transparent,
                    unfocusedIndicatorColor = Color.Transparent,
                    disabledIndicatorColor = Color.Transparent
                ),
                shape = MaterialTheme.shapes.extraLarge,
                minLines = 1,
                maxLines = 6
            )
            
            Spacer(modifier = Modifier.width(4.dp))
            
            // Mode settings button
            Box {
                IconButton(
                    onClick = { showModeMenu = true },
                    modifier = Modifier.size(40.dp)
                ) {
                    Icon(
                        Icons.Default.Settings,
                        contentDescription = "Mode Settings",
                        tint = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.size(20.dp)
                    )
                }
                
                DropdownMenu(
                    expanded = showModeMenu,
                    onDismissRequest = { showModeMenu = false },
                    modifier = Modifier.widthIn(min = 220.dp)
                ) {
                    // デュアルモード設定
                    DropdownMenuItem(
                        text = {
                            Row(
                                verticalAlignment = Alignment.CenterVertically,
                                modifier = Modifier.fillMaxWidth()
                            ) {
                                Icon(
                                    Icons.Default.Compare,
                                    contentDescription = "Dual Mode",
                                    modifier = Modifier.size(20.dp),
                                    tint = if (isDualModeActive) 
                                        MaterialTheme.colorScheme.primary 
                                    else 
                                        MaterialTheme.colorScheme.onSurfaceVariant
                                )
                                Spacer(modifier = Modifier.width(12.dp))
                                Column(modifier = Modifier.weight(1f)) {
                                    Text(
                                        text = "デュアルモード",
                                        style = MaterialTheme.typography.bodyMedium,
                                        color = if (isDualModeActive) 
                                            MaterialTheme.colorScheme.primary 
                                        else 
                                            MaterialTheme.colorScheme.onSurface
                                    )
                                    Text(
                                        text = if (isDualModeActive) "2つのモデルで比較中" else "モデル比較機能",
                                        style = MaterialTheme.typography.bodySmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant
                                    )
                                }
                                Switch(
                                    checked = isDualModeActive,
                                    onCheckedChange = { onDualModeToggle() },
                                    modifier = Modifier.scale(0.8f)
                                )
                            }
                        },
                        onClick = { onDualModeToggle() }
                    )
                    
                    HorizontalDivider()
                    
                    // 自動会話設定
                    DropdownMenuItem(
                        text = {
                            Row(
                                verticalAlignment = Alignment.CenterVertically,
                                modifier = Modifier.fillMaxWidth()
                            ) {
                                Icon(
                                    Icons.Default.AutoAwesome,
                                    contentDescription = "Auto Conversation",
                                    modifier = Modifier.size(20.dp),
                                    tint = if (isAutoConversationEnabled) 
                                        MaterialTheme.colorScheme.secondary 
                                    else 
                                        MaterialTheme.colorScheme.onSurfaceVariant
                                )
                                Spacer(modifier = Modifier.width(12.dp))
                                Column(modifier = Modifier.weight(1f)) {
                                    Text(
                                        text = "LLM自動会話",
                                        style = MaterialTheme.typography.bodyMedium,
                                        color = if (isAutoConversationEnabled) 
                                            MaterialTheme.colorScheme.secondary 
                                        else 
                                            MaterialTheme.colorScheme.onSurface
                                    )
                                    Text(
                                        text = if (isAutoConversationEnabled) "AI同士の自動会話" else "AI同士の会話機能",
                                        style = MaterialTheme.typography.bodySmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant
                                    )
                                }
                                Switch(
                                    checked = isAutoConversationEnabled,
                                    onCheckedChange = { onAutoConversationToggle() },
                                    modifier = Modifier.scale(0.8f)
                                )
                            }
                        },
                        onClick = { onAutoConversationToggle() }
                    )
                }
            }
            
            Spacer(modifier = Modifier.width(4.dp))
            
            // Send button
            FilledIconButton(
                onClick = onSendClick,
                enabled = value.isNotBlank() || attachments.isNotEmpty(),
                modifier = Modifier.size(40.dp),
                colors = IconButtonDefaults.filledIconButtonColors(
                    containerColor = if (value.isNotBlank() || attachments.isNotEmpty()) 
                        MaterialTheme.colorScheme.primary else 
                        MaterialTheme.colorScheme.surfaceVariant,
                    contentColor = if (value.isNotBlank() || attachments.isNotEmpty()) 
                        MaterialTheme.colorScheme.onPrimary else 
                        MaterialTheme.colorScheme.onSurfaceVariant
                )
            ) {
                Icon(
                    Icons.AutoMirrored.Filled.Send,
                    contentDescription = "Send",
                    modifier = Modifier.size(20.dp)
                )
            }
            }
            // 右上のチップ表示
            if (!contextLabel.isNullOrBlank()) {
                Surface(
                    modifier = Modifier
                        .align(Alignment.TopEnd)
                        .padding(top = 6.dp, end = 6.dp),
                    color = MaterialTheme.colorScheme.surface,
                    tonalElevation = 2.dp,
                    shape = MaterialTheme.shapes.small
                ) {
                    Text(
                        text = contextLabel,
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp)
                    )
                }
            }
        }
    }
}

@Preview(showBackground = true)
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ChatScreenPreview() {
    YamabikoPreview {
        val now = System.currentTimeMillis()
        var text by rememberSaveable { mutableStateOf("こんにちは") }

        Scaffold(
            topBar = {
                TopAppBar(
                    title = { Text("Chat") },
                    navigationIcon = {
                        IconButton(onClick = {}) {
                            Icon(Icons.Default.Menu, contentDescription = "Menu")
                        }
                    },
                    actions = {
                        IconButton(onClick = {}) {
                            Icon(Icons.Default.Tune, contentDescription = "Model")
                        }
                    }
                )
            }
        ) { padding ->
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(padding)
            ) {
                LazyColumn(
                    modifier = Modifier
                        .fillMaxWidth()
                        .weight(1f),
                    contentPadding = PaddingValues(vertical = 8.dp)
                ) {
                    item {
                        ChatMessageSummaryItem(
                            summary = ChatMessageSummary(
                                id = 1L,
                                conversationId = 1L,
                                role = "user",
                                timestamp = now - 60_000L,
                                hasAttachments = false,
                                hasThinking = false,
                                textPreview = "こんにちは"
                            ),
                            highlighted = false
                        )
                    }
                    item {
                        ChatMessageSummaryItem(
                            summary = ChatMessageSummary(
                                id = 2L,
                                conversationId = 1L,
                                role = "model",
                                timestamp = now - 58_000L,
                                hasAttachments = false,
                                hasThinking = true,
                                textPreview = "こんにちは。ご挨拶ありがとうございます。"
                            ),
                            highlighted = true
                        )
                    }
                    item {
                        DualChatMessageItem(
                            dualMessage = DualChatMessage(
                                id = 3L,
                                conversationId = 1L,
                                role = "dual_model",
                                userText = "この文章を要約して",
                                modelAText = "要点は3つです…",
                                modelBText = "結論から言うと…",
                                modelAName = "glm-4.6",
                                modelBName = "MiniMax-M2.1",
                                modelAProvider = "ZAI",
                                modelBProvider = "MINIMAX",
                                timestamp = now - 40_000L
                            ),
                            dualChatSettings = com.porarri.yamabikochat.data.local.DualChatSettings(
                                isDualModeEnabled = true,
                                splitLayout = SplitLayoutType.VERTICAL,
                                splitRatio = 0.5f
                            ),
                            highlighted = false,
                            onSplitRatioChanged = {}
                        )
                    }
                }

                ChatMessageInputBar(
                    value = text,
                    onValueChange = { text = it },
                    attachments = emptyList(),
                    onSendClick = {},
                    onImagePick = {},
                    onFilePick = {},
                    isAutoConversationEnabled = false,
                    contextLabel = "GEMINI · gemini-3-flash-preview",
                    isSecretMode = false
                )
            }
        }
    }
}

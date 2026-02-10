package com.porarri.yamabikochat.ui.conversation

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Chat
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.ViewColumn
import androidx.compose.material3.AssistChip
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Observer
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.navigation.NavController
import androidx.navigation.compose.currentBackStackEntryAsState
import com.porarri.yamabikochat.MyApplication
import com.porarri.yamabikochat.data.local.ConversationListEntry
import com.porarri.yamabikochat.data.local.ConversationSearchResult
import com.porarri.yamabikochat.ui.components.YamabikoTextField
import com.porarri.yamabikochat.ui.preview.YamabikoPreview
import java.util.Calendar
import java.util.Locale

@Composable
fun ConversationListScreen(
    navController: NavController,
    onConversationClick: () -> Unit,
    onClose: (() -> Unit)? = null,
    viewModel: ConversationListViewModel = viewModel(
        factory = (LocalContext.current.applicationContext as MyApplication).viewModelFactory
    )
) {
    val conversationEntries by viewModel.conversationEntries.collectAsState()   
    val searchQuery by viewModel.searchQuery.collectAsState()
    val searchResults by viewModel.searchResults.collectAsState()
    val entryMap = remember(conversationEntries) {
        conversationEntries.associateBy { it.conversationId }
    }
    val backStackEntry by navController.currentBackStackEntryAsState()
    val currentBackStackEntry = backStackEntry
    var selectedConversationIdText by remember(currentBackStackEntry) {
        mutableStateOf(
            currentBackStackEntry?.savedStateHandle?.get<String>("conversationId")
                ?: currentBackStackEntry?.arguments?.getString("conversationId")
        )
    }
    DisposableEffect(currentBackStackEntry) {
        val liveData = currentBackStackEntry?.savedStateHandle?.getLiveData<String>("conversationId")
        if (liveData == null) {
            onDispose {}
        } else {
            val observer = Observer<String> { selectedConversationIdText = it }
            liveData.observeForever(observer)
            onDispose { liveData.removeObserver(observer) }
        }
    }
    val selectedConversationId = selectedConversationIdText?.toLongOrNull()

    ConversationListContent(
        conversationEntries = conversationEntries,
        searchQuery = searchQuery,
        onSearchQueryChange = viewModel::updateSearchQuery,
        searchResults = searchResults,
        entryMap = entryMap,
        selectedConversationId = selectedConversationId,
        isSettingsSelected = navController.currentDestination?.route == "settings",
        onNewConversationClick = {
            navController.navigate("chat/0") {
                popUpTo("chat/0") { inclusive = true }
            }
            onConversationClick()
        },
        onSearchResultClick = { result ->
            val route = when (result.source) {
                "DUAL" -> "chat/${result.conversationId}?focusDualMessageId=${result.messageId}"
                else -> "chat/${result.conversationId}?focusMessageId=${result.messageId}"
            }
            navController.navigate(route) {
                popUpTo("chat/0") { inclusive = true }
            }
            onConversationClick()
        },
        onConversationClick = { conversationId ->
            navController.navigate("chat/$conversationId") {
                popUpTo("chat/0") { inclusive = true }
            }
            onConversationClick()
        },
        onDeleteConversationClick = { conversationId ->
            viewModel.deleteConversation(conversationId)
        },
        onSettingsClick = {
            navController.navigate("settings")
            onConversationClick()
        },
        onClose = onClose
    )
}

@Composable
private fun ConversationListContent(
    conversationEntries: List<ConversationListEntry>,
    searchQuery: String,
    onSearchQueryChange: (String) -> Unit,
    searchResults: List<ConversationSearchResult>,
    entryMap: Map<Long, ConversationListEntry>,
    selectedConversationId: Long?,
    isSettingsSelected: Boolean,
    onNewConversationClick: () -> Unit,
    onSearchResultClick: (ConversationSearchResult) -> Unit,
    onConversationClick: (Long) -> Unit,
    onDeleteConversationClick: (Long) -> Unit,
    onSettingsClick: () -> Unit,
    onClose: (() -> Unit)? = null
) {
    val isSearching = searchQuery.isNotBlank()
    val focusManager = LocalFocusManager.current
    val selectedEntry = selectedConversationId?.let { entryMap[it] }
    val isSelectedPristineNewChat =
        when (selectedConversationId) {
            null -> false
            0L -> true
            else ->
                selectedEntry?.let { entry ->
                    entry.title == "New Chat" &&
                        entry.lastChatTimestamp == null &&
                        entry.lastDualTimestamp == null
                } ?: false
        }
    val newConversationEnabled = !isSelectedPristineNewChat

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.surface)
            .statusBarsPadding()
    ) {
        ConversationDrawerHeader(
            searchQuery = searchQuery,
            onSearchQueryChange = onSearchQueryChange,
            onClearSearchClick = {
                onSearchQueryChange("")
                focusManager.clearFocus()
            },
            onNewConversationClick = onNewConversationClick,
            newConversationEnabled = newConversationEnabled,
            onClose = onClose
        )

        LazyColumn(
            modifier = Modifier.weight(1f),
            contentPadding = PaddingValues(vertical = 8.dp)
        ) {
            item {
                DrawerSectionHeader(
                    title = "ショートカット",
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp)
                )
            }

            item {
                DrawerActionRow(
                    icon = Icons.Default.Edit,
                    label = "新しいチャット",
                    onClick = onNewConversationClick,
                    enabled = newConversationEnabled
                )
            }

            item {
                Spacer(modifier = Modifier.height(8.dp))
            }

            item {
                DrawerSectionHeader(
                    title = if (isSearching) "検索結果 (${searchResults.size})" else "チャット履歴",
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp)
                )
            }

            if (isSearching) {
                if (searchResults.isEmpty()) {
                    item {
                        Box(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(24.dp),
                            contentAlignment = Alignment.Center
                        ) {
                            Text(
                                text = "結果がありません",
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                    }
                } else {
                    items(searchResults, key = { "${it.conversationId}-${it.messageId}" }) { result ->
                        ConversationSearchResultRow(
                            result = result,
                            entry = entryMap[result.conversationId],
                            onClick = {
                                onSearchQueryChange("")
                                focusManager.clearFocus()
                                onSearchResultClick(result)
                            }
                        )
                    }
                }
            } else {
                items(conversationEntries, key = { it.conversationId }) { entry ->
                    ConversationHistoryRow(
                        title = entry.title,
                        timestamp = entry.timestamp,
                        isSelected = entry.conversationId == selectedConversationId,
                        onClick = { onConversationClick(entry.conversationId) },
                        onDeleteClick = { onDeleteConversationClick(entry.conversationId) }
                    )
                }
            }
        }

        HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)

        DrawerProfileFooter(
            displayName = "Yamabiko",
            subtitle = "設定を開く",
            selected = isSettingsSelected,
            onClick = onSettingsClick
        )
    }
}

@Composable
private fun ConversationDrawerHeader(
    searchQuery: String,
    onSearchQueryChange: (String) -> Unit,
    onClearSearchClick: () -> Unit,
    onNewConversationClick: () -> Unit,
    newConversationEnabled: Boolean,
    onClose: (() -> Unit)? = null
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        YamabikoTextField(
            value = searchQuery,
            onValueChange = onSearchQueryChange,
            modifier = Modifier.weight(1f),
            singleLine = true,
            placeholder = { Text("検索") },
            leadingIcon = { Icon(Icons.Default.Search, contentDescription = null) },
            trailingIcon = {
                if (searchQuery.isNotBlank()) {
                    IconButton(onClick = onClearSearchClick) {
                        Icon(Icons.Default.Close, contentDescription = "Clear search")
                    }
                }
            }
        )

        Spacer(modifier = Modifier.width(8.dp))

        IconButton(
            onClick = onNewConversationClick,
            enabled = newConversationEnabled,
            modifier = Modifier.size(40.dp)
        ) {
            Icon(
                imageVector = Icons.Default.Edit,
                contentDescription = "New Chat"
            )
        }

        if (onClose != null) {
            Spacer(modifier = Modifier.width(4.dp))
            IconButton(
                onClick = onClose,
                modifier = Modifier.size(40.dp)
            ) {
                Icon(
                    imageVector = Icons.Default.Close,
                    contentDescription = "Close drawer"
                )
            }
        }
    }
}

@Composable
private fun DrawerSectionHeader(
    title: String,
    modifier: Modifier = Modifier
) {
    Text(
        text = title,
        style = MaterialTheme.typography.labelMedium,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = modifier
    )
}

@Composable
private fun DrawerActionRow(
    icon: ImageVector,
    label: String,
    onClick: () -> Unit,
    enabled: Boolean = true
) {
    val contentAlpha = if (enabled) 1f else 0.38f

    Surface(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 12.dp, vertical = 2.dp),
        shape = MaterialTheme.shapes.medium,
        color = MaterialTheme.colorScheme.surface
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .clickable(enabled = enabled, onClick = onClick)
                .padding(horizontal = 12.dp, vertical = 12.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Icon(
                imageVector = icon,
                contentDescription = null,
                modifier = Modifier.size(20.dp),
                tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = contentAlpha)
            )
            Spacer(modifier = Modifier.width(12.dp))
            Text(
                text = label,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurface.copy(alpha = contentAlpha),
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
        }
    }
}

@Composable
@OptIn(ExperimentalFoundationApi::class)
private fun ConversationHistoryRow(
    title: String,
    timestamp: Long,
    isSelected: Boolean,
    onClick: () -> Unit,
    onDeleteClick: () -> Unit
) {
    var showDeleteMenu by remember { mutableStateOf(false) }

    Surface(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 12.dp, vertical = 2.dp),
        shape = MaterialTheme.shapes.medium,
        color = if (isSelected) {
            MaterialTheme.colorScheme.surfaceContainerHigh
        } else {
            MaterialTheme.colorScheme.surface
        }
    ) {
        Box(modifier = Modifier.fillMaxWidth()) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .combinedClickable(
                        onClick = onClick,
                        onLongClick = { showDeleteMenu = true }
                    )
                    .padding(horizontal = 12.dp, vertical = 12.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    text = title,
                    modifier = Modifier.weight(1f),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurface,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
                val timeLabel = remember(timestamp) { formatRelativeTime(timestamp) }
                if (timeLabel.isNotBlank()) {
                    Spacer(modifier = Modifier.width(8.dp))
                    Text(
                        text = timeLabel,
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }

            DropdownMenu(
                expanded = showDeleteMenu,
                onDismissRequest = { showDeleteMenu = false }
            ) {
                DropdownMenuItem(
                    text = { Text("削除") },
                    leadingIcon = {
                        Icon(
                            imageVector = Icons.Default.Delete,
                            contentDescription = "Delete",
                            tint = MaterialTheme.colorScheme.error
                        )
                    },
                    onClick = {
                        showDeleteMenu = false
                        onDeleteClick()
                    }
                )
            }
        }
    }
}

@Composable
private fun DrawerProfileFooter(
    displayName: String,
    subtitle: String,
    selected: Boolean,
    onClick: () -> Unit
) {
    Surface(
        modifier = Modifier.fillMaxWidth(),
        color = if (selected) {
            MaterialTheme.colorScheme.surfaceContainerHigh
        } else {
            MaterialTheme.colorScheme.surface
        }
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .clickable(onClick = onClick)
                .padding(horizontal = 16.dp, vertical = 14.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Surface(
                modifier = Modifier.size(34.dp),
                shape = CircleShape,
                color = MaterialTheme.colorScheme.surfaceContainerHigh
            ) {
                Box(contentAlignment = Alignment.Center) {
                    Text(
                        text = displayName.take(2).uppercase(),
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.onSurface
                    )
                }
            }
            Spacer(modifier = Modifier.width(12.dp))
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = displayName,
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.SemiBold,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
                Text(
                    text = subtitle,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
            }
            Icon(
                imageVector = Icons.Default.Settings,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }
}

@Composable
private fun ConversationSearchResultRow(
    result: ConversationSearchResult,
    entry: ConversationListEntry?,
    onClick: () -> Unit
) {
    val icon = when (result.source) {
        "DUAL" -> Icons.Default.ViewColumn
        else -> Icons.AutoMirrored.Filled.Chat
    }
    val badge = when (result.matchedField) {
        "USER" -> "User"
        "MODEL_A" -> "A"
        "MODEL_B" -> "B"
        else -> null
    }
    val providerLine = entry?.let { buildProviderModelLine(it) } ?: "—"

    Surface(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 12.dp, vertical = 2.dp),
        shape = MaterialTheme.shapes.medium,
        color = MaterialTheme.colorScheme.surfaceContainerLow
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .clickable(onClick = onClick)
                .padding(horizontal = 12.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Icon(
                imageVector = icon,
                contentDescription = null,
                modifier = Modifier.size(18.dp),
                tint = MaterialTheme.colorScheme.onSurfaceVariant
            )
            Spacer(modifier = Modifier.width(12.dp))
            Column(modifier = Modifier.weight(1f)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        text = result.conversationTitle,
                        modifier = Modifier.weight(1f),
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurface,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                    val timeLabel = remember(result.timestamp) { formatRelativeTime(result.timestamp) }
                    if (timeLabel.isNotBlank()) {
                        Spacer(modifier = Modifier.width(8.dp))
                        Text(
                            text = timeLabel,
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                }

                Spacer(modifier = Modifier.height(4.dp))

                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        text = providerLine,
                        modifier = Modifier.weight(1f),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                    if (badge != null) {
                        Spacer(modifier = Modifier.width(8.dp))
                        AssistChip(
                            onClick = {},
                            enabled = false,
                            label = { Text(badge) }
                        )
                    }
                }

                Spacer(modifier = Modifier.height(4.dp))

                Text(
                    text = result.snippet,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis
                )
            }
        }
    }
}

private fun buildProviderModelLine(entry: ConversationListEntry): String {
    val dualModelTimestamp = entry.lastDualModelTimestamp ?: 0L
    val chatModelTimestamp = entry.lastChatModelTimestamp ?: 0L
    val dualLine = formatDualProviderLine(entry)
    return if (dualModelTimestamp > 0L && dualModelTimestamp >= chatModelTimestamp && dualLine.isNotBlank()) {
        dualLine
    } else {
        formatProviderModel(entry.apiProvider, entry.model).ifBlank { "—" }
    }
}

private fun formatDualProviderLine(entry: ConversationListEntry): String {
    val a = formatProviderModel(entry.lastDualModelAProvider, entry.lastDualModelAName)
    val b = formatProviderModel(entry.lastDualModelBProvider, entry.lastDualModelBName)
    val parts = buildList {
        if (a.isNotBlank()) add("A: $a")
        if (b.isNotBlank()) add("B: $b")
    }
    return parts.joinToString(" / ")
}

private fun formatProviderModel(provider: String?, model: String?): String {
    val providerLabel = providerDisplayName(provider)
    val modelLabel = model?.trim().orEmpty()
    return listOf(providerLabel, modelLabel).filter { it.isNotBlank() }.joinToString(" / ")
}

private fun providerDisplayName(provider: String?): String {
    return when (provider?.uppercase()) {
        "GEMINI" -> "Google Gemini"
        "GEMINI_AUTH" -> "Gemini Auth (CLI)"
        "OPENROUTER" -> "OpenRouter"
        "MINIMAX" -> "MiniMax"
        "OPENAI" -> "OpenAI"
        "CODEX_AUTH" -> "Codex Auth"
        "OPENAI_COMPAT" -> "OpenAI (Custom)"
        "ZAI" -> "Z.ai"
        else -> provider?.uppercase().orEmpty()
    }
}

private fun formatRelativeTime(timestamp: Long, now: Long = System.currentTimeMillis()): String {
    if (timestamp <= 0L) return ""
    val diff = now - timestamp
    if (diff < 60_000L) return "今"
    val minutes = diff / 60_000L
    if (minutes < 60) return "${minutes}m"
    val hours = minutes / 60
    if (hours < 24) return "${hours}h"

    val calNow = Calendar.getInstance()
    val calThen = Calendar.getInstance().apply { timeInMillis = timestamp }
    val dayIndexNow = calNow.get(Calendar.YEAR) * 400 + calNow.get(Calendar.DAY_OF_YEAR)
    val dayIndexThen = calThen.get(Calendar.YEAR) * 400 + calThen.get(Calendar.DAY_OF_YEAR)
    val dayDiff = dayIndexNow - dayIndexThen
    if (dayDiff == 1) return "昨日"

    return if (calNow.get(Calendar.YEAR) == calThen.get(Calendar.YEAR)) {
        String.format(Locale.getDefault(), "%d/%d", calThen.get(Calendar.MONTH) + 1, calThen.get(Calendar.DAY_OF_MONTH))
    } else {
        String.format(
            Locale.getDefault(),
            "%d/%d/%d",
            calThen.get(Calendar.YEAR),
            calThen.get(Calendar.MONTH) + 1,
            calThen.get(Calendar.DAY_OF_MONTH)
        )
    }
}

@Preview(showBackground = true)
@Composable
private fun ConversationListScreenPreview() {
    YamabikoPreview {
        val now = System.currentTimeMillis()
        val entries = listOf(
            ConversationListEntry(
                conversationId = 1L,
                title = "UI確認方法提案",
                timestamp = now - 2 * 60_000L,
                apiProvider = "GEMINI",
                model = "gemini-3-flash-preview",
                lastChatTimestamp = now - 2 * 60_000L,
                lastChatSnippet = "こんにちは！今日は何をお手伝いしましょうか？",
                lastDualTimestamp = null,
                lastDualSnippet = null,
                lastChatModelTimestamp = now - 2 * 60_000L,
                lastDualModelTimestamp = null,
                lastDualModelAProvider = null,
                lastDualModelAName = null,
                lastDualModelBProvider = null,
                lastDualModelBName = null
            ),
            ConversationListEntry(
                conversationId = 2L,
                title = "UI実装計画と翻訳",
                timestamp = now - 3 * 60 * 60_000L,
                apiProvider = "OPENROUTER",
                model = "deepseek/deepseek-chat",
                lastChatTimestamp = now - 3 * 60 * 60_000L,
                lastChatSnippet = "まだメッセージがありません",
                lastDualTimestamp = null,
                lastDualSnippet = null,
                lastChatModelTimestamp = now - 3 * 60 * 60_000L,
                lastDualModelTimestamp = null,
                lastDualModelAProvider = null,
                lastDualModelAName = null,
                lastDualModelBProvider = null,
                lastDualModelBName = null
            )
        )

        ConversationListContent(
            conversationEntries = entries,
            searchQuery = "",
            onSearchQueryChange = {},
            searchResults = emptyList(),
            entryMap = entries.associateBy { it.conversationId },
            selectedConversationId = 1L,
            isSettingsSelected = false,
            onNewConversationClick = {},
            onSearchResultClick = {},
            onConversationClick = {},
            onDeleteConversationClick = {},
            onSettingsClick = {},
            onClose = {}
        )
    }
}

@Preview(showBackground = true)
@Composable
private fun ConversationListSearchPreview() {
    YamabikoPreview {
        val now = System.currentTimeMillis()
        val entries = listOf(
            ConversationListEntry(
                conversationId = 1L,
                title = "Gmailアドレスの解析",
                timestamp = now - 25 * 60_000L,
                apiProvider = "OPENAI_COMPAT",
                model = "*[A]-[A]*",
                lastChatTimestamp = now - 25 * 60_000L,
                lastChatSnippet = "はち",
                lastDualTimestamp = null,
                lastDualSnippet = null,
                lastChatModelTimestamp = now - 25 * 60_000L,
                lastDualModelTimestamp = null,
                lastDualModelAProvider = null,
                lastDualModelAName = null,
                lastDualModelBProvider = null,
                lastDualModelBName = null
            )
        )
        val results = listOf(
            ConversationSearchResult(
                conversationId = 1L,
                conversationTitle = entries.first().title,
                source = "CHAT",
                messageId = 42L,
                timestamp = now - 25 * 60_000L,
                role = "user",
                matchedField = "USER",
                snippet = "…はち…"
            )
        )

        ConversationListContent(
            conversationEntries = entries,
            searchQuery = "はち",
            onSearchQueryChange = {},
            searchResults = results,
            entryMap = entries.associateBy { it.conversationId },
            selectedConversationId = null,
            isSettingsSelected = false,
            onNewConversationClick = {},
            onSearchResultClick = {},
            onConversationClick = {},
            onDeleteConversationClick = {},
            onSettingsClick = {},
            onClose = {}
        )
    }
}

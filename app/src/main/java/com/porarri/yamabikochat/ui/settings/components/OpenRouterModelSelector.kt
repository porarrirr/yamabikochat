package com.porarri.yamabikochat.ui.settings.components

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.StarBorder
import androidx.compose.material3.BottomSheetDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.porarri.yamabikochat.data.remote.SimpleModel
import com.porarri.yamabikochat.data.remote.matchesSearchQuery
import com.porarri.yamabikochat.ui.components.YamabikoOption
import com.porarri.yamabikochat.ui.components.YamabikoOptionBottomSheet
import com.porarri.yamabikochat.ui.components.YamabikoSelectRow
import com.porarri.yamabikochat.ui.components.YamabikoTextField

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun OpenRouterModelSelector(
    selectedModel: String,
    onModelSelected: (String) -> Unit,
    models: List<SimpleModel>,
    isLoading: Boolean,
    error: String?,
    onRefresh: () -> Unit,
    selectedProvider: String?,
    onProviderSelected: (String?) -> Unit,
    pinnedModelIds: List<String>,
    recentModelIds: List<String>,
    onTogglePinned: (String) -> Unit,
    onRecentUsed: (String) -> Unit
) {
    var showModelSheet by remember { mutableStateOf(false) }
    var showProviderSheet by remember { mutableStateOf(false) }
    var searchQuery by remember { mutableStateOf("") }
    val focusRequester = remember { FocusRequester() }
    val keyboardController = LocalSoftwareKeyboardController.current

    val availableProviders = remember(models) {
        models.mapNotNull { it.provider }.distinct().sorted()
    }

    val filteredModels = remember(searchQuery, selectedProvider, models) {      
        models.filter { model ->
            val matchesQuery = model.matchesSearchQuery(searchQuery)
            val matchesProvider = selectedProvider?.let { provider ->
                model.provider.equals(provider, ignoreCase = true)
            } ?: true
            matchesQuery && matchesProvider
        }
    }

    val pinnedLookup = remember(pinnedModelIds) {
        pinnedModelIds.map { it.lowercase() }.toSet()
    }
    val recentLookup = remember(recentModelIds) {
        recentModelIds.map { it.lowercase() }.toSet()
    }
    val filteredModelsById = remember(filteredModels) {
        filteredModels.associateBy { it.id.lowercase() }
    }
    val pinnedModels = remember(filteredModelsById, pinnedModelIds) {
        pinnedModelIds.mapNotNull { id -> filteredModelsById[id.lowercase()] }
    }
    val recentModels = remember(filteredModelsById, recentModelIds, pinnedLookup) {
        recentModelIds
            .filterNot { id -> pinnedLookup.contains(id.lowercase()) }
            .mapNotNull { id -> filteredModelsById[id.lowercase()] }
    }
    val remainingModels = remember(filteredModels, pinnedLookup, recentLookup) {
        filteredModels.filter { model ->
            val key = model.id.lowercase()
            !pinnedLookup.contains(key) && !recentLookup.contains(key)
        }
    }

    val selectedModelInfo = remember(selectedModel, models) {
        models.find { it.id == selectedModel }
    }

    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        val providerCounts = remember(models) {
            models.mapNotNull { it.provider }
                .groupingBy { it }
                .eachCount()
        }

        if (availableProviders.isNotEmpty()) {
            YamabikoSelectRow(
                title = "プロバイダー",
                value = selectedProvider ?: "すべて",
                onClick = { showProviderSheet = true }
            )
            if (showProviderSheet) {
                val providerOptions = buildList {
                    add(YamabikoOption(key = "__ALL__", title = "すべて"))
                    availableProviders.forEach { provider ->
                        val count = providerCounts[provider] ?: 0
                        add(YamabikoOption(key = provider, title = provider, subtitle = "${count}個"))
                    }
                }
                YamabikoOptionBottomSheet(
                    title = "プロバイダー",
                    options = providerOptions,
                    selectedKey = selectedProvider ?: "__ALL__",
                    onOptionSelected = { option ->
                        if (option.key == "__ALL__") onProviderSelected(null) else onProviderSelected(option.key)
                    },
                    onDismissRequest = { showProviderSheet = false }
                )
            }
        }

        val modelTitle = selectedModelInfo?.name ?: selectedModel
        val modelSubtitle: String? = when {
            isLoading -> "読み込み中..."
            error != null -> "エラー: $error"
            selectedModelInfo != null -> {
                val priceText = if (selectedModelInfo.isFree) {
                    "無料"
                } else {
                    "出力 $" + String.format(java.util.Locale.US, "%.2f", selectedModelInfo.completionPricePerMillion) + "/1M tokens"
                }
                buildString {
                    append("${selectedModelInfo.provider} • $priceText")
                    if (selectedModelInfo.topProvider != null) append(" • 推奨")
                }
            }
            else -> null
        }
        YamabikoSelectRow(
            title = "OpenRouter Model",
            value = modelTitle,
            description = modelSubtitle,
            onClick = { showModelSheet = true }
        )
        if (error != null) {
            TextButton(onClick = onRefresh, modifier = Modifier.align(Alignment.End)) {
                Text("更新")
            }
        }

        if (showModelSheet) {
            val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
            ModalBottomSheet(
                onDismissRequest = { showModelSheet = false },
                sheetState = sheetState,
                dragHandle = { BottomSheetDefaults.DragHandle() }
            ) {
                Column(modifier = Modifier.fillMaxWidth()) {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 16.dp, vertical = 4.dp),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text("OpenRouter Model", style = MaterialTheme.typography.titleMedium)
                        IconButton(onClick = onRefresh) {
                            Icon(Icons.Filled.Refresh, contentDescription = "Refresh")
                        }
                    }

                    YamabikoTextField(
                        value = searchQuery,
                        onValueChange = { searchQuery = it },
                        label = { Text("検索") },
                        placeholder = { Text("モデル名で検索...") },
                        leadingIcon = { Icon(Icons.Filled.Search, null) },
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 16.dp, vertical = 8.dp)
                            .focusRequester(focusRequester),
                        singleLine = true
                    )

                    HorizontalDivider()

                    LazyColumn(
                        modifier = Modifier
                            .fillMaxWidth()
                            .heightIn(max = 520.dp)
                    ) {
                        if (pinnedModels.isNotEmpty()) {
                            item { SectionHeader(text = "ピン留め", color = MaterialTheme.colorScheme.primary) }
                            items(pinnedModels, key = { it.id }) { model ->
                                ModelSheetItem(
                                    model = model,
                                    isSelected = model.id == selectedModel,
                                    isPinned = true,
                                    onTogglePinned = { onTogglePinned(model.id) },
                                    onClick = {
                                        onRecentUsed(model.id)
                                        onModelSelected(model.id)
                                        showModelSheet = false
                                    }
                                )
                            }
                            if (recentModels.isNotEmpty() || remainingModels.isNotEmpty()) {
                                item { HorizontalDivider() }
                            }
                        }

                        if (recentModels.isNotEmpty()) {
                            item { SectionHeader(text = "最近使った", color = MaterialTheme.colorScheme.secondary) }
                            items(recentModels, key = { it.id }) { model ->
                                ModelSheetItem(
                                    model = model,
                                    isSelected = model.id == selectedModel,
                                    isPinned = pinnedLookup.contains(model.id.lowercase()),
                                    onTogglePinned = { onTogglePinned(model.id) },
                                    onClick = {
                                        onRecentUsed(model.id)
                                        onModelSelected(model.id)
                                        showModelSheet = false
                                    }
                                )
                            }
                            if (remainingModels.isNotEmpty()) {
                                item { HorizontalDivider() }
                            }
                        }

                        val freeModels = remainingModels.filter { it.isFree }
                        if (freeModels.isNotEmpty()) {
                            item { SectionHeader(text = "無料モデル", color = MaterialTheme.colorScheme.primary) }
                            items(freeModels, key = { it.id }) { model ->
                                ModelSheetItem(
                                    model = model,
                                    isSelected = model.id == selectedModel,
                                    isPinned = pinnedLookup.contains(model.id.lowercase()),
                                    onTogglePinned = { onTogglePinned(model.id) },
                                    onClick = {
                                        onRecentUsed(model.id)
                                        onModelSelected(model.id)
                                        showModelSheet = false
                                    }
                                )
                            }
                            if (remainingModels.any { !it.isFree }) {
                                item { HorizontalDivider() }
                            }
                        }

                        val paidModels = remainingModels.filter { !it.isFree }
                        if (paidModels.isNotEmpty()) {
                            if (freeModels.isNotEmpty()) {
                                item { SectionHeader(text = "有料モデル", color = MaterialTheme.colorScheme.secondary) }
                            }
                            items(paidModels, key = { it.id }) { model ->
                                ModelSheetItem(
                                    model = model,
                                    isSelected = model.id == selectedModel,
                                    isPinned = pinnedLookup.contains(model.id.lowercase()),
                                    onTogglePinned = { onTogglePinned(model.id) },
                                    onClick = {
                                        onRecentUsed(model.id)
                                        onModelSelected(model.id)
                                        showModelSheet = false
                                    }
                                )
                            }
                        }

                        if (filteredModels.isEmpty() && models.isNotEmpty()) {
                            item {
                                Text(
                                    "検索結果が見つかりません",
                                    modifier = Modifier.padding(16.dp),
                                    style = MaterialTheme.typography.bodyMedium,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant
                                )
                            }
                        }

                        item { Spacer(modifier = Modifier.heightIn(min = 24.dp)) }
                    }
                }
            }
        }
    }

    LaunchedEffect(showModelSheet) {
        if (showModelSheet) {
            focusRequester.requestFocus()
            keyboardController?.show()
        }
    }
}

@Composable
private fun SectionHeader(
    text: String,
    color: androidx.compose.ui.graphics.Color,
    modifier: Modifier = Modifier
) {
    Text(
        text = text,
        style = MaterialTheme.typography.titleSmall,
        fontWeight = FontWeight.SemiBold,
        modifier = modifier.padding(horizontal = 16.dp, vertical = 12.dp),
        color = color
    )
}

@Composable
private fun ModelSheetItem(
    model: SimpleModel,
    isSelected: Boolean,
    isPinned: Boolean,
    onTogglePinned: () -> Unit,
    onClick: () -> Unit
) {
    ListItem(
        headlineContent = {
            Text(
                text = model.name,
                style = MaterialTheme.typography.bodyMedium,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                color = if (isSelected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurface
            )
        },
        supportingContent = {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        text = model.provider,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    if (model.topProvider != null) {
                        Spacer(modifier = Modifier.width(4.dp))
                        Card(
                            colors = CardDefaults.cardColors(
                                containerColor = MaterialTheme.colorScheme.secondary.copy(alpha = 0.1f)
                            )
                        ) {
                            Text(
                                text = "推奨",
                                style = MaterialTheme.typography.labelSmall,
                                color = MaterialTheme.colorScheme.secondary,
                                modifier = Modifier.padding(horizontal = 4.dp, vertical = 1.dp)
                            )
                        }
                    }
                }
                if (model.isFree) {
                    Card(
                        colors = CardDefaults.cardColors(
                            containerColor = MaterialTheme.colorScheme.primary.copy(alpha = 0.1f)
                        )
                    ) {
                        Text(
                            text = "無料",
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.primary,
                            modifier = Modifier.padding(horizontal = 6.dp, vertical = 2.dp)
                        )
                    }
                } else {
                    Text(
                        text = "出力 $" + String.format(java.util.Locale.US, "%.2f", model.completionPricePerMillion) + "/1M",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.secondary
                    )
                }
            }
        },
        trailingContent = {
            IconButton(onClick = onTogglePinned) {
                Icon(
                    imageVector = if (isPinned) Icons.Filled.Star else Icons.Filled.StarBorder,
                    contentDescription = if (isPinned) "ピン解除" else "ピン留め",
                    tint = if (isPinned) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        },
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
    )
}

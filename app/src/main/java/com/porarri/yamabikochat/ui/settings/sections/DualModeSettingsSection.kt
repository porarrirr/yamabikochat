package com.porarri.yamabikochat.ui.settings.sections

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Compare
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import com.porarri.yamabikochat.ui.components.YamabikoOption
import com.porarri.yamabikochat.ui.components.YamabikoOptionBottomSheet
import com.porarri.yamabikochat.ui.components.YamabikoSelectRow
import com.porarri.yamabikochat.ui.components.YamabikoTextField
import androidx.compose.material3.Slider
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.material3.Icon
import androidx.compose.ui.graphics.Color
import com.porarri.yamabikochat.data.local.ModelPreset
import com.porarri.yamabikochat.data.modelsdev.CatalogProvider
import com.porarri.yamabikochat.data.modelsdev.ProviderReference
import com.porarri.yamabikochat.data.modelsdev.ModelsDevMergedProvider
import com.porarri.yamabikochat.data.remote.ProviderCatalog
import com.porarri.yamabikochat.data.remote.SimpleModel
import com.porarri.yamabikochat.ui.settings.components.OpenRouterModelSelector
import com.porarri.yamabikochat.ui.settings.sections.ToolingOverrideSection
import com.porarri.yamabikochat.ui.settings.sections.ThinkingOverrideSection

@OptIn(ExperimentalMaterial3Api::class)
@Suppress("LongParameterList")
fun LazyListScope.dualModeSettingsSection(
    isDualModeEnabled: Boolean,
    onDualModeEnabledChange: (Boolean) -> Unit,
    dualBlockedByFusion: Boolean = false,
    presetOptions: List<ModelPreset>,
    onPresetSelectedA: (ModelPreset) -> Unit,
    onPresetSelectedB: (ModelPreset) -> Unit,
    providerA: String,
    onProviderAChange: (String) -> Unit,
    modelA: String,
    onModelAChange: (String) -> Unit,
    selectedProviderA: String?,
    onSelectedProviderAChange: (String?) -> Unit,
    reasoningA: ReasoningOverrideUiState,
    toolsA: ToolingOverrideUiState,
    thinkingA: ThinkingOverrideUiState,
    providerB: String,
    onProviderBChange: (String) -> Unit,
    modelB: String,
    onModelBChange: (String) -> Unit,
    selectedProviderB: String?,
    onSelectedProviderBChange: (String?) -> Unit,
    reasoningB: ReasoningOverrideUiState,
    toolsB: ToolingOverrideUiState,
    thinkingB: ThinkingOverrideUiState,
    openRouterModels: List<SimpleModel>,
    openRouterModelsLoading: Boolean,
    openRouterModelsError: String?,
    onRefreshOpenRouterModels: () -> Unit,
    pinnedModelIds: List<String>,
    recentModelIds: List<String>,
    onTogglePinned: (String) -> Unit,
    onRecentUsed: (String) -> Unit,
    catalogProviders: List<CatalogProvider> = emptyList(),
    dualSplitLayout: String,
    onDualSplitLayoutChange: (String) -> Unit,
    dualSplitRatio: Float,
    onDualSplitRatioChange: (Float) -> Unit
) {
    item {
        Card(
            modifier = Modifier.fillMaxWidth(),
            colors = CardDefaults.cardColors(
                containerColor = MaterialTheme.colorScheme.surface
            ),
            border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.6f)),
            elevation = CardDefaults.cardElevation(defaultElevation = 1.dp)
        ) {
            Column(
                modifier = Modifier.padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp)
            ) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Icon(
                        Icons.Filled.Compare,
                        contentDescription = "Dual Mode",
                        modifier = Modifier.size(24.dp),
                        tint = MaterialTheme.colorScheme.primary
                    )
                    Spacer(modifier = Modifier.width(12.dp))
                    Column(modifier = Modifier.weight(1f)) {
                        Text(
                            "デュアルモード",
                            style = MaterialTheme.typography.titleMedium,
                            fontWeight = FontWeight.SemiBold,
                            color = MaterialTheme.colorScheme.onSurface
                        )
                        Text(
                            "2つのAIモデルに同時送信して比較",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                    Switch(
                        checked = isDualModeEnabled,
                        onCheckedChange = onDualModeEnabledChange,
                        enabled = isDualModeEnabled || !dualBlockedByFusion
                    )
                }
                if (dualBlockedByFusion && !isDualModeEnabled) {
                    Text(
                        "Fusion モードが有効なときはデュアルを使えません",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.error
                    )
                }

                if (isDualModeEnabled) {
                    HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.8f))

                    DualModelConfiguration(
                        title = "モデル A",
                        titleColor = MaterialTheme.colorScheme.primary,
                        presetOptions = presetOptions,
                        onPresetSelected = onPresetSelectedA,
                        provider = providerA,
                        onProviderChange = onProviderAChange,
                        model = modelA,
                        onModelChange = onModelAChange,
                        selectedProvider = selectedProviderA,
                        onSelectedProviderChange = onSelectedProviderAChange,
                        reasoning = reasoningA,
                        tools = toolsA,
                        thinking = thinkingA,
                        openRouterModels = openRouterModels,
                        openRouterModelsLoading = openRouterModelsLoading,      
                        openRouterModelsError = openRouterModelsError,
                        onRefreshOpenRouterModels = onRefreshOpenRouterModels,  
                        pinnedModelIds = pinnedModelIds,
                        recentModelIds = recentModelIds,
                        onTogglePinned = onTogglePinned,
                        onRecentUsed = onRecentUsed,
                        catalogProviders = catalogProviders,
                        placeholder = "例: gemini-2.5-flash"
                    )

                    DualModelConfiguration(
                        title = "モデル B",
                        titleColor = MaterialTheme.colorScheme.secondary,
                        presetOptions = presetOptions,
                        onPresetSelected = onPresetSelectedB,
                        provider = providerB,
                        onProviderChange = onProviderBChange,
                        model = modelB,
                        onModelChange = onModelBChange,
                        selectedProvider = selectedProviderB,
                        onSelectedProviderChange = onSelectedProviderBChange,
                        reasoning = reasoningB,
                        tools = toolsB,
                        thinking = thinkingB,
                        openRouterModels = openRouterModels,
                        openRouterModelsLoading = openRouterModelsLoading,      
                        openRouterModelsError = openRouterModelsError,
                        onRefreshOpenRouterModels = onRefreshOpenRouterModels,  
                        pinnedModelIds = pinnedModelIds,
                        recentModelIds = recentModelIds,
                        onTogglePinned = onTogglePinned,
                        onRecentUsed = onRecentUsed,
                        catalogProviders = catalogProviders,
                        placeholder = "例: deepseek/deepseek-chat"
                    )

                    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        var showLayoutSheet by remember { mutableStateOf(false) }
                        val layoutLabel = when (dualSplitLayout) {
                            "VERTICAL" -> "左右分割 (|)"
                            else -> "上下分割 (-)"
                        }
                        YamabikoSelectRow(
                            title = "レイアウト",
                            value = layoutLabel,
                            onClick = { showLayoutSheet = true }
                        )
                        if (showLayoutSheet) {
                            YamabikoOptionBottomSheet(
                                title = "レイアウト",
                                options = listOf(
                                    YamabikoOption(key = "VERTICAL", title = "左右分割 (|)"),
                                    YamabikoOption(key = "HORIZONTAL", title = "上下分割 (-)")
                                ),
                                selectedKey = dualSplitLayout,
                                onOptionSelected = { onDualSplitLayoutChange(it.key) },
                                onDismissRequest = { showLayoutSheet = false }
                            )
                        }

                        Text(
                            "分割比率: ${(dualSplitRatio * 100).toInt()}% : ${((1 - dualSplitRatio) * 100).toInt()}%",
                            style = MaterialTheme.typography.bodyLarge,
                            fontWeight = FontWeight.Medium,
                            color = MaterialTheme.colorScheme.onSurface
                        )
                        Slider(
                            value = dualSplitRatio,
                            onValueChange = onDualSplitRatioChange,
                            valueRange = 0.1f..0.9f,
                            modifier = Modifier.fillMaxWidth()
                        )
                    }
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Suppress("LongParameterList")
@Composable
private fun DualModelConfiguration(
    title: String,
    titleColor: Color,
    presetOptions: List<ModelPreset>,
    onPresetSelected: (ModelPreset) -> Unit,
    provider: String,
    onProviderChange: (String) -> Unit,
    model: String,
    onModelChange: (String) -> Unit,
    selectedProvider: String?,
    onSelectedProviderChange: (String?) -> Unit,
    reasoning: ReasoningOverrideUiState,
    tools: ToolingOverrideUiState,
    thinking: ThinkingOverrideUiState,
    openRouterModels: List<SimpleModel>,
    openRouterModelsLoading: Boolean,
    openRouterModelsError: String?,
    onRefreshOpenRouterModels: () -> Unit,
    pinnedModelIds: List<String>,
    recentModelIds: List<String>,
    onTogglePinned: (String) -> Unit,
    onRecentUsed: (String) -> Unit,
    catalogProviders: List<CatalogProvider>,
    placeholder: String
) {
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text(
            title,
            style = MaterialTheme.typography.titleSmall,
            fontWeight = FontWeight.SemiBold,
            color = titleColor
        )

        if (presetOptions.isNotEmpty()) {
            var showPresetSheet by remember { mutableStateOf(false) }
            var selectedPresetKey by remember { mutableStateOf<String?>(null) }
            var selectedPresetLabel by remember { mutableStateOf("") }
            YamabikoSelectRow(
                title = "プリセット",
                value = selectedPresetLabel.ifBlank { "プリセットを選択" },
                onClick = { showPresetSheet = true }
            )
            if (showPresetSheet) {
                YamabikoOptionBottomSheet(
                    title = "プリセット",
                    options = presetOptions.map { preset ->
                        YamabikoOption(
                            key = preset.id.toString(),
                            title = preset.name,
                            subtitle = "${ProviderCatalog.displayName(preset.apiProvider)} ・ ${preset.model}"
                        )
                    },
                    selectedKey = selectedPresetKey,
                    onOptionSelected = { option ->
                        val preset = presetOptions.firstOrNull { it.id.toString() == option.key }
                            ?: return@YamabikoOptionBottomSheet
                        selectedPresetKey = option.key
                        selectedPresetLabel = preset.name
                        onPresetSelected(preset)
                    },
                    onDismissRequest = { showPresetSheet = false }
                )
            }
        }

        var showProviderSheet by remember { mutableStateOf(false) }
        val dynamicProvider = ModelsDevMergedProvider.catalogIdFor(provider)
            ?.takeUnless { provider.equals("OPENROUTER", ignoreCase = true) }
            ?.let { id -> catalogProviders.firstOrNull { it.id == id } }
        val providerLabel = dynamicProvider?.name ?: ProviderCatalog.displayName(provider)
        YamabikoSelectRow(
            title = "プロバイダー",
            value = providerLabel,
            onClick = { showProviderSheet = true }
        )
        if (showProviderSheet) {
            YamabikoOptionBottomSheet(
                title = "プロバイダー",
                options = ProviderCatalog.dualAutoConversationOptions.map {
                    YamabikoOption(key = it.key, title = it.title)
                } + catalogProviders.filterNot { it.id == "openrouter" }.map {
                    YamabikoOption(key = it.reference.persistedId, title = it.name, subtitle = it.id)
                },
                selectedKey = provider,
                onOptionSelected = {
                    val changed = !provider.equals(it.key, ignoreCase = true)
                    onProviderChange(it.key)
                    if (changed) {
                        onModelChange(
                            if (ProviderReference(it.key).isModelsDev) ""
                            else ProviderCatalog.defaultModel(it.key)
                        )
                    }
                },
                onDismissRequest = { showProviderSheet = false }
            )
        }

        if (provider == "OPENROUTER") {
            OpenRouterModelSelector(
                selectedModel = model,
                onModelSelected = onModelChange,
                models = openRouterModels,
                isLoading = openRouterModelsLoading,
                error = openRouterModelsError,
                onRefresh = onRefreshOpenRouterModels,
                selectedProvider = selectedProvider,
                onProviderSelected = onSelectedProviderChange,
                pinnedModelIds = pinnedModelIds,
                recentModelIds = recentModelIds,
                onTogglePinned = onTogglePinned,
                onRecentUsed = onRecentUsed
            )

            Spacer(modifier = Modifier.height(12.dp))

            ReasoningOverrideSection(reasoning)
            ToolingOverrideSection(provider = provider, tooling = tools)
        } else if (ProviderCatalog.constrainedModelIds(provider) != null) {
            val modelIds = ProviderCatalog.constrainedModelIds(provider).orEmpty()
            var showModelSheet by remember { mutableStateOf(false) }
            YamabikoSelectRow(
                title = "モデル",
                value = model.ifBlank { ProviderCatalog.defaultModel(provider) },
                onClick = { showModelSheet = true }
            )
            if (showModelSheet) {
                YamabikoOptionBottomSheet(
                    title = ProviderCatalog.displayName(provider),
                    options = modelIds.map { YamabikoOption(key = it, title = it) },
                    selectedKey = model,
                    onOptionSelected = { onModelChange(it.key) },
                    onDismissRequest = { showModelSheet = false },
                    searchable = true
                )
            }
            ToolingOverrideSection(provider = provider, tooling = tools)
            ThinkingOverrideSection(provider = provider, model = model, thinking = thinking)
        } else if (dynamicProvider != null) {
            var showModelSheet by remember { mutableStateOf(false) }
            YamabikoSelectRow(
                title = "モデル",
                value = dynamicProvider.models.firstOrNull { it.id == model }?.name ?: model.ifBlank { "モデルを選択" },
                onClick = { showModelSheet = true }
            )
            if (showModelSheet) {
                YamabikoOptionBottomSheet(
                    title = dynamicProvider.name,
                    options = dynamicProvider.models.map { catalogModel ->
                        YamabikoOption(
                            key = catalogModel.id,
                            title = catalogModel.name,
                            subtitle = listOfNotNull(catalogModel.family, catalogModel.description).joinToString(" ・ ")
                        )
                    },
                    selectedKey = model,
                    onOptionSelected = { onModelChange(it.key) },
                    onDismissRequest = { showModelSheet = false },
                    searchable = true
                )
            }
            ToolingOverrideSection(provider = provider, tooling = tools)
            ThinkingOverrideSection(provider = provider, model = model, thinking = thinking)
        } else {
            YamabikoTextField(
                value = model,
                onValueChange = onModelChange,
                label = { Text("モデル名") },
                placeholder = { Text(placeholder) },
                modifier = Modifier.fillMaxWidth()
            )
            ToolingOverrideSection(provider = provider, tooling = tools)
            ThinkingOverrideSection(provider = provider, model = model, thinking = thinking)
        }
    }
}

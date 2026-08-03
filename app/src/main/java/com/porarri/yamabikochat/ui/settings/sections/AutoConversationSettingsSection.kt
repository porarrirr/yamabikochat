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
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
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
fun LazyListScope.autoConversationSettingsSection(
    isAutoConversationEnabled: Boolean,
    onAutoConversationEnabledChange: (Boolean) -> Unit,
    autoBlockedByFusion: Boolean = false,
    presetOptions: List<ModelPreset>,
    onPresetSelectedA: (ModelPreset) -> Unit,
    onPresetSelectedB: (ModelPreset) -> Unit,
    providerA: String,
    onProviderAChange: (String) -> Unit,
    modelA: String,
    onModelAChange: (String) -> Unit,
    selectedProviderA: String?,
    onSelectedProviderAChange: (String?) -> Unit,
    systemPromptA: String,
    onSystemPromptAChange: (String) -> Unit,
    reasoningA: ReasoningOverrideUiState,
    toolsA: ToolingOverrideUiState,
    thinkingA: ThinkingOverrideUiState,
    providerB: String,
    onProviderBChange: (String) -> Unit,
    modelB: String,
    onModelBChange: (String) -> Unit,
    selectedProviderB: String?,
    onSelectedProviderBChange: (String?) -> Unit,
    systemPromptB: String,
    onSystemPromptBChange: (String) -> Unit,
    reasoningB: ReasoningOverrideUiState,
    toolsB: ToolingOverrideUiState,
    thinkingB: ThinkingOverrideUiState,
    maxTurns: Int,
    onMaxTurnsChange: (Int) -> Unit,
    openRouterModels: List<SimpleModel>,
    openRouterModelsLoading: Boolean,
    openRouterModelsError: String?,
    onRefreshOpenRouterModels: () -> Unit,
    pinnedModelIds: List<String>,
    recentModelIds: List<String>,
    onTogglePinned: (String) -> Unit,
    onRecentUsed: (String) -> Unit,
    catalogProviders: List<CatalogProvider> = emptyList()
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
                        Icons.Filled.AutoAwesome,
                        contentDescription = "Auto Conversation",
                        modifier = Modifier.size(24.dp),
                        tint = if (isAutoConversationEnabled) {
                            MaterialTheme.colorScheme.secondary
                        } else {
                            MaterialTheme.colorScheme.onSurfaceVariant
                        }
                    )
                    Spacer(modifier = Modifier.width(12.dp))
                    Column(modifier = Modifier.weight(1f)) {
                        Text(
                            "LLM自動会話",
                            style = MaterialTheme.typography.titleMedium,
                            fontWeight = FontWeight.SemiBold,
                            color = MaterialTheme.colorScheme.onSurface
                        )
                        Text(
                            if (isAutoConversationEnabled) "2つのAIモデルが自動で会話" else "AIモデル同士の自動会話機能を有効化",
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                    Switch(
                        checked = isAutoConversationEnabled,
                        onCheckedChange = onAutoConversationEnabledChange,
                        enabled = isAutoConversationEnabled || !autoBlockedByFusion
                    )
                }
                if (autoBlockedByFusion && !isAutoConversationEnabled) {
                    Text(
                        "Fusion モードが有効なときは自動会話を使えません",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.error
                    )
                }

                if (isAutoConversationEnabled) {
                    HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.8f))

                    AutoConversationModelConfiguration(
                        title = "AI モデル A（会話開始側）",
                        presetOptions = presetOptions,
                        onPresetSelected = onPresetSelectedA,
                        provider = providerA,
                        onProviderChange = onProviderAChange,
                        model = modelA,
                        onModelChange = onModelAChange,
                        selectedProvider = selectedProviderA,
                        onSelectedProviderChange = onSelectedProviderAChange,
                        systemPrompt = systemPromptA,
                        onSystemPromptChange = onSystemPromptAChange,
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
                        placeholder = "例: gemini-2.5-flash",
                        promptPlaceholder = "モデルAの役割や話し方を指定"       
                    )

                    AutoConversationModelConfiguration(
                        title = "AI モデル B（応答側）",
                        presetOptions = presetOptions,
                        onPresetSelected = onPresetSelectedB,
                        provider = providerB,
                        onProviderChange = onProviderBChange,
                        model = modelB,
                        onModelChange = onModelBChange,
                        selectedProvider = selectedProviderB,
                        onSelectedProviderChange = onSelectedProviderBChange,
                        systemPrompt = systemPromptB,
                        onSystemPromptChange = onSystemPromptBChange,
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
                        placeholder = "例: deepseek/deepseek-chat",
                        promptPlaceholder = "モデルBの役割や話し方を指定"       
                    )

                    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        Text(
                            "会話設定",
                            style = MaterialTheme.typography.titleSmall,
                            fontWeight = FontWeight.SemiBold,
                            color = MaterialTheme.colorScheme.onSurface
                        )

                        val isUnlimited = maxTurns <= 0
                        Text(
                            if (isUnlimited) "最大ターン数: 無制限" else "最大ターン数: ${maxTurns}回",
                            style = MaterialTheme.typography.bodyLarge,
                            fontWeight = FontWeight.Medium,
                            color = MaterialTheme.colorScheme.onSurface
                        )

                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text(
                                text = "無制限",
                                style = MaterialTheme.typography.labelLarge,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                            Spacer(modifier = Modifier.width(8.dp))
                            Switch(
                                checked = isUnlimited,
                                onCheckedChange = { checked ->
                                    if (checked) onMaxTurnsChange(0) else onMaxTurnsChange(20)
                                }
                            )
                        }

                        Slider(
                            value = if (isUnlimited) 200f else maxTurns.toFloat(),
                            onValueChange = { onMaxTurnsChange(it.toInt()) },
                            valueRange = 5f..200f,
                            steps = 195,
                            enabled = !isUnlimited,
                            modifier = Modifier.fillMaxWidth()
                        )

                        Card(
                            modifier = Modifier.fillMaxWidth(),
                            colors = CardDefaults.cardColors(
                                containerColor = MaterialTheme.colorScheme.surfaceContainerHigh
                            ),
                            border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.6f)),
                            elevation = CardDefaults.cardElevation(defaultElevation = 0.dp)
                        ) {
                            Column(
                                modifier = Modifier.padding(12.dp),
                                verticalArrangement = Arrangement.spacedBy(4.dp)
                            ) {
                                Row(verticalAlignment = Alignment.CenterVertically) {
                                    Icon(
                                        Icons.Filled.AutoAwesome,
                                        contentDescription = "Info",
                                        modifier = Modifier.size(16.dp),
                                        tint = MaterialTheme.colorScheme.tertiary
                                    )
                                    Spacer(modifier = Modifier.width(8.dp))
                                    Text(
                                        "使用方法",
                                        style = MaterialTheme.typography.labelLarge,
                                        fontWeight = FontWeight.SemiBold,
                                        color = MaterialTheme.colorScheme.onSurface
                                    )
                                }
                                val endRule = if (isUnlimited) "[END]シグナルまたは手動停止" else "[END]シグナルまたは最大ターン数"
                                Text(
                                    "1. 新しい会話で「こんにちは。AIについて話しましょう」と入力\n" +
                                            "2. 自動会話が開始され、2つのAIが交互に会話します\n" +
                                            "3. 会話は${endRule}で終了します\n" +
                                            "4. 実行中は進行状況が表示され、停止ボタンで中断可能\n\n" +
                                            "トリガーワード例：\n• 「こんにちは」「〜について話しましょう」\n• 「〜について議論しましょう」「会話しましょう」",
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Suppress("LongParameterList")
@Composable
private fun AutoConversationModelConfiguration(
    title: String,
    presetOptions: List<ModelPreset>,
    onPresetSelected: (ModelPreset) -> Unit,
    provider: String,
    onProviderChange: (String) -> Unit,
    model: String,
    onModelChange: (String) -> Unit,
    selectedProvider: String?,
    onSelectedProviderChange: (String?) -> Unit,
    systemPrompt: String,
    onSystemPromptChange: (String) -> Unit,
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
    placeholder: String,
    promptPlaceholder: String
) {
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text(
            title,
            style = MaterialTheme.typography.titleSmall,
            fontWeight = FontWeight.SemiBold,
            color = MaterialTheme.colorScheme.onSurface
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
                    if (changed && ProviderReference(it.key).isModelsDev) onModelChange("")
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

        YamabikoTextField(
            value = systemPrompt,
            onValueChange = onSystemPromptChange,
            label = { Text("システムプロンプト") },
            placeholder = { Text(promptPlaceholder) },
            modifier = Modifier.fillMaxWidth(),
            minLines = 2,
            maxLines = 4
        )
    }
}

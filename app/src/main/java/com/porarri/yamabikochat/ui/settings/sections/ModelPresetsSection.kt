package com.porarri.yamabikochat.ui.settings.sections

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Build
import androidx.compose.material.icons.filled.Cloud
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.EditNote
import androidx.compose.material.icons.filled.Psychology
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.AssistChip
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import com.porarri.yamabikochat.ui.components.YamabikoOption
import com.porarri.yamabikochat.ui.components.YamabikoOptionBottomSheet
import com.porarri.yamabikochat.ui.components.YamabikoSelectRow
import com.porarri.yamabikochat.ui.components.YamabikoTextField
import androidx.compose.material3.Slider
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.ui.text.font.FontWeight
import com.porarri.yamabikochat.data.local.ModelPreset
import com.porarri.yamabikochat.data.local.SystemPromptPreset
import com.porarri.yamabikochat.data.remote.OpenAiCompatPreset
import com.porarri.yamabikochat.data.remote.SimpleModel
import com.porarri.yamabikochat.ui.settings.components.SettingsToggleRow    
import com.porarri.yamabikochat.ui.settings.components.OpenRouterModelSelector
import com.porarri.yamabikochat.utils.CodexModelPresets
import com.porarri.yamabikochat.utils.ModelUtils

data class ModelPresetDialogState(
    val isVisible: Boolean,
    val isEditing: Boolean,
    val name: String,
    val onNameChange: (String) -> Unit,
    val model: String,
    val onModelChange: (String) -> Unit,
    val systemPrompt: String,
    val onSystemPromptChange: (String) -> Unit,
    val systemPromptPresetName: String?,
    val onSystemPromptPresetSelected: (SystemPromptPreset?) -> Unit,
    val thinkingEnabled: Boolean,
    val onThinkingEnabledChange: (Boolean) -> Unit,
    val thinkingBudget: Float,
    val onThinkingBudgetChange: (Float) -> Unit,
    val thinkingLevel: String,
    val onThinkingLevelChange: (String) -> Unit,
    val googleSearchEnabled: Boolean,
    val onGoogleSearchEnabledChange: (Boolean) -> Unit,
    val codeExecutionEnabled: Boolean,
    val onCodeExecutionEnabledChange: (Boolean) -> Unit,
    val urlContextEnabled: Boolean,
    val onUrlContextEnabledChange: (Boolean) -> Unit,
    val googleMapsEnabled: Boolean,
    val onGoogleMapsEnabledChange: (Boolean) -> Unit,
    val computerUseEnabled: Boolean,
    val onComputerUseEnabledChange: (Boolean) -> Unit,
    val responseMimeType: String,
    val onResponseMimeTypeChange: (String) -> Unit,
    val responseJsonSchema: String,
    val onResponseJsonSchemaChange: (String) -> Unit,
    val functionDeclarations: String,
    val onFunctionDeclarationsChange: (String) -> Unit,
    val apiProvider: String,
    val onApiProviderChange: (String) -> Unit,
    val apiKey: String,
    val onApiKeyChange: (String) -> Unit,
    val reasoningMode: String,
    val onReasoningModeChange: (String) -> Unit,
    val reasoningEffort: String,
    val onReasoningEffortChange: (String) -> Unit,
    val reasoningExclude: Boolean,
    val onReasoningExcludeChange: (Boolean) -> Unit,
    val codexReasoningSummary: String,
    val onCodexReasoningSummaryChange: (String) -> Unit,
    val codexVerbosity: String,
    val onCodexVerbosityChange: (String) -> Unit,
    val codexWebSearchEnabled: Boolean,
    val onCodexWebSearchEnabledChange: (Boolean) -> Unit,
    val codexWebSearchContextSize: String,
    val onCodexWebSearchContextSizeChange: (String) -> Unit,
    val codexPromptCacheEnabled: Boolean,
    val onCodexPromptCacheEnabledChange: (Boolean) -> Unit,
    val codexPromptCacheMinLength: Int,
    val onCodexPromptCacheMinLengthChange: (Int) -> Unit,
    val codexPromptCacheType: String,
    val onCodexPromptCacheTypeChange: (String) -> Unit,
    val codexShowReasoningSummary: Boolean,
    val onCodexShowReasoningSummaryChange: (Boolean) -> Unit,
    val codexSupportsReasoningSummaries: Boolean,
    val onCodexSupportsReasoningSummariesChange: (Boolean) -> Unit,
    val openAiCompatPresetName: String?,
    val onOpenAiCompatPresetNameChange: (String?) -> Unit,
    val selectedProvider: String?,
    val onSelectedProviderChange: (String?) -> Unit
)

@Suppress("LongParameterList")
@Composable
fun ModelPresetDialog(
    state: ModelPresetDialogState,
    onDismiss: () -> Unit,
    onConfirm: () -> Unit,
    systemPromptPresets: List<SystemPromptPreset>,
    openAiCompatPresets: List<OpenAiCompatPreset>,
    openRouterModels: List<SimpleModel>,
    openRouterModelsLoading: Boolean,
    openRouterModelsError: String?,
    onRefreshOpenRouterModels: () -> Unit,
    pinnedModelIds: List<String>,
    recentModelIds: List<String>,
    onTogglePinned: (String) -> Unit,
    onRecentUsed: (String) -> Unit
) {
    if (!state.isVisible) return

    AlertDialog(
        onDismissRequest = onDismiss,
        title = {
            Text(
                text = if (state.isEditing) "Edit Model Preset" else "Create Model Preset",
                style = MaterialTheme.typography.headlineSmall
            )
        },
        text = {
            val scrollState = rememberScrollState()
            val maxHeight = (LocalConfiguration.current.screenHeightDp * 0.7f).dp
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .heightIn(max = maxHeight)
                    .verticalScroll(scrollState),
                verticalArrangement = Arrangement.spacedBy(16.dp)
            ) {
                YamabikoTextField(
                    value = state.name,
                    onValueChange = state.onNameChange,
                    label = { Text("Preset Name") },
                    modifier = Modifier.fillMaxWidth(),
                    singleLine = true
                )
                if (state.apiProvider == "OPENROUTER") {
                    OpenRouterModelSelector(
                        selectedModel = state.model,
                        onModelSelected = state.onModelChange,
                        models = openRouterModels,
                        isLoading = openRouterModelsLoading,
                        error = openRouterModelsError,
                        onRefresh = onRefreshOpenRouterModels,
                        selectedProvider = state.selectedProvider,
                        onProviderSelected = state.onSelectedProviderChange,
                        pinnedModelIds = pinnedModelIds,
                        recentModelIds = recentModelIds,
                        onTogglePinned = onTogglePinned,
                        onRecentUsed = onRecentUsed
                    )
                } else {
                    YamabikoTextField(
                        value = state.model,
                        onValueChange = state.onModelChange,
                        label = { Text("Model") },
                        placeholder = { Text("gemini-2.5-flash") },
                        modifier = Modifier.fillMaxWidth(),
                        singleLine = true
                    )
                }
                val usingPresetPrompt = !state.systemPromptPresetName.isNullOrBlank()
                var showSystemPromptSheet by remember { mutableStateOf(false) }
                YamabikoSelectRow(
                    title = "System Prompt Preset",
                    value = state.systemPromptPresetName ?: "Custom",
                    onClick = { showSystemPromptSheet = true }
                )
                if (showSystemPromptSheet) {
                    val options = buildList {
                        add(
                            YamabikoOption(
                                key = "",
                                title = "Custom",
                                subtitle = "Free text"
                            )
                        )
                        systemPromptPresets.forEach { preset ->
                            add(
                                YamabikoOption(
                                    key = preset.name,
                                    title = preset.name,
                                    subtitle = preset.prompt.lineSequence().firstOrNull().orEmpty()
                                )
                            )
                        }
                    }
                    YamabikoOptionBottomSheet(
                        title = "System Prompt Preset",
                        options = options,
                        selectedKey = state.systemPromptPresetName ?: "",
                        onOptionSelected = { option ->
                            val selected = systemPromptPresets.firstOrNull { it.name == option.key }
                            state.onSystemPromptPresetSelected(selected)
                        },
                        onDismissRequest = { showSystemPromptSheet = false }
                    )
                }
                YamabikoTextField(
                    value = state.systemPrompt,
                    onValueChange = state.onSystemPromptChange,
                    label = { Text("System Prompt (Optional)") },
                    modifier = Modifier.fillMaxWidth(),
                    minLines = 3,
                    maxLines = 5,
                    readOnly = usingPresetPrompt,
                    supportingText = if (usingPresetPrompt) {
                        { Text("Preset selected. Switch to Custom to edit.") }
                    } else {
                        null
                    }
                )

                PresetProviderCard(state = state, openAiCompatPresets = openAiCompatPresets)
                PresetThinkingCard(state = state)
                PresetToolsCard(state = state)
                PresetGeminiAdvancedCard(state = state)
                PresetCodexAdvancedCard(state = state)
            }
        },
        confirmButton = {
            FilledTonalButton(
                onClick = onConfirm,
                enabled = state.name.isNotBlank() && state.model.isNotBlank()
            ) {
                Text(if (state.isEditing) "Update Preset" else "Create Preset")
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) {
                Text("Cancel")
            }
        }
    )
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun PresetProviderCard(
    state: ModelPresetDialogState,
    openAiCompatPresets: List<OpenAiCompatPreset>
) {
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
            Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
                Icon(
                    Icons.Default.Cloud,
                    contentDescription = "API Provider",
                    modifier = Modifier.size(20.dp),
                    tint = MaterialTheme.colorScheme.primary
                )
                Spacer(modifier = Modifier.width(8.dp))
                Text(
                    "API Provider",
                    modifier = Modifier.weight(1f),
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold
                )
            }

            var showProviderSheet by remember { mutableStateOf(false) }
            val providerLabel = when (state.apiProvider) {
                "GEMINI" -> "Google Gemini"
                "GEMINI_AUTH" -> "Gemini Auth (CLI)"
                "OPENROUTER" -> "OpenRouter"
                "MINIMAX" -> "MiniMax"
                "OPENAI" -> "OpenAI"
                "CODEX_AUTH" -> "Codex Auth"
                "OPENAI_COMPAT" -> "OpenAI (Custom)"
                "ZAI" -> "Z.ai"
                else -> "Google Gemini"
            }
            YamabikoSelectRow(
                title = "Provider",
                value = providerLabel,
                onClick = { showProviderSheet = true }
            )
            if (showProviderSheet) {
                YamabikoOptionBottomSheet(
                    title = "Provider",
                    options = listOf(
                        YamabikoOption(key = "GEMINI", title = "Google Gemini"),
                        YamabikoOption(key = "GEMINI_AUTH", title = "Gemini Auth (CLI)"),
                        YamabikoOption(key = "OPENROUTER", title = "OpenRouter"),
                        YamabikoOption(key = "MINIMAX", title = "MiniMax"),
                        YamabikoOption(key = "OPENAI", title = "OpenAI"),
                        YamabikoOption(key = "CODEX_AUTH", title = "Codex Auth"),
                        YamabikoOption(key = "OPENAI_COMPAT", title = "OpenAI (Custom)"),
                        YamabikoOption(key = "ZAI", title = "Z.ai")
                    ),
                    selectedKey = state.apiProvider,
                    onOptionSelected = { state.onApiProviderChange(it.key) },
                    onDismissRequest = { showProviderSheet = false }
                )
            }

            if (state.apiProvider == "OPENAI_COMPAT") {
                var showCompatSheet by remember { mutableStateOf(false) }
                val compatLabel = state.openAiCompatPresetName
                    ?.takeIf { it.isNotBlank() }
                    ?: "Select preset"
                YamabikoSelectRow(
                    title = "OpenAI (Custom) Preset",
                    value = compatLabel,
                    onClick = { showCompatSheet = true },
                    enabled = openAiCompatPresets.isNotEmpty()
                )
                if (showCompatSheet) {
                    val options = buildList {
                        add(YamabikoOption(key = "", title = "Keep current selection"))
                        openAiCompatPresets.forEach { preset ->
                            add(
                                YamabikoOption(
                                    key = preset.name,
                                    title = preset.name,
                                    subtitle = preset.baseUrl
                                )
                            )
                        }
                    }
                    YamabikoOptionBottomSheet(
                        title = "OpenAI (Custom) Preset",
                        options = options,
                        selectedKey = state.openAiCompatPresetName ?: "",
                        onOptionSelected = { option ->
                            state.onOpenAiCompatPresetNameChange(option.key.takeIf { it.isNotBlank() })
                        },
                        onDismissRequest = { showCompatSheet = false }
                    )
                }
                if (openAiCompatPresets.isEmpty()) {
                    Text(
                        text = "Custom presets are not configured yet. Add them in Settings.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }

            val requiresApiKey = state.apiProvider != "CODEX_AUTH" && state.apiProvider != "GEMINI_AUTH"
            if (requiresApiKey) {
                YamabikoTextField(
                    value = state.apiKey,
                    onValueChange = state.onApiKeyChange,
                    label = {
                        Text(
                            when (state.apiProvider) {
                                "GEMINI" -> "Gemini API Key (Optional)"
                                "OPENROUTER" -> "OpenRouter API Key (Optional)"
                                "MINIMAX" -> "MiniMax API Key (Optional)"
                                "ZAI" -> "Z.ai API Key (Optional)"
                                else -> "API Key (Optional)"
                            }
                        )
                    },
                    placeholder = { Text(if (state.apiKey.isEmpty()) "Leave empty to use global settings" else "") },
                    modifier = Modifier.fillMaxWidth(),
                    singleLine = true
                )
            } else {
                Text(
                    text = "このプロバイダーは設定画面のログインを使用します。",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun PresetThinkingCard(state: ModelPresetDialogState) {
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
            val isOpenRouter = state.apiProvider == "OPENROUTER"
            val isCodex = state.apiProvider == "CODEX_AUTH"
            val isZai = state.apiProvider == "ZAI"
            val isGeminiProvider = state.apiProvider == "GEMINI" || state.apiProvider == "GEMINI_AUTH"
            val isGeminiThinkingLevel = isGeminiProvider && ModelUtils.isThinkingLevelSupported(state.model)
            val isAlwaysOn = isGeminiProvider && ModelUtils.isThinkingAlwaysOn(state.model)
            val thinkingLabel = when (state.apiProvider) {
                "OPENROUTER", "CODEX_AUTH" -> "Reasoning"
                "ZAI" -> "Deep Thinking"
                else -> "Thinking"
            }
            SettingsToggleRow(
                title = thinkingLabel,
                checked = state.thinkingEnabled,
                onCheckedChange = state.onThinkingEnabledChange,
                enabled = !isAlwaysOn,
                titleStyle = MaterialTheme.typography.titleMedium,
                leadingContent = {
                    Icon(
                        Icons.Default.Psychology,
                        contentDescription = thinkingLabel,
                        modifier = Modifier.size(20.dp),
                        tint = MaterialTheme.colorScheme.primary
                    )
                }
            )

            if (isCodex) {
                if (state.thinkingEnabled) {
                    val preset = CodexModelPresets.findPreset(state.model)
                    val effortOptions = preset?.supportedReasoningEfforts
                        ?.map { it.effort }
                        ?.ifEmpty { null }
                        ?: listOf("low", "medium", "high")
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        effortOptions.forEach { effort ->
                            FilterChip(
                                selected = state.reasoningEffort == effort,
                                onClick = { state.onReasoningEffortChange(effort) },
                                label = { Text(effort.replaceFirstChar { it.uppercase() }) }
                            )
                        }
                    }
                }
            } else if (isGeminiThinkingLevel) {
                val options = ModelUtils.getThinkingLevelOptions(state.model)
                val normalized = ModelUtils.normalizeThinkingLevel(state.model, state.thinkingLevel)
                val selected = normalized ?: ModelUtils.getDefaultThinkingLevel(state.model)
                val levelSelectorEnabled = isAlwaysOn || state.thinkingEnabled
                var showThinkingLevelSheet by remember { mutableStateOf(false) }
                val selectedLabel = when (selected) {
                    "minimal" -> "Minimal (ほぼOFF)"
                    "low" -> "Low"
                    "medium" -> "Medium"
                    else -> "High"
                }
                YamabikoSelectRow(
                    title = "Thinking Level",
                    value = selectedLabel,
                    enabled = levelSelectorEnabled,
                    onClick = { showThinkingLevelSheet = true }
                )
                if (showThinkingLevelSheet) {
                    YamabikoOptionBottomSheet(
                        title = "Thinking Level",
                        options = options.map { level ->
                            YamabikoOption(
                                key = level,
                                title = when (level) {
                                    "minimal" -> "Minimal (ほぼOFF)"
                                    "low" -> "Low"
                                    "medium" -> "Medium"
                                    else -> "High"
                                }
                            )
                        },
                        selectedKey = selected,
                        onOptionSelected = { state.onThinkingLevelChange(it.key) },
                        onDismissRequest = { showThinkingLevelSheet = false }
                    )
                }
            } else {
                val showBudgetSlider = !isGeminiThinkingLevel &&
                    !isCodex &&
                    !isZai &&
                    state.thinkingEnabled &&
                    (!isOpenRouter || state.reasoningMode == "budget")
                if (showBudgetSlider) {
                    val optimalRange = when (state.apiProvider) {
                        "OPENROUTER" -> 0f..32000f
                        else -> ModelUtils.getThinkingBudgetFloatRange(state.model) ?: 0f..24576f
                    }
                    val steps = when (state.apiProvider) {
                        "OPENROUTER" -> 0
                        else -> ModelUtils.getOptimalThinkingSteps(state.model)
                    }
                    Slider(
                        value = state.thinkingBudget.coerceIn(optimalRange.start, optimalRange.endInclusive),
                        onValueChange = state.onThinkingBudgetChange,
                        valueRange = optimalRange,
                        steps = steps,
                        enabled = !isOpenRouter || state.reasoningMode == "budget"
                    )
                }

                if (isOpenRouter) {
                    Text(
                        "Leave at 0 to let the provider infer a budget. Some models will translate this into an effort level automatically.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }

            if (isOpenRouter) {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    listOf(
                        "auto" to "Automatic",
                        "effort" to "Effort",
                        "budget" to "Max tokens"
                    ).forEach { (mode, label) ->
                        FilterChip(
                            selected = state.reasoningMode == mode,
                            onClick = {
                                state.onReasoningModeChange(mode)
                                if (mode == "effort" && state.reasoningEffort.isBlank()) {
                                    state.onReasoningEffortChange("medium")
                                }
                            },
                            label = { Text(label) }
                        )
                    }
                }

                if (state.reasoningMode == "effort") {
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        listOf("low", "medium", "high").forEach { effort ->
                            FilterChip(
                                selected = state.reasoningEffort == effort,
                                onClick = { state.onReasoningEffortChange(effort) },
                                label = { Text(effort.replaceFirstChar { it.uppercase() }) }
                            )
                        }
                    }
                }

                SettingsToggleRow(
                    title = "レスポンスにReasoningを含めない",
                    checked = state.reasoningExclude,
                    onCheckedChange = state.onReasoningExcludeChange
                )
            }
        }
    }
}

@Composable
private fun PresetToolsCard(state: ModelPresetDialogState) {
    val isGemini = state.apiProvider == "GEMINI" || state.apiProvider == "GEMINI_AUTH"
    val isOpenRouter = state.apiProvider == "OPENROUTER"
    if (!isGemini && !isOpenRouter) return

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
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Text(
                text = "Tools",
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold
            )
            SettingsToggleRow(
                title = "Google Search",
                checked = state.googleSearchEnabled,
                onCheckedChange = state.onGoogleSearchEnabledChange,
                showDivider = true
            )
            if (isGemini) {
                SettingsToggleRow(
                    title = "URL Context",
                    checked = state.urlContextEnabled,
                    onCheckedChange = state.onUrlContextEnabledChange,
                    showDivider = true
                )
            }
            SettingsToggleRow(
                title = "Code Execution",
                checked = state.codeExecutionEnabled,
                onCheckedChange = state.onCodeExecutionEnabledChange,
                showDivider = isGemini
            )
            if (isGemini) {
                SettingsToggleRow(
                    title = "Google Maps",
                    checked = state.googleMapsEnabled,
                    onCheckedChange = state.onGoogleMapsEnabledChange,
                    showDivider = true
                )
                SettingsToggleRow(
                    title = "Computer Use",
                    checked = state.computerUseEnabled,
                    onCheckedChange = state.onComputerUseEnabledChange,
                    showDivider = false
                )
            }
        }
    }
}

@Composable
private fun PresetGeminiAdvancedCard(state: ModelPresetDialogState) {
    val isGemini = state.apiProvider == "GEMINI" || state.apiProvider == "GEMINI_AUTH"
    if (!isGemini) return

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
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Text(
                text = "Gemini Custom Settings",
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold
            )
            YamabikoTextField(
                value = state.responseMimeType,
                onValueChange = state.onResponseMimeTypeChange,
                label = { Text("Response MIME Type") },
                placeholder = { Text("e.g. application/json") },
                modifier = Modifier.fillMaxWidth(),
                singleLine = true
            )
            YamabikoTextField(
                value = state.responseJsonSchema,
                onValueChange = state.onResponseJsonSchemaChange,
                label = { Text("Response JSON Schema") },
                placeholder = { Text("{ ... }") },
                modifier = Modifier.fillMaxWidth(),
                minLines = 3,
                maxLines = 6
            )
            YamabikoTextField(
                value = state.functionDeclarations,
                onValueChange = state.onFunctionDeclarationsChange,
                label = { Text("Function Declarations (JSON)") },
                placeholder = { Text("[{ ... }]") },
                modifier = Modifier.fillMaxWidth(),
                minLines = 3,
                maxLines = 6
            )
        }
    }
}

@Composable
private fun PresetCodexAdvancedCard(state: ModelPresetDialogState) {
    if (state.apiProvider != "CODEX_AUTH") return

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
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Text(
                text = "Codex Settings",
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold
            )

            var showSummarySheet by remember { mutableStateOf(false) }
            val summaryLabel = state.codexReasoningSummary.ifBlank { "auto" }
            YamabikoSelectRow(
                title = "Reasoning Summary",
                value = summaryLabel,
                enabled = state.thinkingEnabled,
                onClick = { showSummarySheet = true }
            )
            if (showSummarySheet) {
                val options = listOf(
                    YamabikoOption(key = "auto", title = "auto", subtitle = "Model decides summary detail"),
                    YamabikoOption(key = "concise", title = "concise", subtitle = "Short, high-level summary"),
                    YamabikoOption(key = "detailed", title = "detailed", subtitle = "Longer, more detailed summary"),
                    YamabikoOption(key = "none", title = "none", subtitle = "Do not request a summary")
                )
                YamabikoOptionBottomSheet(
                    title = "Reasoning Summary",
                    options = options,
                    selectedKey = summaryLabel,
                    onOptionSelected = { state.onCodexReasoningSummaryChange(it.key) },
                    onDismissRequest = { showSummarySheet = false }
                )
            }

            SettingsToggleRow(
                title = "Show Reasoning Summary",
                checked = state.codexShowReasoningSummary,
                enabled = state.thinkingEnabled,
                onCheckedChange = state.onCodexShowReasoningSummaryChange
            )
            SettingsToggleRow(
                title = "Assume model supports summaries",
                checked = state.codexSupportsReasoningSummaries,
                onCheckedChange = state.onCodexSupportsReasoningSummariesChange
            )

            var showVerbositySheet by remember { mutableStateOf(false) }
            val verbosityLabel = state.codexVerbosity.ifBlank { "medium" }
            YamabikoSelectRow(
                title = "Verbosity",
                value = verbosityLabel,
                onClick = { showVerbositySheet = true }
            )
            if (showVerbositySheet) {
                val options = listOf(
                    YamabikoOption(key = "low", title = "low", subtitle = "Shorter responses"),
                    YamabikoOption(key = "medium", title = "medium", subtitle = "Balanced responses"),
                    YamabikoOption(key = "high", title = "high", subtitle = "More verbose responses")
                )
                YamabikoOptionBottomSheet(
                    title = "Verbosity",
                    options = options,
                    selectedKey = verbosityLabel,
                    onOptionSelected = { state.onCodexVerbosityChange(it.key) },
                    onDismissRequest = { showVerbositySheet = false }
                )
            }

            SettingsToggleRow(
                title = "Web Search (Codex)",
                checked = state.codexWebSearchEnabled,
                onCheckedChange = state.onCodexWebSearchEnabledChange
            )
            if (state.codexWebSearchEnabled) {
                var showContextSheet by remember { mutableStateOf(false) }
                val contextLabel = state.codexWebSearchContextSize.ifBlank { "medium" }
                YamabikoSelectRow(
                    title = "Search Context Size",
                    value = contextLabel,
                    onClick = { showContextSheet = true }
                )
                if (showContextSheet) {
                    val options = listOf(
                        YamabikoOption(key = "low", title = "low", subtitle = "Smaller search context"),
                        YamabikoOption(key = "medium", title = "medium", subtitle = "Balanced search context"),
                        YamabikoOption(key = "high", title = "high", subtitle = "Larger search context")
                    )
                    YamabikoOptionBottomSheet(
                        title = "Web Search Context",
                        options = options,
                        selectedKey = contextLabel,
                        onOptionSelected = { state.onCodexWebSearchContextSizeChange(it.key) },
                        onDismissRequest = { showContextSheet = false }
                    )
                }
            }

            SettingsToggleRow(
                title = "Prompt Cache",
                checked = state.codexPromptCacheEnabled,
                onCheckedChange = state.onCodexPromptCacheEnabledChange
            )
            if (state.codexPromptCacheEnabled) {
                YamabikoTextField(
                    value = state.codexPromptCacheMinLength.toString(),
                    onValueChange = { value ->
                        value.toIntOrNull()?.let { state.onCodexPromptCacheMinLengthChange(it.coerceAtLeast(0)) }
                    },
                    label = { Text("Cache min length (chars)") },
                    modifier = Modifier.fillMaxWidth(),
                    singleLine = true
                )
                YamabikoTextField(
                    value = state.codexPromptCacheType,
                    onValueChange = state.onCodexPromptCacheTypeChange,
                    label = { Text("Prompt Cache Type") },
                    placeholder = { Text("ephemeral") },
                    modifier = Modifier.fillMaxWidth(),
                    singleLine = true
                )
            }
        }
    }
}

fun LazyListScope.modelPresetsSection(
    presets: List<ModelPreset>,
    onCreatePreset: () -> Unit,
    onEditPreset: (ModelPreset) -> Unit,
    onDeletePreset: (Long) -> Unit
) {
    item {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(vertical = 16.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                "Model Presets",
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold,
                modifier = Modifier.weight(1f)
            )
            TextButton(onClick = onCreatePreset) {
                Icon(Icons.Filled.Add, contentDescription = "Add")
                Spacer(modifier = Modifier.width(4.dp))
                Text("Add")
            }
        }
    }

    items(presets) { preset ->
        Card(
            modifier = Modifier
                .fillMaxWidth()
                .padding(vertical = 4.dp),
            colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
            elevation = CardDefaults.cardElevation(defaultElevation = 2.dp),
            border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.6f))
        ) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(16.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Column(modifier = Modifier.weight(1f)) {
                    Text(preset.name, style = MaterialTheme.typography.titleSmall)
                    Text(
                        preset.model,
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(top = 2.dp)
                    )
                    Row(
                        modifier = Modifier.padding(top = 8.dp),
                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        AssistChip(
                            onClick = { },
                            label = {
                    Text(
                        when (preset.apiProvider) {
                            "OPENROUTER" -> "OpenRouter"
                            "MINIMAX" -> "MiniMax"
                            "OPENAI" -> "OpenAI"
                            "CODEX_AUTH" -> "Codex Auth"
                            "GEMINI_AUTH" -> "Gemini Auth (CLI)"
                            "OPENAI_COMPAT" -> "OpenAI (Custom)"
                            "ZAI" -> "Z.ai"
                            else -> "Gemini"
                        },
                        style = MaterialTheme.typography.labelSmall
                    )
                            },
                            leadingIcon = {
                                Icon(Icons.Filled.Cloud, contentDescription = null, modifier = Modifier.size(16.dp))
                            },
                            modifier = Modifier.height(24.dp)
                        )
                        if (preset.thinkingEnabled) {
                            AssistChip(
                                onClick = { },
                                label = { Text("Thinking", style = MaterialTheme.typography.labelSmall) },
                                leadingIcon = {
                                    Icon(Icons.Filled.Psychology, contentDescription = null, modifier = Modifier.size(16.dp))
                                },
                                modifier = Modifier.height(24.dp)
                            )
                        }
                        if (!preset.systemPromptPresetName.isNullOrBlank()) {
                            AssistChip(
                                onClick = { },
                                label = { Text("Prompt Preset", style = MaterialTheme.typography.labelSmall) },
                                leadingIcon = {
                                    Icon(Icons.Filled.EditNote, contentDescription = null, modifier = Modifier.size(16.dp))
                                },
                                modifier = Modifier.height(24.dp)
                            )
                        }
                        if (preset.systemPromptPresetName.isNullOrBlank() && !preset.systemPrompt.isNullOrBlank()) {
                            AssistChip(
                                onClick = { },
                                label = { Text("Custom Prompt", style = MaterialTheme.typography.labelSmall) },
                                leadingIcon = {
                                    Icon(Icons.Filled.EditNote, contentDescription = null, modifier = Modifier.size(16.dp))
                                },
                                modifier = Modifier.height(24.dp)
                            )
                        }
                        val hasTools = preset.googleSearchEnabled ||
                            preset.codeExecutionEnabled ||
                            preset.urlContextEnabled ||
                            preset.googleMapsEnabled ||
                            preset.computerUseEnabled ||
                            preset.codexWebSearchEnabled
                        if (hasTools) {
                            AssistChip(
                                onClick = { },
                                label = { Text("Tools", style = MaterialTheme.typography.labelSmall) },
                                leadingIcon = {
                                    Icon(Icons.Filled.Build, contentDescription = null, modifier = Modifier.size(16.dp))
                                },
                                modifier = Modifier.height(24.dp)
                            )
                        }
                        val hasCodexConfig = preset.apiProvider == "CODEX_AUTH" && (
                            preset.codexReasoningSummary != "auto" ||
                                preset.codexVerbosity != "medium" ||
                                preset.codexPromptCacheType != "ephemeral" ||
                                preset.codexPromptCacheMinLength != 512 ||
                                !preset.codexPromptCacheEnabled ||
                                preset.codexSupportsReasoningSummaries ||
                                !preset.codexShowReasoningSummary
                            )
                        val hasCustomConfig = preset.responseMimeType.isNotBlank() ||
                            preset.responseJsonSchema.isNotBlank() ||
                            preset.functionDeclarations.isNotBlank() ||
                            preset.openAiCompatPresetName != null ||
                            hasCodexConfig
                        if (hasCustomConfig) {
                            AssistChip(
                                onClick = { },
                                label = { Text("Custom Config", style = MaterialTheme.typography.labelSmall) },
                                leadingIcon = {
                                    Icon(Icons.Filled.EditNote, contentDescription = null, modifier = Modifier.size(16.dp))
                                },
                                modifier = Modifier.height(24.dp)
                            )
                        }
                    }
                }
                IconButton(onClick = { onEditPreset(preset) }) {
                    Icon(Icons.Filled.Edit, contentDescription = "Edit Preset", tint = MaterialTheme.colorScheme.primary)
                }
                IconButton(onClick = { onDeletePreset(preset.id) }) {
                    Icon(Icons.Filled.Delete, contentDescription = "Delete Preset", tint = MaterialTheme.colorScheme.error)
                }
            }
        }
    }
}

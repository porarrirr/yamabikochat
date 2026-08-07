package com.porarri.yamabikochat.ui.settings.sections

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Slider
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.unit.dp
import com.porarri.yamabikochat.ui.components.YamabikoOption
import com.porarri.yamabikochat.ui.components.YamabikoOptionBottomSheet
import com.porarri.yamabikochat.ui.components.YamabikoSelectRow
import com.porarri.yamabikochat.ui.settings.components.SettingsToggleRow
import com.porarri.yamabikochat.utils.CodexModelPresets
import com.porarri.yamabikochat.utils.ModelUtils

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ThinkingOverrideSection(
    provider: String,
    model: String,
    thinking: ThinkingOverrideUiState
) {
    val normalized = provider.uppercase()
    if (normalized == "OPENROUTER") return

    val isGemini = normalized == "GEMINI"
    val isCodex = normalized == "CODEX_AUTH" || normalized == "SUPERGROK"
    val isZai = normalized == "ZAI"
    val isGeminiThinkingLevel = isGemini && ModelUtils.isThinkingLevelSupported(model)
    val isAlwaysOn = isGemini && ModelUtils.isThinkingAlwaysOn(model)

    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        SettingsToggleRow(
            title = "Thinking 設定",
            description = if (thinking.overrideEnabled) "カスタム設定を使用" else "グローバル設定を継承",
            checked = thinking.overrideEnabled,
            onCheckedChange = {
                thinking.onOverrideEnabledChange(it)
                if (it) thinking.onApplyDefaults()
            }
        )

        if (thinking.overrideEnabled) {
            val thinkingLabel = when (normalized) {
                "CODEX_AUTH", "SUPERGROK" -> "Reasoning"
                "ZAI" -> "Deep Thinking"
                else -> "Thinking"
            }
            SettingsToggleRow(
                title = thinkingLabel,
                checked = thinking.thinkingEnabled,
                onCheckedChange = thinking.onThinkingEnabledChange,
                enabled = !isAlwaysOn,
                showDivider = false
            )

            if (isCodex) {
                if (thinking.thinkingEnabled) {
                    val preset = CodexModelPresets.findPreset(model)
                    val effortOptions = preset?.supportedReasoningEfforts
                        ?.map { it.effort }
                        ?.ifEmpty { null }
                        ?: listOf("low", "medium", "high")
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        effortOptions.forEach { effort ->
                            FilterChip(
                                selected = thinking.codexReasoningEffort == effort,
                                onClick = { thinking.onCodexReasoningEffortChange(effort) },
                                label = { Text(effort.replaceFirstChar { it.uppercase() }) }
                            )
                        }
                    }
                }
            } else if (isGeminiThinkingLevel) {
                val options = ModelUtils.getThinkingLevelOptions(model)
                val normalizedLevel = ModelUtils.normalizeThinkingLevel(model, thinking.thinkingLevel)
                val selected = normalizedLevel ?: ModelUtils.getDefaultThinkingLevel(model)
                val levelSelectorEnabled = isAlwaysOn || thinking.thinkingEnabled
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
                        onOptionSelected = { thinking.onThinkingLevelChange(it.key) },
                        onDismissRequest = { showThinkingLevelSheet = false }
                    )
                }
            } else {
                val showBudgetSlider = !isZai && thinking.thinkingEnabled
                if (showBudgetSlider) {
                    val optimalRange = ModelUtils.getThinkingBudgetFloatRange(model) ?: 0f..24576f
                    val steps = ModelUtils.getOptimalThinkingSteps(model)
                    Slider(
                        value = thinking.thinkingBudget.coerceIn(optimalRange.start, optimalRange.endInclusive),
                        onValueChange = thinking.onThinkingBudgetChange,
                        valueRange = optimalRange,
                        steps = steps
                    )
                }
                if (isZai) {
                    Text(
                        text = "Z.ai Coding Plan はON/OFFのみ対応しています",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
        }
    }
}

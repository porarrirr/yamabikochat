package com.porarri.yamabikochat.ui.settings.sections

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Slider
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.dp
import com.porarri.yamabikochat.ui.settings.components.SettingsToggleRow

@Composable
fun ReasoningOverrideSection(reasoning: ReasoningOverrideUiState) {
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        SettingsToggleRow(
            title = "Reasoning Tokens",
            description = if (reasoning.overrideEnabled) "カスタム設定を使用" else "グローバル設定を継承",
            checked = reasoning.overrideEnabled,
            onCheckedChange = {
                reasoning.onOverrideEnabledChange(it)
                if (it) reasoning.onApplyDefaults()
            }
        )

        if (reasoning.overrideEnabled) {
            SettingsToggleRow(
                title = "Reasoning",
                checked = reasoning.reasoningEnabled,
                onCheckedChange = reasoning.onReasoningEnabledChange
            )

            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                listOf(
                    "auto" to "Auto",
                    "effort" to "Effort",
                    "budget" to "Max tokens"
                ).forEach { (mode, label) ->
                    FilterChip(
                        selected = reasoning.reasoningMode == mode,
                        onClick = {
                            reasoning.onReasoningModeChange(mode)
                            if (mode == "effort" && reasoning.reasoningEffort.isBlank()) {
                                reasoning.onReasoningEffortChange("medium")
                            }
                        },
                        label = { Text(label) },
                        enabled = reasoning.reasoningEnabled
                    )
                }
            }

            if (reasoning.reasoningMode == "effort" && reasoning.reasoningEnabled) {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    listOf("low", "medium", "high").forEach { effort ->
                        FilterChip(
                            selected = reasoning.reasoningEffort.equals(effort, ignoreCase = true),
                            onClick = { reasoning.onReasoningEffortChange(effort) },
                            label = { Text(effort.replaceFirstChar { it.uppercase() }) }
                        )
                    }
                }
            }

            SettingsToggleRow(
                title = "レスポンスにReasoningを含めない",
                checked = reasoning.reasoningExclude,
                onCheckedChange = reasoning.onReasoningExcludeChange,
                enabled = reasoning.reasoningEnabled
            )

            if (reasoning.reasoningEnabled && reasoning.reasoningMode == "budget") {
                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(
                        text = "Max reasoning tokens: ${reasoning.reasoningBudget.toInt()}",
                        style = MaterialTheme.typography.bodySmall
                    )
                    Slider(
                        value = reasoning.reasoningBudget.coerceIn(0f, 32000f),
                        onValueChange = reasoning.onReasoningBudgetChange,
                        valueRange = 0f..32000f,
                        enabled = reasoning.reasoningEnabled
                    )
                }
            }
        }
    }
}

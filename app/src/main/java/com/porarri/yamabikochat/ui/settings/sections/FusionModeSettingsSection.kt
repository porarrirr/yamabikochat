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
import androidx.compose.material.icons.filled.MergeType
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.porarri.yamabikochat.ui.components.YamabikoOption
import com.porarri.yamabikochat.ui.components.YamabikoOptionBottomSheet
import com.porarri.yamabikochat.ui.components.YamabikoSelectRow
import com.porarri.yamabikochat.ui.components.YamabikoTextField

@OptIn(ExperimentalMaterial3Api::class)
fun LazyListScope.fusionModeSettingsSection(
    isFusionModeEnabled: Boolean,
    onFusionModeEnabledChange: (Boolean) -> Unit,
    fusionBlockedByDualOrAuto: Boolean,
    fusionTaskType: String,
    onFusionTaskTypeChange: (String) -> Unit,
    fusionDebugModeEnabled: Boolean,
    onFusionDebugModeEnabledChange: (Boolean) -> Unit,
    fusionLogPromptsEnabled: Boolean,
    onFusionLogPromptsEnabledChange: (Boolean) -> Unit,
    fusionCustomPresetJSON: String,
    onFusionCustomPresetJSONChange: (String) -> Unit
) {
    item {
        Card(
            modifier = Modifier.fillMaxWidth(),
            colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
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
                        Icons.Filled.MergeType,
                        contentDescription = "Fusion Mode",
                        modifier = Modifier.size(24.dp),
                        tint = MaterialTheme.colorScheme.primary
                    )
                    Spacer(modifier = Modifier.width(12.dp))
                    Column(modifier = Modifier.weight(1f)) {
                        Text(
                            "Fusion モード",
                            style = MaterialTheme.typography.titleMedium,
                            fontWeight = FontWeight.SemiBold
                        )
                        Text(
                            "複数モデルを並列実行し、ジャッジと合成で最終回答を生成",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                    Switch(
                        checked = isFusionModeEnabled,
                        onCheckedChange = onFusionModeEnabledChange,
                        enabled = isFusionModeEnabled || !fusionBlockedByDualOrAuto
                    )
                }

                if (fusionBlockedByDualOrAuto && !isFusionModeEnabled) {
                    Text(
                        "デュアルモードまたは自動会話が有効な間は Fusion を ON にできません。",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }

                Text(
                    "Fusion・デュアル・自動会話は同時に有効化できません。",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )

                if (isFusionModeEnabled) {
                    HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.8f))

                    var showTaskSheet by remember { mutableStateOf(false) }
                    YamabikoSelectRow(
                        title = "Task type",
                        value = when (fusionTaskType) {
                            "research" -> "Research"
                            "coding" -> "Coding"
                            else -> "Auto"
                        },
                        onClick = { showTaskSheet = true }
                    )
                    if (showTaskSheet) {
                        YamabikoOptionBottomSheet(
                            title = "Task type",
                            options = listOf(
                                YamabikoOption("auto", "Auto"),
                                YamabikoOption("research", "Research"),
                                YamabikoOption("coding", "Coding")
                            ),
                            selectedKey = fusionTaskType,
                            onOptionSelected = {
                                onFusionTaskTypeChange(it.key)
                                showTaskSheet = false
                            },
                            onDismissRequest = { showTaskSheet = false }
                        )
                    }

                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text("Debug mode", modifier = Modifier.weight(1f))
                        Switch(
                            checked = fusionDebugModeEnabled,
                            onCheckedChange = onFusionDebugModeEnabledChange
                        )
                    }
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text("Log prompts in trace", modifier = Modifier.weight(1f))
                        Switch(
                            checked = fusionLogPromptsEnabled,
                            onCheckedChange = onFusionLogPromptsEnabledChange
                        )
                    }

                    Text(
                        "カスタムプリセット JSON（空ならデフォルト 4 パネル構成を使用）",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    YamabikoTextField(
                        value = fusionCustomPresetJSON,
                        onValueChange = onFusionCustomPresetJSONChange,
                        label = { Text("fusionCustomPresetJSON") },
                        singleLine = false,
                        minLines = 3,
                        modifier = Modifier.fillMaxWidth()
                    )
                    Spacer(modifier = Modifier.height(4.dp))
                }
            }
        }
    }
}

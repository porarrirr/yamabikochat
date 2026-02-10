package com.porarri.yamabikochat.ui.settings.sections

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.expandVertically
import androidx.compose.animation.shrinkVertically
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.spring
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.ExpandLess
import androidx.compose.material.icons.outlined.ExpandMore
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Slider
import androidx.compose.material3.Text
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.porarri.yamabikochat.data.remote.ModelEndpoint
import com.porarri.yamabikochat.data.remote.ProviderDirectory
import com.porarri.yamabikochat.ui.components.ModelEndpointsSelector
import com.porarri.yamabikochat.ui.settings.components.SettingsToggleRow

@Suppress("LongParameterList")
fun LazyListScope.openRouterAdvancedSettingsSection(
    expanded: Boolean,
    onExpandedChange: (Boolean) -> Unit,
    providerSort: String,
    onProviderSortChange: (String) -> Unit,
    providerSelectionMax: Int,
    onProviderSelectionMaxChange: (Int) -> Unit,
    preferredProviders: List<String>,
    onPreferredProvidersChange: (List<String>) -> Unit,
    selectedQuantizations: List<String>,
    onSelectedQuantizationsChange: (List<String>) -> Unit,
    maxPrice: Float,
    onMaxPriceChange: (Float) -> Unit,
    allowFallbacks: Boolean,
    onAllowFallbacksChange: (Boolean) -> Unit,
    requireParameters: Boolean,
    onRequireParametersChange: (Boolean) -> Unit,
    modelEndpoints: List<ModelEndpoint>,
    providerDirectory: ProviderDirectory,
    freeModelOnly: Boolean = false
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
            Column(modifier = Modifier.padding(16.dp)) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clickable { onExpandedChange(!expanded) }
                        .padding(vertical = 12.dp),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        androidx.compose.material3.Icon(
                            imageVector = Icons.Outlined.Settings,
                            contentDescription = "高度な設定",
                            tint = MaterialTheme.colorScheme.primary
                        )
                        Spacer(modifier = Modifier.width(12.dp))
                        Column {
                            Text(
                                text = "高度なプロバイダー設定",
                                style = MaterialTheme.typography.titleMedium,
                                fontWeight = FontWeight.SemiBold
                            )
                            Text(
                                text = if (expanded) "設定を折りたたむ" else "プロバイダー・量子化・価格制限などの詳細設定",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                    }
                    androidx.compose.material3.Icon(
                        imageVector = if (expanded) Icons.Outlined.ExpandLess else Icons.Outlined.ExpandMore,
                        contentDescription = if (expanded) "折りたたむ" else "展開する",
                        tint = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }

                AnimatedVisibility(
                    visible = expanded,
                    enter = expandVertically(
                        animationSpec = spring(
                            dampingRatio = Spring.DampingRatioMediumBouncy,
                            stiffness = Spring.StiffnessLow
                        )
                    ),
                    exit = shrinkVertically(
                        animationSpec = spring(
                            dampingRatio = Spring.DampingRatioMediumBouncy,
                            stiffness = Spring.StiffnessLow
                        )
                    )
                ) {
                    Column(
                        verticalArrangement = Arrangement.spacedBy(16.dp),
                        modifier = Modifier.padding(top = 16.dp)
                    ) {
                        HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.8f))

                        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                            Text(
                                text = "並べ替え（provider.sort に反映）",
                                style = MaterialTheme.typography.titleSmall,
                                fontWeight = FontWeight.SemiBold
                            )
                            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                listOf(
                                    "price" to "価格",
                                    "throughput" to "稼働率（スループット）",
                                    "latency" to "レイテンシ"
                                ).forEach { (value, label) ->
                                    FilterChip(
                                        selected = providerSort == value,
                                        onClick = { onProviderSortChange(value) },
                                        label = { Text(label) }
                                    )
                                }
                            }

                            Text(
                                text = "プロバイダー選択上限",
                                style = MaterialTheme.typography.titleSmall,
                                fontWeight = FontWeight.SemiBold
                            )
                            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                listOf(0, 3, 5, 10, 12, 20, 30).forEach { option ->
                                    FilterChip(
                                        selected = providerSelectionMax == option,
                                        onClick = { onProviderSelectionMaxChange(option) },
                                        label = { Text(if (option == 0) "無制限" else option.toString()) }
                                    )
                                }
                            }
                        }

                        // When a free model is selected, hide paid providers by filtering endpoints.
                        // Consider missing prompt/completion as zero for free queues, but exclude if per-request is set.
                        val filteredEndpoints = if (freeModelOnly) {
                            modelEndpoints.filter { ep ->
                                val p = ep.pricing.prompt?.toDoubleOrNull()
                                val c = ep.pricing.completion?.toDoubleOrNull()
                                val req = ep.pricing.request?.toDoubleOrNull()
                                (req == null || req == 0.0) && ((p == null || p == 0.0) && (c == null || c == 0.0))
                            }
                        } else modelEndpoints

                        if (freeModelOnly && filteredEndpoints.isEmpty()) {
                            // Show a friendly notice instead of an empty list
                            Card(
                                colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerHigh),
                                border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.6f)),
                                elevation = CardDefaults.cardElevation(defaultElevation = 0.dp)
                            ) {
                                Column(Modifier.padding(16.dp)) {
                                    Text(
                                        text = "無料モデルはOpenRouterのフリーキュー経由で提供されます",
                                        style = MaterialTheme.typography.bodyMedium,
                                        fontWeight = FontWeight.Medium
                                    )
                                    Spacer(Modifier.height(4.dp))
                                    Text(
                                        text = "このモデルでは個別のプロバイダー選択はありません",
                                        style = MaterialTheme.typography.bodySmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant
                                    )
                                }
                            }
                        } else {
                            ModelEndpointsSelector(
                                endpoints = filteredEndpoints,
                                providerDirectory = providerDirectory,
                                selectedProviders = preferredProviders,
                                onProvidersChanged = onPreferredProvidersChange,
                                selectedQuantizations = selectedQuantizations,
                                onQuantizationsChanged = onSelectedQuantizationsChange,
                                maxSelection = providerSelectionMax,
                                sortMode = providerSort
                            )
                        }

                        Column {
                            Text(
                                text = "最大価格制限（USD / 1M tokens）",
                                style = MaterialTheme.typography.titleSmall,
                                fontWeight = FontWeight.SemiBold
                            )
                            Spacer(modifier = Modifier.height(8.dp))
                            Row(
                                verticalAlignment = Alignment.CenterVertically,
                                modifier = Modifier.fillMaxWidth()
                            ) {
                                Slider(
                                    value = maxPrice,
                                    onValueChange = onMaxPriceChange,
                                    valueRange = 0f..100f,
                                    steps = 99,
                                    modifier = Modifier.weight(1f)
                                )
                                Text(
                                    text = if (maxPrice == 0f) "無制限" else "$${maxPrice.toInt()}",
                                    modifier = Modifier.padding(start = 8.dp),
                                    fontWeight = FontWeight.Medium
                                )
                            }
                        }

                        Card(
                            colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerHigh),
                            border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.6f)),
                            elevation = CardDefaults.cardElevation(defaultElevation = 0.dp)
                        ) {
                            Column(modifier = Modifier.padding(16.dp)) {
                                Text(
                                    text = "エラー処理設定",
                                    style = MaterialTheme.typography.titleSmall,
                                    fontWeight = FontWeight.SemiBold
                                )
                                Spacer(modifier = Modifier.height(12.dp))
                                SettingsToggleRow(
                                    title = "フォールバック許可",
                                    description = "プロバイダー障害時の自動切り替え",
                                    checked = allowFallbacks,
                                    onCheckedChange = onAllowFallbacksChange
                                )
                                Spacer(modifier = Modifier.height(12.dp))
                                SettingsToggleRow(
                                    title = "パラメーター要求",
                                    description = "すべてのパラメーターをサポートするプロバイダーのみ使用",
                                    checked = requireParameters,
                                    onCheckedChange = onRequireParametersChange
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}

fun LazyListScope.openRouterReasoningSection(
    reasoningMode: String,
    onReasoningModeChange: (String) -> Unit,
    reasoningEffort: String,
    onReasoningEffortChange: (String) -> Unit,
    reasoningExclude: Boolean,
    onReasoningExcludeChange: (Boolean) -> Unit,
    thinkingEnabled: Boolean
) {
    item {
        Card(
            modifier = Modifier.fillMaxWidth(),
            colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
            border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.6f)),
            elevation = CardDefaults.cardElevation(defaultElevation = 1.dp)
        ) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp)
            ) {
                Text(
                    text = "Reasoning Tokens",
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold
                )

                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Text(
                        text = "Control how many reasoning tokens the model spends.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )

                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        listOf(
                            "auto" to "Automatic",
                            "effort" to "Effort",
                            "budget" to "Max tokens"
                        ).forEach { (value, label) ->
                            FilterChip(
                                selected = reasoningMode == value,
                                onClick = {
                                    onReasoningModeChange(value)
                                    if (value == "effort" && reasoningEffort.isBlank()) {
                                        onReasoningEffortChange("medium")
                                    }
                                },
                                label = { Text(label) }
                            )
                        }
                    }

                    if (reasoningMode == "effort") {
                        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            Text(
                                text = "Effort level",
                                style = MaterialTheme.typography.bodySmall,
                                fontWeight = FontWeight.Medium
                            )
                            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                listOf("low" to "Low", "medium" to "Medium", "high" to "High").forEach { (effort, label) ->
                                    FilterChip(
                                        selected = reasoningEffort == effort,
                                        onClick = { onReasoningEffortChange(effort) },
                                        label = { Text(label) }
                                    )
                                }
                            }
                            Text(
                                text = "Not all providers support effort overrides; unsupported models will fall back to automatic allocation.",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                    }
                }

                SettingsToggleRow(
                    title = "Exclude reasoning from response",
                    checked = reasoningExclude,
                    onCheckedChange = onReasoningExcludeChange,
                    enabled = thinkingEnabled
                )
                Text(
                    text = "Reasoning tokens are billed as output tokens. Some models may ignore unsupported parameters.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
    }
}

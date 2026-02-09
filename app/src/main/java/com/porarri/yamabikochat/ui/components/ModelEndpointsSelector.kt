package com.porarri.yamabikochat.ui.components

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.porarri.yamabikochat.data.remote.ModelEndpoint
import com.porarri.yamabikochat.data.remote.statusText

/**
 * ModelEndpointsSelector
 * - モデル固有のエンドポイント一覧を元に、対応プロバイダー選択（最大3つ）と量子化選択を行う新UI。
 * - 価格/量子化/稼働状況/稼働率/コンテキスト長/最大出力トークン/対応パラメータを表示。
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun ModelEndpointsSelector(
    endpoints: List<ModelEndpoint>,
    providerDirectory: com.porarri.yamabikochat.data.remote.ProviderDirectory,
    selectedProviders: List<String>, // store slugs
    onProvidersChanged: (List<String>) -> Unit,
    selectedQuantizations: List<String>,
    onQuantizationsChanged: (List<String>) -> Unit,
    modifier: Modifier = Modifier,
    maxSelection: Int = 12,
    sortMode: String = "price" // "price"|"throughput"|"latency"
) {
    // provider_name でグルーピング
    val grouped = remember(endpoints) {
        endpoints
            .filter { !it.providerName.isNullOrBlank() }
            .groupBy { it.providerName!!.trim() }
            .toSortedMap(String.CASE_INSENSITIVE_ORDER)
    }

    // 量子化のユニオン（UIのチップとして提供）
    val allQuantizations = remember(endpoints) {
        endpoints.mapNotNull { it.quantization?.uppercase() }
            .distinct()
            .sorted()
    }

    Column(modifier = modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        // 量子化の選択（ユニオン）
        if (allQuantizations.isNotEmpty()) {
            Text(
                text = "量子化（モデル内の提供状況）",
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.Bold,
                color = MaterialTheme.colorScheme.primary
            )
            FlowRow(
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                AssistChip(
                    onClick = { onQuantizationsChanged(emptyList()) },
                    label = { Text("自動（未指定）") },
                    colors = AssistChipDefaults.assistChipColors(
                        containerColor = if (selectedQuantizations.isEmpty()) MaterialTheme.colorScheme.primary.copy(alpha = 0.12f) else MaterialTheme.colorScheme.surfaceVariant
                    )
                )
                allQuantizations.forEach { q ->
                    val checked = selectedQuantizations.any { it.equals(q, ignoreCase = true) }
                    FilterChip(
                        selected = checked,
                        onClick = {
                            val cur = selectedQuantizations.toMutableList()
                            if (checked) cur.removeAll { it.equals(q, ignoreCase = true) } else cur.add(q)
                            onQuantizationsChanged(cur)
                        },
                        label = { Text(q) }
                    )
                }
            }
        }

        // プロバイダーの選択（モデル別）
        Text(
            text = "対応プロバイダー（モデル別・最大${maxSelection}つ）",
            style = MaterialTheme.typography.titleSmall,
            fontWeight = FontWeight.Bold,
            color = MaterialTheme.colorScheme.primary
        )

        if (grouped.isEmpty()) {
            Text(
                text = "このモデルに紐づくエンドポイント情報が見つかりません",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        } else {
            // 並び替え
            val sortedKeys: List<String> = remember(endpoints, sortMode) {
                val groups = grouped.mapValues { (_, eps) ->
                    // Keep sorting by per-token price (units cancel out), no need to scale
                    val minPrice = eps.minOfOrNull {
                        minOf(
                            it.pricing.prompt?.toDoubleOrNull() ?: Double.POSITIVE_INFINITY,
                            it.pricing.completion?.toDoubleOrNull() ?: Double.POSITIVE_INFINITY
                        )
                    } ?: Double.POSITIVE_INFINITY
                    val uptime = eps.mapNotNull { it.uptimeLast30m }.takeIf { it.isNotEmpty() }?.average() ?: -1.0
                    Triple(minPrice, uptime, 0.0)
                }
                when (sortMode.lowercase()) {
                    "price" -> groups.entries.sortedBy { it.value.first }.map { it.key }
                    "throughput" -> groups.entries.sortedByDescending { it.value.second }.map { it.key }
                    "latency" -> groups.keys.sorted() // データなしのため名称順フォールバック
                    else -> groups.keys.sorted()
                }
            }

            LazyColumn(
                modifier = Modifier
                    .fillMaxWidth()
                    .heightIn(max = 420.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                items(sortedKeys) { providerName ->
                    val eps = grouped.getValue(providerName)
                    val slug = providerDirectory.slugForName(providerName) ?: providerName.lowercase()
                    ProviderCard(
                        providerName = providerName,
                        providerSlug = slug,
                        endpoints = eps,
                        isSelected = selectedProviders.any { it.equals(slug, ignoreCase = true) },
                        onToggle = { checked ->
                            val cur = selectedProviders.toMutableList()
                            if (checked) {
                                if (cur.none { it.equals(slug, ignoreCase = true) }) cur.add(0, slug)
                                if (maxSelection > 0) {
                                    while (cur.size > maxSelection) cur.removeAt(cur.lastIndex)
                                }
                            } else {
                                cur.removeAll { it.equals(slug, ignoreCase = true) }
                            }
                            onProvidersChanged(cur)
                        },
                        enabled = selectedProviders.any { it.equals(slug, ignoreCase = true) } || (maxSelection <= 0) || selectedProviders.size < maxSelection
                    )
                }
            }
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun ProviderCard(
    providerName: String,
    providerSlug: String,
    endpoints: List<ModelEndpoint>,
    isSelected: Boolean,
    onToggle: (Boolean) -> Unit,
    enabled: Boolean
) {
    // 集約情報
    val quantizations = endpoints.mapNotNull { it.quantization?.uppercase() }.distinct().sorted()
    // Convert to USD per 1M tokens for display
    val promptMin = endpoints.minOfOrNull { it.pricing.prompt?.toDoubleOrNull()?.times(1_000_000.0) ?: Double.POSITIVE_INFINITY }
    val completionMin = endpoints.minOfOrNull { it.pricing.completion?.toDoubleOrNull()?.times(1_000_000.0) ?: Double.POSITIVE_INFINITY }
    val ctxMax = endpoints.maxOfOrNull { it.contextLength?.toInt() ?: 0 }
    val maxCompMax = endpoints.maxOfOrNull { it.maxCompletionTokens?.toInt() ?: 0 }
    val anyStatus = endpoints.firstNotNullOfOrNull { it.statusText() }
    val uptimeAvg = endpoints.mapNotNull { it.uptimeLast30m }.takeIf { it.isNotEmpty() }?.average()

    Card(
        colors = CardDefaults.cardColors(
            containerColor = if (isSelected) MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.35f)
            else MaterialTheme.colorScheme.surface
        ),
        border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.6f))
    ) {
        Column(Modifier
            .fillMaxWidth()
            .padding(12.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(providerName, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Medium, modifier = Modifier.weight(1f))
                Checkbox(checked = isSelected, onCheckedChange = onToggle, enabled = enabled)
            }
            // 価格
            val priceText = buildString {
                if (promptMin != null && promptMin.isFinite()) {
                    append("Prompt $")
                    append(String.format(java.util.Locale.US, "%.2f", promptMin))
                    append("/1M tokens")
                }
                if (completionMin != null && completionMin.isFinite()) {
                    if (isNotEmpty()) append(" • ")
                    append("Completion $")
                    append(String.format(java.util.Locale.US, "%.2f", completionMin))
                    append("/1M tokens")
                }
                if (isEmpty()) append("価格情報なし")
            }
            Text(priceText, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)

            // スタッツ
            val stats = buildList {
                ctxMax?.takeIf { it > 0 }?.let {
                    add("コンテキスト長: ${java.text.NumberFormat.getIntegerInstance().format(it)}")
                }
                maxCompMax?.takeIf { it > 0 }?.let {
                    add("最大出力トークン: ${java.text.NumberFormat.getIntegerInstance().format(it)}")
                }
                anyStatus?.let { s ->
                    val up = uptimeAvg?.let { u -> String.format(java.util.Locale.US, "(30分稼働率 %.1f%%)", u * 100) }
                    add("稼働: ${s}${if (up != null) " " + up else ""}")
                }
            }
            if (stats.isNotEmpty()) {
                Text(stats.joinToString("  •  "), style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }

            // 量子化（閲覧表示）
            if (quantizations.isNotEmpty()) {
                Spacer(Modifier.height(6.dp))
                FlowRow(
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                    verticalArrangement = Arrangement.spacedBy(6.dp)
                ) {
                    quantizations.forEach { q ->
                        AssistChip(onClick = {}, label = { Text(q) })
                    }
                }
            }
        }
    }
}

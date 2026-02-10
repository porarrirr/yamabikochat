package com.porarri.yamabikochat.ui.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Checkbox
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.porarri.yamabikochat.data.remote.ModelEndpoint

/**
 * Provider-level selector that groups OpenRouter endpoints by provider_name,
 * summarizes quantizations and pricing, and lets user pick preferred providers.
 */
@Composable
fun EndpointProviderSelector(
    endpoints: List<ModelEndpoint>,
    selectedProviders: List<String>,
    onProvidersChanged: (List<String>) -> Unit,
    label: String = "対応プロバイダー（モデル別）",
    maxSelection: Int = 3
) {
    val grouped = remember(endpoints) {
        endpoints
            .filter { !it.providerName.isNullOrBlank() }
            .groupBy { it.providerName!!.trim() }
            .toSortedMap(String.CASE_INSENSITIVE_ORDER)
    }

    Column(modifier = Modifier.fillMaxWidth()) {
        Text(
            text = label,
            style = MaterialTheme.typography.titleSmall,
            fontWeight = FontWeight.Bold,
            color = MaterialTheme.colorScheme.primary
        )
        Spacer(modifier = Modifier.height(8.dp))

        grouped.forEach { (provider, eps) ->
            val isSelected = selectedProviders.any { it.equals(provider, ignoreCase = true) }

            val quantizations = eps.mapNotNull { it.quantization?.uppercase() }
                .distinct()
                .sorted()

            // API returns USD per 1 token; display in USD per 1M tokens
            val promptMin = eps.minOfOrNull { it.pricing.prompt?.toDoubleOrNull()?.times(1_000_000.0) ?: Double.POSITIVE_INFINITY }
            val completionMin = eps.minOfOrNull { it.pricing.completion?.toDoubleOrNull()?.times(1_000_000.0) ?: Double.POSITIVE_INFINITY }

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

            Card(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(vertical = 4.dp),
                colors = CardDefaults.cardColors(
                    containerColor = if (isSelected) MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.35f)
                    else MaterialTheme.colorScheme.surface
                )
            ) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(12.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.SpaceBetween
                ) {
                    Column(modifier = Modifier.weight(1f)) {
                        Text(provider, style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.Medium)
                        Text(priceText, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        if (quantizations.isNotEmpty()) {
                            Text(
                                text = "量子化: " + quantizations.joinToString(", "),
                                style = MaterialTheme.typography.labelSmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                    }
                    Checkbox(
                        checked = isSelected,
                        onCheckedChange = { checked ->
                            val current = selectedProviders.toMutableList()
                            if (checked) {
                                if (current.none { it.equals(provider, ignoreCase = true) }) {
                                    current.add(0, provider)
                                }
                                while (current.size > maxSelection) current.removeAt(current.lastIndex)
                            } else {
                                current.removeAll { it.equals(provider, ignoreCase = true) }
                            }
                            onProvidersChanged(current)
                        },
                        enabled = isSelected || selectedProviders.size < maxSelection
                    )
                }
            }
        }
    }
}

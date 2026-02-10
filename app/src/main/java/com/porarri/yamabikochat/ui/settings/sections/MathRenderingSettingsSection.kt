package com.porarri.yamabikochat.ui.settings.sections

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Calculate
import androidx.compose.material.icons.filled.Info
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.porarri.yamabikochat.ui.settings.components.SettingsToggleRow

fun LazyListScope.mathRenderingSettingsSection(
    mathRenderingEnabled: Boolean,
    onMathRenderingChange: (Boolean) -> Unit
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
                SettingsToggleRow(
                    title = "数学表記の改善",
                    description = if (mathRenderingEnabled) "LaTeX数式を美しく表示" else "LaTeX数式の高品質レンダリングを有効化",
                    checked = mathRenderingEnabled,
                    onCheckedChange = onMathRenderingChange,
                    titleStyle = MaterialTheme.typography.titleMedium,
                    leadingContent = {
                        Icon(
                            Icons.Filled.Calculate,
                            contentDescription = "Math Rendering",
                            tint = if (mathRenderingEnabled) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                )

                if (mathRenderingEnabled) {
                    HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.8f))

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
                                    Icons.Filled.Info,
                                    contentDescription = "Info",
                                    modifier = Modifier.size(16.dp),
                                    tint = MaterialTheme.colorScheme.primary
                                )
                                Spacer(modifier = Modifier.width(8.dp))
                                Text(
                                    "数学表記の改善について",
                                    style = MaterialTheme.typography.titleSmall,
                                    color = MaterialTheme.colorScheme.onSurface,
                                    fontWeight = FontWeight.SemiBold
                                )
                            }
                            Text(
                                "有効にすると、LaTeX数式記法（\$...\$、\\frac{}{}、\\theta、\\mu など）が美しい数学記号として表示されます。\n\n"
                                        + "例：\n• \$\\pi \\approx 3.14159\$ → π ≈ 3.14159\n• \$\\frac{a}{b}\$ → 分数形式で表示\n"
                                        + "• \$\\theta = 30°\$ → θ = 30°\n\n複雑な数式はWebViewで高品質にレンダリングされ、簡単な記号はUnicode文字に変換されます。",
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

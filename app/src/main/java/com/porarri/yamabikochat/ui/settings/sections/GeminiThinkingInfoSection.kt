package com.porarri.yamabikochat.ui.settings.sections

import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.BorderStroke
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.porarri.yamabikochat.utils.ModelUtils

fun LazyListScope.geminiThinkingInfoSection(model: String) {
    item {
        val thinkingDescription = ModelUtils.getThinkingDescription(model)
        val isSupported = ModelUtils.isThinkingSupported(model)
        val isAlwaysOn = ModelUtils.isThinkingAlwaysOn(model)

        val icon = if (isSupported) Icons.Filled.CheckCircle else Icons.Filled.Warning
        val containerColor = if (isSupported) {
            if (isAlwaysOn) MaterialTheme.colorScheme.secondaryContainer else MaterialTheme.colorScheme.primaryContainer
        } else {
            MaterialTheme.colorScheme.errorContainer
        }
        val iconTint = when {
            !isSupported -> MaterialTheme.colorScheme.error
            isAlwaysOn -> MaterialTheme.colorScheme.secondary
            else -> MaterialTheme.colorScheme.primary
        }
        val textColor = when {
            !isSupported -> MaterialTheme.colorScheme.onErrorContainer
            isAlwaysOn -> MaterialTheme.colorScheme.onSecondaryContainer
            else -> MaterialTheme.colorScheme.onPrimaryContainer
        }

        Card(
            modifier = Modifier
                .fillMaxWidth()
                .padding(vertical = 4.dp),
            colors = CardDefaults.cardColors(containerColor = containerColor),
            border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.6f))
        ) {
            Row(
                modifier = Modifier.padding(12.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Icon(imageVector = icon, contentDescription = null, tint = iconTint)
                Text(
                    text = thinkingDescription,
                    style = MaterialTheme.typography.bodySmall,
                    color = textColor,
                    modifier = Modifier.padding(start = 8.dp)
                )
            }
        }
    }
}

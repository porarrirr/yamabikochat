package com.porarri.yamabikochat.ui.chat

import android.content.Intent
import android.net.Uri
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.OpenInNew
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Error
import androidx.compose.material.icons.filled.ExpandLess
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material.icons.filled.Language
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.porarri.yamabikochat.data.local.ToolActivityStep
import com.porarri.yamabikochat.data.model.ToolSource

@Composable
fun ToolActivityDisclosure(
    steps: List<ToolActivityStep>,
    modifier: Modifier = Modifier
) {
    if (steps.isEmpty()) return

    var expanded by remember { mutableStateOf(false) }
    val isRunning = steps.any { it.status == ToolActivityStep.Status.running }
    val hasFailure = steps.any { it.status == ToolActivityStep.Status.failed }
    val currentStep = steps.lastOrNull { it.status == ToolActivityStep.Status.running }
    val hasNonWebTool = steps.any { it.toolName != "web_search" && it.toolName != "fetch_url" }
    val statusLabel = if (isRunning) {
        if (currentStep?.toolName == "str_replace_editor") "ファイル操作中：${currentStep.detail}"
        else
        if (currentStep?.toolName == "fetch_url") "確認中：${currentStep.detail}"
        else "検索中：${currentStep?.detail.orEmpty()}"
    } else {
        if (hasNonWebTool) "ツール・${steps.size}ステップ" else "Web検索・${steps.size}ステップ"
    }

    Column(modifier = modifier.fillMaxWidth()) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .clickable { expanded = !expanded }
                .semantics {
                    role = Role.Button
                    contentDescription = statusLabel
                    stateDescription = if (expanded) "展開中" else "折りたたみ中"
                }
                .padding(vertical = 4.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Icon(
                imageVector = when {
                    isRunning -> Icons.Default.Language
                    hasFailure -> Icons.Default.Error
                    else -> Icons.Default.CheckCircle
                },
                contentDescription = null,
                modifier = Modifier.size(16.dp),
                tint = if (hasFailure && !isRunning) MaterialTheme.colorScheme.error
                    else MaterialTheme.colorScheme.onSurfaceVariant
            )
            Spacer(modifier = Modifier.width(8.dp))
            if (isRunning) {
                CircularProgressIndicator(
                    modifier = Modifier.size(12.dp),
                    strokeWidth = 1.5.dp
                )
                Spacer(modifier = Modifier.width(8.dp))
                Text(
                    text = statusLabel,
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f)
                )
            } else {
                Text(
                    text = statusLabel,
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                    modifier = Modifier.weight(1f)
                )
            }
            if (!isRunning) Spacer(modifier = Modifier.width(8.dp))
            Icon(
                imageVector = if (expanded) Icons.Default.ExpandLess else Icons.Default.ExpandMore,
                contentDescription = null,
                modifier = Modifier.size(16.dp),
                tint = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }

        AnimatedVisibility(visible = expanded) {
            Column(
                modifier = Modifier.padding(top = 8.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                steps.forEach { step ->
                    ToolActivityStepRow(step = step)
                }
                val sources = steps.flatMap { it.sources }.distinctBy { it.url }
                if (sources.isNotEmpty()) {
                    ToolSourcesList(sources = sources)
                }
            }
        }
    }
}

@Composable
private fun ToolActivityStepRow(step: ToolActivityStep) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(9.dp)
    ) {
        when (step.status) {
            ToolActivityStep.Status.running -> {
                CircularProgressIndicator(
                    modifier = Modifier
                        .padding(top = 2.dp)
                        .size(14.dp),
                    strokeWidth = 1.5.dp
                )
            }
            ToolActivityStep.Status.completed -> {
                Icon(
                    imageVector = Icons.Default.CheckCircle,
                    contentDescription = null,
                    modifier = Modifier.size(16.dp),
                    tint = MaterialTheme.colorScheme.primary
                )
            }
            ToolActivityStep.Status.failed -> {
                Icon(
                    imageVector = Icons.Default.Error,
                    contentDescription = null,
                    modifier = Modifier.size(16.dp),
                    tint = MaterialTheme.colorScheme.error
                )
            }
        }
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = step.title,
                style = MaterialTheme.typography.labelMedium,
                fontWeight = FontWeight.SemiBold
            )
            Text(
                text = step.detail,
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 3,
                overflow = TextOverflow.Ellipsis
            )
            step.resultCount?.let { count ->
                Text(
                    text = "${count}件の結果",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            step.errorMessage?.takeIf { it.isNotBlank() }?.let { error ->
                Text(
                    text = error,
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.error
                )
            }
            step.artifactNames?.takeIf { it.isNotEmpty() }?.let { names ->
                Text(
                    text = "生成ファイル: ${names.joinToString(", ")}",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.primary
                )
            }
        }
    }
}

@Composable
private fun ToolSourcesList(sources: List<ToolSource>) {
    val context = LocalContext.current
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text(
            text = "出典",
            style = MaterialTheme.typography.labelMedium,
            fontWeight = FontWeight.SemiBold,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        sources.forEachIndexed { index, source ->
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable {
                        runCatching {
                            context.startActivity(
                                Intent(Intent.ACTION_VIEW, Uri.parse(source.url))
                            )
                        }
                    },
                verticalAlignment = Alignment.Top
            ) {
                Text(
                    text = "[${index + 1}]",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.primary
                )
                Spacer(modifier = Modifier.width(6.dp))
                Text(
                    text = source.title.ifBlank { source.url },
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.primary,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f)
                )
                Icon(
                    imageVector = Icons.AutoMirrored.Filled.OpenInNew,
                    contentDescription = null,
                    modifier = Modifier.size(12.dp),
                    tint = MaterialTheme.colorScheme.primary
                )
            }
        }
        Spacer(modifier = Modifier.height(2.dp))
    }
}

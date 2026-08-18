package com.porarri.yamabikochat.ui.fusion

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CallMerge
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import com.porarri.yamabikochat.data.fusion.FusionTrace
import com.porarri.yamabikochat.ui.chat.ToolActivityDisclosure

@Composable
fun FusionMessageSummary(
    trace: FusionTrace,
    onShowDetails: () -> Unit,
    modifier: Modifier = Modifier
) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        val toolSteps = trace.panelResults.mapNotNull { it.toolActivity }.flatMap { it.steps }
        if (toolSteps.isNotEmpty()) ToolActivityDisclosure(steps = toolSteps)
        Surface(
        modifier = modifier
            .fillMaxWidth()
            .clickable(onClick = onShowDetails),
        color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.55f),
        shape = RoundedCornerShape(12.dp)
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 12.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Icon(
                imageVector = Icons.Default.CallMerge,
                contentDescription = null,
                tint = Color(0xFF10B981)
            )
            Spacer(modifier = Modifier.width(8.dp))
            Text(
                text = FusionTracePresentation.summaryLine(trace),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.weight(1f),
                maxLines = 2
            )
            TextButton(onClick = onShowDetails) {
                Text("詳細")
            }
        }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FusionDetailSheet(
    trace: FusionTrace,
    onDismiss: () -> Unit
) {
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 8.dp)
                .verticalScroll(rememberScrollState())
                .padding(bottom = 32.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Text("Fusion 詳細", style = MaterialTheme.typography.titleMedium)
            Text("Status: ${trace.status}", style = MaterialTheme.typography.bodyMedium)
            trace.totalLatencyMs?.let {
                Text("Latency: ${FusionTracePresentation.formatLatency(it)}")
            }
            FusionTracePresentation.formatCost(trace.totalCost)?.let {
                Text("Cost: $it")
            }
            if (trace.failedModels.isNotEmpty()) {
                Text(
                    "Failed models: ${trace.failedModels.joinToString { FusionTracePresentation.shortModelLabel(it) }}"
                )
            }
            trace.judgeResult?.analysis?.let { analysis ->
                Text(
                    "Recommended: ${analysis.recommendedFinalPosition}",
                    style = MaterialTheme.typography.bodyMedium
                )
                Text(
                    "Confidence: ${FusionTracePresentation.confidenceLabel(analysis.confidence)}"
                )
            }
            Text("Panels", style = MaterialTheme.typography.titleSmall)
            trace.panelResults.forEach { panel ->
                Text(
                    "${FusionTracePresentation.shortModelLabel(panel.modelId)} · " +
                        "${if (panel.success) "OK" else "FAIL"} · " +
                        FusionTracePresentation.formatLatency(panel.latencyMs)
                )
                panel.toolActivity?.steps?.takeIf { it.isNotEmpty() }?.let {
                    ToolActivityDisclosure(steps = it)
                }
            }
        }
    }
}

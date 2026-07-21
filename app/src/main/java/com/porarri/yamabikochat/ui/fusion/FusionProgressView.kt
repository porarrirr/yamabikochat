package com.porarri.yamabikochat.ui.fusion

import androidx.compose.foundation.border
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CallMerge
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Error
import androidx.compose.material.icons.filled.GridView
import androidx.compose.material.icons.filled.Balance
import androidx.compose.material.icons.filled.Undo
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import com.porarri.yamabikochat.data.fusion.FusionPanelChipState
import com.porarri.yamabikochat.data.fusion.FusionPanelChipStatus
import com.porarri.yamabikochat.data.fusion.FusionPhase
import com.porarri.yamabikochat.data.fusion.FusionProgressSnapshot

@Composable
fun FusionProgressView(
    snapshot: FusionProgressSnapshot,
    modifier: Modifier = Modifier
) {
    val phaseColor = when (snapshot.phase) {
        FusionPhase.panel -> Color(0xFF3B82F6)
        FusionPhase.judge -> Color(0xFF8B5CF6)
        FusionPhase.synthesizer -> Color(0xFF10B981)
        FusionPhase.fallback -> Color(0xFFF59E0B)
    }
    Column(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = 10.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            if (snapshot.phase == FusionPhase.panel &&
                snapshot.completedPanelCount < snapshot.totalPanelCount
            ) {
                CircularProgressIndicator(
                    modifier = Modifier.size(16.dp),
                    strokeWidth = 2.dp,
                    color = phaseColor
                )
            } else {
                Icon(
                    imageVector = when (snapshot.phase) {
                        FusionPhase.panel -> Icons.Default.GridView
                        FusionPhase.judge -> Icons.Default.Balance
                        FusionPhase.synthesizer -> Icons.Default.CallMerge
                        FusionPhase.fallback -> Icons.Default.Undo
                    },
                    contentDescription = null,
                    modifier = Modifier.size(16.dp),
                    tint = phaseColor
                )
            }
            Spacer(modifier = Modifier.width(6.dp))
            Column {
                Text(
                    text = FusionTracePresentation.progressPhaseTitle(snapshot),
                    style = MaterialTheme.typography.labelMedium,
                    color = phaseColor
                )
                snapshot.substatus?.takeIf { it.isNotBlank() }?.let {
                    Text(
                        text = it,
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
        }
        if (snapshot.panels.isNotEmpty()) {
            Row(
                modifier = Modifier.horizontalScroll(rememberScrollState()),
                horizontalArrangement = Arrangement.spacedBy(6.dp)
            ) {
                snapshot.panels.forEach { panel ->
                    FusionPanelChip(panel = panel)
                }
            }
        }
    }
}

@Composable
private fun FusionPanelChip(panel: FusionPanelChipStatus) {
    val bg = when (panel.state) {
        FusionPanelChipState.failed -> Color.Red.copy(alpha = 0.08f)
        FusionPanelChipState.succeeded -> Color.Green.copy(alpha = 0.08f)
        else -> MaterialTheme.colorScheme.onSurface.copy(alpha = 0.08f)
    }
    val border = when (panel.state) {
        FusionPanelChipState.failed -> Color.Red.copy(alpha = 0.25f)
        FusionPanelChipState.succeeded -> Color.Green.copy(alpha = 0.25f)
        else -> MaterialTheme.colorScheme.onSurface.copy(alpha = 0.18f)
    }
    Surface(
        color = bg,
        shape = RoundedCornerShape(50),
        modifier = Modifier.border(1.dp, border, RoundedCornerShape(50))
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 8.dp, vertical = 5.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(4.dp)
        ) {
            when (panel.state) {
                FusionPanelChipState.pending, FusionPanelChipState.running ->
                    CircularProgressIndicator(modifier = Modifier.size(12.dp), strokeWidth = 1.5.dp)
                FusionPanelChipState.succeeded ->
                    Icon(Icons.Default.CheckCircle, null, Modifier.size(12.dp), tint = Color(0xFF16A34A))
                FusionPanelChipState.failed ->
                    Icon(Icons.Default.Error, null, Modifier.size(12.dp), tint = Color(0xFFDC2626))
            }
            Text(
                text = FusionTracePresentation.shortModelLabel(panel.modelId),
                style = MaterialTheme.typography.labelSmall,
                maxLines = 1
            )
        }
    }
}

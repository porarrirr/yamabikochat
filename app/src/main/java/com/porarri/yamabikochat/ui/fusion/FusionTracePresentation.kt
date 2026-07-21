package com.porarri.yamabikochat.ui.fusion

import com.porarri.yamabikochat.data.fusion.FusionConfidence
import com.porarri.yamabikochat.data.fusion.FusionPhase
import com.porarri.yamabikochat.data.fusion.FusionProgressSnapshot
import com.porarri.yamabikochat.data.fusion.FusionTrace

object FusionTracePresentation {
    fun shortModelLabel(model: String): String {
        val trimmed = model.trim()
        if (trimmed.isEmpty()) return trimmed
        val slash = trimmed.lastIndexOf('/')
        if (slash >= 0 && slash < trimmed.lastIndex) {
            return trimmed.substring(slash + 1)
        }
        return if (trimmed.length > 24) trimmed.take(22) + "…" else trimmed
    }

    fun confidenceLabel(confidence: FusionConfidence): String = when (confidence) {
        FusionConfidence.low -> "低信頼"
        FusionConfidence.medium -> "中信頼"
        FusionConfidence.high -> "高信頼"
    }

    fun phaseLabel(phase: FusionPhase): String = when (phase) {
        FusionPhase.panel -> "パネル"
        FusionPhase.judge -> "ジャッジ"
        FusionPhase.synthesizer -> "合成"
        FusionPhase.fallback -> "フォールバック"
    }

    fun progressPhaseTitle(snapshot: FusionProgressSnapshot): String = when (snapshot.phase) {
        FusionPhase.panel ->
            "パネル実行中 (${snapshot.completedPanelCount}/${snapshot.totalPanelCount})"
        FusionPhase.judge -> "ジャッジ中"
        FusionPhase.synthesizer -> "回答を合成中"
        FusionPhase.fallback -> "フォールバックで回答中"
    }

    fun summaryLine(forTrace: FusionTrace): String {
        val successCount = forTrace.panelResults.count { it.success }
        val totalPanels = forTrace.panelResults.size
        val parts = mutableListOf("Fusion · $successCount/$totalPanels panels")
        forTrace.judgeResult?.analysis?.let {
            parts.add(confidenceLabel(it.confidence))
        }
        forTrace.totalLatencyMs?.let { parts.add(formatLatency(it)) }
        forTrace.totalCost?.let { parts.add(String.format("$%.4f", it)) }
        return parts.joinToString(" · ")
    }

    fun formatLatency(ms: Long): String {
        if (ms < 1_000) return "$ms ms"
        return String.format("%.1f s", ms / 1000.0)
    }

    fun formatCost(cost: Double?): String? =
        cost?.let { String.format("$%.4f", it) }
}

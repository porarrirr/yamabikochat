package com.porarri.yamabikochat.data.fusion

import com.porarri.yamabikochat.data.local.FusionTraceRecord
import com.porarri.yamabikochat.data.local.Settings
import com.porarri.yamabikochat.utils.DiagnosticsLogger
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

class FusionTraceStore(
    private val saveRecord: suspend (FusionTraceRecord) -> Unit,
    private val loadRecord: suspend (String) -> FusionTraceRecord?
) {
    private val json = Json {
        ignoreUnknownKeys = true
        encodeDefaults = true
    }

    suspend fun save(trace: FusionTrace, conversationId: Long?) {
        val failedModelsJSON = runCatching {
            json.encodeToString(trace.failedModels)
        }.getOrDefault("[]")
        val traceJSON = runCatching {
            json.encodeToString(FusionTrace.serializer(), trace)
        }.getOrDefault("{}")
        saveRecord(
            FusionTraceRecord(
                id = trace.requestId,
                conversationId = conversationId,
                preset = trace.preset,
                startedAtMs = trace.startedAtMs,
                completedAtMs = trace.completedAtMs,
                totalLatencyMs = trace.totalLatencyMs,
                totalCostUsd = trace.totalCost,
                failedModelsJSON = failedModelsJSON,
                traceJSON = traceJSON,
                status = trace.status
            )
        )
        logTraceSummary(trace, conversationId)
    }

    suspend fun fetch(id: String): FusionTrace? {
        val record = loadRecord(id) ?: return null
        return runCatching {
            json.decodeFromString(FusionTrace.serializer(), record.traceJSON)
        }.getOrNull()
    }

    private fun logTraceSummary(trace: FusionTrace, conversationId: Long?) {
        val metadata = mutableMapOf(
            "traceId" to trace.requestId,
            "preset" to trace.preset,
            "status" to trace.status,
            "panelCount" to trace.panelResults.size.toString(),
            "failedCount" to trace.failedModels.size.toString()
        )
        if (conversationId != null) {
            metadata["conversationId"] = conversationId.toString()
        }
        trace.totalLatencyMs?.let { metadata["totalLatencyMs"] = it.toString() }
        trace.totalCost?.let { metadata["totalCostUsd"] = String.format("%.6f", it) }
        trace.judgeResult?.let { metadata["judgeParseSucceeded"] = it.parseSucceeded.toString() }
        for (panel in trace.panelResults) {
            metadata["panel.${panel.modelId}.success"] = panel.success.toString()
            metadata["panel.${panel.modelId}.latencyMs"] = panel.latencyMs.toString()
        }
        DiagnosticsLogger.log(
            "Fusion trace saved traceId=${trace.requestId} status=${trace.status} panels=${trace.panelResults.size}"
        )
    }
}

fun Settings.toFusionContext(conversationId: Long?): FusionContext =
    FusionContext(
        fusionDepth = 0,
        debugMode = fusionDebugModeEnabled,
        logPrompts = fusionLogPromptsEnabled,
        conversationId = conversationId
    )

package com.porarri.yamabikochat.data.fusion

import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

typealias FusionPanelInvoke =
    suspend (FusionPanelRunner.GenerateRequestBundle, FusionPhase) -> FusionInvokeResult
typealias FusionPanelCostEstimator =
    suspend (provider: String, model: String, inputTokens: Int?, outputTokens: Int?) -> Double?
typealias FusionPanelProgressHandler = (FusionProgressSnapshot) -> Unit
typealias FusionPanelRequestBuilder =
    suspend (PanelModelConfig, String) -> FusionPanelRunner.GenerateRequestBundle

object FusionPanelRunner {
    data class GenerateRequestBundle(
        val model: String,
        val provider: String,
        val request: com.porarri.yamabikochat.data.remote.GenerateContentRequest
    )

    suspend fun runAll(
        request: FusionRequest,
        panelSystemPrompt: String,
        buildPanelRequest: FusionPanelRequestBuilder,
        invoke: FusionPanelInvoke,
        estimateCost: FusionPanelCostEstimator,
        onProgress: FusionPanelProgressHandler? = null
    ): List<PanelResult> = coroutineScope {
        var chipPanels = FusionProgressSnapshot.initialPanels(from = request)
        onProgress?.invoke(FusionProgressSnapshot.panelPhase(panels = chipPanels))
        val mutex = Mutex()

        request.panelModels.map { panel ->
            async {
                val result = runSingle(
                    panel = panel,
                    panelSystemPrompt = panelSystemPrompt,
                    buildPanelRequest = buildPanelRequest,
                    invoke = invoke,
                    estimateCost = estimateCost
                )
                mutex.withLock {
                    val snapshot = FusionProgressSnapshot.panelPhase(panels = chipPanels)
                        .applyingPanelResult(result)
                    chipPanels = snapshot.panels
                    onProgress?.invoke(snapshot)
                }
                result
            }
        }.awaitAll()
    }

    private suspend fun runSingle(
        panel: PanelModelConfig,
        panelSystemPrompt: String,
        buildPanelRequest: FusionPanelRequestBuilder,
        invoke: FusionPanelInvoke,
        estimateCost: FusionPanelCostEstimator
    ): PanelResult {
        val started = System.currentTimeMillis()
        return try {
            val bundle = buildPanelRequest(panel, panelSystemPrompt)
            val response = invoke(bundle, FusionPhase.panel)
            val latencyMs = System.currentTimeMillis() - started
            val cost = estimateCost(
                panel.provider,
                panel.modelId,
                response.inputTokens,
                response.outputTokens
            )
            PanelResult(
                modelId = panel.modelId,
                provider = panel.provider.uppercase(),
                success = true,
                content = response.text,
                error = null,
                latencyMs = latencyMs,
                inputTokens = response.inputTokens,
                outputTokens = response.outputTokens,
                cost = cost,
                toolCalls = response.toolCalls?.map { it.toSerializable() },
                finishReason = null,
                role = panel.role
            )
        } catch (e: Exception) {
            val latencyMs = System.currentTimeMillis() - started
            PanelResult(
                modelId = panel.modelId,
                provider = panel.provider.uppercase(),
                success = false,
                content = "",
                error = e.message ?: e.toString(),
                latencyMs = latencyMs,
                inputTokens = null,
                outputTokens = null,
                cost = null,
                toolCalls = null,
                finishReason = null,
                role = panel.role
            )
        }
    }
}

data class FusionInvokeResult(
    val text: String,
    val inputTokens: Int? = null,
    val outputTokens: Int? = null,
    val toolCalls: List<com.porarri.yamabikochat.data.tools.ToolCall>? = null
)

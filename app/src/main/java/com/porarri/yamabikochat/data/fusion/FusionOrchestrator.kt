package com.porarri.yamabikochat.data.fusion

import com.porarri.yamabikochat.data.model.ProviderRequest
import com.porarri.yamabikochat.data.model.ProviderRequestMessage
import com.porarri.yamabikochat.data.model.ProviderResponse
import com.porarri.yamabikochat.data.model.ProviderUsage
import java.util.UUID

typealias FusionOrchestratorInvoke =
    suspend (FusionPanelRunner.GenerateRequestBundle, FusionPhase, (com.porarri.yamabikochat.data.local.ToolActivityPayload) -> Unit) -> ProviderResponse
typealias FusionOrchestratorCostEstimator =
    suspend (provider: String, model: String, usage: ProviderUsage?) -> Double?
typealias FusionOrchestratorRequestBuilder = suspend (
    model: PanelModelConfig,
    systemPrompt: String,
    phase: FusionPhase,
    allowTools: Boolean,
    maxTokens: Int
) -> ProviderRequest
typealias FusionOrchestratorProgressHandler = (FusionProgressSnapshot) -> Unit

class FusionOrchestrator {
    suspend fun runThroughJudge(
        request: FusionRequest,
        context: FusionContext,
        buildRequest: FusionOrchestratorRequestBuilder,
        invoke: FusionOrchestratorInvoke,
        estimateCost: FusionOrchestratorCostEstimator,
        onProgress: FusionOrchestratorProgressHandler? = null
    ): FusionJudgeOutcome {
        val requestId = UUID.randomUUID().toString()
        val startedAtMs = System.currentTimeMillis()

        if (context.fusionDepth >= FusionContext.MAX_FUSION_DEPTH) {
            return runRecursionFallback(
                request = request,
                context = context,
                requestId = requestId,
                startedAtMs = startedAtMs,
                buildRequest = buildRequest,
                invoke = invoke,
                estimateCost = estimateCost
            )
        }

        val panelResults = FusionPanelRunner.runAll(
            request = request,
            panelSystemPrompt = FusionPrompts.panelSystemPrompt(request.taskType),
            buildPanelRequest = { panel, systemPrompt ->
                val genRequest = buildRequest(
                    panel,
                    systemPrompt,
                    FusionPhase.panel,
                    request.allowWebSearch,
                    request.maxPanelTokens
                )
                FusionPanelRunner.GenerateRequestBundle(
                    model = panel.modelId,
                    provider = panel.provider.uppercase(),
                    request = genRequest
                )
            },
            invoke = invoke,
            estimateCost = estimateCost,
            onProgress = onProgress
        )

        val successfulPanels = panelResults.filter { it.success }
        val failedModels = panelResults.filter { !it.success }.map { it.modelId }

        if (successfulPanels.isEmpty()) {
            throw FusionError.AllPanelsFailed(panelResults)
        }

        val finalPanelChips = panelResults.map { result ->
            FusionPanelChipStatus(
                modelId = result.modelId,
                provider = result.provider,
                state = if (result.success) FusionPanelChipState.succeeded else FusionPanelChipState.failed
            )
        }
        onProgress?.invoke(FusionProgressSnapshot.phaseOnly(FusionPhase.judge, finalPanelChips))

        val judgeOutcome = runJudge(
            request = request,
            successfulPanels = successfulPanels,
            failedModels = failedModels,
            buildRequest = buildRequest,
            invoke = invoke,
            estimateCost = estimateCost
        )

        val judgeAnalysis = judgeOutcome.analysis
        val synthesisUserPrompt = if (judgeAnalysis != null) {
            FusionPrompts.synthesizerUserPrompt(
                userPrompt = request.userPrompt,
                judgeAnalysis = judgeAnalysis,
                rawPanels = successfulPanels,
                judgeParseFailed = !judgeOutcome.parseSucceeded
            )
        } else {
            FusionPrompts.synthesizerUserPromptWithoutJudge(
                userPrompt = request.userPrompt,
                rawPanels = successfulPanels
            )
        }

        val synthSystemPrompt = FusionPrompts.synthesizerSystemPrompt(debugMode = context.debugMode)
        val mergedSystem = mergeSystemPrompts(request.systemPrompt, synthSystemPrompt)
        val synthesisRequest = buildRequest(
            request.synthesizerModel,
            synthSystemPrompt,
            FusionPhase.synthesizer,
            false,
            4096
        ).copy(
            messages = listOf(
                ProviderRequestMessage(role = "user", content = synthesisUserPrompt)
            ),
            systemPrompt = mergedSystem
        )

        val staticFallback = buildStaticFallback(
            judgeAnalysis = judgeAnalysis,
            judgeRaw = judgeOutcome.rawJSON,
            panels = successfulPanels
        )

        val trace = FusionTrace(
            requestId = requestId,
            preset = request.preset,
            startedAtMs = startedAtMs,
            completedAtMs = null,
            panelResults = panelResults,
            judgeResult = judgeOutcome,
            synthesisResult = null,
            totalLatencyMs = null,
            totalCost = sumCosts(panelResults = panelResults, judge = judgeOutcome, synthesis = null),
            failedModels = failedModels,
            status = "judge_complete",
            userPrompt = if (context.logPrompts) request.userPrompt else null,
            finalAnswer = null
        )

        val panelUsages = panelResults.mapNotNull { panel ->
            if (!panel.success) return@mapNotNull null
            val usage = tokenUsageOrNull(panel.inputTokens, panel.outputTokens)
            val requestType = "fusion_panel_${sanitizedModelId(panel.modelId)}"
            FusionTokenUsageRecord(panel.provider, panel.modelId, usage, requestType)
        }

        val judgeUsage = if (judgeOutcome.parseSucceeded || judgeOutcome.rawJSON != null) {
            FusionTokenUsageRecord(
                provider = request.judgeModel.provider.uppercase(),
                model = request.judgeModel.modelId,
                usage = tokenUsageOrNull(judgeOutcome.inputTokens, judgeOutcome.outputTokens),
                requestType = "fusion_judge"
            )
        } else {
            null
        }

        onProgress?.invoke(FusionProgressSnapshot.phaseOnly(FusionPhase.synthesizer, finalPanelChips))

        return FusionJudgeOutcome(
            trace = trace,
            synthesisRequest = synthesisRequest,
            synthesizerProvider = request.synthesizerModel.provider.uppercase(),
            synthesizerModel = request.synthesizerModel,
            staticFallbackAnswer = staticFallback,
            panelTokenUsages = panelUsages,
            judgeTokenUsage = judgeUsage
        )
    }

    fun finalizeTrace(
        trace: FusionTrace,
        synthesisResult: SynthesisPhaseResult,
        finalAnswer: String,
        logPrompts: Boolean
    ): FusionTrace {
        val completedAtMs = System.currentTimeMillis()
        return trace.copy(
            synthesisResult = synthesisResult,
            completedAtMs = completedAtMs,
            totalLatencyMs = completedAtMs - trace.startedAtMs,
            totalCost = sumCosts(
                panelResults = trace.panelResults,
                judge = trace.judgeResult,
                synthesis = synthesisResult
            ),
            status = if (synthesisResult.success) "completed" else "synthesis_fallback",
            finalAnswer = if (logPrompts) finalAnswer else null
        )
    }

    fun buildStaticFallback(
        judgeAnalysis: JudgeAnalysis?,
        judgeRaw: String?,
        panels: List<PanelResult>
    ): String = Companion.buildStaticFallback(judgeAnalysis, judgeRaw, panels)

    private suspend fun runJudge(
        request: FusionRequest,
        successfulPanels: List<PanelResult>,
        failedModels: List<String>,
        buildRequest: FusionOrchestratorRequestBuilder,
        invoke: FusionOrchestratorInvoke,
        estimateCost: FusionOrchestratorCostEstimator
    ): JudgePhaseResult {
        val started = System.currentTimeMillis()
        val judgeUserContent = FusionPrompts.judgeUserPrompt(
            userPrompt = request.userPrompt,
            successfulPanels = successfulPanels,
            failedModels = failedModels
        )

        suspend fun makeJudgeRequest(systemPrompt: String, userContent: String): FusionPanelRunner.GenerateRequestBundle {
            val base = buildRequest(
                request.judgeModel,
                systemPrompt,
                FusionPhase.judge,
                false,
                4096
            )
            val provider = request.judgeModel.provider.uppercase()
            return FusionPanelRunner.GenerateRequestBundle(
                model = request.judgeModel.modelId,
                provider = provider,
                request = base.copy(
                    messages = listOf(
                        ProviderRequestMessage(role = "user", content = userContent)
                    )
                )
            )
        }

        return try {
            val response = invoke(
                makeJudgeRequest(FusionPrompts.judgeSystemPrompt(), judgeUserContent),
                FusionPhase.judge,
                {}
            )
            val latencyMs = System.currentTimeMillis() - started
            val cost = estimateCost(
                request.judgeModel.provider,
                request.judgeModel.modelId,
                response.usage
            )

            val parsed = FusionJudgeParser.parse(response.text)
            if (parsed != null) {
                return JudgePhaseResult(
                    analysis = parsed,
                    rawJSON = response.text,
                    parseSucceeded = true,
                    latencyMs = latencyMs,
                    inputTokens = response.usage?.inputTokens,
                    outputTokens = response.usage?.outputTokens,
                    cost = cost,
                    error = null
                )
            }

            val repairStarted = System.currentTimeMillis()
            val repairResponse = invoke(
                makeJudgeRequest(
                    FusionPrompts.judgeSystemPrompt(),
                    FusionPrompts.jsonRepairPrompt(invalidJSON = response.text)
                ),
                FusionPhase.judge,
                {}
            )
            val repairLatency = System.currentTimeMillis() - repairStarted
            val repairCost = estimateCost(
                request.judgeModel.provider,
                request.judgeModel.modelId,
                repairResponse.usage
            )
            val repaired = FusionJudgeParser.parse(repairResponse.text)
            if (repaired != null) {
                return JudgePhaseResult(
                    analysis = repaired,
                    rawJSON = repairResponse.text,
                    parseSucceeded = true,
                    latencyMs = repairLatency,
                    inputTokens = repairResponse.usage?.inputTokens,
                    outputTokens = repairResponse.usage?.outputTokens,
                    cost = (cost ?: 0.0) + (repairCost ?: 0.0),
                    error = null
                )
            }

            JudgePhaseResult(
                analysis = null,
                rawJSON = repairResponse.text,
                parseSucceeded = false,
                latencyMs = repairLatency,
                inputTokens = repairResponse.usage?.inputTokens,
                outputTokens = repairResponse.usage?.outputTokens,
                cost = (cost ?: 0.0) + (repairCost ?: 0.0),
                error = "Judge JSON parse failed"
            )
        } catch (e: Exception) {
            JudgePhaseResult(
                analysis = null,
                rawJSON = null,
                parseSucceeded = false,
                latencyMs = System.currentTimeMillis() - started,
                inputTokens = null,
                outputTokens = null,
                cost = null,
                error = e.message ?: e.toString()
            )
        }
    }

    private suspend fun runRecursionFallback(
        request: FusionRequest,
        context: FusionContext,
        requestId: String,
        startedAtMs: Long,
        buildRequest: FusionOrchestratorRequestBuilder,
        invoke: FusionOrchestratorInvoke,
        estimateCost: FusionOrchestratorCostEstimator
    ): FusionJudgeOutcome {
        val fallback = request.synthesizerModel
        val genRequest = buildRequest(
            fallback,
            request.systemPrompt.orEmpty(),
            FusionPhase.fallback,
            false,
            4096
        ).copy(
            messages = listOf(
                ProviderRequestMessage(role = "user", content = request.userPrompt)
            )
        )
        val bundle = FusionPanelRunner.GenerateRequestBundle(
            model = fallback.modelId,
            provider = fallback.provider.uppercase(),
            request = genRequest
        )
        val started = System.currentTimeMillis()
        val response = invoke(bundle, FusionPhase.fallback) {}
        val latencyMs = System.currentTimeMillis() - started
        val cost = estimateCost(fallback.provider, fallback.modelId, response.usage)

        val synthesisResult = SynthesisPhaseResult(
            modelId = fallback.modelId,
            provider = fallback.provider.uppercase(),
            success = true,
            content = response.text,
            latencyMs = latencyMs,
            inputTokens = response.usage?.inputTokens,
            outputTokens = response.usage?.outputTokens,
            cost = cost,
            error = null,
            usedFallback = true
        )
        val trace = FusionTrace(
            requestId = requestId,
            preset = request.preset,
            startedAtMs = startedAtMs,
            completedAtMs = System.currentTimeMillis(),
            panelResults = emptyList(),
            judgeResult = null,
            synthesisResult = synthesisResult,
            totalLatencyMs = latencyMs,
            totalCost = cost,
            failedModels = emptyList(),
            status = "recursion_fallback",
            userPrompt = if (context.logPrompts) request.userPrompt else null,
            finalAnswer = if (context.logPrompts) response.text else null
        )

        return FusionJudgeOutcome(
            trace = trace,
            synthesisRequest = genRequest,
            synthesizerProvider = fallback.provider.uppercase(),
            synthesizerModel = fallback,
            staticFallbackAnswer = response.text,
            panelTokenUsages = emptyList(),
            judgeTokenUsage = null
        )
    }

    companion object {
        fun buildStaticFallback(
            judgeAnalysis: JudgeAnalysis?,
            judgeRaw: String?,
            panels: List<PanelResult>
        ): String {
            val sections = mutableListOf<String>()
            if (judgeAnalysis != null) {
                when {
                    judgeAnalysis.recommendedFinalPosition.isNotEmpty() ->
                        sections.add(judgeAnalysis.recommendedFinalPosition)
                    judgeAnalysis.consensus.isNotEmpty() ->
                        sections.add(judgeAnalysis.consensus.joinToString("\n"))
                }
            } else if (!judgeRaw.isNullOrEmpty()) {
                sections.add(judgeRaw)
            }
            val best = panels.filter { it.success }.minByOrNull { it.latencyMs }
            if (best != null && best.content.isNotEmpty()) {
                sections.add(best.content)
            }
            return sections.joinToString("\n\n").trim()
        }

        fun sanitizedModelId(modelId: String): String {
            val trimmed = modelId.trim()
            val replaced = trimmed
                .replace("/", "_")
                .replace(":", "_")
                .replace(" ", "_")
            return replaced.ifEmpty { "unknown" }
        }

        fun sumCosts(
            panelResults: List<PanelResult>,
            judge: JudgePhaseResult?,
            synthesis: SynthesisPhaseResult?
        ): Double? {
            var total = 0.0
            var hasCost = false
            for (panel in panelResults) {
                val cost = panel.cost
                if (cost != null) {
                    total += cost
                    hasCost = true
                }
            }
            judge?.cost?.let {
                total += it
                hasCost = true
            }
            synthesis?.cost?.let {
                total += it
                hasCost = true
            }
            return if (hasCost) total else null
        }

        fun mergeSystemPrompts(conversation: String?, fusion: String): String? {
            val left = conversation?.trim().orEmpty()
            val right = fusion.trim()
            return when {
                left.isEmpty() && right.isEmpty() -> null
                left.isEmpty() -> right
                right.isEmpty() -> left
                else -> "$left\n\n$right"
            }
        }

        fun tokenUsageOrNull(input: Int?, output: Int?): ProviderUsage? {
            if (input == null && output == null) return null
            return ProviderUsage(
                inputTokens = input ?: 0,
                outputTokens = output ?: 0,
                totalTokens = (input ?: 0) + (output ?: 0)
            ).normalizedNonEmpty()
        }
    }
}

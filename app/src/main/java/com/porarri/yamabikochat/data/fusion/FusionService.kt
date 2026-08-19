package com.porarri.yamabikochat.data.fusion

import com.porarri.yamabikochat.data.local.Settings
import com.porarri.yamabikochat.data.local.ToolActivityPayload
import com.porarri.yamabikochat.data.model.LLMProvider
import com.porarri.yamabikochat.data.model.ProviderRequest
import com.porarri.yamabikochat.data.model.ProviderRequestMessage
import com.porarri.yamabikochat.data.model.ProviderResponse
import com.porarri.yamabikochat.data.model.ProviderStreamEvent
import com.porarri.yamabikochat.data.model.ProviderUsage
import com.porarri.yamabikochat.data.modelsdev.ProviderReference
import com.porarri.yamabikochat.data.repositories.ProviderGateway
import com.porarri.yamabikochat.data.repositories.ProviderRequestSettingsResolver
import com.porarri.yamabikochat.data.repositories.ProviderRequestToolScope
import com.porarri.yamabikochat.data.skills.AgentSkillPromptComposer
import com.porarri.yamabikochat.data.skills.AgentSkillRepository
import com.porarri.yamabikochat.data.skills.SkillRequestContext
import kotlinx.coroutines.flow.Flow

class FusionService(
    private val settingsProvider: suspend () -> Settings,
    private val providerGateway: ProviderGateway,
    private val estimateCost: suspend (provider: String, model: String, usage: ProviderUsage?) -> Double? = { _, _, _ -> null },
    private val modelSupportsVision: suspend (provider: String, model: String) -> Boolean = { _, _ -> false },
    private val traceStore: FusionTraceStore? = null,
    private val requestSettingsResolver: ProviderRequestSettingsResolver,
    private val skillRepository: AgentSkillRepository? = null,
    private val orchestrator: FusionOrchestrator = FusionOrchestrator()
) {
    suspend fun runFusion(
        userPrompt: String,
        options: FusionRunOptions = FusionRunOptions()
    ): FusionRunResult {
        val settings = settingsProvider()
        val allowWebSearch = options.allowWebSearch ?: settings.clientWebSearchToolEnabled
        val request = FusionPresetLoader.buildRequest(
            userPrompt = userPrompt,
            systemPrompt = options.systemPrompt,
            taskTypeOverride = options.taskType,
            allowWebSearchOverride = if (allowWebSearch) null else false,
            customPresetJSON = settings.fusionCustomPresetJSON
        )
        val context = FusionContext(
            fusionDepth = options.fusionDepth,
            debugMode = options.debugMode,
            logPrompts = options.logPrompts,
            conversationId = options.conversationId
        )

        val outcome = runThroughJudge(
            request = request,
            context = context,
            conversationHistory = emptyList(),
            userAttachments = emptyList()
        )

        val synthStarted = System.currentTimeMillis()
        return try {
            val response = invoke(
                request = outcome.synthesisRequest,
                provider = outcome.synthesizerProvider,
                phase = FusionPhase.synthesizer
            )
            val latencyMs = System.currentTimeMillis() - synthStarted
            val cost = estimateCost(
                outcome.synthesizerModel.provider,
                outcome.synthesizerModel.modelId,
                response.usage
            )
            val synthesisResult = SynthesisPhaseResult(
                modelId = outcome.synthesizerModel.modelId,
                provider = outcome.synthesizerModel.provider.uppercase(),
                success = true,
                content = response.text,
                latencyMs = latencyMs,
                inputTokens = response.usage?.inputTokens,
                outputTokens = response.usage?.outputTokens,
                cost = cost,
                error = null,
                usedFallback = false
            )
            val trace = orchestrator.finalizeTrace(
                trace = outcome.trace,
                synthesisResult = synthesisResult,
                finalAnswer = response.text,
                logPrompts = context.logPrompts
            )
            traceStore?.save(trace, context.conversationId)
            FusionRunResult(
                finalAnswer = response.text,
                traceId = trace.requestId,
                judgeAnalysis = if (options.debugMode) trace.judgeResult?.analysis else null,
                rawPanelResults = if (options.debugMode) trace.panelResults else null,
                totalLatencyMs = trace.totalLatencyMs,
                totalCost = trace.totalCost
            )
        } catch (e: Exception) {
            val fallback = outcome.staticFallbackAnswer
            val synthesisResult = SynthesisPhaseResult(
                modelId = outcome.synthesizerModel.modelId,
                provider = outcome.synthesizerModel.provider.uppercase(),
                success = false,
                content = fallback,
                latencyMs = System.currentTimeMillis() - synthStarted,
                inputTokens = null,
                outputTokens = null,
                cost = null,
                error = e.message ?: e.toString(),
                usedFallback = true
            )
            val trace = orchestrator.finalizeTrace(
                trace = outcome.trace,
                synthesisResult = synthesisResult,
                finalAnswer = fallback,
                logPrompts = context.logPrompts
            )
            traceStore?.save(trace, context.conversationId)
            FusionRunResult(
                finalAnswer = fallback,
                traceId = trace.requestId,
                judgeAnalysis = if (options.debugMode) trace.judgeResult?.analysis else null,
                rawPanelResults = if (options.debugMode) trace.panelResults else null,
                totalLatencyMs = trace.totalLatencyMs,
                totalCost = trace.totalCost
            )
        }
    }

    suspend fun runThroughJudge(
        request: FusionRequest,
        context: FusionContext,
        conversationHistory: List<FusionHistoryMessage>,
        userAttachments: List<String> = emptyList(),
        onProgress: FusionOrchestratorProgressHandler? = null
    ): FusionJudgeOutcome {
        val settings = settingsProvider()
        val visionSupportByModel = request.panelModels.associate { panel ->
            panel.modelId to modelSupportsVision(panel.provider, panel.modelId)
        }
        return orchestrator.runThroughJudge(
            request = request,
            context = context,
            buildRequest = { model, systemPrompt, phase, allowTools, _ ->
                buildProviderRequest(
                    model = model,
                    systemPrompt = systemPrompt,
                    phase = phase,
                    allowTools = allowTools,
                    settings = settings,
                    fusionDepth = context.fusionDepth,
                    userPrompt = request.userPrompt,
                    conversationHistory = conversationHistory.map {
                        ProviderRequestMessage(role = it.role, content = it.text, attachments = it.attachments)
                    },
                    userAttachments = userAttachments,
                    supportsVision = visionSupportByModel[model.modelId] ?: false,
                    conversationId = context.conversationId?.toString()
                )
            },
            invoke = { bundle, phase, onToolActivity ->
                invoke(
                    request = bundle.request,
                    provider = bundle.provider,
                    phase = phase,
                    onToolActivity = onToolActivity
                )
            },
            estimateCost = { provider, model, usage ->
                estimateCost(provider, model, usage)
            },
            onProgress = onProgress
        )
    }

    suspend fun buildProviderRequest(
        model: PanelModelConfig,
        systemPrompt: String,
        phase: FusionPhase,
        allowTools: Boolean,
        settings: Settings,
        fusionDepth: Int,
        userPrompt: String,
        conversationHistory: List<ProviderRequestMessage>,
        userAttachments: List<String> = emptyList(),
        supportsVision: Boolean = false,
        conversationId: String? = null
    ): ProviderRequest {
        val toolScope: ProviderRequestToolScope = if (phase == FusionPhase.panel) {
            ProviderRequestToolScope.FusionPanel(allowWebSearch = allowTools)
        } else {
            ProviderRequestToolScope.ProviderOnly
        }

        val resolvedSettings = requestSettingsResolver.resolve(
            settings = settings,
            provider = model.provider,
            model = model.modelId,
            toolScope = toolScope
        )

        val metadata = resolvedSettings.metadata.toMutableMap()
        metadata["provider"] = model.provider.uppercase()
        metadata["fusionPhase"] = phase.name
        metadata["fusionDepth"] = fusionDepth.toString()
        if (!conversationId.isNullOrBlank()) {
            metadata["promptCacheKey"] = "fusion-$conversationId"
        }
        if (phase == FusionPhase.panel) {
            metadata["supportsVision"] = if (supportsVision) "true" else "false"
        }

        var messages = if (phase == FusionPhase.panel) {
            panelMessages(
                history = conversationHistory,
                userPrompt = userPrompt,
                userAttachments = userAttachments
            )
        } else {
            conversationHistory
        }

        if (phase == FusionPhase.panel && skillRepository != null) {
            val supportsTools = resolvedSettings.metadata["supportsClientTools"] == "true"
            val applied = AgentSkillPromptComposer.apply(
                repository = skillRepository,
                messages = messages,
                conversationId = conversationId,
                clientToolsSupported = supportsTools
            )
            messages = applied.messages
        }

        return ProviderRequest(
            model = model.modelId,
            messages = messages,
            systemPrompt = systemPrompt.takeIf { it.isNotBlank() },
            stream = true,
            tools = resolvedSettings.tools,
            thinking = resolvedSettings.thinking,
            provider = resolvedSettings.routing,
            metadata = metadata
        )
    }

    private suspend fun invoke(
        request: ProviderRequest,
        provider: String,
        phase: FusionPhase,
        onToolActivity: ((ToolActivityPayload) -> Unit)? = null
    ): ProviderResponse {
        val accumulator = FusionToolActivityAccumulator()
        return providerGateway.generate(
            request = request,
            providerID = provider,
            onStreamEvent = { event ->
                if (event is ProviderStreamEvent.ToolActivity) {
                    onToolActivity?.invoke(accumulator.apply(event.event))
                }
            }
        )
    }

    suspend fun streamInvoke(
        request: ProviderRequest,
        provider: String,
        phase: FusionPhase
    ): Flow<ProviderStreamEvent> {
        return providerGateway.stream(request = request, providerID = provider)
    }

    private fun panelMessages(
        history: List<ProviderRequestMessage>,
        userPrompt: String,
        userAttachments: List<String>
    ): List<ProviderRequestMessage> {
        val result = history.toMutableList()
        val last = result.lastOrNull()
        if (last != null && last.role == "user" && last.content == userPrompt) {
            return result
        }
        result.add(
            ProviderRequestMessage(
                role = "user",
                content = userPrompt,
                attachments = userAttachments
            )
        )
        return result
    }

    fun finalizeTrace(
        trace: FusionTrace,
        synthesisResult: SynthesisPhaseResult,
        finalAnswer: String,
        logPrompts: Boolean
    ): FusionTrace = orchestrator.finalizeTrace(
        trace = trace,
        synthesisResult = synthesisResult,
        finalAnswer = finalAnswer,
        logPrompts = logPrompts
    )
}

private class FusionToolActivityAccumulator {
    private var payload = ToolActivityPayload()
    @Synchronized fun apply(event: com.porarri.yamabikochat.data.model.ToolActivityEvent): ToolActivityPayload {
        payload = payload.applying(event)
        return payload
    }
}

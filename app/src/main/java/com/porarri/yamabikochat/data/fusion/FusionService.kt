package com.porarri.yamabikochat.data.fusion

import com.porarri.yamabikochat.data.local.Settings
import com.porarri.yamabikochat.data.remote.Content
import com.porarri.yamabikochat.data.remote.GenerateContentRequest
import com.porarri.yamabikochat.data.remote.GenerateContentResponse
import com.porarri.yamabikochat.data.remote.GenerationConfig
import com.porarri.yamabikochat.data.remote.Part
import com.porarri.yamabikochat.data.remote.SystemInstruction
import com.porarri.yamabikochat.data.remote.Tool
import com.porarri.yamabikochat.data.skills.AgentSkillRepository
import com.porarri.yamabikochat.data.skills.AgentSkillTools
import com.porarri.yamabikochat.data.skills.SkillRequestContext
import com.porarri.yamabikochat.data.tools.ClientTools
import com.porarri.yamabikochat.utils.DiagnosticsLogger

class FusionService(
    private val generate: FusionGenerate,
    private val stream: FusionStream? = null,
    private val estimateCost: FusionCostEstimator = { _, _, _, _ -> null },
    private val settingsProvider: suspend () -> Settings,
    private val skillRepository: AgentSkillRepository? = null,
    private val toolRunner: ClientToolCallingRunner? = null,
    private val traceStore: FusionTraceStore? = null,
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
            val response = generate(
                outcome.synthesizerModel.modelId,
                outcome.synthesizerProvider,
                outcome.synthesisRequest
            )
            val result = response.toFusionInvokeResult()
            val latencyMs = System.currentTimeMillis() - synthStarted
            val cost = estimateCost(
                outcome.synthesizerModel.provider,
                outcome.synthesizerModel.modelId,
                result.inputTokens ?: 0,
                result.outputTokens ?: 0
            )
            val synthesisResult = SynthesisPhaseResult(
                modelId = outcome.synthesizerModel.modelId,
                provider = outcome.synthesizerModel.provider.uppercase(),
                success = true,
                content = result.text,
                latencyMs = latencyMs,
                inputTokens = result.inputTokens,
                outputTokens = result.outputTokens,
                cost = cost,
                error = null,
                usedFallback = false
            )
            val trace = orchestrator.finalizeTrace(
                trace = outcome.trace,
                synthesisResult = synthesisResult,
                finalAnswer = result.text,
                logPrompts = context.logPrompts
            )
            traceStore?.save(trace, context.conversationId)
            FusionRunResult(
                finalAnswer = result.text,
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
        return orchestrator.runThroughJudge(
            request = request,
            context = context,
            buildRequest = { model, systemPrompt, phase, allowTools, maxTokens ->
                buildGenerateRequest(
                    model = model,
                    systemPrompt = systemPrompt,
                    phase = phase,
                    allowTools = allowTools,
                    maxTokens = maxTokens,
                    settings = settings,
                    fusionDepth = context.fusionDepth,
                    userPrompt = request.userPrompt,
                    conversationHistory = conversationHistory,
                    userAttachments = userAttachments,
                    conversationId = context.conversationId?.toString()
                )
            },
            invoke = { bundle, phase ->
                invoke(
                    model = bundle.model,
                    provider = bundle.provider,
                    request = bundle.request,
                    phase = phase,
                    settings = settings
                )
            },
            estimateCost = { provider, model, input, output ->
                estimateCost(provider, model, input ?: 0, output ?: 0)
            },
            onProgress = onProgress
        )
    }

    fun buildGenerateRequest(
        model: PanelModelConfig,
        systemPrompt: String,
        phase: FusionPhase,
        allowTools: Boolean,
        maxTokens: Int,
        settings: Settings,
        fusionDepth: Int,
        userPrompt: String,
        conversationHistory: List<FusionHistoryMessage>,
        userAttachments: List<String> = emptyList(),
        conversationId: String? = null
    ): GenerateContentRequest {
        var contents = when (phase) {
            FusionPhase.panel -> panelContents(
                history = conversationHistory,
                userPrompt = userPrompt,
                userAttachments = userAttachments
            )
            else -> listOf(
                Content(role = "user", parts = listOf(Part(text = userPrompt)))
            )
        }

        val skillContext = if (phase == FusionPhase.panel) {
            skillRepository?.requestContext(userPrompt, conversationId)
        } else {
            null
        }
        contents = applySkillContext(contents, skillContext)

        val declarations = buildList {
            if (
                allowTools &&
                phase == FusionPhase.panel &&
                settings.clientWebSearchToolEnabled &&
                ClientTools.supportsClientWebSearchTool(model.provider)
            ) {
                addAll(ClientTools.toGeminiFunctionDeclarations())
            }
            if (
                phase == FusionPhase.panel &&
                ClientTools.supportsClientWebSearchTool(model.provider) &&
                skillRepository != null
            ) {
                addAll(AgentSkillTools.declarations(skillRepository))
            }
        }
        val tools: List<Tool>? = declarations.takeIf { it.isNotEmpty() }
            ?.let { listOf(Tool(function_declarations = it)) }

        val resolvedMaxTokens = model.maxTokens ?: maxTokens
        val generationConfig = GenerationConfig(
            temperature = model.temperature?.toFloat(),
            maxOutputTokens = resolvedMaxTokens.takeIf { it > 0 }
        )

        val mergedSystem = FusionOrchestrator.mergeSystemPrompts(
            if (phase == FusionPhase.panel || phase == FusionPhase.fallback) {
                // For panel, systemPrompt is fusion panel system; conversation system merged by caller via request.systemPrompt in orchestrator for synth only.
                null
            } else {
                null
            },
            systemPrompt
        )

        return GenerateContentRequest(
            contents = contents,
            system_instruction = systemPrompt.trim().takeIf { it.isNotEmpty() }?.let {
                SystemInstruction(parts = listOf(Part(text = it)))
            },
            generationConfig = generationConfig,
            tools = tools,
            skillContext = skillContext
        ).also {
            // fusionDepth retained for parity / future metadata; unused in GenerateContentRequest
            if (fusionDepth > 0) {
                DiagnosticsLogger.log("Fusion buildRequest phase=$phase depth=$fusionDepth model=${model.modelId}")
            }
        }
    }

    private fun applySkillContext(
        contents: List<Content>,
        context: SkillRequestContext?
    ): List<Content> {
        if (context == null) return contents
        val injection = listOfNotNull(context.syntheticUserContext, context.explicitUserContext)
            .joinToString("\n\n")
        if (injection.isBlank()) return contents
        val index = contents.indexOfLast { it.role == "user" }
        if (index < 0) return contents
        return contents.toMutableList().also { result ->
            val content = result[index]
            val parts = content.parts.toMutableList()
            val textIndex = parts.indexOfLast { it.text != null }
            if (textIndex >= 0) {
                parts[textIndex] = parts[textIndex].copy(
                    text = parts[textIndex].text.orEmpty() + "\n\n" + injection
                )
            } else {
                parts += Part(text = injection)
            }
            result[index] = content.copy(parts = parts)
        }
    }

    private fun panelContents(
        history: List<FusionHistoryMessage>,
        userPrompt: String,
        userAttachments: List<String>
    ): List<Content> {
        if (history.isEmpty()) {
            return listOf(
                Content(
                    role = "user",
                    parts = listOf(Part(text = userPrompt))
                    // Attachments handled by ChatRepository when building history for sendFusionMessage
                )
            )
        }
        val last = history.lastOrNull()
        if (last != null && last.role == "user" && last.text == userPrompt) {
            return history.map { it.toContent() }
        }
        return history.map { it.toContent() } + Content(
            role = "user",
            parts = listOf(Part(text = userPrompt))
        )
    }

    private fun FusionHistoryMessage.toContent(): Content =
        Content(role = if (role == "model" || role == "assistant") "model" else "user", parts = listOf(Part(text = text)))

    private suspend fun invoke(
        model: String,
        provider: String,
        request: GenerateContentRequest,
        phase: FusionPhase,
        settings: Settings
    ): FusionInvokeResult {
        val hasTools = !request.tools.isNullOrEmpty()
        if (phase == FusionPhase.panel && hasTools && toolRunner != null) {
            return toolRunner.run(model, provider, request)
        }
        val response: GenerateContentResponse = generate(model, provider, request)
        return response.toFusionInvokeResult()
    }

    fun finalizeTrace(
        trace: FusionTrace,
        synthesisResult: SynthesisPhaseResult,
        finalAnswer: String,
        logPrompts: Boolean
    ): FusionTrace = orchestrator.finalizeTrace(trace, synthesisResult, finalAnswer, logPrompts)
}

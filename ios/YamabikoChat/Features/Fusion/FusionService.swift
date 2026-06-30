import Foundation

final class FusionService {
    private let settingsRepository: SettingsRepository
    private let providerGateway: ProviderGateway
    private let pricingRepository: any LiteLlmPricingEstimating
    private let traceStore: FusionTraceStore
    private let orchestrator: FusionOrchestrator
    private let localToolRegistry: LocalToolRegistry

    init(
        settingsRepository: SettingsRepository,
        providerGateway: ProviderGateway,
        pricingRepository: any LiteLlmPricingEstimating,
        traceStore: FusionTraceStore,
        localToolRegistry: LocalToolRegistry = LocalToolRegistry(
            executors: [WebSearchTool(), FetchUrlTool()]
        ),
        orchestrator: FusionOrchestrator = FusionOrchestrator()
    ) {
        self.settingsRepository = settingsRepository
        self.providerGateway = providerGateway
        self.pricingRepository = pricingRepository
        self.traceStore = traceStore
        self.localToolRegistry = localToolRegistry
        self.orchestrator = orchestrator
    }

    func runFusion(
        userPrompt: String,
        options: FusionRunOptions = FusionRunOptions()
    ) async throws -> FusionRunResult {
        let settings = try settingsRepository.load()
        let allowWebSearch = options.allowWebSearch ?? settings.clientWebSearchToolEnabled
        let request = try FusionPresetLoader.buildRequest(
            userPrompt: userPrompt,
            systemPrompt: options.systemPrompt,
            taskTypeOverride: options.taskType,
            allowWebSearchOverride: allowWebSearch ? nil : false,
            customPresetJSON: settings.fusionCustomPresetJSON
        )
        let context = FusionContext(
            fusionDepth: options.fusionDepth,
            debugMode: options.debugMode,
            logPrompts: options.logPrompts,
            conversationId: options.conversationId
        )

        let outcome = try await runThroughJudge(
            request: request,
            context: context,
            conversationHistory: [],
            userAttachments: []
        )

        let synthStarted = Date()
        do {
            let response = try await providerGateway.generate(
                request: {
                    var req = outcome.synthesisRequest
                    req.stream = false
                    return req
                }(),
                provider: outcome.synthesizerProvider
            )
            let latencyMs = Int64(Date().timeIntervalSince(synthStarted) * 1000)
            let usage = response.usage?.normalizedNonEmpty()
            let cost = await estimateCost(
                provider: outcome.synthesizerModel.provider,
                model: outcome.synthesizerModel.modelId,
                usage: usage
            )
            let synthesisResult = SynthesisPhaseResult(
                modelId: outcome.synthesizerModel.modelId,
                provider: outcome.synthesizerModel.provider.uppercased(),
                success: true,
                content: response.text,
                latencyMs: latencyMs,
                inputTokens: usage?.inputTokens,
                outputTokens: usage?.outputTokens,
                cost: cost,
                error: nil,
                usedFallback: false
            )
            let trace = orchestrator.finalizeTrace(
                trace: outcome.trace,
                synthesisResult: synthesisResult,
                finalAnswer: response.text,
                logPrompts: context.logPrompts
            )
            try traceStore.save(trace: trace, conversationId: context.conversationId)
            return FusionRunResult(
                finalAnswer: response.text,
                traceId: trace.requestId,
                judgeAnalysis: options.debugMode ? trace.judgeResult?.analysis : nil,
                rawPanelResults: options.debugMode ? trace.panelResults : nil,
                totalLatencyMs: trace.totalLatencyMs,
                totalCost: trace.totalCost
            )
        } catch {
            let fallback = outcome.staticFallbackAnswer
            let synthesisResult = SynthesisPhaseResult(
                modelId: outcome.synthesizerModel.modelId,
                provider: outcome.synthesizerModel.provider.uppercased(),
                success: false,
                content: fallback,
                latencyMs: Int64(Date().timeIntervalSince(synthStarted) * 1000),
                inputTokens: nil,
                outputTokens: nil,
                cost: nil,
                error: error.localizedDescription,
                usedFallback: true
            )
            let trace = orchestrator.finalizeTrace(
                trace: outcome.trace,
                synthesisResult: synthesisResult,
                finalAnswer: fallback,
                logPrompts: context.logPrompts
            )
            try traceStore.save(trace: trace, conversationId: context.conversationId)
            return FusionRunResult(
                finalAnswer: fallback,
                traceId: trace.requestId,
                judgeAnalysis: options.debugMode ? trace.judgeResult?.analysis : nil,
                rawPanelResults: options.debugMode ? trace.panelResults : nil,
                totalLatencyMs: trace.totalLatencyMs,
                totalCost: trace.totalCost
            )
        }
    }

    func runThroughJudge(
        request: FusionRequest,
        context: FusionContext,
        conversationHistory: [ProviderRequestMessage],
        userAttachments: [String] = []
    ) async throws -> FusionJudgeOutcome {
        let settings = try settingsRepository.load()
        var visionSupportByModel: [String: Bool] = [:]
        for panel in request.panelModels {
            let supports = await pricingRepository.modelSupportsVision(
                provider: panel.provider,
                model: panel.modelId
            )
            visionSupportByModel[panel.modelId] = supports
        }

        return try await orchestrator.runThroughJudge(
            request: request,
            context: context,
            buildRequest: { [weak self] model, systemPrompt, phase, allowTools, maxTokens in
                guard let self else {
                    throw FusionError.serviceDeallocated
                }
                return self.buildProviderRequest(
                    model: model,
                    systemPrompt: systemPrompt,
                    phase: phase,
                    allowTools: allowTools,
                    maxTokens: maxTokens,
                    settings: settings,
                    fusionDepth: context.fusionDepth,
                    userPrompt: request.userPrompt,
                    conversationHistory: conversationHistory,
                    userAttachments: userAttachments,
                    supportsVision: visionSupportByModel[model.modelId] ?? false
                )
            },
            invoke: { [weak self] providerRequest, provider, phase in
                guard let self else {
                    throw FusionError.serviceDeallocated
                }
                return try await self.invoke(
                    request: providerRequest,
                    provider: provider,
                    phase: phase,
                    settings: settings
                )
            },
            estimateCost: { [weak self] provider, model, usage in
                await self?.estimateCost(provider: provider, model: model, usage: usage)
            }
        )
    }

    func buildProviderRequest(
        model: PanelModelConfig,
        systemPrompt: String,
        phase: FusionPhase,
        allowTools: Bool,
        maxTokens: Int,
        settings: AppSettings,
        fusionDepth: Int,
        userPrompt: String,
        conversationHistory: [ProviderRequestMessage],
        userAttachments: [String] = [],
        supportsVision: Bool = false
    ) -> ProviderRequest {
        var metadata: [String: String] = [
            "provider": model.provider.uppercased(),
            "fusionPhase": phase.rawValue,
            "fusionDepth": String(fusionDepth)
        ]
        Self.applyGenerationMetadata(
            to: &metadata,
            model: model,
            phaseMaxTokens: maxTokens
        )
        if phase == .panel {
            metadata["supportsVision"] = supportsVision ? "true" : "false"
        }

        var messages = conversationHistory
        if phase == .panel {
            messages = Self.panelMessages(
                history: conversationHistory,
                userPrompt: userPrompt,
                userAttachments: userAttachments
            )
        }

        var tools: [ProviderTool] = []
        if allowTools, phase == .panel, settings.clientWebSearchToolEnabled {
            let provider = LLMProvider(rawOrDefault: model.provider)
            if provider.supportsClientWebSearchTool {
                tools = localToolRegistry.definitions.map(\.providerTool)
            }
        }

        return ProviderRequest(
            model: model.modelId,
            messages: messages,
            systemPrompt: SystemPromptComposer.composeForAPI(
                systemPrompt.trimmedNonEmpty
            ),
            stream: phase == .synthesizer,
            tools: tools,
            thinking: nil,
            provider: nil,
            metadata: metadata
        )
    }

    private static func panelMessages(
        history: [ProviderRequestMessage],
        userPrompt: String,
        userAttachments: [String]
    ) -> [ProviderRequestMessage] {
        if history.isEmpty {
            return [
                ProviderRequestMessage(
                    role: "user",
                    content: userPrompt,
                    attachments: userAttachments
                )
            ]
        }
        if let last = history.last,
           last.role == "user",
           last.content == userPrompt {
            return history
        }
        var messages = history
        messages.append(
            ProviderRequestMessage(
                role: "user",
                content: userPrompt,
                attachments: userAttachments
            )
        )
        return messages
    }

    private static func applyGenerationMetadata(
        to metadata: inout [String: String],
        model: PanelModelConfig,
        phaseMaxTokens: Int
    ) {
        let resolvedMaxTokens = model.maxTokens ?? phaseMaxTokens
        if resolvedMaxTokens > 0 {
            metadata["max_output_tokens"] = String(resolvedMaxTokens)
        }
        if let temperature = model.temperature {
            metadata["temperature"] = String(temperature)
        }
    }

    private func invoke(
        request: ProviderRequest,
        provider: LLMProvider,
        phase: FusionPhase,
        settings: AppSettings
    ) async throws -> ProviderResponse {
        try Task.checkCancellation()
        if phase == .panel, !request.tools.isEmpty {
            let toolOrchestrator = ToolCallingOrchestrator(registry: localToolRegistry)
            let outcome = try await toolOrchestrator.run(request: request) { req, _ in
                try Task.checkCancellation()
                return try await self.providerGateway.generate(request: req, provider: provider)
            }
            return outcome.response
        }
        return try await providerGateway.generate(request: request, provider: provider)
    }

    private func estimateCost(provider: String, model: String, usage: ProviderUsage?) async -> Double? {
        guard let usage else { return nil }
        let normalized = usage.normalized()
        return await pricingRepository.estimateCostUsd(
            provider: provider,
            model: model,
            inputTokens: normalized.inputTokens ?? 0,
            outputTokens: normalized.outputTokens ?? 0,
            cachedInputTokens: normalized.cachedInputTokens,
            cacheCreationInputTokens: normalized.cacheCreationInputTokens,
            reasoningTokens: normalized.reasoningTokens
        )
    }
}
import Foundation

final class FusionService {
    static let reasoningContinuationLimit = 3

    private let settingsRepository: SettingsRepository
    private let providerGateway: ProviderGateway
    private let pricingRepository: any LiteLlmPricingEstimating
    private let traceStore: FusionTraceStore
    private let orchestrator: FusionOrchestrator
    private let requestSettingsResolver: ProviderRequestSettingsResolver
    private let skillRepository: AgentSkillRepository?

    init(
        settingsRepository: SettingsRepository,
        providerGateway: ProviderGateway,
        pricingRepository: any LiteLlmPricingEstimating,
        traceStore: FusionTraceStore,
        requestSettingsResolver: ProviderRequestSettingsResolver,
        skillRepository: AgentSkillRepository? = nil,
        orchestrator: FusionOrchestrator = FusionOrchestrator()
    ) {
        self.settingsRepository = settingsRepository
        self.providerGateway = providerGateway
        self.pricingRepository = pricingRepository
        self.traceStore = traceStore
        self.requestSettingsResolver = requestSettingsResolver
        self.skillRepository = skillRepository
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
        let response = try await invoke(
            request: {
                var req = outcome.synthesisRequest
                req.stream = false
                return req
            }(),
            provider: outcome.synthesizerProvider,
            phase: .synthesizer
        )
        guard let answer = response.text.trimmedNonEmpty else {
            throw ProviderClientError.parseFailure(
                L10n.text("Fusion synthesizer returned no answer text.")
            )
        }
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
            content: answer,
            latencyMs: latencyMs,
            inputTokens: usage?.inputTokens,
            outputTokens: usage?.outputTokens,
            cost: cost,
            error: nil,
            piExecution: response.piExecution
        )
        let trace = orchestrator.finalizeTrace(
            trace: outcome.trace,
            synthesisResult: synthesisResult,
            finalAnswer: answer,
            logPrompts: context.logPrompts
        )
        try traceStore.save(trace: trace, conversationId: context.conversationId)
        return FusionRunResult(
            finalAnswer: answer,
            traceId: trace.requestId,
            judgeAnalysis: options.debugMode ? trace.judgeResult?.analysis : nil,
            rawPanelResults: options.debugMode ? trace.panelResults : nil,
            totalLatencyMs: trace.totalLatencyMs,
            totalCost: trace.totalCost
        )
    }

    func runThroughJudge(
        request: FusionRequest,
        context: FusionContext,
        conversationHistory: [ProviderRequestMessage],
        userAttachments: [String] = [],
        onProgress: FusionOrchestrator.ProgressHandler? = nil
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
        let resolvedVisionSupportByModel = visionSupportByModel

        return try await orchestrator.runThroughJudge(
            request: request,
            context: context,
            buildRequest: { [weak self] model, systemPrompt, phase, allowTools in
                guard let self else {
                    throw FusionError.serviceDeallocated
                }
                return try await self.buildProviderRequest(
                    model: model,
                    systemPrompt: systemPrompt,
                    phase: phase,
                    allowTools: allowTools,
                    settings: settings,
                    fusionDepth: context.fusionDepth,
                    userPrompt: request.userPrompt,
                    conversationHistory: conversationHistory,
                    userAttachments: userAttachments,
                    supportsVision: resolvedVisionSupportByModel[model.modelId] ?? false,
                    conversationID: context.conversationId.map(String.init),
                    clientToolsAllowed: context.clientToolsAllowed
                )
            },
            invoke: { [weak self] providerRequest, provider, phase, onToolActivity in
                guard let self else {
                    throw FusionError.serviceDeallocated
                }
                return try await self.invoke(
                    request: providerRequest,
                    provider: provider,
                    phase: phase,
                    onToolActivity: onToolActivity
                )
            },
            estimateCost: { [weak self] provider, model, usage in
                await self?.estimateCost(provider: provider, model: model, usage: usage)
            },
            onProgress: onProgress
        )
    }

    func buildProviderRequest(
        model: PanelModelConfig,
        systemPrompt: String,
        phase: FusionPhase,
        allowTools: Bool,
        settings: AppSettings,
        fusionDepth: Int,
        userPrompt: String,
        conversationHistory: [ProviderRequestMessage],
        userAttachments: [String] = [],
        supportsVision: Bool = false,
        conversationID: String? = nil,
        clientToolsAllowed: Bool = true
    ) async throws -> ProviderRequest {
        let toolScope: ProviderRequestToolScope = clientToolsAllowed && phase == .panel
            ? .fusionPanel(allowWebSearch: allowTools)
            : .providerOnly
        let resolvedSettings = try await requestSettingsResolver.resolve(
            settings: settings,
            provider: model.provider,
            model: model.modelId,
            toolScope: toolScope
        )
        var metadata = resolvedSettings.metadata
        metadata.merge([
            "provider": model.provider.uppercased(),
            "fusionPhase": phase.rawValue,
            "fusionDepth": String(fusionDepth)
        ], uniquingKeysWith: { _, fusionValue in fusionValue })
        if let conversationID = conversationID?.trimmedNonEmpty {
            metadata["promptCacheKey"] = "fusion-\(conversationID)"
        }
        Self.applyGenerationMetadata(
            to: &metadata,
            model: model
        )
        if phase == .panel {
            metadata["supportsVision"] = supportsVision ? "true" : "false"
        }
        if !clientToolsAllowed {
            metadata["supportsClientTools"] = "false"
        }

        var messages = conversationHistory
        if phase == .panel {
            messages = Self.panelMessages(
                history: conversationHistory,
                userPrompt: userPrompt,
                userAttachments: userAttachments
            )
        }

        let skillContext: SkillRequestContext?
        if clientToolsAllowed, phase == .panel, let skillRepository {
            let supportsTools = resolvedSettings.metadata["supportsClientTools"] == "true"
            let application = try AgentSkillPromptComposer.apply(
                repository: skillRepository,
                to: messages,
                conversationID: conversationID,
                providerSupportsTools: supportsTools
            )
            skillContext = application.currentContext
            messages = application.messages
        } else {
            skillContext = nil
        }

        return ProviderRequest(
            model: model.modelId,
            messages: messages,
            systemPrompt: SystemPromptComposer.composeForAPI(
                systemPrompt.trimmedNonEmpty,
                enablesAgenticWebSearch: clientToolsAllowed && resolvedSettings.tools.containsWebSearchTool
            ),
            stream: phase == .synthesizer,
            tools: clientToolsAllowed ? resolvedSettings.tools : [],
            thinking: resolvedSettings.thinking,
            provider: resolvedSettings.routing,
            metadata: metadata,
            timeoutInterval: TimeInterval(max(model.timeoutMs ?? 120_000, 1_000)) / 1_000,
            skillContext: skillContext
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
        model: PanelModelConfig
    ) {
        if let temperature = model.temperature {
            metadata["temperature"] = String(temperature)
        }
    }

    private func invoke(
        request: ProviderRequest,
        provider: String,
        phase: FusionPhase,
        onToolActivity: (@Sendable (ToolActivityPayload) -> Void)? = nil
    ) async throws -> ProviderResponse {
        var currentRequest = request
        var accumulatedUsage: ProviderUsage?
        var accumulatedReasoning: [String] = []
        var continuationRounds = 0
        let activityAccumulator = FusionToolActivityAccumulator()

        while true {
            try Task.checkCancellation()
            let response: ProviderResponse
            response = try await providerGateway.generate(
                request: currentRequest,
                providerID: provider,
                onStreamEvent: { event in
                    switch event {
                    case let .toolActivity(toolEvent):
                        onToolActivity?(activityAccumulator.apply(toolEvent))
                    case let .executionSnapshot(execution):
                        onToolActivity?(activityAccumulator.setExecution(execution))
                    case .answerStart, .textDelta, .reasoningDelta, .completed:
                        break
                    }
                }
            )

            if let usage = response.usage {
                accumulatedUsage = accumulatedUsage?.adding(usage) ?? usage
            }
            if let reasoning = response.reasoningSummary?.trimmedNonEmpty {
                accumulatedReasoning.append(reasoning)
            }
            if response.text.trimmedNonEmpty != nil || !response.toolCalls.isEmpty {
                var completed = response
                completed.usage = accumulatedUsage
                completed.reasoningSummary = accumulatedReasoning.isEmpty
                    ? response.reasoningSummary
                    : accumulatedReasoning.joined(separator: "\n\n")
                return completed
            }

            guard let reasoning = response.reasoningSummary?.trimmedNonEmpty else {
                return response
            }
            guard continuationRounds < Self.reasoningContinuationLimit else {
                throw ProviderClientError.parseFailure(
                    "Fusion \(phase.rawValue) returned reasoning without answer text after \(Self.reasoningContinuationLimit) continuation requests."
                )
            }
            continuationRounds += 1
            currentRequest.messages.append(
                ProviderRequestMessage(role: "assistant", content: "", reasoningContent: reasoning)
            )
            currentRequest.messages.append(
                ProviderRequestMessage(
                    role: "user",
                    content: Self.continuationPrompt(for: phase)
                )
            )
        }
    }

    private static func continuationPrompt(for phase: FusionPhase) -> String {
        switch phase {
        case .judge:
            return "Continue the same response and return only the required JSON now."
        case .panel, .synthesizer:
            return "Continue the same response and provide the answer text now."
        }
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

private final class FusionToolActivityAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var payload = ToolActivityPayload()

    func apply(_ event: ToolActivityEvent) -> ToolActivityPayload {
        lock.lock()
        payload.apply(event)
        let value = payload
        lock.unlock()
        return value
    }

    func setExecution(_ execution: JSONValue) -> ToolActivityPayload {
        lock.lock()
        payload.piExecution = execution
        let value = payload
        lock.unlock()
        return value
    }
}

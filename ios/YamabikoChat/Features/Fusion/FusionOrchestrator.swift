import Foundation

struct FusionOrchestrator: Sendable {
    typealias Invoke = @Sendable (ProviderRequest, String, FusionPhase, @escaping @Sendable (ToolActivityPayload) -> Void) async throws -> ProviderResponse
    typealias CostEstimator = @Sendable (String, String, ProviderUsage?) async -> Double?
    typealias RequestBuilder = @Sendable (
        PanelModelConfig,
        String,
        FusionPhase,
        Bool
    ) async throws -> ProviderRequest

    typealias ProgressHandler = @Sendable (FusionProgressSnapshot) -> Void

    func runThroughJudge(
        request: FusionRequest,
        context: FusionContext,
        buildRequest: @escaping RequestBuilder,
        invoke: @escaping Invoke,
        estimateCost: @escaping CostEstimator,
        onProgress: ProgressHandler? = nil
    ) async throws -> FusionJudgeOutcome {
        let requestId = UUID().uuidString
        let startedAtMs = Int64(Date().timeIntervalSince1970 * 1000)

        if context.fusionDepth >= FusionContext.maxFusionDepth {
            throw FusionError.recursionLimitExceeded
        }

        let panelResults = await FusionPanelRunner.runAll(
            request: request,
            panelSystemPrompt: FusionPrompts.panelSystemPrompt(),
            buildPanelRequest: { panel, systemPrompt in
                try await buildRequest(panel, systemPrompt, .panel, request.allowWebSearch)
            },
            invoke: invoke,
            estimateCost: estimateCost,
            onProgress: onProgress
        )

        let successfulPanels = panelResults.filter { $0.success }
        let failedModels = panelResults.filter { !$0.success }.map { $0.modelId }

        guard !successfulPanels.isEmpty else {
            throw FusionError.allPanelsFailed(panelResults: panelResults)
        }

        let finalPanelChips = panelResults.map { result in
            FusionPanelChipStatus(
                modelId: result.modelId,
                provider: result.provider,
                state: result.success ? .succeeded : .failed
            )
        }
        onProgress?(
            FusionProgressSnapshot.phaseOnly(.judge, panels: finalPanelChips)
        )

        let judgeOutcome = try await runJudge(
            request: request,
            successfulPanels: successfulPanels,
            failedModels: failedModels,
            buildRequest: buildRequest,
            invoke: invoke,
            estimateCost: estimateCost
        )

        let judgeAnalysis = judgeOutcome.analysis
        let synthesisUserPrompt = judgeAnalysis != nil
            ? FusionPrompts.synthesizerUserPrompt(
                userPrompt: request.userPrompt,
                judgeAnalysis: judgeAnalysis,
                rawPanels: successfulPanels,
                judgeParseFailed: !judgeOutcome.parseSucceeded
            )
            : FusionPrompts.synthesizerUserPromptWithoutJudge(
                userPrompt: request.userPrompt,
                rawPanels: successfulPanels
            )

        let synthSystemPrompt = FusionPrompts.synthesizerSystemPrompt(debugMode: context.debugMode)
        var synthesisRequest = try await buildRequest(
            request.synthesizerModel,
            synthSystemPrompt,
            .synthesizer,
            false
        )
        synthesisRequest.messages = [
            ProviderRequestMessage(role: "user", content: synthesisUserPrompt)
        ]
        synthesisRequest.stream = true
        synthesisRequest.systemPrompt = SystemPromptComposer.mergeForAPI(
            request.systemPrompt,
            synthSystemPrompt
        )

        let trace = FusionTrace(
            requestId: requestId,
            preset: request.preset,
            startedAtMs: startedAtMs,
            completedAtMs: nil,
            panelResults: panelResults,
            judgeResult: judgeOutcome,
            synthesisResult: nil,
            totalLatencyMs: nil,
            totalCost: Self.sumCosts(panelResults: panelResults, judge: judgeOutcome, synthesis: nil),
            failedModels: failedModels,
            status: "judge_complete",
            userPrompt: context.logPrompts ? request.userPrompt : nil,
            finalAnswer: nil
        )

        let panelUsages = panelResults.compactMap { panel -> (String, String, ProviderUsage?, String)? in
            guard panel.success else { return nil }
            let usage = ProviderUsage(
                inputTokens: panel.inputTokens,
                outputTokens: panel.outputTokens
            ).normalizedNonEmpty()
            let requestType = "fusion_panel_\(Self.sanitizedModelId(panel.modelId))"
            return (panel.provider, panel.modelId, usage, requestType)
        }

        let judgeUsage: (String, String, ProviderUsage?)? = {
            guard judgeOutcome.parseSucceeded || judgeOutcome.rawJSON != nil else { return nil }
            let usage = ProviderUsage(
                inputTokens: judgeOutcome.inputTokens,
                outputTokens: judgeOutcome.outputTokens
            ).normalizedNonEmpty()
            return (request.judgeModel.provider.uppercased(), request.judgeModel.modelId, usage)
        }()

        onProgress?(
            FusionProgressSnapshot.phaseOnly(.synthesizer, panels: finalPanelChips)
        )

        return FusionJudgeOutcome(
            trace: trace,
            synthesisRequest: synthesisRequest,
            synthesizerProvider: request.synthesizerModel.provider,
            synthesizerModel: request.synthesizerModel,
            panelTokenUsages: panelUsages,
            judgeTokenUsage: judgeUsage
        )
    }

    func finalizeTrace(
        trace: FusionTrace,
        synthesisResult: SynthesisPhaseResult,
        finalAnswer: String,
        logPrompts: Bool
    ) -> FusionTrace {
        var updated = trace
        updated.synthesisResult = synthesisResult
        updated.completedAtMs = Int64(Date().timeIntervalSince1970 * 1000)
        updated.totalLatencyMs = (updated.completedAtMs ?? updated.startedAtMs) - updated.startedAtMs
        updated.totalCost = Self.sumCosts(
            panelResults: updated.panelResults,
            judge: updated.judgeResult,
            synthesis: synthesisResult
        )
        updated.status = "completed"
        updated.finalAnswer = logPrompts ? finalAnswer : nil
        return updated
    }

    // MARK: - Private

    private func runJudge(
        request: FusionRequest,
        successfulPanels: [PanelResult],
        failedModels: [String],
        buildRequest: @escaping RequestBuilder,
        invoke: @escaping Invoke,
        estimateCost: @escaping CostEstimator
    ) async throws -> JudgePhaseResult {
        let started = Date()
        let judgeUserContent = FusionPrompts.judgeUserPrompt(
            userPrompt: request.userPrompt,
            successfulPanels: successfulPanels,
            failedModels: failedModels
        )

        @Sendable func makeJudgeRequest(systemPrompt: String, userContent: String) async throws -> ProviderRequest {
            var providerRequest = try await buildRequest(
                request.judgeModel,
                systemPrompt,
                .judge,
                false
            )
            providerRequest.messages = [ProviderRequestMessage(role: "user", content: userContent)]
            providerRequest.stream = false
            providerRequest.metadata["responseMimeType"] = "application/json"
            if request.judgeModel.provider.uppercased() == "GEMINI" {
                providerRequest.metadata["geminiResponseMimeType"] = "application/json"
            }
            return providerRequest
        }

        let provider = request.judgeModel.provider

        let response = try await invoke(
                try await makeJudgeRequest(
                    systemPrompt: FusionPrompts.judgeSystemPrompt(),
                    userContent: judgeUserContent
                ),
                provider,
                .judge,
                { _ in }
            )
            let latencyMs = Int64(Date().timeIntervalSince(started) * 1000)
            let usage = response.usage?.normalizedNonEmpty()
            let cost = await estimateCost(request.judgeModel.provider, request.judgeModel.modelId, usage)

        if let analysis = FusionJudgeParser.parse(response.text) {
            return JudgePhaseResult(
                    analysis: analysis,
                    rawJSON: response.text,
                    parseSucceeded: true,
                    latencyMs: latencyMs,
                    inputTokens: usage?.inputTokens,
                    outputTokens: usage?.outputTokens,
                    cost: cost,
                    error: nil,
                    piExecutions: [response.piExecution].compactMap { $0 }
                )
        }

        let repairStarted = Date()
        let repairResponse = try await invoke(
                try await makeJudgeRequest(
                    systemPrompt: FusionPrompts.judgeSystemPrompt(),
                    userContent: FusionPrompts.jsonRepairPrompt(invalidJSON: response.text)
                ),
                provider,
                .judge,
                { _ in }
            )
            let repairLatency = Int64(Date().timeIntervalSince(repairStarted) * 1000)
            let repairUsage = repairResponse.usage?.normalizedNonEmpty()
            let repairCost = await estimateCost(request.judgeModel.provider, request.judgeModel.modelId, repairUsage)

        if let analysis = FusionJudgeParser.parse(repairResponse.text) {
            return JudgePhaseResult(
                    analysis: analysis,
                    rawJSON: repairResponse.text,
                    parseSucceeded: true,
                    latencyMs: repairLatency,
                    inputTokens: repairUsage?.inputTokens,
                    outputTokens: repairUsage?.outputTokens,
                    cost: (cost ?? 0) + (repairCost ?? 0),
                    error: nil,
                    piExecutions: [response.piExecution, repairResponse.piExecution].compactMap { $0 }
                )
        }
        throw ProviderClientError.parseFailure("Judge JSON parse failed")
    }

    private static func sanitizedModelId(_ modelId: String) -> String {
        let trimmed = modelId.trimmingCharacters(in: .whitespacesAndNewlines)
        let replaced = trimmed
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
            .replacingOccurrences(of: " ", with: "_")
        return replaced.isEmpty ? "unknown" : replaced
    }

    private static func sumCosts(
        panelResults: [PanelResult],
        judge: JudgePhaseResult?,
        synthesis: SynthesisPhaseResult?
    ) -> Double? {
        var total: Double = 0
        var hasCost = false
        for panel in panelResults {
            if let cost = panel.cost {
                total += cost
                hasCost = true
            }
        }
        if let cost = judge?.cost {
            total += cost
            hasCost = true
        }
        if let cost = synthesis?.cost {
            total += cost
            hasCost = true
        }
        return hasCost ? total : nil
    }
}

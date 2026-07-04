import Foundation

struct FusionOrchestrator: Sendable {
    typealias Invoke = @Sendable (ProviderRequest, LLMProvider, FusionPhase) async throws -> ProviderResponse
    typealias CostEstimator = @Sendable (String, String, ProviderUsage?) async -> Double?
    typealias RequestBuilder = @Sendable (
        PanelModelConfig,
        String,
        FusionPhase,
        Bool,
        Int
    ) throws -> ProviderRequest

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
            return try await runRecursionFallback(
                request: request,
                context: context,
                requestId: requestId,
                startedAtMs: startedAtMs,
                buildRequest: buildRequest,
                invoke: invoke,
                estimateCost: estimateCost
            )
        }

        let panelResults = await FusionPanelRunner.runAll(
            request: request,
            panelSystemPrompt: FusionPrompts.panelSystemPrompt(taskType: request.taskType),
            buildPanelRequest: { panel, systemPrompt in
                try buildRequest(panel, systemPrompt, .panel, request.allowWebSearch, request.maxPanelTokens)
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

        let judgeOutcome = await runJudge(
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
        var synthesisRequest = try buildRequest(
            request.synthesizerModel,
            synthSystemPrompt,
            .synthesizer,
            false,
            request.maxSynthesizerTokens
        )
        synthesisRequest.messages = [
            ProviderRequestMessage(role: "user", content: synthesisUserPrompt)
        ]
        synthesisRequest.stream = true
        synthesisRequest.systemPrompt = SystemPromptComposer.mergeForAPI(
            request.systemPrompt,
            synthSystemPrompt
        )

        let staticFallback = Self.buildStaticFallback(
            judgeAnalysis: judgeAnalysis,
            judgeRaw: judgeOutcome.rawJSON,
            panels: successfulPanels
        )

        var trace = FusionTrace(
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
            synthesizerProvider: LLMProvider(rawOrDefault: request.synthesizerModel.provider),
            synthesizerModel: request.synthesizerModel,
            staticFallbackAnswer: staticFallback,
            panelTokenUsages: panelUsages,
            judgeTokenUsage: judgeUsage
        )
    }

    func buildStaticFallback(
        judgeAnalysis: JudgeAnalysis?,
        judgeRaw: String?,
        panels: [PanelResult]
    ) -> String {
        Self.buildStaticFallback(judgeAnalysis: judgeAnalysis, judgeRaw: judgeRaw, panels: panels)
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
        updated.status = synthesisResult.success ? "completed" : "synthesis_fallback"
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
    ) async -> JudgePhaseResult {
        let started = Date()
        let judgeUserContent = FusionPrompts.judgeUserPrompt(
            userPrompt: request.userPrompt,
            successfulPanels: successfulPanels,
            failedModels: failedModels
        )

        func makeJudgeRequest(systemPrompt: String, userContent: String) throws -> ProviderRequest {
            var providerRequest = try buildRequest(
                request.judgeModel,
                systemPrompt,
                .judge,
                false,
                request.maxJudgeTokens
            )
            providerRequest.messages = [ProviderRequestMessage(role: "user", content: userContent)]
            providerRequest.stream = false
            providerRequest.metadata["responseMimeType"] = "application/json"
            if request.judgeModel.provider.uppercased() == "GEMINI" {
                providerRequest.metadata["geminiResponseMimeType"] = "application/json"
            }
            return providerRequest
        }

        let provider = LLMProvider(rawOrDefault: request.judgeModel.provider)
        let timeoutMs = request.judgeModel.timeoutMs ?? request.timeoutMs

        do {
            let response = try await FusionTimeout.run(milliseconds: timeoutMs) {
                try await invoke(
                    try makeJudgeRequest(
                        systemPrompt: FusionPrompts.judgeSystemPrompt(),
                        userContent: judgeUserContent
                    ),
                    provider,
                    .judge
                )
            }
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
                    error: nil
                )
            }

            let repairStarted = Date()
            let repairResponse = try await FusionTimeout.run(milliseconds: timeoutMs) {
                try await invoke(
                    try makeJudgeRequest(
                        systemPrompt: FusionPrompts.judgeSystemPrompt(),
                        userContent: FusionPrompts.jsonRepairPrompt(invalidJSON: response.text)
                    ),
                    provider,
                    .judge
                )
            }
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
                    error: nil
                )
            }

            return JudgePhaseResult(
                analysis: nil,
                rawJSON: repairResponse.text,
                parseSucceeded: false,
                latencyMs: repairLatency,
                inputTokens: repairUsage?.inputTokens,
                outputTokens: repairUsage?.outputTokens,
                cost: (cost ?? 0) + (repairCost ?? 0),
                error: "Judge JSON parse failed"
            )
        } catch {
            let latencyMs = Int64(Date().timeIntervalSince(started) * 1000)
            return JudgePhaseResult(
                analysis: nil,
                rawJSON: nil,
                parseSucceeded: false,
                latencyMs: latencyMs,
                inputTokens: nil,
                outputTokens: nil,
                cost: nil,
                error: error.localizedDescription
            )
        }
    }

    private func runRecursionFallback(
        request: FusionRequest,
        context: FusionContext,
        requestId: String,
        startedAtMs: Int64,
        buildRequest: @escaping RequestBuilder,
        invoke: @escaping Invoke,
        estimateCost: @escaping CostEstimator
    ) async throws -> FusionJudgeOutcome {
        let fallback = request.fallbackModel ?? request.synthesizerModel
        var providerRequest = try buildRequest(fallback, request.systemPrompt ?? "", .fallback, false, request.maxSynthesizerTokens)
        providerRequest.messages = [ProviderRequestMessage(role: "user", content: request.userPrompt)]
        providerRequest.stream = true
        providerRequest.metadata["fusionDepth"] = String(context.fusionDepth)

        let timeoutMs = fallback.timeoutMs ?? request.timeoutMs
        let started = Date()
        let response = try await FusionTimeout.run(milliseconds: timeoutMs) {
            try await invoke(
                providerRequest,
                LLMProvider(rawOrDefault: fallback.provider),
                .fallback
            )
        }
        let latencyMs = Int64(Date().timeIntervalSince(started) * 1000)
        let usage = response.usage?.normalizedNonEmpty()
        let cost = await estimateCost(fallback.provider, fallback.modelId, usage)

        let trace = FusionTrace(
            requestId: requestId,
            preset: request.preset,
            startedAtMs: startedAtMs,
            completedAtMs: Int64(Date().timeIntervalSince1970 * 1000),
            panelResults: [],
            judgeResult: nil,
            synthesisResult: SynthesisPhaseResult(
                modelId: fallback.modelId,
                provider: fallback.provider.uppercased(),
                success: true,
                content: response.text,
                latencyMs: latencyMs,
                inputTokens: usage?.inputTokens,
                outputTokens: usage?.outputTokens,
                cost: cost,
                error: nil,
                usedFallback: true
            ),
            totalLatencyMs: latencyMs,
            totalCost: cost,
            failedModels: [],
            status: "recursion_fallback",
            userPrompt: context.logPrompts ? request.userPrompt : nil,
            finalAnswer: context.logPrompts ? response.text : nil
        )

        return FusionJudgeOutcome(
            trace: trace,
            synthesisRequest: providerRequest,
            synthesizerProvider: LLMProvider(rawOrDefault: fallback.provider),
            synthesizerModel: fallback,
            staticFallbackAnswer: response.text,
            panelTokenUsages: [],
            judgeTokenUsage: nil
        )
    }

    private static func buildStaticFallback(
        judgeAnalysis: JudgeAnalysis?,
        judgeRaw: String?,
        panels: [PanelResult]
    ) -> String {
        var sections: [String] = []
        if let judgeAnalysis {
            if !judgeAnalysis.recommendedFinalPosition.isEmpty {
                sections.append(judgeAnalysis.recommendedFinalPosition)
            } else if !judgeAnalysis.consensus.isEmpty {
                sections.append(judgeAnalysis.consensus.joined(separator: "\n"))
            }
        } else if let judgeRaw, !judgeRaw.isEmpty {
            sections.append(judgeRaw)
        }
        if let best = panels.filter({ $0.success }).min(by: { $0.latencyMs < $1.latencyMs }) {
            if !best.content.isEmpty {
                sections.append(best.content)
            }
        }
        return sections.joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
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
import Foundation

enum FusionPanelRunner {
    typealias Invoke = @Sendable (ProviderRequest, String, FusionPhase) async throws -> ProviderResponse
    typealias CostEstimator = @Sendable (String, String, ProviderUsage?) async -> Double?
    typealias ProgressHandler = @Sendable (FusionProgressSnapshot) -> Void

    static func runAll(
        request: FusionRequest,
        panelSystemPrompt: String,
        buildPanelRequest: @escaping @Sendable (PanelModelConfig, String) async throws -> ProviderRequest,
        invoke: @escaping Invoke,
        estimateCost: @escaping CostEstimator,
        onProgress: ProgressHandler? = nil
    ) async -> [PanelResult] {
        var chipPanels = FusionProgressSnapshot.initialPanels(from: request)
        onProgress?(FusionProgressSnapshot.panelPhase(panels: chipPanels))

        return await withTaskGroup(of: PanelResult.self) { group in
            for panel in request.panelModels {
                group.addTask {
                    await runSingle(
                        panel: panel,
                        request: request,
                        panelSystemPrompt: panelSystemPrompt,
                        buildPanelRequest: buildPanelRequest,
                        invoke: invoke,
                        estimateCost: estimateCost
                    )
                }
            }
            var results: [PanelResult] = []
            for await result in group {
                let snapshot = FusionProgressSnapshot.panelPhase(panels: chipPanels)
                    .applyingPanelResult(result)
                chipPanels = snapshot.panels
                onProgress?(snapshot)
                results.append(result)
            }
            return results
        }
    }

    private static func runSingle(
        panel: PanelModelConfig,
        request: FusionRequest,
        panelSystemPrompt: String,
        buildPanelRequest: @escaping @Sendable (PanelModelConfig, String) async throws -> ProviderRequest,
        invoke: @escaping Invoke,
        estimateCost: @escaping CostEstimator
    ) async -> PanelResult {
        let timeoutMs = panel.timeoutMs ?? request.timeoutMs
        let provider = panel.provider
        let started = Date()

        do {
            let providerRequest = try await buildPanelRequest(panel, panelSystemPrompt)
            let response = try await FusionTimeout.run(milliseconds: timeoutMs) {
                try await invoke(providerRequest, provider, .panel)
            }
            let latencyMs = Int64(Date().timeIntervalSince(started) * 1000)
            let usage = response.usage?.normalizedNonEmpty()
            let cost = await estimateCost(panel.provider, panel.modelId, usage)
            return PanelResult(
                modelId: panel.modelId,
                provider: panel.provider.uppercased(),
                success: true,
                content: response.text,
                error: nil,
                latencyMs: latencyMs,
                inputTokens: usage?.inputTokens,
                outputTokens: usage?.outputTokens,
                cost: cost,
                toolCalls: response.toolCalls.isEmpty ? nil : response.toolCalls,
                finishReason: nil,
                role: panel.role
            )
        } catch {
            let latencyMs = Int64(Date().timeIntervalSince(started) * 1000)
            return PanelResult(
                modelId: panel.modelId,
                provider: panel.provider.uppercased(),
                success: false,
                content: "",
                error: error.localizedDescription,
                latencyMs: latencyMs,
                inputTokens: nil,
                outputTokens: nil,
                cost: nil,
                toolCalls: nil,
                finishReason: nil,
                role: panel.role
            )
        }
    }
}

import Foundation

enum FusionPanelRunner {
    typealias Invoke = @Sendable (ProviderRequest, String, FusionPhase, @escaping @Sendable (ToolActivityPayload) -> Void) async throws -> ProviderResponse
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
        let progressState = FusionPanelToolProgressState(
            panels: FusionProgressSnapshot.initialPanels(from: request),
            onProgress: onProgress
        )
        progressState.emit()

        return await withTaskGroup(of: PanelResult.self) { group in
            for panel in request.panelModels {
                group.addTask {
                    await runSingle(
                        panel: panel,
                        panelSystemPrompt: panelSystemPrompt,
                        buildPanelRequest: buildPanelRequest,
                        invoke: invoke,
                        estimateCost: estimateCost,
                        onToolActivity: { progressState.update(modelId: panel.modelId, activity: $0) }
                    )
                }
            }
            var results: [PanelResult] = []
            for await result in group {
                progressState.finish(result)
                results.append(result)
            }
            return results
        }
    }

    private static func runSingle(
        panel: PanelModelConfig,
        panelSystemPrompt: String,
        buildPanelRequest: @escaping @Sendable (PanelModelConfig, String) async throws -> ProviderRequest,
        invoke: @escaping Invoke,
        estimateCost: @escaping CostEstimator,
        onToolActivity: @escaping @Sendable (ToolActivityPayload) -> Void
    ) async -> PanelResult {
        let provider = panel.provider
        let started = Date()
        let activityState = FusionPanelActivityState()
        let publishActivity: @Sendable (ToolActivityPayload) -> Void = { activity in
            activityState.update(activity)
            onToolActivity(activity)
        }

        do {
            let providerRequest = try await buildPanelRequest(panel, panelSystemPrompt)
            let response = try await invoke(providerRequest, provider, .panel, publishActivity)
            guard let answer = response.text.trimmedNonEmpty else {
                throw ProviderClientError.parseFailure(
                    L10n.format("Fusion panel %@ returned no answer text.", panel.modelId)
                )
            }
            let latencyMs = Int64(Date().timeIntervalSince(started) * 1000)
            let usage = response.usage?.normalizedNonEmpty()
            let cost = await estimateCost(panel.provider, panel.modelId, usage)
            return PanelResult(
                modelId: panel.modelId,
                provider: panel.provider.uppercased(),
                success: true,
                content: answer,
                error: nil,
                latencyMs: latencyMs,
                inputTokens: usage?.inputTokens,
                outputTokens: usage?.outputTokens,
                cost: cost,
                toolCalls: response.toolCalls.isEmpty ? nil : response.toolCalls,
                toolActivity: response.toolActivity ?? activityState.snapshot(),
                finishReason: nil,
                role: panel.role,
                piExecution: response.piExecution
            )
        } catch {
            let latencyMs = Int64(Date().timeIntervalSince(started) * 1000)
            let failedActivity = activityState.failRunning()
            if let failedActivity {
                onToolActivity(failedActivity)
            }
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
                toolActivity: failedActivity,
                finishReason: nil,
                role: panel.role,
                piExecution: nil
            )
        }
    }
}

private final class FusionPanelActivityState: @unchecked Sendable {
    private let lock = NSLock()
    private var activity = ToolActivityPayload()

    func update(_ value: ToolActivityPayload) {
        lock.lock()
        activity = value
        lock.unlock()
    }

    func snapshot() -> ToolActivityPayload? {
        lock.lock()
        let value = activity
        lock.unlock()
        return value.hasPersistableContent ? value : nil
    }

    func failRunning() -> ToolActivityPayload? {
        lock.lock()
        activity.failRunning(message: L10n.text("ツールの実行が中断されました"))
        let value = activity
        lock.unlock()
        return value.hasPersistableContent ? value : nil
    }
}

private final class FusionPanelToolProgressState: @unchecked Sendable {
    private let lock = NSLock()
    private var panels: [FusionPanelChipStatus]
    private let onProgress: FusionPanelRunner.ProgressHandler?

    init(panels: [FusionPanelChipStatus], onProgress: FusionPanelRunner.ProgressHandler?) {
        self.panels = panels
        self.onProgress = onProgress
    }

    func emit() { publish { _ in } }

    func update(modelId: String, activity: ToolActivityPayload) {
        publish { panels in
            if let index = panels.firstIndex(where: { $0.modelId == modelId }) {
                panels[index].toolActivity = activity
            }
        }
    }

    func finish(_ result: PanelResult) {
        publish { panels in
            if let index = panels.firstIndex(where: { $0.modelId == result.modelId }) {
                panels[index].state = result.success ? .succeeded : .failed
                panels[index].toolActivity = result.toolActivity
            }
        }
    }

    private func publish(_ mutation: (inout [FusionPanelChipStatus]) -> Void) {
        lock.lock()
        mutation(&panels)
        let snapshot = FusionProgressSnapshot.panelPhase(panels: panels)
        lock.unlock()
        onProgress?(snapshot)
    }
}

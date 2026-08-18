import XCTest
@testable import YamabikoChat

private let validJudgeJSON = """
{
  "consensus": ["agree on A"],
  "contradictions": [],
  "unique_insights": [{"model": "m1", "insight": "insight", "use_in_final": true}],
  "coverage_gaps": [],
  "suspected_errors": [],
  "strongest_answer_parts": [{"model": "m1", "part": "part", "reason": "clear"}],
  "recommended_final_position": "Use A",
  "confidence": "high"
}
"""

final class FusionOrchestratorTests: XCTestCase {
    private let orchestrator = FusionOrchestrator()

    private func sampleRequest(panelModels: [PanelModelConfig]) -> FusionRequest {
        FusionRequest(
            userPrompt: "What is 2+2?",
            systemPrompt: nil,
            panelModels: panelModels,
            judgeModel: PanelModelConfig(
                modelId: "judge-model",
                provider: "OPENAI",
                temperature: 0.1,
                timeoutMs: 5_000
            ),
            synthesizerModel: PanelModelConfig(
                modelId: "synth-model",
                provider: "OPENAI",
                temperature: 0.3,
                timeoutMs: 5_000
            ),
            preset: "quality",
            timeoutMs: 5_000,
            allowWebSearch: false,
            taskType: .research,
            metadata: [:]
        )
    }

    private func buildRequest(
        model: PanelModelConfig,
        systemPrompt: String,
        phase: FusionPhase,
        allowTools: Bool
    ) throws -> ProviderRequest {
        ProviderRequest(
            model: model.modelId,
            messages: [ProviderRequestMessage(role: "user", content: "What is 2+2?")],
            systemPrompt: systemPrompt,
            stream: phase == .synthesizer,
            tools: [],
            metadata: ["phase": phase.rawValue]
        )
    }

    func testAllPanelModelsSucceed() async throws {
        let request = sampleRequest(panelModels: [
            PanelModelConfig(modelId: "panel-a", provider: "OPENAI", timeoutMs: 5_000),
            PanelModelConfig(modelId: "panel-b", provider: "OPENAI", timeoutMs: 5_000)
        ])

        let outcome = try await orchestrator.runThroughJudge(
            request: request,
            context: FusionContext(),
            buildRequest: buildRequest,
            invoke: mockInvoke,
            estimateCost: { _, _, _ in 0.001 }
        )

        XCTAssertEqual(outcome.trace.panelResults.count, 2)
        XCTAssertTrue(outcome.trace.panelResults.allSatisfy(\.success))
        XCTAssertTrue(outcome.trace.judgeResult?.parseSucceeded == true)
        XCTAssertEqual(outcome.synthesisRequest.model, "synth-model")
    }

    func testProgressCallbackReportsPanelJudgeAndSynthesizerPhases() async throws {
        let request = sampleRequest(panelModels: [
            PanelModelConfig(modelId: "panel-a", provider: "OPENAI", timeoutMs: 5_000),
            PanelModelConfig(modelId: "panel-b", provider: "OPENAI", timeoutMs: 5_000)
        ])
        var progressSnapshots: [FusionProgressSnapshot] = []

        _ = try await orchestrator.runThroughJudge(
            request: request,
            context: FusionContext(),
            buildRequest: buildRequest,
            invoke: mockInvoke,
            estimateCost: { _, _, _ in nil },
            onProgress: { snapshot in
                progressSnapshots.append(snapshot)
            }
        )

        XCTAssertFalse(progressSnapshots.isEmpty)
        XCTAssertEqual(progressSnapshots.first?.phase, .panel)
        XCTAssertTrue(progressSnapshots.contains(where: { $0.phase == .judge }))
        XCTAssertEqual(progressSnapshots.last?.phase, .synthesizer)
        XCTAssertEqual(progressSnapshots.last?.completedPanelCount, 2)
    }

    func testOnePanelModelFails() async throws {
        let request = sampleRequest(panelModels: [
            PanelModelConfig(modelId: "panel-ok", provider: "OPENAI", timeoutMs: 5_000),
            PanelModelConfig(modelId: "panel-fail", provider: "OPENAI", timeoutMs: 5_000)
        ])

        let outcome = try await orchestrator.runThroughJudge(
            request: request,
            context: FusionContext(),
            buildRequest: buildRequest,
            invoke: mockInvoke,
            estimateCost: { _, _, _ in nil }
        )

        XCTAssertEqual(outcome.trace.failedModels, ["panel-fail"])
        XCTAssertEqual(outcome.trace.panelResults.filter(\.success).count, 1)
        XCTAssertNotNil(outcome.trace.judgeResult)
    }

    func testAllPanelModelsFailThrows() async {
        let request = sampleRequest(panelModels: [
            PanelModelConfig(modelId: "panel-fail", provider: "OPENAI", timeoutMs: 5_000)
        ])

        do {
            _ = try await orchestrator.runThroughJudge(
                request: request,
                context: FusionContext(),
                buildRequest: buildRequest,
                invoke: mockInvoke,
                estimateCost: { _, _, _ in nil }
            )
            XCTFail("Expected allPanelsFailed")
        } catch FusionError.allPanelsFailed(let panelResults) {
            XCTAssertFalse(panelResults.isEmpty)
            XCTAssertTrue(panelResults.allSatisfy { !$0.success })
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testReasoningOnlyPanelResponseIsRecordedAsFailure() async {
        let request = sampleRequest(panelModels: [
            PanelModelConfig(modelId: "reasoning-only", provider: "OPENAI", timeoutMs: 5_000)
        ])

        do {
            _ = try await orchestrator.runThroughJudge(
                request: request,
                context: FusionContext(),
                buildRequest: buildRequest,
                invoke: { _, _, _, _ in
                    ProviderResponse(text: "", reasoningSummary: "unfinished reasoning")
                },
                estimateCost: { _, _, _ in nil }
            )
            XCTFail("Expected reasoning-only panel response to fail")
        } catch FusionError.allPanelsFailed(let panelResults) {
            XCTAssertEqual(panelResults.count, 1)
            XCTAssertFalse(panelResults[0].success)
            XCTAssertTrue(panelResults[0].error?.contains("returned no answer text") == true)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testPanelRunsPastLegacyConfiguredTimeout() async throws {
        let request = sampleRequest(panelModels: [
            PanelModelConfig(modelId: "panel-slow", provider: "OPENAI", timeoutMs: 50)
        ])

        let outcome = try await orchestrator.runThroughJudge(
            request: request,
            context: FusionContext(),
            buildRequest: buildRequest,
            invoke: slowInvoke,
            estimateCost: { _, _, _ in nil }
        )

        XCTAssertEqual(outcome.trace.panelResults.first?.content, "late")
        XCTAssertTrue(outcome.trace.panelResults.first?.success == true)
    }

    func testSynthesizerMergesConversationSystemPrompt() async throws {
        var request = sampleRequest(panelModels: [
            PanelModelConfig(modelId: "panel-a", provider: "OPENAI", timeoutMs: 5_000)
        ])
        request.systemPrompt = "Custom conversation system"

        let outcome = try await orchestrator.runThroughJudge(
            request: request,
            context: FusionContext(),
            buildRequest: buildRequest,
            invoke: mockInvoke,
            estimateCost: { _, _, _ in nil }
        )

        let systemPrompt = outcome.synthesisRequest.systemPrompt ?? ""
        XCTAssertTrue(systemPrompt.contains("Custom conversation system"))
        XCTAssertTrue(systemPrompt.contains("final user-facing answer"))
    }

    func testJudgeValidJSON() async throws {
        let request = sampleRequest(panelModels: [
            PanelModelConfig(modelId: "panel-a", provider: "OPENAI", timeoutMs: 5_000)
        ])
        let outcome = try await orchestrator.runThroughJudge(
            request: request,
            context: FusionContext(),
            buildRequest: buildRequest,
            invoke: mockInvoke,
            estimateCost: { _, _, _ in nil }
        )
        XCTAssertEqual(outcome.trace.judgeResult?.analysis?.recommendedFinalPosition, "Use A")
    }

    func testJudgeInvalidJSONThrows() async throws {
        let request = sampleRequest(panelModels: [
            PanelModelConfig(modelId: "panel-a", provider: "OPENAI", timeoutMs: 5_000)
        ])
        do {
            _ = try await orchestrator.runThroughJudge(
                request: request,
                context: FusionContext(),
                buildRequest: buildRequest,
                invoke: invalidJudgeInvoke,
                estimateCost: { _, _, _ in nil }
            )
            XCTFail("Expected invalid judge JSON to fail")
        } catch ProviderClientError.parseFailure {
            // Expected.
        }
    }

    func testRecursionGuardThrows() async throws {
        let request = sampleRequest(panelModels: [
            PanelModelConfig(modelId: "panel-a", provider: "OPENAI", timeoutMs: 5_000)
        ])
        do {
            _ = try await orchestrator.runThroughJudge(
                request: request,
                context: FusionContext(fusionDepth: 1),
                buildRequest: buildRequest,
                invoke: mockInvoke,
                estimateCost: { _, _, _ in nil }
            )
            XCTFail("Expected recursion limit error")
        } catch FusionError.recursionLimitExceeded {
            // Expected.
        }
    }

    func testPresetLoaderResolvesDefaultWhenJSONEmpty() throws {
        let resolved = try FusionPresetLoader.resolveDefinition(customPresetJSON: "")
        XCTAssertGreaterThanOrEqual(resolved.panelModels.count, 1)
    }

    func testPresetLoaderResolvesCustomPresetJSON() throws {
        let defaultPreset = AppSettings.defaultFusionCustomPreset()
        var custom = defaultPreset
        custom.panelModels = [defaultPreset.panelModels[0]]
        let json = AppSettings().encodeFusionCustomPreset(custom)

        let resolved = try FusionPresetLoader.resolveDefinition(customPresetJSON: json)
        XCTAssertEqual(resolved.panelModels.count, 1)
        XCTAssertEqual(resolved.panelModels[0].modelId, defaultPreset.panelModels[0].modelId)

        let request = try FusionPresetLoader.buildRequest(
            userPrompt: "hello",
            customPresetJSON: json
        )
        XCTAssertEqual(request.preset, FusionPresetLoader.presetLabel)
        XCTAssertEqual(request.panelModels.count, 1)
    }

    func testTraceCostAggregation() {
        let trace = orchestrator.finalizeTrace(
            trace: FusionTrace(
                requestId: "t1",
                preset: "quality",
                startedAtMs: 0,
                completedAtMs: nil,
                panelResults: [
                    PanelResult(
                        modelId: "a",
                        provider: "OPENAI",
                        success: true,
                        content: "a",
                        error: nil,
                        latencyMs: 10,
                        inputTokens: 1,
                        outputTokens: 1,
                        cost: 0.01,
                        toolCalls: nil,
                        finishReason: nil,
                        role: nil
                    )
                ],
                judgeResult: JudgePhaseResult(
                    analysis: nil,
                    rawJSON: nil,
                    parseSucceeded: true,
                    latencyMs: 5,
                    inputTokens: 1,
                    outputTokens: 1,
                    cost: 0.02,
                    error: nil
                ),
                synthesisResult: nil,
                totalLatencyMs: nil,
                totalCost: nil,
                failedModels: [],
                status: "judge_complete",
                userPrompt: nil,
                finalAnswer: nil
            ),
            synthesisResult: SynthesisPhaseResult(
                modelId: "s",
                provider: "OPENAI",
                success: true,
                content: "final",
                latencyMs: 8,
                inputTokens: 1,
                outputTokens: 1,
                cost: 0.03,
                error: nil
            ),
            finalAnswer: "final",
            logPrompts: false
        )
        XCTAssertEqual(trace.totalCost ?? 0, 0.06, accuracy: 0.0001)
        XCTAssertEqual(trace.status, "completed")
    }

    // MARK: - Mock invokes

    private func mockInvoke(
        request: ProviderRequest,
        provider: String,
        phase: FusionPhase,
        onToolActivity: @escaping @Sendable (ToolActivityPayload) -> Void
    ) async throws -> ProviderResponse {
        switch phase {
        case .panel:
            if request.model.contains("fail") || request.model.contains("slow") {
                throw ProviderClientError.parseFailure("panel failed")
            }
            return ProviderResponse(text: "panel-\(request.model)", usage: ProviderUsage(inputTokens: 3, outputTokens: 5))
        case .judge:
            return ProviderResponse(text: validJudgeJSON, usage: ProviderUsage(inputTokens: 10, outputTokens: 20))
        case .synthesizer:
            return ProviderResponse(text: "synth-\(request.model)", usage: ProviderUsage(inputTokens: 4, outputTokens: 6))
        }
    }

    private func slowInvoke(
        request: ProviderRequest,
        provider: String,
        phase: FusionPhase,
        onToolActivity: @escaping @Sendable (ToolActivityPayload) -> Void
    ) async throws -> ProviderResponse {
        if phase == .panel {
            try await Task.sleep(nanoseconds: 200_000_000)
            return ProviderResponse(text: "late")
        }
        return try await mockInvoke(request: request, provider: provider, phase: phase, onToolActivity: onToolActivity)
    }

    private func invalidJudgeInvoke(
        request: ProviderRequest,
        provider: String,
        phase: FusionPhase,
        onToolActivity: @escaping @Sendable (ToolActivityPayload) -> Void
    ) async throws -> ProviderResponse {
        if phase == .judge {
            if request.messages.first?.content.contains("Repair") == true {
                return ProviderResponse(text: "not-json", usage: ProviderUsage(inputTokens: 1, outputTokens: 1))
            }
            return ProviderResponse(text: "{invalid", usage: ProviderUsage(inputTokens: 1, outputTokens: 1))
        }
        return try await mockInvoke(request: request, provider: provider, phase: phase, onToolActivity: onToolActivity)
    }
}

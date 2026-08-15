import XCTest
@testable import YamabikoChat

final class FusionProgressSnapshotTests: XCTestCase {
    private func sampleRequest() -> FusionRequest {
        FusionRequest(
            userPrompt: "test",
            systemPrompt: nil,
            panelModels: [
                PanelModelConfig(modelId: "panel-a", provider: "OPENAI"),
                PanelModelConfig(modelId: "panel-b", provider: "GEMINI")
            ],
            judgeModel: PanelModelConfig(modelId: "judge", provider: "OPENAI"),
            synthesizerModel: PanelModelConfig(modelId: "synth", provider: "OPENAI"),
            preset: "quality",
            timeoutMs: 5_000,
            allowWebSearch: false,
            taskType: .auto,
            metadata: [:]
        )
    }

    func testInitialPanelsAreRunning() {
        let panels = FusionProgressSnapshot.initialPanels(from: sampleRequest())
        XCTAssertEqual(panels.count, 2)
        XCTAssertTrue(panels.allSatisfy { $0.state == .running })
    }

    func testApplyingPanelResultUpdatesChipState() {
        let initial = FusionProgressSnapshot.initialPanels(from: sampleRequest())
        let snapshot = FusionProgressSnapshot.panelPhase(panels: initial)
        let successResult = PanelResult(
            modelId: "panel-a",
            provider: "OPENAI",
            success: true,
            content: "ok",
            error: nil,
            latencyMs: 100,
            inputTokens: 1,
            outputTokens: 2,
            cost: 0.001,
            toolCalls: nil,
            finishReason: nil,
            role: nil
        )

        let updated = snapshot.applyingPanelResult(successResult)
        XCTAssertEqual(updated.completedPanelCount, 1)
        XCTAssertEqual(updated.panels.first(where: { $0.modelId == "panel-a" })?.state, .succeeded)
        XCTAssertEqual(updated.panels.first(where: { $0.modelId == "panel-b" })?.state, .running)
    }

    func testApplyingFailedPanelResultMarksFailed() {
        let initial = FusionProgressSnapshot.initialPanels(from: sampleRequest())
        let snapshot = FusionProgressSnapshot.panelPhase(panels: initial)
        let failedResult = PanelResult(
            modelId: "panel-b",
            provider: "GEMINI",
            success: false,
            content: "",
            error: "timeout",
            latencyMs: 50,
            inputTokens: nil,
            outputTokens: nil,
            cost: nil,
            toolCalls: nil,
            finishReason: nil,
            role: nil
        )

        let updated = snapshot.applyingPanelResult(failedResult)
        XCTAssertEqual(updated.completedPanelCount, 1)
        XCTAssertEqual(updated.panels.first(where: { $0.modelId == "panel-b" })?.state, .failed)
    }
}

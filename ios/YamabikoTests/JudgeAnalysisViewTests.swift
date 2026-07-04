import XCTest
@testable import YamabikoChat

final class JudgeAnalysisViewTests: XCTestCase {
    func testConfidenceLabels() {
        XCTAssertEqual(FusionTracePresentation.confidenceLabel(.low), L10n.text("低信頼"))
        XCTAssertEqual(FusionTracePresentation.confidenceLabel(.medium), L10n.text("中信頼"))
        XCTAssertEqual(FusionTracePresentation.confidenceLabel(.high), L10n.text("高信頼"))
    }

    func testHasVisibleContentWhenConsensusPresent() {
        let analysis = JudgeAnalysis(
            consensus: ["A"],
            contradictions: [],
            uniqueInsights: [],
            coverageGaps: [],
            suspectedErrors: [],
            sourceQualityIssues: [],
            strongestAnswerParts: [],
            recommendedFinalPosition: "",
            confidence: .medium,
            notes: nil
        )
        XCTAssertTrue(JudgeAnalysisPresentation.hasVisibleContent(analysis))
    }

    func testHasVisibleContentFalseForNil() {
        XCTAssertFalse(JudgeAnalysisPresentation.hasVisibleContent(nil))
    }

    func testSummaryLineIncludesPanelCounts() {
        let trace = FusionTrace(
            requestId: "trace-1",
            preset: "quality",
            startedAtMs: 0,
            completedAtMs: 1_000,
            panelResults: [
                PanelResult(
                    modelId: "a",
                    provider: "OPENAI",
                    success: true,
                    content: "x",
                    error: nil,
                    latencyMs: 100,
                    inputTokens: nil,
                    outputTokens: nil,
                    cost: nil,
                    toolCalls: nil,
                    finishReason: nil,
                    role: nil
                ),
                PanelResult(
                    modelId: "b",
                    provider: "GEMINI",
                    success: false,
                    content: "",
                    error: "fail",
                    latencyMs: 50,
                    inputTokens: nil,
                    outputTokens: nil,
                    cost: nil,
                    toolCalls: nil,
                    finishReason: nil,
                    role: nil
                )
            ],
            judgeResult: JudgePhaseResult(
                analysis: JudgeAnalysis(
                    consensus: [],
                    contradictions: [],
                    uniqueInsights: [],
                    coverageGaps: [],
                    suspectedErrors: [],
                    sourceQualityIssues: [],
                    strongestAnswerParts: [],
                    recommendedFinalPosition: "ok",
                    confidence: .high,
                    notes: nil
                ),
                rawJSON: nil,
                parseSucceeded: true,
                latencyMs: 200,
                inputTokens: nil,
                outputTokens: nil,
                cost: 0.01,
                error: nil
            ),
            synthesisResult: nil,
            totalLatencyMs: 1_000,
            totalCost: 0.02,
            failedModels: ["b"],
            status: "completed",
            userPrompt: nil,
            finalAnswer: nil
        )

        let summary = FusionTracePresentation.summaryLine(for: trace)
        XCTAssertTrue(summary.contains("1/2"))
        XCTAssertTrue(summary.contains(L10n.text("高信頼")))
    }
}
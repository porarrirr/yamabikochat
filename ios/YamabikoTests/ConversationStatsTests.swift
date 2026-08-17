import XCTest
import Combine
import GRDB
@testable import YamabikoChat

private final class ConversationMetricSink: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [ConversationExecutionMetric] = []

    func append(_ metric: ConversationExecutionMetric) {
        lock.withLock { storage.append(metric) }
    }

    var values: [ConversationExecutionMetric] {
        lock.withLock { storage }
    }
}

final class ConversationStatsTests: XCTestCase {
    func testFormattingMatchesCompactStatsLine() {
        XCTAssertEqual(ChatStatsFormatter.tokens(517), "517")
        XCTAssertEqual(ChatStatsFormatter.tokens(12_200), "12.2K")
        XCTAssertEqual(ChatStatsFormatter.tokens(643_000), "643K")
        XCTAssertEqual(ChatStatsFormatter.tokens(1_250_000), "1.3M")
        XCTAssertEqual(ChatStatsFormatter.duration(milliseconds: 45_240), "45.2s")
        XCTAssertEqual(ChatStatsFormatter.duration(milliseconds: 162_000), "2m42s")
        XCTAssertEqual(ChatStatsFormatter.throughput(154.6), "155")
    }

    func testDerivedAveragesAndCacheHitUseDisjointBuckets() {
        let stats = ConversationStats(
            turns: 2,
            steps: 3,
            llmDurationMs: 4_500,
            toolDurationMs: 1_000,
            ttftTotalMs: 1_500,
            ttftSampleCount: 2,
            decodeDurationMs: 3_000,
            decodeOutputTokens: 30,
            inputTokens: 80,
            outputTokens: 30,
            cachedInputTokens: 70,
            cacheCreationInputTokens: 5
        )

        XCTAssertEqual(stats.averageTTFTMs, 750)
        XCTAssertEqual(stats.tokensPerSecond, 10)
        XCTAssertEqual(stats.billedInputTokens, 155)
        XCTAssertEqual(stats.cacheHitPercent, 45)
    }

    func testMissingSamplesDoNotInventLatencyOrThroughput() {
        let stats = ConversationStats(steps: 1, llmDurationMs: 900)

        XCTAssertNil(stats.averageTTFTMs)
        XCTAssertNil(stats.tokensPerSecond)
        XCTAssertNil(stats.cacheHitPercent)
    }

    func testContextUsageUsesPiOfficialEstimate() throws {
        let usage = try XCTUnwrap(ContextUsage(
            record: TokenUsageRecord(
                provider: "OPENAI",
                model: "gpt-test",
                inputTokens: 25,
                outputTokens: 40_000,
                totalTokens: 40_100,
                reasoningTokens: 30_000,
                cachedInputTokens: 70,
                cacheCreationInputTokens: 5,
                contextTokens: 100,
                contextWindow: 400
            )
        ))

        XCTAssertEqual(usage.usedTokens, 100)
        XCTAssertEqual(usage.percent, 25)
        XCTAssertEqual(usage.fraction, 0.25)
    }

    func testContextUsageRequiresCapacityAndClampsDisplayAtOneHundredPercent() throws {
        let record = TokenUsageRecord(
            provider: "OPENAI",
            model: "gpt-test",
            inputTokens: 500
        )

        XCTAssertNil(ContextUsage(record: record))

        let usage = try XCTUnwrap(ContextUsage(record: TokenUsageRecord(
            provider: "OPENAI",
            model: "gpt-test",
            inputTokens: 500,
            contextTokens: 500,
            contextWindow: 100
        )))
        XCTAssertEqual(usage.percent, 100)
        XCTAssertEqual(usage.fraction, 1)
    }

    func testPiAgentEventsRecordEachLLMStepAndMatchedToolDirectly() throws {
        let sink = ConversationMetricSink()
        let context = ProviderMetricsContext(
            conversationId: 9,
            turnId: "turn-1",
            recorder: { [sink] metric in sink.append(metric) }
        )
        var collector = PiConversationMetricsCollector(context: context)

        collector.startLLM(stepID: 1, at: 1_000)
        collector.observeToken(at: 1_200)
        collector.endLLM(
            stepID: 1,
            at: 1_700,
            succeeded: true,
            usage: ProviderUsage(
                inputTokens: 100,
                outputTokens: 20,
                cachedInputTokens: 70,
                cacheCreationInputTokens: 5
            )
        )
        collector.startTool(callID: "call-1", at: 1_710)
        collector.endTool(callID: "call-1", at: 1_900, succeeded: true)
        collector.startLLM(stepID: 2, at: 2_000)
        collector.observeToken(at: 2_100)
        collector.endLLM(
            stepID: 2,
            at: 2_500,
            succeeded: true,
            usage: ProviderUsage(inputTokens: 30, outputTokens: 10)
        )

        let metrics = sink.values
        XCTAssertEqual(metrics.map(\.kind), [.llm, .tool, .llm])
        XCTAssertEqual(metrics.map(\.turnId), ["turn-1", "turn-1", "turn-1"])
        XCTAssertEqual(metrics[0].firstTokenAtMs, 1_200)
        XCTAssertEqual(metrics[0].inputTokens, 100)
        XCTAssertEqual(metrics[0].cachedInputTokens, 70)
        XCTAssertEqual(metrics[0].cacheCreationInputTokens, 5)
        XCTAssertEqual(metrics[0].outputTokens, 20)
        XCTAssertEqual(metrics[1].completedAtMs - metrics[1].startedAtMs, 190)
        XCTAssertEqual(metrics[2].firstTokenAtMs, 2_100)
        XCTAssertEqual(metrics[2].outputTokens, 10)
    }

    func testPiUsageBucketsRemainDisjointWithoutSubtractingCacheTwice() {
        let usage = ProviderUsage(
            inputTokens: 25,
            outputTokens: 10,
            cachedInputTokens: 70,
            cacheCreationInputTokens: 5
        ).normalized()
        XCTAssertEqual(usage.inputTokens, 25)
        XCTAssertEqual(usage.cachedInputTokens, 70)
        XCTAssertEqual(usage.cacheCreationInputTokens, 5)
        XCTAssertEqual(usage.totalTokens, 35)

        let stats = ConversationStats(
            inputTokens: 96,
            outputTokens: 101,
            cachedInputTokens: 800
        )
        XCTAssertEqual(stats.billedInputTokens, 896)
        XCTAssertEqual(stats.cacheHitPercent, 89)
    }

    func testDefaultVisibilityAndRoundTrip() {
        var settings = AppSettings()
        XCTAssertEqual(settings.visibleChatStatsFields(), [.tokensPerSecond, .cacheHit, .tokens])

        settings.setVisibleChatStatsFields([.turns, .averageTTFT])
        XCTAssertEqual(settings.visibleChatStatsFields(), [.turns, .averageTTFT])
    }

    func testRepositoryAggregatesTurnsStepsTimingToolsAndUsage() throws {
        let dbQueue = try DatabaseQueue()
        try AppDatabase.migrator.migrate(dbQueue)
        let repository = ConversationRepository(dbQueue: dbQueue)
        let conversationId = try repository.createConversation(
            title: "Stats",
            model: "model",
            provider: "OPENAI"
        )

        try repository.insertExecutionMetric(metric(
            conversationId: conversationId,
            turnId: "turn-1",
            kind: .llm,
            start: 0,
            first: 1_000,
            end: 3_000,
            succeeded: true,
            input: 30,
            output: 20,
            cached: 70,
            created: 0
        ))
        try repository.insertExecutionMetric(metric(
            conversationId: conversationId,
            turnId: "turn-1",
            kind: .tool,
            start: 3_000,
            first: nil,
            end: 4_000,
            succeeded: true
        ))
        try repository.insertExecutionMetric(metric(
            conversationId: conversationId,
            turnId: "turn-1",
            kind: .llm,
            start: 4_000,
            first: nil,
            end: 4_500,
            succeeded: false
        ))
        try repository.insertExecutionMetric(metric(
            conversationId: conversationId,
            turnId: "turn-2",
            kind: .llm,
            start: 5_000,
            first: 5_500,
            end: 6_500,
            succeeded: true,
            input: 50,
            output: 10,
            cached: 0,
            created: 5
        ))

        let observed = expectation(description: "aggregated stats")
        var value: ConversationStats?
        var cancellable: AnyCancellable?
        cancellable = repository.observeConversationStats(conversationId: conversationId)
            .sink { stats in
                guard stats.steps == 3 else { return }
                value = stats
                observed.fulfill()
            }
        wait(for: [observed], timeout: 2)
        withExtendedLifetime(cancellable) {}

        XCTAssertEqual(value?.turns, 2)
        XCTAssertEqual(value?.steps, 3)
        XCTAssertEqual(value?.llmDurationMs, 4_500)
        XCTAssertEqual(value?.toolDurationMs, 1_000)
        XCTAssertEqual(value?.ttftTotalMs, 1_500)
        XCTAssertEqual(value?.ttftSampleCount, 2)
        XCTAssertEqual(value?.decodeDurationMs, 3_000)
        XCTAssertEqual(value?.decodeOutputTokens, 30)
        XCTAssertEqual(value?.billedInputTokens, 155)
        XCTAssertEqual(value?.outputTokens, 30)
    }

    private func metric(
        conversationId: Int64,
        turnId: String,
        kind: ConversationExecutionMetric.Kind,
        start: Int64,
        first: Int64?,
        end: Int64,
        succeeded: Bool,
        input: Int? = nil,
        output: Int? = nil,
        cached: Int? = nil,
        created: Int? = nil
    ) -> ConversationExecutionMetric {
        ConversationExecutionMetric(
            conversationId: conversationId,
            turnId: turnId,
            kind: kind,
            startedAtMs: start,
            firstTokenAtMs: first,
            completedAtMs: end,
            succeeded: succeeded,
            inputTokens: input,
            outputTokens: output,
            cachedInputTokens: cached,
            cacheCreationInputTokens: created
        )
    }
}

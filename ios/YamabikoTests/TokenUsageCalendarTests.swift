import XCTest
@testable import YamabikoChat

final class TokenUsageCalendarTests: XCTestCase {
    private let dayMs: Int64 = 86_400_000
    // Sunday, 2026-10-11, 00:00 UTC.
    private let sunday: Int64 = 1_791_676_800_000

    func testRollingWindowKeepsBothPartialBoundaryDaysAndFillsInactiveDays() {
        let end = sunday + 3 * dayMs
        let point = makePoint(bucket: end - dayMs, tokens: 40)
        let calendar = TokenUsageCalendar(
            points: [point], rangeDays: 3,
            referenceDate: Date(timeIntervalSince1970: Double(end) / 1000 + 3600)
        )

        XCTAssertEqual(calendar.days.count, 4)
        XCTAssertEqual(calendar.days.map(\.bucketStartMs), [sunday, sunday + dayMs, sunday + 2 * dayMs, end])
        XCTAssertEqual(calendar.days.map(\.tokens), [0, 0, 40, 0])
        XCTAssertEqual(calendar.days.map(\.level), [0, 0, 4, 0])
        XCTAssertEqual(calendar.leadingEmptyDays, 0)
    }

    func testWeekPaddingDoesNotCreateSelectableDaysOutsideWindow() {
        let calendar = TokenUsageCalendar(
            points: [], rangeDays: 2,
            referenceDate: Date(timeIntervalSince1970: Double(sunday + 3 * dayMs) / 1000)
        )
        XCTAssertEqual(calendar.leadingEmptyDays, 1)
        XCTAssertEqual(calendar.weekCount, 1)
        XCTAssertNil(calendar.day(week: 0, weekday: 0))
        XCTAssertEqual(calendar.day(week: 0, weekday: 1)?.bucketStartMs, sunday + dayMs)
        XCTAssertNil(calendar.day(week: 0, weekday: 4))
    }

    func testIntensityUsesOnlyVisibleDaysAndPreservesZero() {
        let points = [
            makePoint(bucket: sunday - dayMs, tokens: 1_000_000),
            makePoint(bucket: sunday, tokens: 0),
            makePoint(bucket: sunday + dayMs, tokens: 1),
            makePoint(bucket: sunday + 2 * dayMs, tokens: 26),
            makePoint(bucket: sunday + 3 * dayMs, tokens: 51),
            makePoint(bucket: sunday + 4 * dayMs, tokens: 100),
            makePoint(bucket: sunday + 5 * dayMs, tokens: 1_000_000)
        ]
        let calendar = TokenUsageCalendar(
            points: points, rangeDays: 4,
            referenceDate: Date(timeIntervalSince1970: Double(sunday + 4 * dayMs) / 1000)
        )
        XCTAssertEqual(calendar.days.map(\.level), [0, 1, 2, 3, 4])
        XCTAssertEqual(calendar.days[2].requests, 1)
        XCTAssertEqual(calendar.days[2].cost, 0.001)
    }

    private func makePoint(bucket: Int64, tokens: Int64) -> TokenUsageDailyPoint {
        TokenUsageDailyPoint(dayBucketStartMs: bucket, requestCount: 1, totalTokens: tokens, totalCostUsd: 0.001)
    }
}

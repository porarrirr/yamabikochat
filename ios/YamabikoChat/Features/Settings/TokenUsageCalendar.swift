import Foundation

/// Presentation of the repository's UTC day buckets. Empty days remain visible.
struct TokenUsageCalendar {
    struct Day: Identifiable {
        var id: Int64 { bucketStartMs }
        let bucketStartMs: Int64
        let point: TokenUsageDailyPoint?
        let level: Int

        var date: Date { Date(timeIntervalSince1970: Double(bucketStartMs) / 1000) }
        var tokens: Int64 { point?.totalTokens ?? 0 }
        var requests: Int64 { point?.requestCount ?? 0 }
        var cost: Double { point?.totalCostUsd ?? 0 }
    }

    let days: [Day]
    let leadingEmptyDays: Int

    init(points: [TokenUsageDailyPoint], rangeDays: Int, referenceDate: Date) {
        let dayMs: Int64 = 86_400_000
        let end = Int64(referenceDate.timeIntervalSince1970 * 1000) / dayMs * dayMs
        // The rolling window can include part of both the first and last UTC day.
        let start = end - Int64(max(1, rangeDays)) * dayMs
        let visible = points.filter { $0.dayBucketStartMs >= start && $0.dayBucketStartMs <= end }
        let maximum = max(1, visible.map(\.totalTokens).max() ?? 1)
        let buckets = Dictionary(visible.map { ($0.dayBucketStartMs, $0) }, uniquingKeysWith: { _, last in last })
        days = stride(from: start, through: end, by: Int(dayMs)).map { bucket in
            let point = buckets[bucket]
            let tokens = point?.totalTokens ?? 0
            let level = tokens > 0 ? min(4, max(1, Int(ceil(Double(tokens) / Double(maximum) * 4)))) : 0
            return Day(bucketStartMs: bucket, point: point, level: level)
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        leadingEmptyDays = calendar.component(.weekday, from: Date(timeIntervalSince1970: Double(start) / 1000)) - 1
    }

    var weekCount: Int { (leadingEmptyDays + days.count + 6) / 7 }

    func day(week: Int, weekday: Int) -> Day? {
        let index = week * 7 + weekday - leadingEmptyDays
        return days.indices.contains(index) ? days[index] : nil
    }
}

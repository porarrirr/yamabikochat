import Foundation

enum OpenCodeGoUsagePeriod: String, CaseIterable, Sendable {
    case rolling
    case weekly
    case monthly
}

struct OpenCodeGoUsageWindow: Equatable, Sendable {
    let period: OpenCodeGoUsagePeriod
    let status: String
    let usedPercent: Double
    let resetsAt: Date

    var boundedUsedPercent: Double {
        min(max(usedPercent, 0), 100)
    }

    var remainingPercent: Double {
        100 - boundedUsedPercent
    }
}

struct OpenCodeGoUsageStatus: Equatable, Sendable {
    let rolling: OpenCodeGoUsageWindow
    let weekly: OpenCodeGoUsageWindow
    let monthly: OpenCodeGoUsageWindow

    var windows: [OpenCodeGoUsageWindow] {
        [rolling, weekly, monthly]
    }
}

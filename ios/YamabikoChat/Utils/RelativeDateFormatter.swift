import Foundation

enum RelativeDateFormatter {
    private static let formatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()

    static func format(epochMs: Int64) -> String {
        guard epochMs > 0 else { return "" }
        let date = Date(timeIntervalSince1970: Double(epochMs) / 1000.0)
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

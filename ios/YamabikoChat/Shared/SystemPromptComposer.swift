import Foundation

enum SystemPromptComposer {
    private static let dateLabel = "Today's date: "
    private static let dateSuffixSeparator = "\n\n"

    static func composeForAPI(_ systemPrompt: String?, now: Date = Date()) -> String? {
        let dateSuffix = dateLabel + formattedDate(now)
        guard let trimmed = systemPrompt?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return dateSuffix
        }
        return trimmed + dateSuffixSeparator + dateSuffix
    }

    static func mergeForAPI(_ systemPrompts: String?..., now: Date = Date()) -> String? {
        let merged = systemPrompts
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: dateSuffixSeparator)
        return composeForAPI(merged.isEmpty ? nil : merged, now: now)
    }

    private static func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy/MM/dd"
        return formatter.string(from: date)
    }
}
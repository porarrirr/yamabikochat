import Foundation

extension String {
    /// Trims whitespace/newlines; returns `nil` when the result is empty.
    var trimmedNonEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

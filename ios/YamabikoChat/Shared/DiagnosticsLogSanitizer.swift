import Foundation

enum DiagnosticsLogSanitizer {
    private static let sensitiveQueryKeys: Set<String> = [
        "code",
        "state",
        "access_token",
        "refresh_token",
        "id_token",
        "token",
        "password",
        "secret",
        "api_key",
        "apikey",
        "authorization"
    ]

    static func sanitize(_ text: String) -> String {
        var result = text

        result = replacingRegex(
            in: result,
            pattern: #"(?i)\bbearer\s+[A-Za-z0-9._\-]+"#,
            with: "Bearer [REDACTED]"
        )
        result = replacingRegex(
            in: result,
            pattern: #"(?i)\b(api[_-]?key|access[_-]?token|refresh[_-]?token|id[_-]?token|client[_-]?secret|password)\s*[:=]\s*["']?[^"'\s,&]+"#,
            with: "$1=[REDACTED]"
        )
        result = redactSensitiveQueryItems(in: result)

        return result
    }

    static func sanitizeCallbackPath(_ pathWithQuery: String) -> String {
        guard let queryIndex = pathWithQuery.firstIndex(of: "?") else {
            return pathWithQuery
        }
        let path = String(pathWithQuery[..<queryIndex])
        return "\(path)?[REDACTED]"
    }

    private static func redactSensitiveQueryItems(in text: String) -> String {
        guard let queryStart = text.firstIndex(of: "?") else { return text }

        let prefix = String(text[..<queryStart])
        let query = String(text[text.index(after: queryStart)...])
        guard !query.isEmpty else { return text }

        let pairs = query.split(separator: "&", omittingEmptySubsequences: false)
        let redactedPairs = pairs.map { pair -> String in
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard let key = parts.first else { return String(pair) }
            let normalizedKey = key.split(separator: ";", maxSplits: 1).first?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased() ?? ""
            if sensitiveQueryKeys.contains(normalizedKey) {
                if parts.count > 1 {
                    return "\(key)=[REDACTED]"
                }
                return "\(key)=[REDACTED]"
            }
            return String(pair)
        }

        return prefix + "?" + redactedPairs.joined(separator: "&")
    }

    private static func replacingRegex(in text: String, pattern: String, with template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: template)
    }
}

import Foundation

enum HTMLTextExtractor {
    static func extract(from html: String, maxCharacters: Int = 8_000) -> String {
        let withoutInvisible = replacingMatches(
            in: html,
            pattern: #"(?is)<(script|style|noscript|svg|template)\b[^>]*>.*?</\1\s*>"#,
            with: " "
        )
        let withLineBreaks = replacingMatches(
            in: withoutInvisible,
            pattern: #"(?i)</?(p|div|section|article|header|footer|main|aside|h[1-6]|li|tr|br|hr)\b[^>]*>"#,
            with: "\n"
        )
        let withoutTags = replacingMatches(in: withLineBreaks, pattern: #"(?s)<[^>]+>"#, with: " ")
        let decoded = decodeEntities(withoutTags)
        let lines = decoded
            .components(separatedBy: .newlines)
            .map {
                $0.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }
        let normalized = lines.joined(separator: "\n")
        guard normalized.count > maxCharacters else { return normalized }
        return String(normalized.prefix(maxCharacters))
    }

    static func decodeEntities(_ input: String) -> String {
        var result = input
        let named = [
            "&amp;": "&",
            "&lt;": "<",
            "&gt;": ">",
            "&quot;": "\"",
            "&#39;": "'",
            "&apos;": "'",
            "&nbsp;": " "
        ]
        for (entity, value) in named {
            result = result.replacingOccurrences(of: entity, with: value, options: .caseInsensitive)
        }

        guard let regex = try? NSRegularExpression(pattern: #"&#(x[0-9a-fA-F]+|[0-9]+);"#) else {
            return result
        }
        let matches = regex.matches(in: result, range: NSRange(result.startIndex..., in: result)).reversed()
        for match in matches {
            guard let range = Range(match.range(at: 0), in: result),
                  let valueRange = Range(match.range(at: 1), in: result)
            else {
                continue
            }
            let raw = String(result[valueRange])
            let scalarValue = raw.lowercased().hasPrefix("x")
                ? UInt32(raw.dropFirst(), radix: 16)
                : UInt32(raw, radix: 10)
            guard let scalarValue, let scalar = UnicodeScalar(scalarValue) else { continue }
            result.replaceSubrange(range, with: String(Character(scalar)))
        }
        return result
    }

    private static func replacingMatches(in input: String, pattern: String, with replacement: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return input }
        return regex.stringByReplacingMatches(
            in: input,
            range: NSRange(input.startIndex..., in: input),
            withTemplate: replacement
        )
    }
}

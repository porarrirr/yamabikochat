import Foundation

enum HTMLTextExtractor {
    static func extract(from html: String, maxCharacters: Int = 8_000) -> String {
        let withoutContainers = replacingMatches(
            in: html,
            pattern: #"(?is)<(nav|header|footer|aside|form|dialog)\b[^>]*>.*?</\1\s*>"#,
            with: " "
        )
        let withoutInvisible = replacingMatches(
            in: withoutContainers,
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
        guard input.contains("&") else { return input }
        let original = input as NSString
        let namedDecoded = NSMutableString(string: input)
        for match in namedEntityRegex.matches(in: input, range: NSRange(location: 0, length: original.length)).reversed() {
            let entity = original.substring(with: match.range).lowercased()
            if let value = namedEntities[entity] { namedDecoded.replaceCharacters(in: match.range, with: value) }
        }
        let result = namedDecoded as String
        guard result.contains("&#") else { return result }
        let source = result as NSString
        let decoded = NSMutableString(string: result)
        let matches = numericEntityRegex.matches(in: result, range: NSRange(location: 0, length: source.length)).reversed()
        for match in matches {
            let raw = source.substring(with: match.range(at: 1))
            let scalarValue = raw.lowercased().hasPrefix("x")
                ? UInt32(raw.dropFirst(), radix: 16)
                : UInt32(raw, radix: 10)
            guard let scalarValue, let scalar = UnicodeScalar(scalarValue) else { continue }
            decoded.replaceCharacters(in: match.range, with: String(scalar))
        }
        return decoded as String
    }

    private static let numericEntityRegex = try! NSRegularExpression(pattern: #"&#(x[0-9a-fA-F]+|[0-9]+);"#)
    private static let namedEntityRegex = try! NSRegularExpression(pattern: #"&(?:amp|lt|gt|quot|apos|nbsp|#39);"#, options: .caseInsensitive)
    private static let namedEntities = ["&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&apos;": "'", "&nbsp;": " "]

    private static func replacingMatches(in input: String, pattern: String, with replacement: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return input }
        return regex.stringByReplacingMatches(
            in: input,
            range: NSRange(input.startIndex..., in: input),
            withTemplate: replacement
        )
    }
}

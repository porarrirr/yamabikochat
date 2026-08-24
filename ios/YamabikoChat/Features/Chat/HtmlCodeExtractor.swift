import Foundation

struct ExtractedHtmlBlock: Identifiable, Hashable {
    let id: String
    let language: String
    let content: String
    let startIndex: Int
    let endIndex: Int
    let extractionMethod: String
    let filename: String
}

enum ExtractedFenceRemover {
    static func remove(from text: String, ranges: [(start: Int, end: Int)]) -> String {
        guard !ranges.isEmpty else { return text }

        let mutable = NSMutableString(string: text)
        for range in ranges.sorted(by: { $0.start > $1.start }) {
            let length = range.end - range.start
            guard range.start >= 0, length > 0, range.end <= mutable.length else {
                continue
            }
            mutable.replaceCharacters(in: NSRange(location: range.start, length: length), with: "")
        }

        var normalized = (mutable as String)
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        normalized = replacing(
            pattern: "\n\\s*\n\\s*\n+",
            in: normalized,
            with: "\n\n"
        )
        return normalized.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func replacing(pattern: String, in text: String, with template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return text
        }
        let range = NSRange(location: 0, length: (text as NSString).length)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: template)
    }
}

enum HtmlCodeExtractor {
    private static let htmlLanguages: Set<String> = ["html", "htm", "xhtml"]

    static func extract(from text: String) -> [ExtractedHtmlBlock] {
        let pattern = "```(\\w*)\\n?([\\s\\S]*?)\\n?```"
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }

        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        var blocks: [ExtractedHtmlBlock] = []

        for match in matches {
            guard match.numberOfRanges >= 3 else { continue }

            let language = nsText.substring(with: match.range(at: 1))
            let content = nsText.substring(with: match.range(at: 2))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !content.isEmpty else { continue }
            guard shouldExtractFencedBlockAsHtml(language: language, content: content) else {
                continue
            }

            let start = match.range.location
            let end = match.range.location + match.range.length
            let filename = generateFilename(from: content)
            let id = "\(start)-\(end)-markdown-\(filename)"

            blocks.append(
                ExtractedHtmlBlock(
                    id: id,
                    language: "html",
                    content: content,
                    startIndex: start,
                    endIndex: end,
                    extractionMethod: "markdown",
                    filename: filename
                )
            )
        }

        return blocks.sorted { $0.startIndex < $1.startIndex }
    }

    static func removeExtractedBlocks(from text: String, blocks: [ExtractedHtmlBlock]) -> String {
        ExtractedFenceRemover.remove(
            from: text,
            ranges: blocks.map { (start: $0.startIndex, end: $0.endIndex) }
        )
    }

    static func documentTitle(from content: String) -> String? {
        firstCapturedValue(
            pattern: "<title[^>]*>(.*?)</title>",
            in: content,
            options: [.caseInsensitive]
        )
        .flatMap { title in
            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
    }

    private static func shouldExtractFencedBlockAsHtml(language: String, content: String) -> Bool {
        if isStandaloneSvg(content) && !isHtmlDocument(content) {
            return false
        }
        if htmlLanguages.contains(language.lowercased()) {
            return true
        }
        return isHtmlDocument(content)
    }

    private static func isHtmlDocument(_ content: String) -> Bool {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        if lower.contains("<!doctype html") { return true }
        if firstMarkupTag(in: trimmed) == "html" { return true }
        return lower.contains("<head")
            && (lower.contains("<body") || lower.contains("<title") || lower.contains("<meta"))
    }

    private static func isStandaloneSvg(_ content: String) -> Bool {
        let lower = content.lowercased()
        guard lower.contains("<svg"), lower.contains("</svg>") else { return false }
        return firstMarkupTag(in: content) == "svg"
    }

    private static func firstMarkupTag(in content: String) -> String? {
        var remaining = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if remaining.hasPrefix("\u{FEFF}") {
            remaining.removeFirst()
            remaining = remaining.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        while !remaining.isEmpty {
            remaining = remaining.trimmingCharacters(in: .whitespacesAndNewlines)
            let lower = remaining.lowercased()
            if lower.hasPrefix("<?xml") {
                guard let end = remaining.range(of: "?>") else { return nil }
                remaining = String(remaining[end.upperBound...])
                continue
            }
            if remaining.hasPrefix("<!--") {
                guard let end = remaining.range(of: "-->") else { return nil }
                remaining = String(remaining[end.upperBound...])
                continue
            }
            if lower.hasPrefix("<!doctype") {
                guard let end = remaining.range(of: ">") else { return nil }
                remaining = String(remaining[end.upperBound...])
                continue
            }
            guard remaining.hasPrefix("<") else { return nil }

            let nameStart = remaining.index(after: remaining.startIndex)
            var nameEnd = nameStart
            while nameEnd < remaining.endIndex {
                let character = remaining[nameEnd]
                if character.isWhitespace || character == ">" || character == "/" {
                    break
                }
                nameEnd = remaining.index(after: nameEnd)
            }
            let name = remaining[nameStart..<nameEnd]
            return name.isEmpty ? nil : name.lowercased()
        }
        return nil
    }

    private static func generateFilename(from content: String) -> String {
        let suggestedName = extractSuggestedName(from: content)
        let contentID = stableContentIdentifier(for: content)
        return "\(suggestedName)_\(contentID).html"
    }

    private static func stableContentIdentifier(for content: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in content.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1_099_511_628_211
        }
        let hex = String(hash, radix: 16)
        return String(repeating: "0", count: max(0, 16 - hex.count)) + hex
    }

    private static func extractSuggestedName(from content: String) -> String {
        if let title = documentTitle(from: content) {
            let cleaned = sanitizeFilenamePart(title)
            if !cleaned.isEmpty {
                return cleaned
            }
        }
        return "page"
    }

    private static func sanitizeFilenamePart(_ raw: String) -> String {
        let pattern = "[^A-Za-z0-9_-]"
        let cleaned = replacing(pattern: pattern, in: raw, with: "_")
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return String(cleaned.prefix(20)).isEmpty ? "page" : String(cleaned.prefix(20))
    }

    private static func firstCapturedValue(
        pattern: String,
        in text: String,
        options: NSRegularExpression.Options = []
    ) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            return nil
        }
        let nsText = text as NSString
        guard let match = regex.firstMatch(
            in: text,
            range: NSRange(location: 0, length: nsText.length)
        ), match.numberOfRanges > 1 else {
            return nil
        }
        return nsText.substring(with: match.range(at: 1))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func replacing(pattern: String, in text: String, with template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return text
        }
        let range = NSRange(location: 0, length: (text as NSString).length)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: template)
    }
}

enum HtmlPreviewPolicy {
    static func blocks(
        from text: String,
        isChatError: Bool,
        isActivelyStreaming: Bool
    ) -> [ExtractedHtmlBlock] {
        guard !isChatError, !isActivelyStreaming else { return [] }
        return HtmlCodeExtractor.extract(from: text)
    }
}

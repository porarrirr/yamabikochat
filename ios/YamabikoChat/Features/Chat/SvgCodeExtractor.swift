import Foundation

struct ExtractedSvgBlock: Identifiable, Hashable {
    let id: String
    let language: String
    let content: String
    let startIndex: Int
    let endIndex: Int
    let extractionMethod: String
    let filename: String
}

enum SvgCodeExtractor {
    static func containsSvgCode(_ text: String) -> Bool {
        !extract(from: text).isEmpty
    }

    static func extract(from text: String) -> [ExtractedSvgBlock] {
        var blocks: [ExtractedSvgBlock] = []
        blocks.append(contentsOf: extractMarkdownSvgBlocks(from: text))
        blocks.append(contentsOf: extractInlineSvgBlocks(from: text, existingBlocks: blocks))

        let deduplicated = Dictionary(
            blocks.map { block in
                ("\(block.startIndex)-\(block.endIndex)-\(block.content)", block)
            },
            uniquingKeysWith: { first, _ in first }
        ).values

        return deduplicated.sorted { $0.startIndex < $1.startIndex }
    }

    static func removeExtractedBlocks(from text: String, blocks: [ExtractedSvgBlock]) -> String {
        guard !blocks.isEmpty else { return text }

        let mutable = NSMutableString(string: text)
        for block in blocks.sorted(by: { $0.startIndex > $1.startIndex }) {
            let length = block.endIndex - block.startIndex
            guard block.startIndex >= 0, length > 0, block.endIndex <= mutable.length else {
                continue
            }
            mutable.replaceCharacters(in: NSRange(location: block.startIndex, length: length), with: "")
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

    private static func extractMarkdownSvgBlocks(from text: String) -> [ExtractedSvgBlock] {
        let pattern = "```(\\w*)\\n?([\\s\\S]*?)\\n?```"
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }

        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        var blocks: [ExtractedSvgBlock] = []

        for match in matches {
            guard match.numberOfRanges >= 3 else { continue }

            let language = nsText.substring(with: match.range(at: 1))
            let content = nsText.substring(with: match.range(at: 2))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !content.isEmpty else { continue }

            let isSvg = language.lowercased() == "svg" || isSvgContent(content)
            guard isSvg else { continue }

            let start = match.range.location
            let end = match.range.location + match.range.length
            let filename = generateFilename(from: content)
            let id = "\(start)-\(end)-markdown-\(filename)"

            blocks.append(
                ExtractedSvgBlock(
                    id: id,
                    language: "svg",
                    content: content,
                    startIndex: start,
                    endIndex: end,
                    extractionMethod: "markdown",
                    filename: filename
                )
            )
        }

        return blocks
    }

    private static func extractInlineSvgBlocks(
        from text: String,
        existingBlocks: [ExtractedSvgBlock]
    ) -> [ExtractedSvgBlock] {
        let pattern = "<svg\\b[^>]*>[\\s\\S]*?</svg>"
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive]
        ) else {
            return []
        }

        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        var blocks: [ExtractedSvgBlock] = []

        for match in matches {
            let start = match.range.location
            let end = match.range.location + match.range.length

            if isWithinCodeFence(text, startIndex: start) {
                continue
            }
            if overlapsExisting(range: match.range, existingBlocks: existingBlocks + blocks) {
                continue
            }

            let content = nsText.substring(with: match.range)
            let filename = generateFilename(from: content)
            let id = "\(start)-\(end)-inline-\(filename)"

            blocks.append(
                ExtractedSvgBlock(
                    id: id,
                    language: "svg",
                    content: content,
                    startIndex: start,
                    endIndex: end,
                    extractionMethod: "inline_svg",
                    filename: filename
                )
            )
        }

        return blocks
    }

    private static func overlapsExisting(
        range: NSRange,
        existingBlocks: [ExtractedSvgBlock]
    ) -> Bool {
        existingBlocks.contains { block in
            let left = max(range.location, block.startIndex)
            let right = min(range.location + range.length, block.endIndex)
            return left < right
        }
    }

    private static func isWithinCodeFence(_ text: String, startIndex: Int) -> Bool {
        guard startIndex > 0 else { return false }
        let nsText = text as NSString
        let beforeText = nsText.substring(to: min(startIndex, nsText.length))
        let fenceCount = beforeText.components(separatedBy: "```").count - 1
        return fenceCount % 2 == 1
    }

    private static func isSvgContent(_ content: String) -> Bool {
        let lower = content.lowercased()
        guard lower.contains("<svg"), lower.contains("</svg>") else { return false }
        return lower.contains("xmlns")
            || lower.contains("viewbox")
            || lower.contains("<path")
            || lower.contains("<circle")
            || lower.contains("<rect")
            || lower.contains("<line")
            || lower.contains("<polygon")
            || lower.contains("<polyline")
    }

    private static func generateFilename(from content: String) -> String {
        let suggestedName = extractSuggestedName(from: content)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = formatter.string(from: Date())
        return "\(suggestedName)_\(timestamp).svg"
    }

    private static func extractSuggestedName(from content: String) -> String {
        let titlePattern = "<title[^>]*>(.*?)</title>"
        if let title = firstCapturedValue(
            pattern: titlePattern,
            in: content,
            options: [.caseInsensitive]
        ) {
            let cleaned = sanitizeFilenamePart(title)
            if !cleaned.isEmpty {
                return cleaned
            }
        }
        return "graphic"
    }

    private static func sanitizeFilenamePart(_ raw: String) -> String {
        let pattern = "[^A-Za-z0-9_-]"
        let cleaned = replacing(pattern: pattern, in: raw, with: "_")
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return String(cleaned.prefix(20)).isEmpty ? "graphic" : String(cleaned.prefix(20))
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

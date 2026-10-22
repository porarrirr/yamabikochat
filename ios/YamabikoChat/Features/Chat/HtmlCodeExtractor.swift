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

enum HtmlCodeExtractor {
    private static let htmlLanguages: Set<String> = ["html", "htm", "xhtml"]

    static func extract(from text: String) -> [ExtractedHtmlBlock] {
        var blocks: [ExtractedHtmlBlock] = []
        for fence in MarkupExtractionSupport.fences(in: text) {
            let language = fence.language
            let content = fence.content
            guard shouldExtractFencedBlockAsHtml(language: language, content: content) else {
                continue
            }

            let start = fence.range.location
            let end = fence.range.location + fence.range.length
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
        if MarkupExtractionSupport.isStandaloneSvg(content) && !MarkupExtractionSupport.isHtmlDocument(content) {
            return false
        }
        if htmlLanguages.contains(language.lowercased()) {
            return true
        }
        return MarkupExtractionSupport.isHtmlDocument(content)
    }




    private static func generateFilename(from content: String) -> String {
        let suggestedName = extractSuggestedName(from: content)
        let contentID = MarkupExtractionSupport.stableContentIdentifier(for: content)
        return "\(suggestedName)_\(contentID).html"
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

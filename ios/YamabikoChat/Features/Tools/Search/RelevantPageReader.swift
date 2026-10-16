import Foundation
import NaturalLanguage

struct PageParagraph: Sendable, Equatable {
    let index: Int
    let heading: String?
    let text: String
    var isTableRow: Bool = false
}

struct RelevantPageSelection: Sendable, Equatable {
    enum Status: String, Sendable {
        case selected
        case overview
        case partialMatch = "partial_match"
        case noRelevantPassages = "no_relevant_passages"
        case dynamicContentUnavailable = "dynamic_content_unavailable"
    }

    let content: String
    let status: Status
    let selectedParagraphCount: Int
    let truncated: Bool
    var nextParagraph: Int? = nil
    var nextCharacter: Int? = nil
}

enum PageParagraphExtractor {
    static func prepare(_ paragraphs: [PageParagraph]) -> [PageParagraph] {
        var result: [PageParagraph] = []
        for paragraph in paragraphs {
            let characters = Array(paragraph.text)
            if paragraph.isTableRow || characters.count <= 1800 {
                result.append(PageParagraph(index: result.count, heading: paragraph.heading,
                                            text: paragraph.text, isTableRow: paragraph.isTableRow))
                continue
            }
            var start = 0
            while start < characters.count {
                let end = min(characters.count, start + 1800)
                result.append(PageParagraph(index: result.count, heading: paragraph.heading,
                                            text: String(characters[start ..< end])))
                if end == characters.count { break }
                start = end - 80 // overlap preserves phrases crossing a chunk boundary
            }
        }
        return result
    }

    static func extractJSON(_ data: Data) throws -> [PageParagraph] {
        let root = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        var texts: [String] = []
        appendJSONLeaves(root, path: "$", to: &texts)
        return texts.enumerated().map { offset, text in
            PageParagraph(index: offset, heading: nil, text: text)
        }
    }

    static func contentHTML(_ html: String) -> String {
        let sanitized = replacingMatches(in: html,
            pattern: #"(?is)<(script|style|noscript|svg|template)\b[^>]*>.*?</\1\s*>"#, with: " ")
        var content = sanitized
        var hasContentRoot = false
        // Prefer explicit content roots. Their headers/footers may contain source
        // dates, authors, definitions or caveats and must not be discarded as chrome.
        for tag in ["main", "article"] {
            guard let regex = try? NSRegularExpression(pattern: "(?is)<" + tag + #"\b[^>]*>(.*?)</"# + tag + #"\s*>"#) else { continue }
            let source = sanitized as NSString
            let roots = regex.matches(in: sanitized, range: NSRange(location: 0, length: source.length)).map { match in
                source.substring(with: match.range(at: 1))
            }
            if !roots.isEmpty { content = roots.joined(separator: "\n"); hasContentRoot = true; break }
        }
        return replacingMatches(in: removeNonContentContainers(from: content, preserveContentMetadata: hasContentRoot),
            pattern: #"(?is)<(script|style|noscript|svg|template)\b[^>]*>.*?</\1\s*>"#, with: " ")
    }

    static func extractHTML(_ html: String) -> [PageParagraph] {
        let visibleHTML = contentHTML(html)
        guard let regex = try? NSRegularExpression(
            pattern: #"(?is)<(h[1-6]|p|li|blockquote|pre|table|dl)\b[^>]*>(.*?)</\1\s*>|<(?:div|header|footer|aside|section|article|main)\b[^>]*>((?:(?!<(?:div|header|footer|aside|main|p|table|h[1-6]|ul|ol|section|article)\b).)*?)</(?:div|header|footer|aside|section|article|main)\s*>"#
        ) else {
            return []
        }

        var heading: String?
        var paragraphs: [PageParagraph] = []
        // ICU reports UTF-16 offsets. Bridging once avoids repeatedly walking
        // a Unicode document from its beginning to convert each match to String.Index.
        let source = visibleHTML as NSString
        for match in regex.matches(in: visibleHTML, range: NSRange(location: 0, length: source.length)) {
            if match.range(at: 3).location != NSNotFound {
                let text = normalizedText(source.substring(with: match.range(at: 3)))
                if !text.isEmpty {
                    paragraphs.append(PageParagraph(index: paragraphs.count, heading: heading, text: text))
                }
                continue
            }
            let tag = source.substring(with: match.range(at: 1)).lowercased()
            let content = source.substring(with: match.range(at: 2))
            let text = normalizedText(content)
            guard !text.isEmpty else { continue }
            if tag.hasPrefix("h") {
                heading = text
            } else if tag == "table" {
                for row in tableRows(content) {
                    paragraphs.append(PageParagraph(index: paragraphs.count, heading: heading, text: row, isTableRow: true))
                }
            } else {
                let body = tag == "pre" ? HTMLTextExtractor.decodeEntities(replacingMatches(
                    in: content, pattern: #"(?s)<[^>]+>"#, with: ""
                )) : text
                paragraphs.append(PageParagraph(index: paragraphs.count, heading: heading, text: body))
            }
        }
        if paragraphs.isEmpty {
            return extractPlainText(HTMLTextExtractor.extract(from: visibleHTML, maxCharacters: 2 * 1024 * 1024))
        }
        return paragraphs
    }

    // Keep each row atomic and expand merged headers before associating values.
    // Empty cells and provider quality markers must retain their column positions.
    private static func tableRows(_ html: String) -> [String] {
        guard let rowRegex = try? NSRegularExpression(pattern: #"(?is)<tr\b[^>]*>(.*?)</tr\s*>"#),
              let cellRegex = try? NSRegularExpression(pattern: #"(?is)<(th|td)\b([^>]*)>(.*?)</\1\s*>"#)
        else { return [] }
        struct Cell {
            let text: String
        }
        var grid: [[Int: Cell]] = []
        var headerDepth = 0
        let rows = rowRegex.matches(in: html, range: NSRange(html.startIndex..., in: html))
        for (rowIndex, row) in rows.enumerated() {
            guard let range = Range(row.range(at: 1), in: html) else { continue }
            let rowHTML = String(html[range])
            while grid.count <= rowIndex { grid.append([:]) }
            var column = 0
            let matches = cellRegex.matches(in: rowHTML, range: NSRange(rowHTML.startIndex..., in: rowHTML))
            for match in matches {
                guard let attributesRange = Range(match.range(at: 2), in: rowHTML),
                      let textRange = Range(match.range(at: 3), in: rowHTML) else { continue }
                let attributes = String(rowHTML[attributesRange])
                let colspan = tableSpan("colspan", attributes: attributes)
                let rowspan = tableSpan("rowspan", attributes: attributes)
                let text = normalizedText(String(rowHTML[textRange]))
                // Some official tables use td for multi-level column headers.
                if (rowIndex == 0 && (colspan > 1 || rowspan > 1)) ||
                    (rowIndex < headerDepth && (colspan > 1 || rowspan > 1)) {
                    headerDepth = max(headerDepth, rowIndex + rowspan)
                }
                while grid[rowIndex][column] != nil { column += 1 }
                let cell = Cell(text: text)
                for r in rowIndex ..< min(rows.count, rowIndex + rowspan) {
                    while grid.count <= r { grid.append([:]) }
                    for c in column ..< column + colspan { grid[r][c] = cell }
                }
                column += colspan
            }
            if !matches.isEmpty && matches.allSatisfy({
                guard let range = Range($0.range(at: 1), in: rowHTML) else { return false }
                return rowHTML[range].lowercased() == "th"
            }) && rowIndex <= headerDepth {
                headerDepth = max(headerDepth, rowIndex + 1)
            }
        }
        headerDepth = min(headerDepth, grid.count)
        var output: [String] = []
        if let captionRegex = try? NSRegularExpression(pattern: #"(?is)<caption\b[^>]*>(.*?)</caption\s*>"#),
           let match = captionRegex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
           let range = Range(match.range(at: 1), in: html) {
            output.append(normalizedText(String(html[range])))
        }
        for rowIndex in headerDepth ..< grid.count {
            let row = grid[rowIndex]
            let values = row.keys.sorted().map { column -> String in
                let value = row[column]?.text ?? ""
                var labels: [String] = []
                for h in 0 ..< headerDepth {
                    if let label = grid[h][column]?.text, !label.isEmpty, labels.last != label {
                        labels.append(label)
                    }
                }
                return labels.isEmpty ? value : labels.joined(separator: " / ") + ": " + value
            }
            output.append(values.joined(separator: " | "))
        }
        return output.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private static func tableSpan(_ name: String, attributes: String) -> Int {
        guard let regex = try? NSRegularExpression(pattern: "(?i)\\b" + name + #"\s*=\s*["']?(\d+)"#),
              let match = regex.firstMatch(in: attributes, range: NSRange(attributes.startIndex..., in: attributes)),
              let range = Range(match.range(at: 1), in: attributes) else { return 1 }
        return min(100, max(1, Int(attributes[range]) ?? 1))
    }

    static func extractPlainText(_ text: String) -> [PageParagraph] {
        let normalizedNewlines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let groupedText = normalizedNewlines.replacingOccurrences(
            of: #"\n\s*\n"#,
            with: "\u{0}",
            options: .regularExpression
        )
        let groups = groupedText.components(separatedBy: "\u{0}")
        let paragraphTexts = groups.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { $0.trimmingCharacters(in: .newlines) }
        return paragraphTexts.enumerated().map { offset, text in
            PageParagraph(index: offset, heading: nil, text: text)
        }
    }

    private static func appendJSONLeaves(_ value: Any, path: String, to texts: inout [String]) {
        switch value {
        case let object as [String: Any]:
            if object.isEmpty {
                texts.append("\(path): {}")
                return
            }
            for key in object.keys.sorted() {
                guard let nested = object[key] else { continue }
                appendJSONLeaves(nested, path: path + jsonPathComponent(key), to: &texts)
            }
        case let array as [Any]:
            if array.isEmpty {
                texts.append("\(path): []")
                return
            }
            for (index, nested) in array.enumerated() {
                appendJSONLeaves(nested, path: "\(path)[\(index)]", to: &texts)
            }
        default:
            texts.append("\(path): \(jsonScalar(value))")
        }
    }

    private static func jsonPathComponent(_ key: String) -> String {
        if key.range(of: #"^[A-Za-z_][A-Za-z0-9_]*$"#, options: .regularExpression) != nil {
            return ".\(key)"
        }
        let encoded = (try? JSONSerialization.data(withJSONObject: key, options: [.fragmentsAllowed]))
            .map { String(decoding: $0, as: UTF8.self) } ?? "\"\(key)\""
        return "[\(encoded)]"
    }

    private static func jsonScalar(_ value: Any) -> String {
        guard !(value is NSNull),
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed])
        else {
            return "null"
        }
        return String(decoding: data, as: UTF8.self)
    }

    private static func normalizedText(_ htmlFragment: String) -> String {
        let withSpaces = inlineTagRegex.stringByReplacingMatches(in: htmlFragment,
            range: NSRange(location: 0, length: (htmlFragment as NSString).length), withTemplate: " ")
        return collapseWhitespace(HTMLTextExtractor.decodeEntities(withSpaces))
    }

    private static let inlineTagRegex = try! NSRegularExpression(pattern: #"(?s)<[^>]+>"#)
    private static let whitespaceRegex = try! NSRegularExpression(pattern: #"\s+"#)

    private static func collapseWhitespace(_ value: String) -> String {
        whitespaceRegex.stringByReplacingMatches(in: value,
            range: NSRange(location: 0, length: (value as NSString).length), withTemplate: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func replacingMatches(in input: String, pattern: String, with replacement: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return input }
        return regex.stringByReplacingMatches(
            in: input,
            range: NSRange(input.startIndex..., in: input),
            withTemplate: replacement
        )
    }

    private static func removeNonContentContainers(from html: String, preserveContentMetadata: Bool = false) -> String {
        let containers = preserveContentMetadata ? "nav|form|dialog" : "nav|header|footer|aside|form|dialog"
        var result = replacingMatches(
            in: html,
            pattern: "(?is)<(" + containers + #")\b[^>]*>.*?</\1\s*>"#,
            with: " "
        )
        let explicitNonContentAttribute = #"(?:role\s*=\s*[\"'](?:navigation|banner|contentinfo|complementary|dialog|advertisement)[\"']|(?:class|id)\s*=\s*[\"'][^\"']*(?:advertisement|ad-container|ad-wrapper|cookie-banner|cookie-consent|newsletter|navbar|navigation|sidebar|site-footer|site-header)[^\"']*[\"'])"#
        result = replacingMatches(
            in: result,
            pattern: #"(?is)<(div|section)\b[^>]*\#(explicitNonContentAttribute)[^>]*>.*?</\1\s*>"#,
            with: " "
        )
        return result
    }
}

enum RelevantPageReader {
    static let defaultSeedLimit = 8
    static let defaultContextRadius = 1
    static let minimumSimilarity = 0.12
    static let minimumGoalTermCoverage = 0.8

    static func select(
        paragraphs: [PageParagraph],
        goal: String,
        maxCharacters: Int,
        seedLimit: Int = defaultSeedLimit,
        contextRadius: Int = defaultContextRadius
    ) -> RelevantPageSelection {
        guard maxCharacters > 0, !paragraphs.isEmpty else {
            return noRelevantSelection
        }

        // Literal source text (including examples such as {{ variable }}) is
        // evidence. Never infer missing content or factual sufficiency from syntax.
        let paragraphs = paragraphs.enumerated().map { offset, paragraph in
            PageParagraph(index: offset, heading: paragraph.heading, text: paragraph.text, isTableRow: paragraph.isTableRow)
        }
        let normalizedGoal = normalizeForComparison(goal)
        let importantTerms = extractImportantTerms(from: normalizedGoal)
        let bodies = paragraphs.map { normalizeForComparison($0.text) }
        let termWeights = Dictionary(uniqueKeysWithValues: importantTerms.map { term in
            let frequency = bodies.filter { $0.contains(term) }.count
            return (term, 0.2 + log(1 + Double(paragraphs.count) / Double(1 + frequency)))
        })
        let scored = paragraphs.compactMap { paragraph -> ScoredParagraph? in
            let body = normalizeForComparison(paragraph.text)
            let heading = normalizeForComparison(paragraph.heading ?? "")
            let bodySimilarity = bigramDice(body, normalizedGoal)
            let headingSimilarity = bigramDice(heading, normalizedGoal)
            let bodyTerms = importantTerms.filter { body.contains($0) }.count
            let headingTerms = importantTerms.filter { heading.contains($0) }.count
            let matchedTerms = bodyTerms + headingTerms
            // An entity in a row matters more than shared page/section headings.
            let weightedBodyTerms = importantTerms.filter { body.contains($0) }.reduce(0.0) { $0 + (termWeights[$1] ?? 0) }
            let score = bodySimilarity + (0.25 * headingSimilarity) + weightedBodyTerms + (0.1 * Double(headingTerms))
            guard matchedTerms > 0 || score >= minimumSimilarity else { return nil }
            return ScoredParagraph(index: paragraph.index, score: score)
        }
        .sorted {
            if $0.score == $1.score { return $0.index < $1.index }
            return $0.score > $1.score
        }

        guard !scored.isEmpty else {
            return window(paragraphs: paragraphs, start: 0, maxCharacters: maxCharacters)
        }
        var seeds = Array(scored.prefix(max(1, seedLimit)))
        var radius = max(0, contextRadius)
        let initialIndices = selectedIndices(
            seeds: seeds,
            paragraphCount: paragraphs.count,
            contextRadius: radius
        )
        let initialContent = render(paragraphs: paragraphs, indices: initialIndices)
        var truncated = initialContent.count > maxCharacters

        // Keep the strongest distinct passages before spending the budget on
        // neighboring rows/paragraphs. Dropping context is reversible via windows.
        while radius > 0 {
            let indices = selectedIndices(seeds: seeds, paragraphCount: paragraphs.count, contextRadius: radius)
            if render(paragraphs: paragraphs, indices: indices).count <= maxCharacters { break }
            radius -= 1
        }
        while seeds.count > 1 {
            let indices = selectedIndices(
                seeds: seeds,
                paragraphCount: paragraphs.count,
                contextRadius: radius
            )
            if render(paragraphs: paragraphs, indices: indices).count <= maxCharacters {
                break
            }
            seeds.removeLast()
        }

        var indices = selectedIndices(
            seeds: seeds,
            paragraphCount: paragraphs.count,
            contextRadius: radius
        )
        var content = render(paragraphs: paragraphs, indices: indices)
        if content.count > maxCharacters {
            indices = [seeds[0].index]
            content = render(paragraphs: paragraphs, indices: indices)
            truncated = true
        }
        if content.count > maxCharacters {
            content = String(content.prefix(maxCharacters))
            truncated = true
        }

        if !importantTerms.isEmpty {
            let normalizedContent = normalizeForComparison(content)
            let matchedCount = importantTerms.filter { normalizedContent.contains($0) }.count
            let coverage = Double(matchedCount) / Double(importantTerms.count)
            if coverage < minimumGoalTermCoverage {
                return RelevantPageSelection(
                    content: content,
                    status: .partialMatch,
                    selectedParagraphCount: indices.count,
                    truncated: truncated
                )
            }
        }

        return RelevantPageSelection(
            content: content,
            status: .selected,
            selectedParagraphCount: indices.count,
            truncated: truncated
        )
    }

    static func window(paragraphs: [PageParagraph], start: Int, maxCharacters: Int, startCharacter: Int = 0) -> RelevantPageSelection {
        guard paragraphs.indices.contains(start), maxCharacters > 0 else { return noRelevantSelection }
        var blocks: [String] = []
        var count = 0
        var size = 0
        for (position, paragraph) in paragraphs.enumerated().dropFirst(start) {
            let offset = position == start ? max(0, startCharacter) : 0
            let heading = offset == 0 ? (paragraph.heading.map { "## " + String($0.prefix(min(300, maxCharacters / 4))) + "\n\n" } ?? "") : ""
            let text = String(paragraph.text.dropFirst(offset))
            let block = heading + text
            let available = maxCharacters - size - (blocks.isEmpty ? 0 : 2)
            if block.count > available {
                if blocks.isEmpty {
                    // Continue inside a long paragraph/PDF page, without losing its tail.
                    let bodyBudget = max(1, available - heading.count)
                    let clipped = String(text.prefix(bodyBudget))
                    return RelevantPageSelection(content: String((heading + clipped).prefix(maxCharacters)), status: .overview,
                        selectedParagraphCount: 1, truncated: true, nextParagraph: position, nextCharacter: offset + clipped.count)
                }
                return RelevantPageSelection(content: blocks.joined(separator: "\n\n"), status: .overview,
                    selectedParagraphCount: count, truncated: true, nextParagraph: position, nextCharacter: 0)
            }
            blocks.append(block)
            count += 1
            size += block.count + (blocks.count == 1 ? 0 : 2)
        }
        return RelevantPageSelection(content: blocks.joined(separator: "\n\n"), status: .overview,
                                     selectedParagraphCount: count, truncated: false)
    }

    static func importantTerms(_ goal: String) -> Set<String> {
        extractImportantTerms(from: normalizeForComparison(goal))
    }

    static func normalizeSearchQuery(_ query: String) -> String {
        normalizeForComparison(query)
    }

    private static var noRelevantSelection: RelevantPageSelection {
        RelevantPageSelection(
            content: "",
            status: .noRelevantPassages,
            selectedParagraphCount: 0,
            truncated: false
        )
    }

    private static func selectedIndices(
        seeds: [ScoredParagraph],
        paragraphCount: Int,
        contextRadius: Int
    ) -> [Int] {
        var result: Set<Int> = []
        for seed in seeds {
            let lower = max(0, seed.index - contextRadius)
            let upper = min(paragraphCount - 1, seed.index + contextRadius)
            result.formUnion(lower ... upper)
        }
        return result.sorted()
    }

    private static func render(paragraphs: [PageParagraph], indices: [Int]) -> String {
        var blocks: [String] = []
        var previousHeading: String?
        for index in indices {
            guard paragraphs.indices.contains(index) else { continue }
            let paragraph = paragraphs[index]
            if let heading = paragraph.heading, heading != previousHeading {
                blocks.append("## \(heading)")
            }
            blocks.append(paragraph.text)
            previousHeading = paragraph.heading
        }
        return blocks.joined(separator: "\n\n")
    }

    private static func normalizeForComparison(_ value: String) -> String {
        let compatible = value.precomposedStringWithCompatibilityMapping.lowercased()
        let separators = CharacterSet.whitespacesAndNewlines
            .union(.punctuationCharacters)
            .union(.symbols)
        var result = ""
        var needsSpace = false
        for scalar in compatible.unicodeScalars {
            if separators.contains(scalar) {
                needsSpace = !result.isEmpty
            } else {
                if needsSpace, result.last != " " { result.append(" ") }
                result.unicodeScalars.append(scalar)
                needsSpace = false
            }
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func extractImportantTerms(from normalizedGoal: String) -> Set<String> {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = normalizedGoal
        let stopWords: Set<String> = ["the", "a", "an", "and", "or", "of", "for", "to", "in", "is", "on", "with", "from", "what", "how", "does", "please", "find", "confirm", "確認", "取得", "教えて", "について", "する", "です"]
        var terms: Set<String> = []
        tokenizer.enumerateTokens(in: normalizedGoal.startIndex ..< normalizedGoal.endIndex) { range, _ in
            let term = String(normalizedGoal[range])
            if term.count >= 2, !stopWords.contains(term) { terms.insert(term) }
            return true
        }
        // Preserve joined identifiers (e.g. OpenAI, model IDs, version numbers).
        if let regex = try? NSRegularExpression(pattern: #"[\p{L}\p{N}][\p{L}\p{N}._+-]*"#) {
            for match in regex.matches(in: normalizedGoal, range: NSRange(normalizedGoal.startIndex..., in: normalizedGoal)) {
                guard let range = Range(match.range, in: normalizedGoal) else { continue }
                let term = String(normalizedGoal[range])
                if term.count >= 2, !stopWords.contains(term) { terms.insert(term) }
            }
        }
        return terms
    }

    private static func bigramDice(_ lhs: String, _ rhs: String) -> Double {
        let left = bigrams(lhs)
        let right = bigrams(rhs)
        guard !left.isEmpty, !right.isEmpty else {
            return lhs == rhs && !lhs.isEmpty ? 1 : 0
        }
        let intersection = left.intersection(right).count
        return (2 * Double(intersection)) / Double(left.count + right.count)
    }

    private static func bigrams(_ value: String) -> Set<String> {
        let characters = Array(value.filter { !$0.isWhitespace })
        guard characters.count >= 2 else { return [] }
        return Set((0 ..< characters.count - 1).map {
            String(characters[$0 ... $0 + 1])
        })
    }

    private struct ScoredParagraph {
        let index: Int
        let score: Double
    }
}

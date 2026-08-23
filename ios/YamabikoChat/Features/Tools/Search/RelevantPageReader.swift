import Foundation

struct PageParagraph: Sendable, Equatable {
    let index: Int
    let heading: String?
    let text: String
}

struct RelevantPageSelection: Sendable, Equatable {
    enum Status: String, Sendable {
        case selected
        case partialMatch = "partial_match"
        case noRelevantPassages = "no_relevant_passages"
        case dynamicContentUnavailable = "dynamic_content_unavailable"
    }

    let content: String
    let status: Status
    let selectedParagraphCount: Int
    let truncated: Bool
}

enum PageParagraphExtractor {
    static func extractJSON(_ data: Data) throws -> [PageParagraph] {
        let root = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        var texts: [String] = []
        appendJSONLeaves(root, path: "$", to: &texts)
        return texts.enumerated().map { offset, text in
            PageParagraph(index: offset, heading: nil, text: text)
        }
    }

    static func extractHTML(_ html: String) -> [PageParagraph] {
        let withoutNonContentContainers = removeNonContentContainers(from: html)
        let visibleHTML = replacingMatches(
            in: withoutNonContentContainers,
            pattern: #"(?is)<(script|style|noscript|svg|template)\b[^>]*>.*?</\1\s*>"#,
            with: " "
        )
        guard let regex = try? NSRegularExpression(
            pattern: #"(?is)<(h[1-3]|p|li)\b[^>]*>(.*?)</\1\s*>"#
        ) else {
            return []
        }

        var heading: String?
        var paragraphs: [PageParagraph] = []
        for match in regex.matches(in: visibleHTML, range: NSRange(visibleHTML.startIndex..., in: visibleHTML)) {
            guard let tagRange = Range(match.range(at: 1), in: visibleHTML),
                  let contentRange = Range(match.range(at: 2), in: visibleHTML)
            else {
                continue
            }
            let tag = visibleHTML[tagRange].lowercased()
            let text = normalizedText(String(visibleHTML[contentRange]))
            guard !text.isEmpty else { continue }
            if tag.hasPrefix("h") {
                heading = text
            } else {
                paragraphs.append(
                    PageParagraph(index: paragraphs.count, heading: heading, text: text)
                )
            }
        }
        return paragraphs
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
        let paragraphTexts: [String] = groups.compactMap { group -> String? in
            let normalized = group
                .components(separatedBy: .newlines)
                .map { collapseWhitespace($0) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            guard !normalized.isEmpty else { return nil }
            return normalized
        }
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
        let withSpaces = replacingMatches(in: htmlFragment, pattern: #"(?s)<[^>]+>"#, with: " ")
        return collapseWhitespace(HTMLTextExtractor.decodeEntities(withSpaces))
    }

    private static func collapseWhitespace(_ value: String) -> String {
        value
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
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

    private static func removeNonContentContainers(from html: String) -> String {
        var result = replacingMatches(
            in: html,
            pattern: #"(?is)<(nav|header|footer|aside|form|dialog)\b[^>]*>.*?</\1\s*>"#,
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

        if paragraphs.contains(where: { containsUnresolvedTemplate($0.text) }) {
            return RelevantPageSelection(
                content: "",
                status: .dynamicContentUnavailable,
                selectedParagraphCount: 0,
                truncated: false
            )
        }

        let normalizedGoal = normalizeForComparison(goal)
        let importantTerms = extractImportantTerms(from: normalizedGoal)
        let scored = paragraphs.compactMap { paragraph -> ScoredParagraph? in
            let body = normalizeForComparison(paragraph.text)
            let heading = normalizeForComparison(paragraph.heading ?? "")
            let bodySimilarity = bigramDice(body, normalizedGoal)
            let headingSimilarity = bigramDice(heading, normalizedGoal)
            let matchedTerms = importantTerms.filter {
                body.contains($0) || heading.contains($0)
            }.count
            let score = bodySimilarity + (0.75 * headingSimilarity) + min(1.0, Double(matchedTerms) * 0.25)
            guard matchedTerms > 0 || score >= minimumSimilarity else { return nil }
            return ScoredParagraph(index: paragraph.index, score: score)
        }
        .sorted {
            if $0.score == $1.score { return $0.index < $1.index }
            return $0.score > $1.score
        }

        guard !scored.isEmpty else { return noRelevantSelection }
        var seeds = Array(scored.prefix(max(1, seedLimit)))
        let initialIndices = selectedIndices(
            seeds: seeds,
            paragraphCount: paragraphs.count,
            contextRadius: max(0, contextRadius)
        )
        let initialContent = render(paragraphs: paragraphs, indices: initialIndices)
        var truncated = initialContent.count > maxCharacters

        while seeds.count > 1 {
            let indices = selectedIndices(
                seeds: seeds,
                paragraphCount: paragraphs.count,
                contextRadius: max(0, contextRadius)
            )
            if render(paragraphs: paragraphs, indices: indices).count <= maxCharacters {
                break
            }
            seeds.removeLast()
        }

        var indices = selectedIndices(
            seeds: seeds,
            paragraphCount: paragraphs.count,
            contextRadius: max(0, contextRadius)
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
        guard let regex = try? NSRegularExpression(
            pattern: #"[\p{Han}]{2,}|[\p{Katakana}ー]{2,}|[a-z0-9][a-z0-9._+-]*"#,
            options: [.caseInsensitive]
        ) else {
            return []
        }
        return Set(regex.matches(
            in: normalizedGoal,
            range: NSRange(normalizedGoal.startIndex..., in: normalizedGoal)
        ).compactMap { match in
            guard let range = Range(match.range, in: normalizedGoal) else { return nil }
            let term = String(normalizedGoal[range])
            return term.count >= 2 ? term : nil
        })
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

    private static func containsUnresolvedTemplate(_ value: String) -> Bool {
        value.range(
            of: #"\{\{[^{}]+\}\}|\{%[^%]+%\}|<%[^%]+%>"#,
            options: .regularExpression
        ) != nil
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

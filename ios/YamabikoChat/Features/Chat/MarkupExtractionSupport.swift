import Foundation

/// Syntax and identity shared by HTML and SVG extraction; format policies stay separate.
enum MarkupExtractionSupport {
    static func isHtmlDocument(_ content: String) -> Bool {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        if lower.contains("<!doctype html") { return true }
        if firstMarkupTag(in: trimmed) == "html" { return true }
        return lower.contains("<head")
            && (lower.contains("<body") || lower.contains("<title") || lower.contains("<meta"))
    }

    static func isStandaloneSvg(_ content: String) -> Bool {
        let lower = content.lowercased()
        guard lower.contains("<svg"), lower.contains("</svg>") else { return false }
        return firstMarkupTag(in: content) == "svg"
    }

    static func firstMarkupTag(in content: String) -> String? {
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

    static func stableContentIdentifier(for content: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in content.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1_099_511_628_211
        }
        let hex = String(hash, radix: 16)
        return String(repeating: "0", count: max(0, 16 - hex.count)) + hex
    }

    struct Fence {
        let language: String
        let content: String
        let range: NSRange
    }

    static func fences(in text: String) -> [Fence] {
        let regex = try! NSRegularExpression(pattern: "```(\\w*)\\n?([\\s\\S]*?)\\n?```")
        let nsText = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: nsText.length)).compactMap { match in
            let content = nsText.substring(with: match.range(at: 2))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !content.isEmpty else { return nil }
            return Fence(language: nsText.substring(with: match.range(at: 1)), content: content, range: match.range)
        }
    }
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


import Foundation

enum LegalMarkdownBlock: Equatable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case table(headers: [String], rows: [[String]])
    case code(String)
}

enum LegalMarkdownParser {
    static func parse(_ markdown: String) -> [LegalMarkdownBlock] {
        let lines = markdown.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)

        var blocks: [LegalMarkdownBlock] = []
        var index = 0
        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                let (code, next) = readCodeBlock(lines: lines, start: index)
                if !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    blocks.append(.code(code))
                }
                index = next
                continue
            }

            if trimmed.isEmpty {
                index += 1
                continue
            }

            if let heading = parseHeading(trimmed) {
                blocks.append(heading)
                index += 1
                continue
            }

            if trimmed.hasPrefix("|") {
                let (table, next) = readTable(lines: lines, start: index)
                if let table {
                    blocks.append(table)
                }
                index = next
                continue
            }

            let (paragraph, next) = readParagraph(lines: lines, start: index)
            if !paragraph.isEmpty {
                blocks.append(.paragraph(paragraph))
            }
            index = next
        }
        return blocks
    }

    static func inlinePlainText(_ markdown: String) -> String {
        var text = markdown
        text = replaceLinks(in: text)
        text = text.replacingOccurrences(of: #"\*\*(.+?)\*\*"#, with: "$1", options: .regularExpression)
        text = text.replacingOccurrences(of: #"`([^`]+)`"#, with: "$1", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func parseHeading(_ line: String) -> LegalMarkdownBlock? {
        guard line.hasPrefix("#") else { return nil }
        var level = 0
        for character in line {
            if character == "#" { level += 1 } else { break }
        }
        guard (1...6).contains(level) else { return nil }
        let raw = String(line.dropFirst(level)).trimmingCharacters(in: .whitespaces)
        guard !raw.isEmpty else { return nil }
        return .heading(level: level, text: inlinePlainText(raw))
    }

    private static func readCodeBlock(lines: [String], start: Int) -> (String, Int) {
        var index = start + 1
        var body: [String] = []
        while index < lines.count {
            if lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                return (body.joined(separator: "\n"), index + 1)
            }
            body.append(lines[index])
            index += 1
        }
        return (body.joined(separator: "\n"), index)
    }

    private static func readTable(lines: [String], start: Int) -> (LegalMarkdownBlock?, Int) {
        var index = start
        var tableLines: [String] = []
        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("|") {
                tableLines.append(trimmed)
                index += 1
            } else {
                break
            }
        }

        let parsedRows = tableLines
            .map(splitTableRow)
            .filter { row in !row.isEmpty && !isAlignmentRow(row) }
        guard let headers = parsedRows.first, headers.count >= 2, parsedRows.count >= 2 else {
            return (nil, index)
        }
        let rows = parsedRows.dropFirst().map { row in
            padded(row, count: headers.count)
        }
        return (.table(headers: headers, rows: Array(rows)), index)
    }

    private static func readParagraph(lines: [String], start: Int) -> (String, Int) {
        var index = start
        var parts: [String] = []
        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") || trimmed.hasPrefix("|") || trimmed.hasPrefix("```") {
                break
            }
            parts.append(trimmed)
            index += 1
        }
        return (inlinePlainText(parts.joined(separator: " ")), index)
    }

    private static func splitTableRow(_ line: String) -> [String] {
        var cells = line.split(separator: "|", omittingEmptySubsequences: false).map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        if cells.first == "" { cells.removeFirst() }
        if cells.last == "" { cells.removeLast() }
        return cells.map(inlinePlainText)
    }

    private static func isAlignmentRow(_ row: [String]) -> Bool {
        !row.isEmpty && row.allSatisfy { cell in
            let compact = cell.replacingOccurrences(of: ":", with: "").replacingOccurrences(of: "-", with: "")
            return compact.isEmpty && cell.contains("-")
        }
    }

    private static func padded(_ row: [String], count: Int) -> [String] {
        if row.count >= count { return Array(row.prefix(count)) }
        return row + Array(repeating: "", count: count - row.count)
    }

    private static func replaceLinks(in text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"\[([^\]]+)\]\(([^)]+)\)"#) else {
            return text
        }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: "$1")
    }
}

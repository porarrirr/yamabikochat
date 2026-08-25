import Foundation
import CryptoKit
import Markdown
import SwiftUI
import UIKit

enum NativeMarkdownBlock: Identifiable, Equatable, Sendable {
    case paragraph(id: String, text: AttributedString)
    case heading(id: String, level: Int, text: AttributedString)
    case code(id: String, language: String?, code: String)
    case math(id: String, markdown: String)
    case quote(id: String, blocks: [NativeMarkdownBlock])
    case list(id: String, ordered: Bool, start: Int, rows: [AttributedString])
    case table(id: String, rows: [[AttributedString]])
    case divider(id: String)

    var id: String {
        switch self {
        case let .paragraph(id, _), let .heading(id, _, _), let .code(id, _, _), let .math(id, _),
             let .quote(id, _), let .list(id, _, _, _), let .table(id, _),
             let .divider(id): id
        }
    }
}

enum NativeMarkdownParser {
    static func parse(
        _ source: String,
        rendersMath: Bool = true,
        rootPath: String = "root"
    ) -> [NativeMarkdownBlock] {
        let document = Document(parsing: source)
        return parseChildren(of: document, path: rootPath, rendersMath: rendersMath)
    }

    private static func parseChildren(of parent: Markup, path: String, rendersMath: Bool) -> [NativeMarkdownBlock] {
        parent.children.enumerated().flatMap { index, child in
            parseBlock(child, path: "\(path)-\(index)", rendersMath: rendersMath)
        }
    }

    private static func parseBlock(_ markup: Markup, path: String, rendersMath: Bool) -> [NativeMarkdownBlock] {
        if let paragraph = markup as? Paragraph {
            if rendersMath, containsMath(paragraph.plainText) {
                return [.math(id: path, markdown: paragraph.plainText)]
            }
            return [.paragraph(id: path, text: inlineText(paragraph))]
        }
        if let heading = markup as? Heading {
            return [.heading(id: path, level: heading.level, text: inlineText(heading))]
        }
        if let code = markup as? CodeBlock {
            return [.code(id: path, language: code.language, code: code.code)]
        }
        if let quote = markup as? BlockQuote {
            return [.quote(id: path, blocks: parseChildren(of: quote, path: path, rendersMath: rendersMath))]
        }
        if let list = markup as? OrderedList {
            return [.list(
                id: path,
                ordered: true,
                start: Int(list.startIndex),
                rows: list.children.map(flattenInlineText)
            )]
        }
        if let list = markup as? UnorderedList {
            return [.list(
                id: path,
                ordered: false,
                start: 1,
                rows: list.children.map(flattenInlineText)
            )]
        }
        if let table = markup as? Markdown.Table {
            let header = table.head.children.compactMap { child -> AttributedString? in
                guard let cell = child as? Markdown.Table.Cell else { return nil }
                return flattenInlineText(cell)
            }
            let body = table.body.children.compactMap { row -> [AttributedString]? in
                guard let row = row as? Markdown.Table.Row else { return nil }
                return row.children.compactMap { child -> AttributedString? in
                    guard let cell = child as? Markdown.Table.Cell else { return nil }
                    return flattenInlineText(cell)
                }
            }
            return [.table(id: path, rows: [header] + body)]
        }
        if markup is ThematicBreak {
            return [.divider(id: path)]
        }
        if let html = markup as? HTMLBlock {
            return [.code(id: path, language: "html", code: html.rawHTML)]
        }
        return parseChildren(of: markup, path: path, rendersMath: rendersMath)
    }

    private static func containsMath(_ value: String) -> Bool {
        let inlinePattern = #"(?<!\\)\$(?!\s)(?:\\.|[^\n$])+(?<!\s)(?<!\\)\$(?![A-Za-z0-9])"#
        return hasOrderedPair(opening: "$$", closing: "$$", in: value)
            || value.range(of: inlinePattern, options: .regularExpression) != nil
            || hasOrderedPair(opening: "\\[", closing: "\\]", in: value)
            || hasOrderedPair(opening: "\\(", closing: "\\)", in: value)
    }

    private static func hasOrderedPair(opening: String, closing: String, in value: String) -> Bool {
        guard let openingRange = value.range(of: opening) else { return false }
        return value[openingRange.upperBound...].range(of: closing) != nil
    }

    private static func flattenInlineText(_ markup: Markup) -> AttributedString {
        if let inline = markup as? InlineContainer {
            return inlineText(inline)
        }
        var result = AttributedString()
        for (index, child) in markup.children.enumerated() {
            result.append(flattenInlineText(child))
            if index < markup.childCount - 1 {
                result.append(AttributedString("\n"))
            }
        }
        return result
    }

    private static func inlineText(_ container: InlineContainer) -> AttributedString {
        var result = AttributedString()
        for child in container.children {
            result.append(inlineText(child))
        }
        return result
    }

    private static func inlineText(_ markup: Markup) -> AttributedString {
        if let text = markup as? Markdown.Text {
            return AttributedString(text.string)
        }
        if let code = markup as? InlineCode {
            var value = AttributedString(code.code)
            value.inlinePresentationIntent = .code
            return value
        }
        if let html = markup as? InlineHTML {
            return AttributedString(html.rawHTML)
        }
        if markup is SoftBreak {
            return AttributedString("\n")
        }
        if markup is LineBreak {
            return AttributedString("\n")
        }

        var value = AttributedString()
        for child in markup.children {
            value.append(inlineText(child))
        }
        if markup is Strong {
            value.inlinePresentationIntent = .stronglyEmphasized
        } else if markup is Emphasis {
            value.inlinePresentationIntent = .emphasized
        } else if markup is Strikethrough {
            value.inlinePresentationIntent = .strikethrough
        } else if let link = markup as? Markdown.Link,
                  let destination = link.destination,
                  let url = URL(string: destination) {
            value.link = url
        }
        return value
    }
}

private actor NativeMarkdownBlockCache {
    static let shared = NativeMarkdownBlockCache()

    private var values: [String: [NativeMarkdownBlock]] = [:]
    private var order: [String] = []
    private let capacity = 256

    func blocks(for source: String, rendersMath: Bool, rootPath: String) -> [NativeMarkdownBlock] {
        let digest = SHA256.hash(data: Data(source.utf8)).map { String(format: "%02x", $0) }.joined()
        let key = "\(rendersMath ? 1 : 0):\(rootPath):\(digest)"
        if let cached = values[key] {
            touch(key)
            return cached
        }
        let parsed = NativeMarkdownParser.parse(source, rendersMath: rendersMath, rootPath: rootPath)
        values[key] = parsed
        order.append(key)
        if order.count > capacity {
            values.removeValue(forKey: order.removeFirst())
        }
        return parsed
    }

    private func touch(_ key: String) {
        if let index = order.firstIndex(of: key) {
            order.remove(at: index)
        }
        order.append(key)
    }
}

struct NativeMarkdownView: View {
    let markdownText: String
    var isStreaming = false
    var mathRenderingEnabled = true

    @State private var blocks: [NativeMarkdownBlock] = []
    @State private var parsedRequest: ParseRequest?
    @State private var stableStreamingPrefix = ""
    @State private var stableStreamingBlocks: [NativeMarkdownBlock] = []

    private struct ParseRequest: Hashable {
        let source: String
        let isStreaming: Bool
        let mathRenderingEnabled: Bool
    }

    private var parseRequest: ParseRequest {
        ParseRequest(
            source: markdownText,
            isStreaming: isStreaming,
            mathRenderingEnabled: mathRenderingEnabled
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if NativeMarkdownPresentationPolicy.showsInitialRawText(
                hasParsedRequest: parsedRequest != nil,
                hasRenderedBlocks: !blocks.isEmpty,
                sourceIsEmpty: markdownText.isEmpty
            ) {
                Text(markdownText)
                    .font(.body)
                    .lineSpacing(3)
                    .textSelection(.enabled)
            } else {
                ForEach(blocks) { block in
                    NativeMarkdownBlockView(block: block)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: parseRequest) {
            let request = parseRequest
            guard parsedRequest != request else { return }
            let source = request.source
            let result: [NativeMarkdownBlock]
            var nextStablePrefix = stableStreamingPrefix
            var nextStableBlocks = stableStreamingBlocks
            if request.isStreaming {
                let split = Self.streamingSplit(source)
                if split.prefix != stableStreamingPrefix {
                    nextStablePrefix = split.prefix
                    nextStableBlocks = await NativeMarkdownBlockCache.shared.blocks(
                        for: split.prefix,
                        rendersMath: false,
                        rootPath: "stable"
                    )
                }
                let tailBlocks = await NativeMarkdownBlockCache.shared.blocks(
                    for: split.tail,
                    rendersMath: false,
                    rootPath: "tail-\(split.prefix.utf8.count)"
                )
                result = nextStableBlocks + tailBlocks
            } else {
                result = await NativeMarkdownBlockCache.shared.blocks(
                    for: source,
                    rendersMath: request.mathRenderingEnabled,
                    rootPath: "root"
                )
                nextStablePrefix = ""
                nextStableBlocks = []
            }
            guard !Task.isCancelled, request == parseRequest else { return }
            blocks = result
            parsedRequest = request
            stableStreamingPrefix = nextStablePrefix
            stableStreamingBlocks = nextStableBlocks
        }
    }

    private static func streamingSplit(_ source: String) -> (prefix: String, tail: String) {
        guard let range = source.range(of: "\n\n", options: .backwards) else {
            return ("", source)
        }
        return (String(source[..<range.upperBound]), String(source[range.upperBound...]))
    }
}

enum NativeMarkdownPresentationPolicy {
    static func showsInitialRawText(
        hasParsedRequest: Bool,
        hasRenderedBlocks: Bool,
        sourceIsEmpty: Bool
    ) -> Bool {
        !sourceIsEmpty && !hasParsedRequest && !hasRenderedBlocks
    }
}

private struct NativeMarkdownBlockView: View {
    let block: NativeMarkdownBlock

    var body: some View {
        switch block {
        case let .paragraph(_, text):
            Text(text)
                .font(.body)
                .lineSpacing(3)
                .textSelection(.enabled)
        case let .heading(_, level, text):
            Text(text)
                .font(headingFont(level))
                .textSelection(.enabled)
                .padding(.top, level <= 2 ? 4 : 0)
        case let .code(_, language, code):
            NativeCodeBlock(language: language, code: code)
        case let .math(_, markdown):
            MathMarkdownView(markdownText: markdown, mathRenderingEnabled: true, isStreaming: false)
        case let .quote(_, blocks):
            HStack(alignment: .top, spacing: 12) {
                Capsule()
                    .fill(Color.secondary.opacity(0.45))
                    .frame(width: 3)
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(blocks) { child in
                        NativeMarkdownBlockView(block: child)
                    }
                }
            }
        case let .list(_, ordered, start, rows):
            VStack(alignment: .leading, spacing: 7) {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(ordered ? "\(start + index)." : "•")
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 18, alignment: .trailing)
                        Text(row)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                }
            }
        case let .table(_, rows):
            NativeMarkdownTable(rows: rows)
        case .divider:
            Divider()
        }
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: .title2.bold()
        case 2: .title3.bold()
        default: .headline
        }
    }
}

private struct NativeCodeBlock: View {
    let language: String?
    let code: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(language?.isEmpty == false ? language! : L10n.text("コード"))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    UIPasteboard.general.string = code
                } label: {
                    Label(L10n.text("コピー"), systemImage: "doc.on.doc")
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .frame(height: 38)

            Divider()

            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(12)
            }
        }
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct NativeMarkdownTable: View {
    let rows: [[AttributedString]]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                            Text(cell)
                                .font(rowIndex == 0 ? .caption.weight(.semibold) : .caption)
                                .frame(minWidth: 110, maxWidth: 220, alignment: .leading)
                                .padding(9)
                                .background(rowIndex == 0 ? Color.secondary.opacity(0.12) : Color.clear)
                                .border(Color.secondary.opacity(0.18), width: 0.5)
                        }
                    }
                }
            }
        }
    }
}

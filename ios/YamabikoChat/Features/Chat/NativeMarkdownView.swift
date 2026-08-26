import Foundation
import CryptoKit
import Markdown
import SwiftUI
import UIKit

private struct AskChatWithSelectionEnvironmentKey: EnvironmentKey {
    static let defaultValue: (String) -> Void = { _ in }
}

extension EnvironmentValues {
    var onAskChatWithSelection: (String) -> Void {
        get { self[AskChatWithSelectionEnvironmentKey.self] }
        set { self[AskChatWithSelectionEnvironmentKey.self] = newValue }
    }
}

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

    var renderID: String {
        let kind: String
        switch self {
        case .paragraph: kind = "paragraph"
        case let .heading(_, level, _): kind = "heading-\(level)"
        case .code: kind = "code"
        case .math: kind = "math"
        case .quote: kind = "quote"
        case let .list(_, ordered, _, _): kind = ordered ? "ordered-list" : "unordered-list"
        case .table: kind = "table"
        case .divider: kind = "divider"
        }
        return "\(id):\(kind)"
    }
}

enum NativeMarkdownParser {
    static func parse(
        _ source: String,
        rendersMath: Bool = true,
        baseUTF8Offset: Int = 0
    ) -> [NativeMarkdownBlock] {
        let document = Document(parsing: source)
        let offsets = SourceOffsetMap(source: source, baseUTF8Offset: baseUTF8Offset)
        return parseChildren(of: document, path: "root", rendersMath: rendersMath, offsets: offsets)
    }

    private static func parseChildren(
        of parent: Markup,
        path: String,
        rendersMath: Bool,
        offsets: SourceOffsetMap
    ) -> [NativeMarkdownBlock] {
        parent.children.enumerated().flatMap { index, child in
            let fallbackPath = "\(path)-\(index)"
            return parseBlock(
                child,
                path: offsets.blockID(for: child, fallbackPath: fallbackPath),
                rendersMath: rendersMath,
                offsets: offsets
            )
        }
    }

    private static func parseBlock(
        _ markup: Markup,
        path: String,
        rendersMath: Bool,
        offsets: SourceOffsetMap
    ) -> [NativeMarkdownBlock] {
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
            return [.quote(
                id: path,
                blocks: parseChildren(of: quote, path: path, rendersMath: rendersMath, offsets: offsets)
            )]
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
        return parseChildren(of: markup, path: path, rendersMath: rendersMath, offsets: offsets)
    }

    fileprivate struct SourceOffsetMap {
        let lineStartUTF8Offsets: [Int]
        let baseUTF8Offset: Int

        init(source: String, baseUTF8Offset: Int) {
            var starts = [0]
            for (index, byte) in source.utf8.enumerated() where byte == 0x0A {
                starts.append(index + 1)
            }
            lineStartUTF8Offsets = starts
            self.baseUTF8Offset = baseUTF8Offset
        }

        func blockID(for markup: Markup, fallbackPath: String) -> String {
            guard let location = markup.range?.lowerBound,
                  let offset = utf8Offset(for: location)
            else {
                return "block-\(baseUTF8Offset)-\(fallbackPath)"
            }
            return "block-\(baseUTF8Offset + offset)"
        }

        func utf8Offset(for location: SourceLocation) -> Int? {
            guard location.line > 0,
                  location.line <= lineStartUTF8Offsets.count
            else { return nil }
            return lineStartUTF8Offsets[location.line - 1] + max(0, location.column - 1)
        }
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
            return linkifiedText(text.string)
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
            if !String(value.characters).hasSuffix("↗") {
                value.append(AttributedString("↗"))
            }
            value.link = url
        }
        return value
    }

    /// Markdown parsers preserve a model-emitted bare URL as ordinary text. Keep
    /// the original destination while presenting a compact, readable link label.
    private static func linkifiedText(_ source: String) -> AttributedString {
        var result = AttributedString()
        var remaining = source[...]

        while let match = remaining.range(
            of: #"https?://[^\s<>\[\]{}\"']+"#,
            options: [.regularExpression, .caseInsensitive]
        ) {
            result.append(AttributedString(String(remaining[..<match.lowerBound])))

            let matchedText = String(remaining[match])
            let trimmedURL = matchedText.trimmingTrailingLinkPunctuation()
            guard let url = URL(string: trimmedURL),
                  let host = url.host,
                  !host.isEmpty else {
                result.append(AttributedString(matchedText))
                remaining = remaining[match.upperBound...]
                continue
            }

            let displayHost = host.replacingOccurrences(
                of: "www.",
                with: "",
                options: [.anchored, .caseInsensitive]
            )
            var link = AttributedString("\(displayHost)↗")
            link.link = url
            result.append(link)
            result.append(AttributedString(String(matchedText.dropFirst(trimmedURL.count))))
            remaining = remaining[match.upperBound...]
        }

        result.append(AttributedString(String(remaining)))
        return result
    }
}

private extension String {
    func trimmingTrailingLinkPunctuation() -> String {
        let punctuation = CharacterSet(charactersIn: ".,!?;:。、！？；：)]}」』》〉")
        var value = self
        while let scalar = value.unicodeScalars.last, punctuation.contains(scalar) {
            value.removeLast()
        }
        return value
    }
}

private actor NativeMarkdownBlockCache {
    static let shared = NativeMarkdownBlockCache()

    private var values: [String: [NativeMarkdownBlock]] = [:]
    private var order: [String] = []
    private let capacity = 256

    func blocks(for source: String, rendersMath: Bool, baseUTF8Offset: Int = 0) -> [NativeMarkdownBlock] {
        let digest = SHA256.hash(data: Data(source.utf8)).map { String(format: "%02x", $0) }.joined()
        let key = "\(rendersMath ? 1 : 0):\(baseUTF8Offset):\(digest)"
        if let cached = values[key] {
            touch(key)
            return cached
        }
        let parsed = NativeMarkdownParser.parse(
            source,
            rendersMath: rendersMath,
            baseUTF8Offset: baseUTF8Offset
        )
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

@MainActor
final class NativeMarkdownIncrementalParser {
    private var stablePrefix = ""
    private var stableBlocks: [NativeMarkdownBlock] = []

    func streamingBlocks(for source: String) -> [NativeMarkdownBlock] {
        if !source.hasPrefix(stablePrefix) {
            stablePrefix = ""
            stableBlocks = []
        }

        let split = Self.streamingSplit(source)
        if split.prefix != stablePrefix {
            let newStableSource = String(split.prefix.dropFirst(stablePrefix.count))
            let appendedBlocks = NativeMarkdownParser.parse(
                newStableSource,
                rendersMath: false,
                baseUTF8Offset: stablePrefix.utf8.count
            )
            stableBlocks.append(contentsOf: appendedBlocks)
            stablePrefix = split.prefix
        }

        let tailBlocks = NativeMarkdownParser.parse(
            split.tail,
            rendersMath: false,
            baseUTF8Offset: split.prefix.utf8.count
        )
        return stableBlocks + tailBlocks
    }

    func reset() {
        stablePrefix = ""
        stableBlocks = []
    }

    static func streamingSplit(_ source: String) -> (prefix: String, tail: String) {
        let document = Document(parsing: source)
        guard document.childCount > 1,
              let lastBlock = document.child(at: document.childCount - 1),
              let location = lastBlock.range?.lowerBound
        else {
            return ("", source)
        }
        let offsets = NativeMarkdownParser.SourceOffsetMap(source: source, baseUTF8Offset: 0)
        guard let boundaryOffset = offsets.utf8Offset(for: location),
              boundaryOffset > 0,
              boundaryOffset <= source.utf8.count
        else {
            return ("", source)
        }
        let utf8Boundary = source.utf8.index(source.utf8.startIndex, offsetBy: boundaryOffset)
        guard let boundary = String.Index(utf8Boundary, within: source) else {
            return ("", source)
        }
        let split = (prefix: String(source[..<boundary]), tail: String(source[boundary...]))
        assert(split.prefix + split.tail == source)
        return split
    }
}

struct NativeMarkdownView: View {
    let markdownText: String
    var isStreaming = false
    var mathRenderingEnabled = true
    var preparsedBlocks: [NativeMarkdownBlock]? = nil

    @State private var blocks: [NativeMarkdownBlock] = []
    @State private var parsedRequest: ParseRequest?
    @State private var incrementalParser = NativeMarkdownIncrementalParser()

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
        let hasCompletedFinalParse = !isStreaming && parsedRequest == parseRequest
        let renderedBlocks = hasCompletedFinalParse ? blocks : (preparsedBlocks ?? blocks)
        VStack(alignment: .leading, spacing: 12) {
            if NativeMarkdownPresentationPolicy.showsInitialRawText(
                hasParsedRequest: preparsedBlocks != nil || parsedRequest != nil,
                hasRenderedBlocks: !renderedBlocks.isEmpty,
                sourceIsEmpty: markdownText.isEmpty
            ) {
                SelectableChatText(text: AttributedString(markdownText), style: .body)
            } else {
                ForEach(renderedBlocks, id: \.renderID) { block in
                    NativeMarkdownBlockView(block: block)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .task(id: parseRequest) {
            let request = parseRequest
            guard parsedRequest != request else { return }
            // Streaming blocks are already published atomically with the snapshot.
            // Do not mirror them into @State: that second mutation schedules another
            // hosting-cell layout pass for the same frame and visibly bumps paragraphs.
            if request.isStreaming, preparsedBlocks != nil { return }
            let source = request.source
            let result: [NativeMarkdownBlock]
            if request.isStreaming {
                result = incrementalParser.streamingBlocks(for: source)
            } else {
                result = await NativeMarkdownBlockCache.shared.blocks(
                    for: source,
                    rendersMath: request.mathRenderingEnabled
                )
                incrementalParser.reset()
            }
            guard !Task.isCancelled, request == parseRequest else { return }
            var transaction = Transaction()
            transaction.animation = nil
            withTransaction(transaction) {
                blocks = result
                parsedRequest = request
            }
        }
        .transaction { transaction in
            transaction.animation = nil
        }
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
            SelectableChatText(text: text, style: .body)
        case let .heading(_, level, text):
            SelectableChatText(text: text, style: headingTextStyle(level), weight: .bold)
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
                            .id(child.renderID)
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
                        SelectableChatText(text: row, style: .body)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        case let .table(_, rows):
            NativeMarkdownTable(rows: rows)
        case .divider:
            Divider()
        }
    }

    private func headingTextStyle(_ level: Int) -> UIFont.TextStyle {
        switch level {
        case 1: .title2
        case 2: .title3
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
                            SelectableChatText(
                                text: cell,
                                style: .caption1,
                                weight: rowIndex == 0 ? .semibold : .regular
                            )
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

enum ChatTextSelectionPolicy {
    static func selectedText(in text: String, range: NSRange) -> String? {
        guard range.location != NSNotFound,
              range.length > 0,
              let swiftRange = Range(range, in: text) else { return nil }
        let selection = String(text[swiftRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        return selection.isEmpty ? nil : selection
    }
}

enum ChatTextLayoutPolicy {
    static func fittedWidth(naturalWidth: CGFloat, proposedWidth: CGFloat) -> CGFloat {
        min(proposedWidth, max(1, ceil(naturalWidth)))
    }
}

private struct SelectableChatText: UIViewRepresentable {
    let text: AttributedString
    let style: UIFont.TextStyle
    var weight: UIFont.Weight = .regular

    @Environment(\.onAskChatWithSelection) private var onAskChatWithSelection

    func makeCoordinator() -> Coordinator {
        Coordinator(onAskChatWithSelection: onAskChatWithSelection)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = false
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.adjustsFontForContentSizeCategory = true
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.setContentHuggingPriority(.required, for: .vertical)
        textView.accessibilityIdentifier = "selectable-chat-text"
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        context.coordinator.onAskChatWithSelection = onAskChatWithSelection
        let rendered = renderedText()
        if textView.attributedText != rendered {
            let selectedRange = textView.selectedRange
            textView.attributedText = rendered
            if NSMaxRange(selectedRange) <= rendered.length {
                textView.selectedRange = selectedRange
            }
        }
        textView.linkTextAttributes = [
            .foregroundColor: UIColor.label,
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiView: UITextView,
        context: Context
    ) -> CGSize? {
        guard let width = proposal.width, width > 0 else { return nil }
        let naturalBounds = uiView.attributedText.boundingRect(
            with: CGSize(
                width: CGFloat.greatestFiniteMagnitude,
                height: CGFloat.greatestFiniteMagnitude
            ),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )
        let fittedWidth = ChatTextLayoutPolicy.fittedWidth(
            naturalWidth: naturalBounds.width,
            proposedWidth: width
        )
        let measured = uiView.sizeThatFits(
            CGSize(width: fittedWidth, height: CGFloat.greatestFiniteMagnitude)
        )
        return CGSize(width: fittedWidth, height: ceil(measured.height))
    }

    private func renderedText() -> NSAttributedString {
        let rendered = NSMutableAttributedString(attributedString: NSAttributedString(text))
        let baseFont = UIFont.systemFont(
            ofSize: UIFont.preferredFont(forTextStyle: style).pointSize,
            weight: weight
        )
        let fullRange = NSRange(location: 0, length: rendered.length)
        rendered.addAttributes([
            .font: baseFont,
            .foregroundColor: UIColor.label
        ], range: fullRange)

        rendered.enumerateAttribute(.inlinePresentationIntent, in: fullRange) { value, range, _ in
            guard let intent = value as? InlinePresentationIntent else { return }
            var traits = baseFont.fontDescriptor.symbolicTraits
            if intent.contains(.stronglyEmphasized) { traits.insert(.traitBold) }
            if intent.contains(.emphasized) { traits.insert(.traitItalic) }
            if let descriptor = baseFont.fontDescriptor.withSymbolicTraits(traits) {
                rendered.addAttribute(.font, value: UIFont(descriptor: descriptor, size: 0), range: range)
            }
            if intent.contains(.strikethrough) {
                rendered.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
            }
        }

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 3
        rendered.addAttribute(.paragraphStyle, value: paragraph, range: fullRange)
        return rendered
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var onAskChatWithSelection: (String) -> Void

        init(onAskChatWithSelection: @escaping (String) -> Void) {
            self.onAskChatWithSelection = onAskChatWithSelection
        }

        func textView(
            _ textView: UITextView,
            editMenuForTextIn range: NSRange,
            suggestedActions: [UIMenuElement]
        ) -> UIMenu? {
            return menu(for: textView, range: range, suggestedActions: suggestedActions)
        }

        private func menu(
            for textView: UITextView,
            range: NSRange,
            suggestedActions: [UIMenuElement]
        ) -> UIMenu? {
            guard ChatTextSelectionPolicy.selectedText(in: textView.text, range: range) != nil else {
                return nil
            }

            let selectAllMenu = UIMenu(
                title: L10n.text("すべて"),
                image: UIImage(systemName: "selection.pin.in.out"),
                children: [
                    UIDeferredMenuElement.uncached { [weak self, weak textView] completion in
                        guard let self, let textView else {
                            completion([])
                            return
                        }
                        textView.selectedRange = NSRange(
                            location: 0,
                            length: textView.textStorage.length
                        )
                        completion(self.expandedMenuActions(for: textView))
                    }
                ]
            )

            return UIMenu(
                options: .displayInline,
                children: [askAction(for: textView), copyAction(for: textView), selectAllMenu]
            )
        }

        private func askAction(for textView: UITextView) -> UIAction {
            UIAction(
                title: L10n.text("チャットで質問する"),
                image: UIImage(systemName: "text.bubble")
            ) { [weak self, weak textView] _ in
                guard let self,
                      let textView,
                      let selection = ChatTextSelectionPolicy.selectedText(
                        in: textView.text,
                        range: textView.selectedRange
                      ) else { return }
                textView.resignFirstResponder()
                DispatchQueue.main.async {
                    self.onAskChatWithSelection(selection)
                }
            }
        }

        private func copyAction(for textView: UITextView) -> UIAction {
            UIAction(
                title: L10n.text("コピー"),
                image: UIImage(systemName: "doc.on.doc")
            ) { [weak self, weak textView] _ in
                guard let self,
                      let textView,
                      let selection = self.selection(in: textView) else { return }
                UIPasteboard.general.string = selection
            }
        }

        private func expandedMenuActions(for textView: UITextView) -> [UIMenuElement] {
            let selectAll = UIAction(
                title: L10n.text("すべてを選択"),
                image: UIImage(systemName: "selection.pin.in.out")
            ) { [weak textView] _ in
                guard let textView else { return }
                textView.selectedRange = NSRange(location: 0, length: textView.textStorage.length)
            }
            let lookup = UIAction(
                title: L10n.text("調べる"),
                image: UIImage(systemName: "info.circle")
            ) { [weak self, weak textView] _ in
                guard let self,
                      let textView,
                      let selection = self.selection(in: textView),
                      let presenter = self.presenter(for: textView) else { return }
                presenter.present(UIReferenceLibraryViewController(term: selection), animated: true)
            }
            let translate = UIAction(
                title: L10n.text("翻訳"),
                image: UIImage(systemName: "character.bubble")
            ) { [weak self, weak textView] _ in
                guard let self,
                      let textView,
                      let selection = self.selection(in: textView),
                      var components = URLComponents(string: "https://translate.google.com/") else { return }
                components.queryItems = [
                    URLQueryItem(name: "sl", value: "auto"),
                    URLQueryItem(name: "tl", value: "en"),
                    URLQueryItem(name: "text", value: selection),
                    URLQueryItem(name: "op", value: "translate")
                ]
                if let url = components.url { UIApplication.shared.open(url) }
            }
            let webSearch = UIAction(
                title: L10n.text("ウェブを検索"),
                image: UIImage(systemName: "magnifyingglass")
            ) { [weak self, weak textView] _ in
                guard let self,
                      let textView,
                      let selection = self.selection(in: textView),
                      var components = URLComponents(string: "https://www.google.com/search") else { return }
                components.queryItems = [URLQueryItem(name: "q", value: selection)]
                if let url = components.url { UIApplication.shared.open(url) }
            }
            let share = UIAction(
                title: L10n.text("共有…"),
                image: UIImage(systemName: "square.and.arrow.up")
            ) { [weak self, weak textView] _ in
                guard let self,
                      let textView,
                      let selection = self.selection(in: textView),
                      let presenter = self.presenter(for: textView) else { return }
                let controller = UIActivityViewController(
                    activityItems: [selection],
                    applicationActivities: nil
                )
                controller.popoverPresentationController?.sourceView = textView
                controller.popoverPresentationController?.sourceRect = textView.bounds
                presenter.present(controller, animated: true)
            }
            return [
                askAction(for: textView),
                copyAction(for: textView),
                selectAll,
                UIMenu(options: .displayInline, children: [lookup, translate, webSearch]),
                UIMenu(options: .displayInline, children: [share])
            ]
        }

        private func selection(in textView: UITextView) -> String? {
            ChatTextSelectionPolicy.selectedText(in: textView.text, range: textView.selectedRange)
        }

        private func presenter(for textView: UITextView) -> UIViewController? {
            var presenter = textView.window?.rootViewController
            while let presented = presenter?.presentedViewController {
                presenter = presented
            }
            return presenter
        }

    }
}

import SwiftUI

struct OpenSourceLicensesView: View {
    var body: some View {
        List {
            ForEach(LegalDocument.allCases) { document in
                NavigationLink(document.title) {
                    LegalDocumentView(document: document)
                }
            }
        }
        .navigationTitle(L10n.text("オープンソースライセンス"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

private enum LegalDocument: String, CaseIterable, Identifiable {
    case projectLicense
    case thirdPartyNotices
    case npmLicenses
    case nodeLicense

    var id: String { rawValue }

    var title: String {
        switch self {
        case .projectLicense:
            return L10n.text("YamabikoChat ライセンス")
        case .thirdPartyNotices:
            return L10n.text("第三者ソフトウェア")
        case .npmLicenses:
            return L10n.text("Pi runtime npm ライセンス")
        case .nodeLicense:
            return L10n.text("Node.js / NodeMobile ライセンス")
        }
    }

    var fileName: String {
        switch self {
        case .projectLicense:
            return "LICENSE"
        case .thirdPartyNotices:
            return "THIRD_PARTY_NOTICES"
        case .npmLicenses:
            return "npm-licenses"
        case .nodeLicense:
            return "NODEJS_LICENSE"
        }
    }

    var fileExtension: String {
        switch self {
        case .thirdPartyNotices, .npmLicenses:
            return "md"
        case .projectLicense, .nodeLicense:
            return "txt"
        }
    }

    var isMarkdown: Bool {
        fileExtension == "md"
    }
}

private struct LegalDocumentView: View {
    let document: LegalDocument

    var body: some View {
        Group {
            if loadError {
                Text(L10n.text("ライセンスファイルを読み込めませんでした"))
                    .foregroundStyle(.secondary)
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else if document.isMarkdown {
                LegalMarkdownDocumentView(blocks: LegalMarkdownParser.parse(documentText))
            } else {
                ScrollView {
                    Text(documentText)
                        .font(.body)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
            }
        }
        .navigationTitle(document.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var loadError: Bool {
        documentURL == nil
    }

    private var documentURL: URL? {
        Bundle.main.url(
            forResource: document.fileName,
            withExtension: document.fileExtension,
            subdirectory: "legal"
        )
    }

    private var documentText: String {
        guard let url = documentURL else { return "" }
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }
}

private struct LegalMarkdownDocumentView: View {
    let blocks: [LegalMarkdownBlock]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                ForEach(displayItems) { item in
                    switch item.block {
                    case let .heading(_, text):
                        Text(text)
                            .font(.title3.weight(.semibold))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 4)
                    case let .paragraph(text):
                        Text(text)
                            .font(.body)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    case let .tableRow(values):
                        LegalTableRowCard(values: values)
                    case let .code(text):
                        Text(text)
                            .font(.footnote.monospaced())
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color(.secondarySystemBackground))
                            )
                    }
                }
            }
            .padding()
        }
    }

    private var displayItems: [LegalDisplayItem] {
        var items: [LegalDisplayItem] = []
        for (blockIndex, block) in blocks.enumerated() {
            switch block {
            case let .heading(level, text):
                items.append(LegalDisplayItem(id: "h-\(blockIndex)", block: .heading(level, text)))
            case let .paragraph(text):
                items.append(LegalDisplayItem(id: "p-\(blockIndex)", block: .paragraph(text)))
            case let .table(_, rows):
                for (rowIndex, row) in rows.enumerated() {
                    items.append(
                        LegalDisplayItem(
                            id: "t-\(blockIndex)-\(rowIndex)",
                            block: .tableRow(row)
                        )
                    )
                }
            case let .code(text):
                items.append(LegalDisplayItem(id: "c-\(blockIndex)", block: .code(text)))
            }
        }
        return items
    }
}

private struct LegalDisplayItem: Identifiable {
    enum Block {
        case heading(Int, String)
        case paragraph(String)
        case tableRow([String])
        case code(String)
    }

    let id: String
    let block: Block
}

private struct LegalTableRowCard: View {
    let values: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title = values.first, !title.isEmpty {
                Text(title)
                    .font(.headline)
                    .textSelection(.enabled)
            }
            if !metaLine.isEmpty {
                Text(metaLine)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            ForEach(Array(urls.enumerated()), id: \.offset) { _, url in
                Link(url.absoluteString, destination: url)
                    .font(.subheadline)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private var detailValues: [String] {
        values.dropFirst().map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    private var metaLine: String {
        detailValues.filter { !$0.hasPrefix("http") }.joined(separator: " · ")
    }

    private var urls: [URL] {
        detailValues.compactMap { value in
            guard value.hasPrefix("http") else { return nil }
            return URL(string: value)
        }
    }
}

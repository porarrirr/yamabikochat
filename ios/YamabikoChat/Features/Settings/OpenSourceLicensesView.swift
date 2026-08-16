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
}

private struct LegalDocumentView: View {
    let document: LegalDocument

    var body: some View {
        ScrollView {
            Text(documentText)
                .font(.footnote.monospaced())
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .navigationTitle(document.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var documentText: String {
        guard let url = Bundle.main.url(
            forResource: document.fileName,
            withExtension: document.fileExtension,
            subdirectory: "legal"
        ) else {
            return L10n.text("ライセンスファイルを読み込めませんでした")
        }
        return (try? String(contentsOf: url, encoding: .utf8))
            ?? L10n.text("ライセンスファイルを読み込めませんでした")
    }
}

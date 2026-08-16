import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct HtmlDownloadDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.yamabikoHtml] }

    let htmlContent: String

    var data: Data {
        Data(htmlContent.utf8)
    }

    init(htmlContent: String) {
        self.htmlContent = htmlContent
    }

    init(configuration: ReadConfiguration) throws {
        let data = configuration.file.regularFileContents ?? Data()
        htmlContent = String(data: data, encoding: .utf8) ?? ""
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

struct HtmlPreviewCard: View {
    let block: ExtractedHtmlBlock

    @State private var isBrowserPresented = false
    @State private var isExportingHtml = false
    @State private var isExportErrorPresented = false
    @State private var exportErrorMessage = ""

    private var previewCode: String {
        let lines = block.content.components(separatedBy: .newlines)
        if lines.count <= 10 {
            return block.content
        }
        return lines.prefix(8).joined(separator: "\n") + "\n..."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "globe")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(red: 0.89, green: 0.31, blue: 0.15))
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 2) {
                    Text("HTML")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(block.filename)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Button {
                    isExportingHtml = true
                } label: {
                    Label(L10n.text("ダウンロード"), systemImage: "square.and.arrow.down")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.text("HTMLをダウンロード"))

                Button {
                    isBrowserPresented = true
                } label: {
                    Label(L10n.text("表示"), systemImage: "eye")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.text("HTMLを表示"))
            }

            Text(previewCode)
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(uiColor: .secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .padding(12)
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(uiColor: .separator).opacity(0.4), lineWidth: 1)
        }
        .fileExporter(
            isPresented: $isExportingHtml,
            document: HtmlDownloadDocument(htmlContent: block.content),
            contentType: .yamabikoHtml,
            defaultFilename: block.filename
        ) { result in
            if case .failure(let error) = result {
                handleExportFailure(error)
            }
        }
        .sheet(isPresented: $isBrowserPresented) {
            HtmlPreviewBrowser(html: block.content, filename: block.filename)
        }
        .alert(
            L10n.text("HTMLのダウンロードに失敗しました"),
            isPresented: $isExportErrorPresented
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportErrorMessage)
        }
    }

    private func handleExportFailure(_ error: Error) {
        if error is CancellationError {
            return
        }

        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain && nsError.code == NSUserCancelledError {
            return
        }

        exportErrorMessage = error.localizedDescription
        isExportErrorPresented = true
    }
}

private extension UTType {
    static let yamabikoHtml = UTType(filenameExtension: "html") ?? .html
}

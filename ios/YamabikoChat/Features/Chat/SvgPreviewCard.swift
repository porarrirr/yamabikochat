import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct SvgDownloadDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.yamabikoSvg] }

    let svgContent: String

    var data: Data {
        Data(svgContent.utf8)
    }

    init(svgContent: String) {
        self.svgContent = svgContent
    }

    init(configuration: ReadConfiguration) throws {
        let data = configuration.file.regularFileContents ?? Data()
        svgContent = String(data: data, encoding: .utf8) ?? ""
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

struct SvgPreviewCard: View {
    let block: ExtractedSvgBlock

    @State private var isPreviewVisible = false
    @State private var renderError: String?
    @State private var isExportingSvg = false
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
                Image(systemName: "photo")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 2) {
                    Text("SVG")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(block.filename)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Button {
                    isExportingSvg = true
                } label: {
                    Label(L10n.text("ダウンロード"), systemImage: "square.and.arrow.down")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.text("SVGをダウンロード"))

                Button {
                    isPreviewVisible.toggle()
                } label: {
                    Label(
                        isPreviewVisible ? L10n.text("非表示") : L10n.text("表示"),
                        systemImage: isPreviewVisible ? "eye.slash" : "eye"
                    )
                    .font(.caption)
                }
                .buttonStyle(.plain)
            }

            Text(previewCode)
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(uiColor: .secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            if isPreviewVisible {
                VStack(alignment: .leading, spacing: 8) {
                    Text("SVGプレビュー")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let renderError {
                        Text(L10n.format("プレビュー表示に失敗しました: %@", renderError))
                            .font(.caption)
                            .foregroundStyle(.red)
                    } else {
                        SvgPreviewWebView(svgContent: block.content, onError: { error in
                            renderError = error
                        })
                        .frame(maxWidth: .infinity)
                        .frame(height: 260)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color(uiColor: .separator).opacity(0.45), lineWidth: 1)
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(uiColor: .separator).opacity(0.4), lineWidth: 1)
        }
        .fileExporter(
            isPresented: $isExportingSvg,
            document: SvgDownloadDocument(svgContent: block.content),
            contentType: .yamabikoSvg,
            defaultFilename: block.filename
        ) { result in
            if case .failure(let error) = result {
                handleExportFailure(error)
            }
        }
        .alert(
            L10n.text("SVGのダウンロードに失敗しました"),
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
    static let yamabikoSvg = UTType(filenameExtension: "svg") ?? .xml
}

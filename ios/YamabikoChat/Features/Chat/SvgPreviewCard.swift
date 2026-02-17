import SwiftUI

struct SvgPreviewCard: View {
    let block: ExtractedSvgBlock

    @State private var isPreviewVisible = false
    @State private var renderError: String?

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
                        SvgPreviewWebView(svgContent: block.content) { error in
                            renderError = error
                        }
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
    }
}

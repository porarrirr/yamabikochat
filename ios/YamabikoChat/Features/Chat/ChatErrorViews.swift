import SwiftUI
import UIKit

struct ChatErrorToast: View {
    let formatted: UserFacingError
    let onDismiss: () -> Void
    @State private var showDetail = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.body)
                    .foregroundStyle(Color.orange)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 4) {
                    Text(formatted.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(formatted.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(showDetail ? nil : 2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(6)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(L10n.text("閉じる")))
            }

            if formatted.hasDetail {
                Button {
                    showDetail.toggle()
                } label: {
                    Text(L10n.text("詳細"))
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.plain)

                if showDetail {
                    Text(formatted.detail)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.orange.opacity(0.45), lineWidth: 1)
        }
        .task(id: "\(formatted.summary)-\(showDetail)") {
            guard !showDetail, !formatted.hasDetail else { return }
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled, !showDetail else { return }
            onDismiss()
        }
    }
}

struct ChatErrorCard: View {
    let formatted: UserFacingError
    @State private var showDetail = false

    init(text: String) {
        formatted = UserFacingErrorFormatter.format(text)
    }

    init(formatted: UserFacingError) {
        self.formatted = formatted
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.subheadline)
                    .foregroundStyle(Color.orange)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 4) {
                    Text(formatted.title)
                        .font(.subheadline.weight(.semibold))
                    Text(formatted.summary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if formatted.hasDetail {
                DisclosureGroup(isExpanded: $showDetail) {
                    Text(formatted.detail)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 4)
                } label: {
                    Text(L10n.text("詳細"))
                        .font(.caption.weight(.semibold))
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
        }
    }
}

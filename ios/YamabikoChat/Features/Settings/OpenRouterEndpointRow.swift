import SwiftUI

struct OpenRouterEndpointRow: View {
    let endpoint: OpenRouterEndpointOption
    @Binding var isSelected: Bool
    @ScaledMetric(relativeTo: .caption) private var priceColumnWidth = 80.0

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: $isSelected) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(endpoint.providerName)
                        .font(.body.weight(.medium))
                    Text(verbatim: endpoint.tag)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("USD / 100万トークン")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if let quantization = endpoint.quantization, quantization != "unknown" {
                    Text(verbatim: quantization)
                        .font(.caption2.monospaced())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
                }
            }

            if endpoint.promptPricePerMillion == nil,
               endpoint.cachedInputPricePerMillion == nil,
               endpoint.completionPricePerMillion == nil {
                Text("Price unavailable")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: priceColumnWidth), alignment: .leading)], alignment: .leading, spacing: 6) {
                    price("入力", value: endpoint.promptPricePerMillion)
                    price("キャッシュ入力", value: endpoint.cachedInputPricePerMillion)
                    price("出力", value: endpoint.completionPricePerMillion)
                }
            }
        }
        .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
    }

    private func price(_ title: String, value: Double?) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(L10n.text(title))
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value.map(formatPrice) ?? "—")
                .font(.subheadline.monospacedDigit())
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func formatPrice(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.currencySymbol = "$"
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 6
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "$%.6f", value)
    }
}

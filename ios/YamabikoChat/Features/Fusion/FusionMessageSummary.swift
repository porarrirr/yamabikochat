import SwiftUI

struct FusionMessageSummary: View {
    let trace: FusionTrace
    let onShowDetails: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            let steps = trace.panelResults.compactMap(\.toolActivity).flatMap(\.steps)
            if !steps.isEmpty {
                ToolActivityDisclosure(steps: steps)
                    .equatable()
            }
            Button(action: onShowDetails) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.merge")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(red: 0.06, green: 0.73, blue: 0.51))

                Text(FusionTracePresentation.summaryLine(for: trace))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Spacer(minLength: 0)

                Text(L10n.text("詳細"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(uiColor: .tertiarySystemFill))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }
}

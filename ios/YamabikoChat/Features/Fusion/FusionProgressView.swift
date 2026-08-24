import SwiftUI

struct FusionProgressView: View {
    let snapshot: FusionProgressSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                phaseIndicator
                VStack(alignment: .leading, spacing: 2) {
                    Text(FusionTracePresentation.progressPhaseTitle(snapshot))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(phaseColor)
                    if let substatus = snapshot.substatus, !substatus.isEmpty {
                        Text(substatus)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }

            if !snapshot.panels.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Array(snapshot.panels.enumerated()), id: \.offset) { _, panel in
                            FusionPanelChipView(panel: panel)
                        }
                    }
                }
            }
            if let activity = snapshot.panels
                .compactMap(\.toolActivity)
                .last(where: { !$0.steps.isEmpty }) {
                ToolActivityDisclosure(steps: activity.steps)
                    .equatable()
            }
        }
        .padding(.horizontal, 10)
    }

    private var phaseIndicator: some View {
        Group {
            if snapshot.phase == .panel, snapshot.completedPanelCount < snapshot.totalPanelCount {
                ProgressView()
                    .controlSize(.mini)
            } else {
                Image(systemName: phaseIcon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(phaseColor)
            }
        }
        .frame(width: 16, height: 16)
    }

    private var phaseColor: Color {
        switch snapshot.phase {
        case .panel:
            return Color(red: 0.23, green: 0.51, blue: 0.96)
        case .judge:
            return Color(red: 0.55, green: 0.36, blue: 0.96)
        case .synthesizer:
            return Color(red: 0.06, green: 0.73, blue: 0.51)
        }
    }

    private var phaseIcon: String {
        switch snapshot.phase {
        case .panel:
            return "square.grid.2x2"
        case .judge:
            return "scale.3d"
        case .synthesizer:
            return "arrow.triangle.merge"
        }
    }
}

private struct FusionPanelChipView: View {
    let panel: FusionPanelChipStatus

    var body: some View {
        HStack(spacing: 4) {
            stateIcon
            Text(FusionTracePresentation.shortModelLabel(panel.modelId))
                .lineLimit(1)
            if panel.toolActivity?.steps.contains(where: { $0.status == .running }) == true {
                Image(systemName: "globe")
                    .font(.system(size: 10))
            }
        }
        .font(.caption2)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(chipBackground)
        .foregroundStyle(chipForeground)
        .clipShape(Capsule())
        .overlay {
            Capsule()
                .stroke(chipBorder, lineWidth: 1)
        }
    }

    @ViewBuilder
    private var stateIcon: some View {
        switch panel.state {
        case .pending, .running:
            ProgressView()
                .controlSize(.mini)
                .frame(width: 12, height: 12)
        case .succeeded:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.red)
        }
    }

    private var chipBackground: Color {
        switch panel.state {
        case .failed:
            return Color.red.opacity(0.08)
        case .succeeded:
            return Color.green.opacity(0.08)
        default:
            return Color.secondary.opacity(0.08)
        }
    }

    private var chipForeground: Color {
        panel.state == .failed ? .primary : .primary
    }

    private var chipBorder: Color {
        switch panel.state {
        case .failed:
            return Color.red.opacity(0.25)
        case .succeeded:
            return Color.green.opacity(0.25)
        default:
            return Color.secondary.opacity(0.18)
        }
    }
}

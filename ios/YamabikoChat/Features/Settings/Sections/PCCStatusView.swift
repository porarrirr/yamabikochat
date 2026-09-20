import SwiftUI
import FoundationModels

@MainActor
final class PCCStatusModel: ObservableObject {
    @Published var capability = PCCCapability(available: false, reason: "pcc_checking")
    @Published var approachingLimit = false
    @Published var resetDate: Date?
    @Published var canIncreaseLimit = false
    private var showLimitIncreaseSuggestion: (() -> Void)?

    func refresh() async {
        capability = await PCCProviderClient.capability()
        if #available(iOS 27.0, *) {
            let usage = PCCSDK.model.quotaUsage
            if case .belowLimit(let info) = usage.status { approachingLimit = info.isApproachingLimit }
            else { approachingLimit = false }
            resetDate = usage.resetDate
            if let suggestion = usage.limitIncreaseSuggestion {
                // Keep the exact suggestion that made the button visible. The
                // system flow is tied to this offer; fetching quotaUsage again
                // on tap can produce a different (or already invalid) offer.
                showLimitIncreaseSuggestion = { suggestion.show() }
                canIncreaseLimit = true
            } else {
                showLimitIncreaseSuggestion = nil
                canIncreaseLimit = false
            }
        }
    }

    func showOptions() {
        showLimitIncreaseSuggestion?()
    }
}

struct PCCStatusView: View {
    @StateObject private var status = PCCStatusModel()
    @Environment(\.scenePhase) private var scenePhase
    var refreshKey: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !status.capability.available {
                Text(status.capability.reason == "pcc_checking" ? L10n.text("Checking Private Cloud Compute…") : PCCProviderClient.message(for: status.capability.reason ?? "pcc_unavailable"))
                    .foregroundStyle(.secondary)
            } else if status.approachingLimit {
                Text("Private Cloud Compute: nearing daily usage limit").foregroundStyle(.orange)
            } else {
                Text("Private Cloud Compute is available").foregroundStyle(.secondary)
            }
            if let date = status.resetDate {
                Text(L10n.format("Usage limit resets: %@", date.formatted(date: .abbreviated, time: .shortened)))
            }
            if status.canIncreaseLimit { Button("Show usage limit options") { status.showOptions() } }
        }
        .font(.caption)
        .task(id: refreshKey) { await status.refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await status.refresh() } }
        }
    }
}

struct AppleIntelligenceModelPicker: View {
    @Binding var model: String
    @StateObject private var status = PCCStatusModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Picker("Model", selection: $model) {
            Text("Apple Intelligence (On-device)").tag(AppleIntelligenceModelCatalog.displayModel)
            Text("Apple Intelligence — Private Cloud Compute")
                .tag(AppleIntelligenceModelCatalog.pccModel)
                .disabled(!status.capability.available)
            if !AppleIntelligenceModelCatalog.supportedModels.contains(model) {
                Text(model).tag(model).disabled(true)
            }
        }
        .task { await status.refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await status.refresh() } }
        }
        PCCStatusView()
    }
}

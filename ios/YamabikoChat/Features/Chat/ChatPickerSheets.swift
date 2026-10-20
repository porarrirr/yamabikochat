import SwiftUI

struct ChatModelPickerSheet: View {
    @ObservedObject var viewModel: ChatViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var searchQuery = ""

    private var presets: [ModelPreset] {
        let values = viewModel.availableChatPresets()
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return values }
        return values.filter {
            $0.name.localizedCaseInsensitiveContains(query) ||
                $0.model.localizedCaseInsensitiveContains(query) ||
                ProviderCatalog.displayName(for: $0.apiProvider).localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationStack {
            AMOLEDList {
                if presets.isEmpty {
                    ContentUnavailableView.search(text: searchQuery)
                } else {
                    ForEach(groupedProviders, id: \.provider) { group in
                        Section(group.displayName) {
                            ForEach(group.presets) { preset in
                                Button {
                                    viewModel.applyChatPreset(preset)
                                    dismiss()
                                } label: {
                                    HStack(spacing: 12) {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(preset.name)
                                                .font(.body.weight(.medium))
                                                .foregroundStyle(.primary)
                                            Text(preset.model)
                                                .font(.caption.monospaced())
                                                .foregroundStyle(.secondary)
                                                .lineLimit(2)
                                        }
                                        Spacer()
                                        if isActive(preset) {
                                            Image(systemName: "checkmark")
                                                .font(.body.weight(.semibold))
                                        }
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .searchable(text: $searchQuery, prompt: L10n.text("モデルまたはProviderを検索"))
            .navigationTitle(L10n.text("モデルを選択"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.text("閉じる")) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var groupedProviders: [(provider: String, displayName: String, presets: [ModelPreset])] {
        let grouped = Dictionary(grouping: presets) { $0.apiProvider.uppercased() }
        return grouped.map { provider, values in
            (provider, ProviderCatalog.displayName(for: provider), values)
        }
        .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    private func isActive(_ preset: ModelPreset) -> Bool {
        preset.apiProvider.caseInsensitiveCompare(viewModel.conversationProvider) == .orderedSame &&
            preset.model == viewModel.conversationModel
    }
}

struct ChatModePickerSheet: View {
    @ObservedObject var viewModel: ChatViewModel
    @Environment(\.dismiss) private var dismiss

    private var activeMode: ChatMode { ChatMode(settings: viewModel.settings) }

    var body: some View {
        NavigationStack {
            AMOLEDList {
                Section {
                    ForEach(ChatMode.allCases) { mode in
                        Button {
                            viewModel.setChatMode(mode)
                            dismiss()
                        } label: {
                            HStack(spacing: 13) {
                                Image(systemName: mode.systemImage)
                                    .frame(width: 28)
                                Text(mode.title)
                                    .font(.body.weight(.medium))
                                Spacer()
                                if mode == activeMode {
                                    Image(systemName: "checkmark")
                                        .font(.body.weight(.semibold))
                                }
                            }
                            .foregroundStyle(.primary)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle(L10n.text("会話モード"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.text("閉じる")) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}

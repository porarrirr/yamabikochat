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
            List {
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
            List {
                Section {
                    ForEach(ChatMode.allCases) { mode in
                        Button {
                            viewModel.setChatMode(mode)
                            dismiss()
                        } label: {
                            HStack(spacing: 13) {
                                Image(systemName: mode.systemImage)
                                    .frame(width: 28)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(mode.title)
                                        .font(.body.weight(.medium))
                                    Text(description(for: mode))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
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
                } footer: {
                    Text(L10n.text("モードは互いに排他的です。変更は次の送信から適用されます。"))
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

    private func description(for mode: ChatMode) -> String {
        switch mode {
        case .standard: L10n.text("1つのモデルと自然に会話します")
        case .dual: L10n.text("2つのモデルの回答を比較します")
        case .fusion: L10n.text("複数の回答を評価して1つに統合します")
        case .autoConversation: L10n.text("2つのモデルが交互に会話します")
        }
    }
}

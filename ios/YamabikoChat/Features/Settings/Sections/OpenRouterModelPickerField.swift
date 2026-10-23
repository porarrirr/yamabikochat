import SwiftUI

struct OpenRouterModelPickerField: View {
    let titleKey: String
    @Binding var model: String
    let models: [SimpleModel]
    let isLoading: Bool
    let error: String?
    let onRefresh: () -> Void

    private var selectedModelLabel: String {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return L10n.text("モデルを選択") }
        if let match = models.first(where: { $0.id == trimmed }) {
            return match.name
        }
        return trimmed
    }

    var body: some View {
        Group {
            NavigationLink {
                OpenRouterModelListView(
                    titleKey: titleKey,
                    model: $model,
                    models: models,
                    isLoading: isLoading,
                    onRefresh: onRefresh
                )
            } label: {
                HStack {
                    Text(L10n.text(titleKey))
                    Spacer()
                    Text(selectedModelLabel)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .buttonStyle(.plain)

            if isLoading {
                ProgressView(L10n.text("読み込み中..."))
            }


            TextField(L10n.text("Custom Model ID"), text: $model)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
    }
}

struct OpenRouterModelListView: View {
    @Environment(\.dismiss) private var dismiss

    let titleKey: String
    @Binding var model: String
    let models: [SimpleModel]
    let isLoading: Bool
    let onRefresh: () -> Void
    var dismissOnSelection = true
    var error: String? = nil

    @State private var searchQuery = ""

    private var filteredModels: [SimpleModel] {
        models.filter { $0.matchesSearchQuery(searchQuery) }
    }

    var body: some View {
        Group {
            if filteredModels.isEmpty && !isLoading {
                ContentUnavailableView(
                    L10n.text("モデルが見つかりません"),
                    systemImage: "magnifyingglass"
                )
            } else {
                List(filteredModels) { item in
                    Button {
                        model = item.id
                        if dismissOnSelection { dismiss() }
                    } label: {
                        ModelSelectionRow(
                            name: item.name,
                            isSelected: item.id == model.trimmingCharacters(in: .whitespacesAndNewlines)
                        )
                    }
                    .buttonStyle(.plain)
                    .listRowSeparator(.visible)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .background(Color(uiColor: .amoledSystemGroupedBackground))
        .navigationTitle(L10n.text(titleKey))
        .navigationBarTitleDisplayMode(.inline)
        .pinnedListSearch(text: $searchQuery, prompt: L10n.text("モデル検索"))
        .safeAreaInset(edge: .bottom) {
            if isLoading {
                ProgressView(L10n.text("読み込み中..."))
                    .padding(8)
            }
        }
        .toolbar {
            if dismissOnSelection {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L10n.text("閉じる")) {
                        dismiss()
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: onRefresh) {
                    Label(L10n.text("更新"), systemImage: "arrow.clockwise")
                        .labelStyle(.iconOnly)
                }
                .disabled(isLoading)
            }
        }
    }
}

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

            if let error, !error.isEmpty {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            TextField(L10n.text("Custom Model ID"), text: $model)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
    }
}

private struct OpenRouterModelListView: View {
    @Environment(\.dismiss) private var dismiss

    let titleKey: String
    @Binding var model: String
    let models: [SimpleModel]
    let isLoading: Bool
    let onRefresh: () -> Void

    @State private var searchQuery = ""

    private var filteredModels: [SimpleModel] {
        models.filter { $0.matchesSearchQuery(searchQuery) }
    }

    var body: some View {
        Group {
            if filteredModels.isEmpty && !isLoading {
                ContentUnavailableView(
                    L10n.text("モデルが見つかりません"),
                    systemImage: "magnifyingglass",
                    description: Text(L10n.text("検索条件を変えるか、一覧を更新してください。"))
                )
            } else {
                List(filteredModels) { item in
                    Button {
                        model = item.id
                        dismiss()
                    } label: {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.name)
                                    .font(.subheadline)
                                Text(item.id)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if item.id == model.trimmingCharacters(in: .whitespacesAndNewlines) {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle(L10n.text(titleKey))
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchQuery, prompt: L10n.text("モデル検索"))
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(L10n.text("閉じる")) {
                    dismiss()
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(L10n.text("更新")) {
                    onRefresh()
                }
                .disabled(isLoading)
            }
        }
    }
}

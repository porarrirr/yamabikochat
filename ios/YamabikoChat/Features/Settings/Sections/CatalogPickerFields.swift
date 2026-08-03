import SwiftUI

struct CatalogProviderPickerField: View {
    @Binding var providerID: String
    let catalogProviders: [CatalogProvider]
    var title: String = "API Provider"

    private var selectedLabel: String {
        if let builtIn = ProviderCatalog.options.first(where: { $0.key == providerID.uppercased() }) { return builtIn.title }
        let reference = ProviderReference(persistedID: providerID)
        return catalogProviders.first(where: { $0.id == reference.modelsDevID })?.name ?? providerID
    }

    var body: some View {
        NavigationLink {
            CatalogProviderListView(providerID: $providerID, catalogProviders: catalogProviders)
        } label: {
            HStack {
                Text(L10n.text(title))
                Spacer()
                Text(selectedLabel).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }
}

private struct CatalogProviderListView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var providerID: String
    let catalogProviders: [CatalogProvider]
    @State private var query = ""

    private var filteredBuiltIns: [ProviderDisplay] {
        ProviderCatalog.options.filter {
            query.isEmpty || $0.key.localizedCaseInsensitiveContains(query) || $0.title.localizedCaseInsensitiveContains(query)
        }
    }

    private var filteredCatalog: [CatalogProvider] {
        catalogProviders.filter { provider in
            !Self.mergedProviderIDs.contains(provider.id) && provider.matches(query)
        }
    }

    var body: some View {
        List {
            Section("YamabikoChat") {
                ForEach(filteredBuiltIns) { provider in providerRow(provider.key, provider.title, nil) }
            }
            Section("models.dev") {
                ForEach(filteredCatalog) { provider in
                    providerRow(provider.reference.persistedID, provider.name, provider.id)
                }
            }
        }
        .navigationTitle("プロバイダー")
        .searchable(text: $query, prompt: "プロバイダーを検索")
    }

    @ViewBuilder
    private func providerRow(_ id: String, _ title: String, _ subtitle: String?) -> some View {
        Button {
            providerID = id
            dismiss()
        } label: {
            HStack {
                VStack(alignment: .leading) {
                    Text(title)
                    if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
                }
                Spacer()
                if providerID.caseInsensitiveCompare(id) == .orderedSame { Image(systemName: "checkmark") }
            }
        }.buttonStyle(.plain)
    }

    private static let mergedProviderIDs: Set<String> = [
        "openrouter", "google", "openai", "opencode", "cline-pass", "alibaba-coding-plan", "zai", "minimax"
    ]
}

struct CatalogModelPickerField: View {
    @Binding var modelID: String
    let provider: CatalogProvider
    var title: String = "Model"

    private var selectedLabel: String {
        provider.models.first(where: { $0.id == modelID })?.name ?? (modelID.isEmpty ? "モデルを選択" : modelID)
    }

    var body: some View {
        NavigationLink {
            CatalogModelListView(modelID: $modelID, provider: provider)
        } label: {
            HStack {
                Text(L10n.text(title))
                Spacer()
                Text(selectedLabel).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }
}

private struct CatalogModelListView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var modelID: String
    let provider: CatalogProvider
    @State private var query = ""

    private var filtered: [CatalogModel] { provider.models.filter { $0.matches(query) } }

    var body: some View {
        List(filtered) { model in
            Button {
                modelID = model.id
                dismiss()
            } label: {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(model.name)
                        Text(model.id).font(.caption).foregroundStyle(.secondary)
                        if let description = model.description { Text(description).font(.caption2).foregroundStyle(.secondary).lineLimit(2) }
                        HStack {
                            if let context = model.limits.context { Text("context \(context)") }
                            if model.reasoning { Text("reasoning") }
                            if model.toolCall { Text("tools") }
                        }.font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if model.id == modelID { Image(systemName: "checkmark") }
                }
            }.buttonStyle(.plain)
        }
        .overlay {
            if filtered.isEmpty { ContentUnavailableView.search(text: query) }
        }
        .navigationTitle(provider.name)
        .searchable(text: $query, prompt: "モデルを検索")
    }
}

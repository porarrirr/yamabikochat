import SwiftUI

struct CatalogProviderPickerField: View {
    @Binding var providerID: String
    private let catalogProviders: [CatalogProviderOption]
    var title: String = "API Provider"

    init(
        providerID: Binding<String>,
        catalogProviders: [CatalogProvider],
        title: String = "API Provider"
    ) {
        _providerID = providerID
        self.catalogProviders = catalogProviders.map(CatalogProviderOption.init)
        self.title = title
    }

    private var selectedLabel: String {
        if let builtIn = ProviderCatalog.options.first(where: { $0.key == providerID.uppercased() }) { return builtIn.title }
        let reference = ProviderReference(persistedID: providerID)
        return catalogProviders.first(where: { $0.id == reference.modelsDevID })?.name ?? providerID
    }

    var body: some View {
        NavigationLink {
            CatalogProviderListView(
                selectedProviderID: providerID,
                catalogProviders: catalogProviders,
                onSelect: { providerID = $0 }
            )
        } label: {
            HStack {
                Text(L10n.text(title))
                Spacer()
                Text(selectedLabel).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .accessibilityIdentifier("provider-picker-field")
    }
}

private struct CatalogProviderOption: Identifiable, Equatable {
    let id: String
    let name: String
    let persistedID: String

    init(_ provider: CatalogProvider) {
        id = provider.id
        name = provider.name
        persistedID = provider.reference.persistedID
    }

    func matches(_ query: String) -> Bool {
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty || id.localizedCaseInsensitiveContains(value) || name.localizedCaseInsensitiveContains(value)
    }
}

private struct CatalogProviderListView: View {
    @Environment(\.dismiss) private var dismiss
    let selectedProviderID: String
    let catalogProviders: [CatalogProviderOption]
    let onSelect: (String) -> Void
    @State private var query = ""

    private var filteredBuiltIns: [ProviderDisplay] {
        ProviderCatalog.options.filter {
            query.isEmpty || $0.key.localizedCaseInsensitiveContains(query) || $0.title.localizedCaseInsensitiveContains(query)
        }
    }

    private var filteredCatalog: [CatalogProviderOption] {
        catalogProviders.filter { provider in
            ModelsDevMergedProvider.isSelectableCatalogProvider(provider.id) && provider.matches(query)
        }
    }

    var body: some View {
        List {
            Section("YamabikoChat") {
                ForEach(filteredBuiltIns) { provider in providerRow(provider.key, provider.title, nil) }
            }
            Section {
                ForEach(filteredCatalog) { provider in
                    providerRow(provider.persistedID, provider.name, provider.id)
                }
            }
        }
        .navigationTitle("プロバイダー")
        .searchable(text: $query, prompt: "プロバイダーを検索")
    }

    @ViewBuilder
    private func providerRow(_ id: String, _ title: String, _ subtitle: String?) -> some View {
        Button {
            onSelect(id)
            dismiss()
        } label: {
            HStack {
                VStack(alignment: .leading) {
                    Text(title)
                    if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
                }
                Spacer()
                if selectedProviderID.caseInsensitiveCompare(id) == .orderedSame { Image(systemName: "checkmark") }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("provider-row-\(id)")
    }
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

struct ModelsDevReasoningEffortPicker: View {
    let model: CatalogModel
    let currentEffort: String
    let onChange: (String) -> Void

    @State private var selection: String

    init(
        model: CatalogModel,
        currentEffort: String,
        onChange: @escaping (String) -> Void
    ) {
        self.model = model
        self.currentEffort = currentEffort
        self.onChange = onChange
        let normalized = currentEffort.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        _selection = State(initialValue: normalized)
    }

    var body: some View {
        Picker("Reasoning effort", selection: Binding(
            get: { selection },
            set: { value in
                selection = value
                onChange(value)
            }
        )) {
            Text("プロバイダー既定").tag("")
            if !selection.isEmpty, !model.supportedReasoningEfforts.contains(selection) {
                Text("\(selection)（現在は非対応）").tag(selection)
            }
            ForEach(model.supportedReasoningEfforts, id: \.self) { effort in
                Text(effort).tag(effort)
            }
        }
    }
}

private struct CatalogModelListView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var modelID: String
    let provider: CatalogProvider
    @State private var query = ""
    @State private var resolutions: [String: PiModelResolution] = [:]
    @State private var resolutionError: String?

    private var filtered: [CatalogModel] { provider.models.filter { $0.matches(query) } }

    var body: some View {
        List(filtered) { model in
            let resolution = resolutions[model.id]
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
                            if model.reasoning == true { Text("reasoning") }
                            if model.toolCall == true { Text("tools") }
                        }.font(.caption2).foregroundStyle(.secondary)
                        if resolution?.supported == false {
                            Text(unsupportedReason(resolution?.reason))
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                    }
                    Spacer()
                    if model.id == modelID { Image(systemName: "checkmark") }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(resolution?.supported != true)
        }
        .overlay {
            if filtered.isEmpty { ContentUnavailableView.search(text: query) }
        }
        .navigationTitle(provider.name)
        .searchable(text: $query, prompt: "モデルを検索")
        .task(id: "\(provider.id):\(provider.models.count)") {
            do {
                let configs = provider.models.map { model in
                    PiAgentConfiguration(
                        provider: provider.id,
                        model: provider.id == "opencode-go"
                            ? OpenCodeGoModelCatalog.normalizedModelID(model.id)
                            : model.id,
                        apiKey: nil,
                        catalogContract: PiCatalogModelContract(
                            providerName: provider.name,
                            npm: model.providerContract?.npm,
                            api: model.providerContract?.api,
                            shape: model.providerContract?.shape,
                            toolCall: model.toolCall,
                            provenance: model.providerContract?.provenance,
                            name: model.name,
                            reasoning: model.reasoning,
                            input: model.inputModalities,
                            contextWindow: model.limits.context,
                            maxTokens: model.limits.output
                        )
                    )
                }
                let values = try await PiAgentRuntime.shared.resolveModels(configs)
                resolutions = Dictionary(uniqueKeysWithValues: zip(provider.models.map(\.id), values))
                resolutionError = nil
            } catch {
                resolutions = [:]
                resolutionError = error.localizedDescription
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let resolutionError {
                Text("Piモデル契約を確認できません: \(resolutionError)")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(8)
            }
        }
    }

    private func unsupportedReason(_ reason: String?) -> String {
        switch reason {
        case "pi_provider_missing": "Piにプロバイダー定義がありません"
        case "pi_provider_ambiguous": "models.devとPiのプロバイダー対応を一意に特定できません"
        case "pi_model_missing": "Piにモデル定義がありません"
        case "pi_protocol_missing": "Piにこのモデルのプロトコル定義がありません"
        case "protocol_conflict": "models.devとPiのプロトコルが一致しません"
        case "endpoint_conflict": "models.devとPiのエンドポイントが一致しません"
        case "catalog_contract_ambiguous": "models.devのモデル実行契約を一意に特定できません"
        case "catalog_contract_incomplete": "公式カタログのモデル実行契約が不完全です"
        case "contract_conflict": "models.devとPiの実行契約が一致しません"
        case "runtime_contract_mismatch": "アプリとPi Runtimeの契約バージョンが一致しません"
        default: "実行契約を確認できません"
        }
    }
}

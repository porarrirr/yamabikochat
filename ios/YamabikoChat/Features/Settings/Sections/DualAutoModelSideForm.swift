import SwiftUI

struct DualAutoModelSideForm: View {
    let providerTitleKey: String
    @Binding var provider: String
    let modelTitleKey: String
    @Binding var model: String
    let systemPromptTitleKey: String
    @Binding var systemPrompt: String
    var providerPresets: [ModelPreset] = []
    var catalogProviders: [CatalogProvider] = []
    var onProviderPresetSelected: (ModelPreset) -> Void = { _ in }
    var systemPromptLineLimit: ClosedRange<Int> = 2 ... 8

    private var availableProviderPresets: [ModelPreset] {
        let supportedProviders = Set(ProviderCatalog.dualAutoConversationOptions.map(\.key))
        return providerPresets.filter {
            supportedProviders.contains($0.apiProvider.uppercased()) || ProviderReference(persistedID: $0.apiProvider).isModelsDev
        }
    }

    private var selectedProviderPresetKey: String {
        let normalizedProvider = provider.uppercased()
        let normalizedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        return availableProviderPresets.first {
            $0.apiProvider.uppercased() == normalizedProvider &&
                $0.model.trimmingCharacters(in: .whitespacesAndNewlines) == normalizedModel
        }?.dualAutoPresetKey ?? ""
    }

    var body: some View {
        if !availableProviderPresets.isEmpty {
            Picker(L10n.text("プロバイダープリセット"), selection: Binding(
                get: { selectedProviderPresetKey },
                set: { key in
                    guard let preset = availableProviderPresets.first(where: { $0.dualAutoPresetKey == key }) else {
                        return
                    }
                    onProviderPresetSelected(preset)
                }
            )) {
                Text(L10n.text("未選択")).tag("")
                ForEach(availableProviderPresets, id: \.dualAutoPresetKey) { preset in
                    Text(preset.name).tag(preset.dualAutoPresetKey)
                }
            }
        }

        CatalogProviderPickerField(
            providerID: Binding(
                get: { provider },
                set: { newValue in
                    let changed = provider.caseInsensitiveCompare(newValue) != .orderedSame
                    provider = newValue
                    if changed {
                        model = ProviderReference(persistedID: newValue).isModelsDev
                            ? ""
                            : ProviderCatalog.defaultModel(for: newValue)
                    }
                }
            ),
            catalogProviders: catalogProviders,
            title: providerTitleKey
        )
        if let modelIDs = ProviderCatalog.constrainedModelIDs(for: provider) {
            Picker(L10n.text(modelTitleKey), selection: $model) {
                ForEach(modelIDs, id: \.self) { modelID in
                    Text(modelID).tag(modelID)
                }
            }
        } else if let dynamicProvider = catalogProvider {
            CatalogModelPickerField(modelID: $model, provider: dynamicProvider, title: modelTitleKey)
        } else {
            TextField(L10n.text(modelTitleKey), text: $model)
        }
        TextField(L10n.text(systemPromptTitleKey), text: $systemPrompt, axis: .vertical)
            .lineLimit(systemPromptLineLimit)
    }

    private var catalogProvider: CatalogProvider? {
        guard provider.uppercased() != "OPENROUTER",
              let id = ModelsDevMergedProvider.catalogID(for: provider) else { return nil }
        return catalogProviders.first { $0.id == id }
    }
}

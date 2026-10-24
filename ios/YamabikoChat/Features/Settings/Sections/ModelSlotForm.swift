import SwiftUI

struct ModelSlotForm: View {
    let providerTitleKey: String
    var presetTitleKey: String = "プロバイダープリセット"
    @Binding var provider: String
    let modelTitleKey: String
    @Binding var model: String
    var providerPresets: [ModelPreset] = []
    var catalogProviders: [CatalogProvider] = []
    @Binding var pccReasoningLevel: String?
    var showsPCCReasoning = true
    var codexModels: [PiCodexModel] = []
    var initialModel: (String) -> String = ProviderCatalog.defaultModel
    var onProviderPresetSelected: (ModelPreset) -> Void = { _ in }
    var openRouterModels: [SimpleModel] = []
    var openRouterModelsLoading: Bool = false
    var openRouterModelsError: String?
    var onRefreshOpenRouterModels: () -> Void = {}
    var onProviderChanged: (String) -> Void = { _ in }

    private var availableProviderPresets: [ModelPreset] {
        let supportedProviders = Set(ProviderCatalog.options.map(\.key))
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

    private var isOpenRouterProvider: Bool {
        provider.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == "OPENROUTER"
    }

    var body: some View {
        if !availableProviderPresets.isEmpty {
            Picker(L10n.text(presetTitleKey), selection: Binding(
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
                        model = initialModel(newValue)
                    }
                    onProviderChanged(newValue)
                }
            ),
            catalogProviders: catalogProviders,
            title: providerTitleKey
        )

        if isOpenRouterProvider {
            OpenRouterModelPickerField(
                titleKey: modelTitleKey,
                model: $model,
                models: openRouterModels,
                isLoading: openRouterModelsLoading,
                error: openRouterModelsError,
                onRefresh: onRefreshOpenRouterModels
            )
        } else if provider.caseInsensitiveCompare("APPLE_INTELLIGENCE") == .orderedSame {
            AppleIntelligenceModelPicker(model: $model)
            if model == AppleIntelligenceModelCatalog.pccModel && showsPCCReasoning {
                Picker("PCC reasoning", selection: Binding(
                    get: { pccReasoningLevel ?? AppleIntelligenceModelCatalog.defaultPCCReasoningLevel },
                    set: { pccReasoningLevel = $0 }
                )) {
                    ForEach(AppleIntelligenceModelCatalog.pccReasoningLevels, id: \.self) { level in
                        Text(level.capitalized).tag(level)
                    }
                }
            }
        } else if provider.caseInsensitiveCompare("CODEX_AUTH") == .orderedSame {
            Picker(L10n.text(modelTitleKey), selection: $model) {
                if !codexModels.contains(where: { $0.id == model }) {
                    Text(model).tag(model).disabled(true)
                }
                ForEach(CodexModelCatalog.visiblePresets(from: codexModels)) { preset in
                    Text(preset.isSupported ? preset.displayName : "\(preset.displayName) · \(preset.unsupportedReason ?? "unsupported")")
                        .tag(preset.model)
                        .disabled(!preset.isSupported)
                }
            }
        } else if let modelIDs = modelOptions {
            Picker(L10n.text(modelTitleKey), selection: $model) {
                if !modelIDs.contains(model) {
                    Text(model).tag(model).disabled(true)
                }
                ForEach(modelIDs, id: \.self) { modelID in
                    Text(modelID).tag(modelID)
                }
            }
        } else if let dynamicProvider = catalogProvider {
            CatalogModelPickerField(modelID: $model, provider: dynamicProvider, title: modelTitleKey)
        } else {
            LabeledContent(L10n.text(modelTitleKey)) {
                TextField(L10n.text(modelTitleKey), text: $model)
                    .multilineTextAlignment(.trailing)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
        }
    }

    private var modelOptions: [String]? {
        if provider.caseInsensitiveCompare("SUPERGROK") == .orderedSame {
            return SuperGrokModelCatalog.supportedModels.map(\.id)
        }
        return ProviderCatalog.constrainedModelIDs(for: provider)
    }

    private var catalogProvider: CatalogProvider? {
        guard provider.uppercased() != "OPENROUTER",
              let id = ModelsDevMergedProvider.catalogID(for: provider) else { return nil }
        return catalogProviders.first { $0.id == id }
    }
}

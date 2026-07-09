import SwiftUI

struct FusionModelSlotForm: View {
    let providerTitleKey: String
    @Binding var provider: String
    let modelTitleKey: String
    @Binding var model: String
    var providerPresets: [ModelPreset] = []
    var onProviderPresetSelected: (ModelPreset) -> Void = { _ in }
    var openRouterModels: [SimpleModel] = []
    var openRouterModelsLoading: Bool = false
    var openRouterModelsError: String?
    var onRefreshOpenRouterModels: () -> Void = {}
    var onProviderChanged: (String) -> Void = { _ in }

    private var availableProviderPresets: [ModelPreset] {
        let supportedProviders = Set(ProviderCatalog.dualAutoConversationOptions.map(\.key))
        return providerPresets.filter {
            supportedProviders.contains($0.apiProvider.uppercased())
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

    private var isClinePassProvider: Bool {
        provider.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == "CLINEPASS"
    }

    private var clinePassModelSelection: Binding<String> {
        Binding(
            get: {
                if let match = ClinePassModelCatalog.model(for: model) {
                    return match.id
                }
                return model
            },
            set: { model = $0 }
        )
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

        SettingsFormHelpers.dualAutoProviderPickerRow(
            title: providerTitleKey,
            selection: Binding(
                get: { provider.uppercased() },
                set: { newValue in
                    provider = newValue.uppercased()
                    onProviderChanged(newValue.uppercased())
                }
            )
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
        } else if isClinePassProvider {
            Picker(L10n.text(modelTitleKey), selection: clinePassModelSelection) {
                ForEach(ClinePassModelCatalog.supportedModels) { option in
                    Text(option.displayName).tag(option.id)
                }
            }

            if let selected = ClinePassModelCatalog.model(for: model) {
                Text(selected.description)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            TextField(L10n.text(modelTitleKey), text: $model)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        } else {
            TextField(L10n.text(modelTitleKey), text: $model)
        }
    }
}
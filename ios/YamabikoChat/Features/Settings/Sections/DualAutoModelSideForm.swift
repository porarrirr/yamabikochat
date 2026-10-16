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
    var openRouterModels: [SimpleModel] = []
    var openRouterModelsLoading = false
    var openRouterModelsError: String?
    var onRefreshOpenRouterModels: () -> Void = {}
    var onProviderPresetSelected: (ModelPreset) -> Void = { _ in }
    var systemPromptLineLimit: ClosedRange<Int> = 2 ... 8

    @Binding var pccReasoningLevel: String?
    var codexModels: [PiCodexModel] = []
    var initialModel: (String) -> String = ProviderCatalog.defaultModel

    var body: some View {
        ModelSlotForm(
            providerTitleKey: providerTitleKey,
            provider: $provider,
            modelTitleKey: modelTitleKey,
            model: $model,
            providerPresets: providerPresets,
            catalogProviders: catalogProviders,
            pccReasoningLevel: $pccReasoningLevel,
            codexModels: codexModels,
            initialModel: initialModel,
            onProviderPresetSelected: onProviderPresetSelected,
            openRouterModels: openRouterModels,
            openRouterModelsLoading: openRouterModelsLoading,
            openRouterModelsError: openRouterModelsError,
            onRefreshOpenRouterModels: onRefreshOpenRouterModels
        )
        TextField(L10n.text(systemPromptTitleKey), text: $systemPrompt, axis: .vertical)
            .lineLimit(systemPromptLineLimit)
    }
}

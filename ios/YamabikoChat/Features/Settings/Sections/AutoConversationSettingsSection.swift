import SwiftUI

struct AutoConversationSettingsSection: View {
    @ObservedObject var viewModel: SettingsViewModel
    @State private var selectedSide: DualModelSide = .a

    private var isUnlimitedTurns: Bool {
        viewModel.settings.autoMaxTurns <= 0
    }

    private var maxTurnsLabel: String {
        if isUnlimitedTurns {
            return L10n.text("最大ターン数: 無制限")
        }
        return L10n.format("最大ターン数: %d回", viewModel.settings.autoMaxTurns)
    }

    private var providerPresetOptions: [ModelPreset] {
        viewModel.settings.buildGlobalProviderPresets()
    }

    var body: some View {
        Group {
            Section {
                Toggle(L10n.text("Enable auto conversation"), isOn: Binding(
                    get: { viewModel.settings.isAutoConversationEnabled },
                    set: { viewModel.setAutoConversationEnabled($0) }
                ))

            }

            if viewModel.settings.isAutoConversationEnabled {
                Section {
                    Picker(L10n.text("Model"), selection: $selectedSide) {
                        Text(L10n.text("Model A")).tag(DualModelSide.a)
                        Text(L10n.text("Model B")).tag(DualModelSide.b)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("conversation-model-side")
                } footer: {
                    Text(selectedSide == .a ? "モデルAから会話を開始します。" : "モデルBが応答します。")
                }

                if selectedSide == .a {
                    DualAutoModelSideForm(
                        providerTitleKey: "プロバイダー",
                        provider: $viewModel.settings.autoProviderA,
                        modelTitleKey: "Model",
                        model: $viewModel.settings.autoModelA,
                        systemPromptTitleKey: "Auto system prompt A",
                        systemPrompt: $viewModel.settings.autoSystemPromptA,
                        providerPresets: providerPresetOptions,
                        catalogProviders: viewModel.modelsDevCatalogState.providers,
                        openRouterModels: viewModel.openRouterModels,
                        openRouterModelsLoading: viewModel.openRouterModelsLoading,
                        openRouterModelsError: viewModel.openRouterModelsError,
                        onRefreshOpenRouterModels: { Task { await viewModel.refreshOpenRouterModels(force: false) } },
                        onProviderPresetSelected: applyProviderPresetToAutoA,
                        pccReasoningLevel: $viewModel.settings.pccReasoningLevel,
                        codexModels: viewModel.codexModels,
                        initialModel: viewModel.initialModelForSlot
                    )
                } else {
                    DualAutoModelSideForm(
                        providerTitleKey: "プロバイダー",
                        provider: $viewModel.settings.autoProviderB,
                        modelTitleKey: "Model",
                        model: $viewModel.settings.autoModelB,
                        systemPromptTitleKey: "Auto system prompt B",
                        systemPrompt: $viewModel.settings.autoSystemPromptB,
                        providerPresets: providerPresetOptions,
                        catalogProviders: viewModel.modelsDevCatalogState.providers,
                        openRouterModels: viewModel.openRouterModels,
                        openRouterModelsLoading: viewModel.openRouterModelsLoading,
                        openRouterModelsError: viewModel.openRouterModelsError,
                        onRefreshOpenRouterModels: { Task { await viewModel.refreshOpenRouterModels(force: false) } },
                        onProviderPresetSelected: applyProviderPresetToAutoB,
                        pccReasoningLevel: $viewModel.settings.pccReasoningLevel,
                        codexModels: viewModel.codexModels,
                        initialModel: viewModel.initialModelForSlot
                    )
                }

                ConversationAdvancedSettingsSection {
                    AutoConversationOverridesForm(viewModel: viewModel, side: selectedSide)
                }
                .id(selectedSide)

                Section(L10n.text("会話設定")) {
                    Text(maxTurnsLabel)
                        .font(.subheadline)

                    Toggle(L10n.text("無制限（安全上限: 100ターン・30分）"), isOn: Binding(
                        get: { isUnlimitedTurns },
                        set: { unlimited in
                            if unlimited {
                                viewModel.settings.autoMaxTurns = 0
                            } else if viewModel.settings.autoMaxTurns <= 0 {
                                viewModel.settings.autoMaxTurns = 20
                            }
                        }
                    ))

                    Slider(
                        value: Binding(
                            get: {
                                if isUnlimitedTurns { return 200 }
                                return Double(viewModel.settings.autoMaxTurns)
                            },
                            set: { viewModel.settings.autoMaxTurns = Int($0.rounded()) }
                        ),
                        in: 5 ... 200,
                        step: 1
                    )
                    .disabled(isUnlimitedTurns)

                }
            }
        }
    }

    private func applyProviderPresetToAutoA(_ preset: ModelPreset) {
        viewModel.settings.autoProviderA = preset.apiProvider.uppercased()
        viewModel.settings.autoModelA = preset.model
        if let prompt = preset.systemPrompt.flatMap(SettingsStringHelpers.nilIfBlank) {
            viewModel.settings.autoSystemPromptA = prompt
        }
        clearAutoOverridesA()
    }

    private func applyProviderPresetToAutoB(_ preset: ModelPreset) {
        viewModel.settings.autoProviderB = preset.apiProvider.uppercased()
        viewModel.settings.autoModelB = preset.model
        if let prompt = preset.systemPrompt.flatMap(SettingsStringHelpers.nilIfBlank) {
            viewModel.settings.autoSystemPromptB = prompt
        }
        clearAutoOverridesB()
    }

    private func clearAutoOverridesA() {
        viewModel.settings.autoOpenRouterThinkingEnabledA = nil
        viewModel.settings.autoOpenRouterThinkingBudgetA = nil
        viewModel.settings.autoOpenRouterReasoningModeA = nil
        viewModel.settings.autoOpenRouterReasoningEffortA = nil
        viewModel.settings.autoOpenRouterReasoningExcludeA = nil
        viewModel.settings.autoGoogleSearchEnabledA = nil
        viewModel.settings.autoCodeExecutionEnabledA = nil
        viewModel.settings.autoURLContextEnabledA = nil
        viewModel.settings.autoGoogleMapsEnabledA = nil
        viewModel.settings.autoComputerUseEnabledA = nil
        viewModel.settings.autoThinkingEnabledA = nil
        viewModel.settings.autoThinkingBudgetA = nil
        viewModel.settings.autoThinkingLevelA = nil
        viewModel.settings.autoCodexReasoningEffortA = nil
    }

    private func clearAutoOverridesB() {
        viewModel.settings.autoOpenRouterThinkingEnabledB = nil
        viewModel.settings.autoOpenRouterThinkingBudgetB = nil
        viewModel.settings.autoOpenRouterReasoningModeB = nil
        viewModel.settings.autoOpenRouterReasoningEffortB = nil
        viewModel.settings.autoOpenRouterReasoningExcludeB = nil
        viewModel.settings.autoGoogleSearchEnabledB = nil
        viewModel.settings.autoCodeExecutionEnabledB = nil
        viewModel.settings.autoURLContextEnabledB = nil
        viewModel.settings.autoGoogleMapsEnabledB = nil
        viewModel.settings.autoComputerUseEnabledB = nil
        viewModel.settings.autoThinkingEnabledB = nil
        viewModel.settings.autoThinkingBudgetB = nil
        viewModel.settings.autoThinkingLevelB = nil
        viewModel.settings.autoCodexReasoningEffortB = nil
    }
}

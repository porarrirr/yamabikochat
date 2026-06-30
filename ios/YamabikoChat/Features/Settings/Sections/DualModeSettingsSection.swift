import SwiftUI

struct DualModeSettingsSection: View {
    @ObservedObject var viewModel: SettingsViewModel

    @State private var modelAOverridesExpanded = false
    @State private var modelBOverridesExpanded = false

    private var dualSplitRatioBinding: Binding<Double> {
        Binding(
            get: { min(max(viewModel.settings.dualSplitRatio, 0.1), 0.9) },
            set: { viewModel.settings.dualSplitRatio = $0 }
        )
    }

    private var splitRatioLabel: String {
        let primary = Int(viewModel.settings.dualSplitRatio * 100)
        let secondary = Int((1 - viewModel.settings.dualSplitRatio) * 100)
        return L10n.format("Split ratio: %d%% : %d%%", primary, secondary)
    }

    private var providerPresetOptions: [ModelPreset] {
        viewModel.settings.buildGlobalProviderPresets()
    }

    var body: some View {
        Group {
            Section {
                Toggle(L10n.text("Enable dual mode"), isOn: Binding(
                    get: { viewModel.settings.isDualModeEnabled },
                    set: { viewModel.setDualModeEnabled($0) }
                ))
                .disabled(
                    (viewModel.settings.isAutoConversationEnabled || viewModel.settings.isFusionModeEnabled)
                        && !viewModel.settings.isDualModeEnabled
                )

                Text(L10n.text("デュアルモードで2つのモデル応答を同時比較します。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if (viewModel.settings.isAutoConversationEnabled || viewModel.settings.isFusionModeEnabled)
                    && !viewModel.settings.isDualModeEnabled {
                    Text(L10n.text("Fusion または自動会話が有効な間はデュアルモードをONにできません。"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text(L10n.text("デュアルモード"))
            } footer: {
                Text(L10n.text("Fusion・デュアル・自動会話は同時に有効化できません。"))
            }

            if viewModel.settings.isDualModeEnabled {
                Section(L10n.text("Model A")) {
                    DualAutoModelSideForm(
                        providerTitleKey: "Provider A",
                        provider: $viewModel.settings.dualProviderA,
                        modelTitleKey: "Model A",
                        model: $viewModel.settings.dualModelA,
                        systemPromptTitleKey: "Dual system prompt A",
                        systemPrompt: dualSystemPromptABinding,
                        providerPresets: providerPresetOptions,
                        onProviderPresetSelected: applyProviderPresetToDualA
                    )
                }

                Section(L10n.text("Model B")) {
                    DualAutoModelSideForm(
                        providerTitleKey: "Provider B",
                        provider: $viewModel.settings.dualProviderB,
                        modelTitleKey: "Model B",
                        model: $viewModel.settings.dualModelB,
                        systemPromptTitleKey: "Dual system prompt B",
                        systemPrompt: dualSystemPromptBBinding,
                        providerPresets: providerPresetOptions,
                        onProviderPresetSelected: applyProviderPresetToDualB
                    )
                }

                Section(L10n.text("レイアウト")) {
                    Picker(L10n.text("Split layout"), selection: Binding(
                        get: {
                            let normalized = viewModel.settings.dualSplitLayout
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                                .uppercased()
                            return normalized == "HORIZONTAL" ? "HORIZONTAL" : "VERTICAL"
                        },
                        set: { viewModel.settings.dualSplitLayout = $0 }
                    )) {
                        Text(L10n.text("左右分割")).tag("VERTICAL")
                        Text(L10n.text("上下分割")).tag("HORIZONTAL")
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text(splitRatioLabel)
                            .font(.subheadline)
                        Slider(value: dualSplitRatioBinding, in: 0.1 ... 0.9)
                    }
                }

                Section {
                    DisclosureGroup(
                        L10n.text("モデルAの詳細設定"),
                        isExpanded: $modelAOverridesExpanded
                    ) {
                        DualModeOverridesForm(viewModel: viewModel, side: .a)
                    }
                }

                Section {
                    DisclosureGroup(
                        L10n.text("モデルBの詳細設定"),
                        isExpanded: $modelBOverridesExpanded
                    ) {
                        DualModeOverridesForm(viewModel: viewModel, side: .b)
                    }
                }
            }
        }
    }

    private var dualSystemPromptABinding: Binding<String> {
        Binding(
            get: { viewModel.settings.dualSystemPromptA ?? "" },
            set: { viewModel.settings.dualSystemPromptA = SettingsStringHelpers.nilIfBlank($0) }
        )
    }

    private var dualSystemPromptBBinding: Binding<String> {
        Binding(
            get: { viewModel.settings.dualSystemPromptB ?? "" },
            set: { viewModel.settings.dualSystemPromptB = SettingsStringHelpers.nilIfBlank($0) }
        )
    }

    private func applyProviderPresetToDualA(_ preset: ModelPreset) {
        viewModel.settings.dualProviderA = preset.apiProvider.uppercased()
        viewModel.settings.dualModelA = preset.model
        if let prompt = preset.systemPrompt.flatMap(SettingsStringHelpers.nilIfBlank) {
            viewModel.settings.dualSystemPromptA = prompt
        }
        clearDualOverridesA()
    }

    private func applyProviderPresetToDualB(_ preset: ModelPreset) {
        viewModel.settings.dualProviderB = preset.apiProvider.uppercased()
        viewModel.settings.dualModelB = preset.model
        if let prompt = preset.systemPrompt.flatMap(SettingsStringHelpers.nilIfBlank) {
            viewModel.settings.dualSystemPromptB = prompt
        }
        clearDualOverridesB()
    }

    private func clearDualOverridesA() {
        viewModel.settings.dualOpenRouterThinkingEnabledA = nil
        viewModel.settings.dualOpenRouterThinkingBudgetA = nil
        viewModel.settings.dualOpenRouterReasoningModeA = nil
        viewModel.settings.dualOpenRouterReasoningEffortA = nil
        viewModel.settings.dualOpenRouterReasoningExcludeA = nil
        viewModel.settings.dualGoogleSearchEnabledA = nil
        viewModel.settings.dualCodeExecutionEnabledA = nil
        viewModel.settings.dualURLContextEnabledA = nil
        viewModel.settings.dualGoogleMapsEnabledA = nil
        viewModel.settings.dualComputerUseEnabledA = nil
        viewModel.settings.dualThinkingEnabledA = nil
        viewModel.settings.dualThinkingBudgetA = nil
        viewModel.settings.dualThinkingLevelA = nil
        viewModel.settings.dualCodexReasoningEffortA = nil
    }

    private func clearDualOverridesB() {
        viewModel.settings.dualOpenRouterThinkingEnabledB = nil
        viewModel.settings.dualOpenRouterThinkingBudgetB = nil
        viewModel.settings.dualOpenRouterReasoningModeB = nil
        viewModel.settings.dualOpenRouterReasoningEffortB = nil
        viewModel.settings.dualOpenRouterReasoningExcludeB = nil
        viewModel.settings.dualGoogleSearchEnabledB = nil
        viewModel.settings.dualCodeExecutionEnabledB = nil
        viewModel.settings.dualURLContextEnabledB = nil
        viewModel.settings.dualGoogleMapsEnabledB = nil
        viewModel.settings.dualComputerUseEnabledB = nil
        viewModel.settings.dualThinkingEnabledB = nil
        viewModel.settings.dualThinkingBudgetB = nil
        viewModel.settings.dualThinkingLevelB = nil
        viewModel.settings.dualCodexReasoningEffortB = nil
    }
}

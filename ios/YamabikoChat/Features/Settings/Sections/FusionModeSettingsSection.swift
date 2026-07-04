import SwiftUI

struct FusionModeSettingsSection: View {
    @ObservedObject var viewModel: SettingsViewModel

    private var chatVisibleProviderPresets: [ModelPreset] {
        viewModel.settings.chatVisibleGlobalProviderPresetsForDualAuto()
    }

    var body: some View {
        Group {
            Section {
                Toggle(L10n.text("Enable Fusion mode"), isOn: Binding(
                    get: { viewModel.settings.isFusionModeEnabled },
                    set: { viewModel.setFusionModeEnabled($0) }
                ))
                .disabled(
                    (viewModel.settings.isDualModeEnabled || viewModel.settings.isAutoConversationEnabled)
                        && !viewModel.settings.isFusionModeEnabled
                )

                Text(L10n.text("Fusion は複数モデルを並列実行し、ジャッジと合成で最終回答を生成します。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if (viewModel.settings.isDualModeEnabled || viewModel.settings.isAutoConversationEnabled)
                    && !viewModel.settings.isFusionModeEnabled {
                    Text(L10n.text("デュアルモードまたは自動会話が有効な間は Fusion を ON にできません。"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text(L10n.text("Fusion モード"))
            } footer: {
                Text(L10n.text("Fusion・デュアル・自動会話は同時に有効化できません。"))
            }

            if viewModel.settings.isFusionModeEnabled {
                Section(L10n.text("Fusion 設定")) {
                    Picker(L10n.text("Task type"), selection: $viewModel.settings.fusionTaskType) {
                        Text(L10n.text("Auto")).tag("auto")
                        Text(L10n.text("Research")).tag("research")
                        Text(L10n.text("Coding")).tag("coding")
                    }

                    Toggle(L10n.text("Debug mode"), isOn: $viewModel.settings.fusionDebugModeEnabled)
                    Toggle(L10n.text("Log prompts in trace"), isOn: $viewModel.settings.fusionLogPromptsEnabled)
                }

                modelSections
            }
        }
    }

    @ViewBuilder
    private var modelSections: some View {
        ForEach(Array(viewModel.fusionCustomPreset.panelModels.enumerated()), id: \.offset) { index, panel in
            Section {
                FusionModelSlotForm(
                    providerTitleKey: "Provider",
                    provider: panelProviderBinding(at: index, fallback: panel.provider),
                    modelTitleKey: "Model",
                    model: panelModelBinding(at: index, fallback: panel.modelId),
                    providerPresets: chatVisibleProviderPresets,
                    onProviderPresetSelected: { preset in
                        viewModel.updateFusionPanelModel(
                            at: index,
                            provider: preset.apiProvider,
                            modelId: preset.model
                        )
                    },
                    openRouterModels: viewModel.openRouterModels,
                    openRouterModelsLoading: viewModel.openRouterModelsLoading,
                    openRouterModelsError: viewModel.openRouterModelsError,
                    onRefreshOpenRouterModels: refreshOpenRouterModels,
                    onProviderChanged: handleProviderChanged
                )
            } header: {
                HStack {
                    Text(L10n.format("Panel %d", index + 1))
                    Spacer()
                    if viewModel.fusionCustomPreset.panelModels.count > 1 {
                        Button(role: .destructive) {
                            viewModel.removeFusionPanel(at: index)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
        }

        if viewModel.fusionCustomPreset.panelModels.count < FusionPresetLoader.maxPanelModelCount {
            Section {
                Button(L10n.text("パネルを追加")) {
                    viewModel.addFusionPanel()
                }
            }
        }

        Section(L10n.text("Judge")) {
            FusionModelSlotForm(
                providerTitleKey: "Provider",
                provider: judgeProviderBinding,
                modelTitleKey: "Model",
                model: judgeModelBinding,
                providerPresets: chatVisibleProviderPresets,
                onProviderPresetSelected: { preset in
                    viewModel.updateFusionJudgeModel(provider: preset.apiProvider, modelId: preset.model)
                },
                openRouterModels: viewModel.openRouterModels,
                openRouterModelsLoading: viewModel.openRouterModelsLoading,
                openRouterModelsError: viewModel.openRouterModelsError,
                onRefreshOpenRouterModels: refreshOpenRouterModels,
                onProviderChanged: handleProviderChanged
            )
        }

        Section(L10n.text("Synthesizer")) {
            FusionModelSlotForm(
                providerTitleKey: "Provider",
                provider: synthesizerProviderBinding,
                modelTitleKey: "Model",
                model: synthesizerModelBinding,
                providerPresets: chatVisibleProviderPresets,
                onProviderPresetSelected: { preset in
                    viewModel.updateFusionSynthesizerModel(provider: preset.apiProvider, modelId: preset.model)
                },
                openRouterModels: viewModel.openRouterModels,
                openRouterModelsLoading: viewModel.openRouterModelsLoading,
                openRouterModelsError: viewModel.openRouterModelsError,
                onRefreshOpenRouterModels: refreshOpenRouterModels,
                onProviderChanged: handleProviderChanged
            )
        }

        Section(L10n.text("Fallback")) {
            FusionModelSlotForm(
                providerTitleKey: "Provider",
                provider: fallbackProviderBinding,
                modelTitleKey: "Model",
                model: fallbackModelBinding,
                providerPresets: chatVisibleProviderPresets,
                onProviderPresetSelected: { preset in
                    viewModel.updateFusionFallbackModel(provider: preset.apiProvider, modelId: preset.model)
                },
                openRouterModels: viewModel.openRouterModels,
                openRouterModelsLoading: viewModel.openRouterModelsLoading,
                openRouterModelsError: viewModel.openRouterModelsError,
                onRefreshOpenRouterModels: refreshOpenRouterModels,
                onProviderChanged: handleProviderChanged
            )
        }
    }

    private func refreshOpenRouterModels() {
        Task { await viewModel.refreshOpenRouterModels(force: false) }
    }

    private func handleProviderChanged(_ provider: String) {
        guard provider == "OPENROUTER", viewModel.openRouterModels.isEmpty else { return }
        refreshOpenRouterModels()
    }

    private func panelProviderBinding(at index: Int, fallback: String) -> Binding<String> {
        Binding(
            get: {
                guard index < viewModel.fusionCustomPreset.panelModels.count else { return fallback }
                return viewModel.fusionCustomPreset.panelModels[index].provider
            },
            set: { newValue in
                let modelId = index < viewModel.fusionCustomPreset.panelModels.count
                    ? viewModel.fusionCustomPreset.panelModels[index].modelId
                    : ""
                viewModel.updateFusionPanelModel(at: index, provider: newValue, modelId: modelId)
            }
        )
    }

    private func panelModelBinding(at index: Int, fallback: String) -> Binding<String> {
        Binding(
            get: {
                guard index < viewModel.fusionCustomPreset.panelModels.count else { return fallback }
                return viewModel.fusionCustomPreset.panelModels[index].modelId
            },
            set: { newValue in
                let provider = index < viewModel.fusionCustomPreset.panelModels.count
                    ? viewModel.fusionCustomPreset.panelModels[index].provider
                    : "GEMINI"
                viewModel.updateFusionPanelModel(at: index, provider: provider, modelId: newValue)
            }
        )
    }

    private var judgeProviderBinding: Binding<String> {
        Binding(
            get: { viewModel.fusionCustomPreset.judgeModel.provider },
            set: { viewModel.updateFusionJudgeModel(provider: $0, modelId: viewModel.fusionCustomPreset.judgeModel.modelId) }
        )
    }

    private var judgeModelBinding: Binding<String> {
        Binding(
            get: { viewModel.fusionCustomPreset.judgeModel.modelId },
            set: { viewModel.updateFusionJudgeModel(provider: viewModel.fusionCustomPreset.judgeModel.provider, modelId: $0) }
        )
    }

    private var synthesizerProviderBinding: Binding<String> {
        Binding(
            get: { viewModel.fusionCustomPreset.synthesizerModel.provider },
            set: {
                viewModel.updateFusionSynthesizerModel(
                    provider: $0,
                    modelId: viewModel.fusionCustomPreset.synthesizerModel.modelId
                )
            }
        )
    }

    private var synthesizerModelBinding: Binding<String> {
        Binding(
            get: { viewModel.fusionCustomPreset.synthesizerModel.modelId },
            set: {
                viewModel.updateFusionSynthesizerModel(
                    provider: viewModel.fusionCustomPreset.synthesizerModel.provider,
                    modelId: $0
                )
            }
        )
    }

    private var fallbackProviderBinding: Binding<String> {
        Binding(
            get: { viewModel.fusionCustomPreset.fallbackModel?.provider ?? viewModel.fusionCustomPreset.synthesizerModel.provider },
            set: {
                viewModel.updateFusionFallbackModel(
                    provider: $0,
                    modelId: viewModel.fusionCustomPreset.fallbackModel?.modelId
                        ?? viewModel.fusionCustomPreset.synthesizerModel.modelId
                )
            }
        )
    }

    private var fallbackModelBinding: Binding<String> {
        Binding(
            get: { viewModel.fusionCustomPreset.fallbackModel?.modelId ?? viewModel.fusionCustomPreset.synthesizerModel.modelId },
            set: {
                viewModel.updateFusionFallbackModel(
                    provider: viewModel.fusionCustomPreset.fallbackModel?.provider
                        ?? viewModel.fusionCustomPreset.synthesizerModel.provider,
                    modelId: $0
                )
            }
        )
    }
}
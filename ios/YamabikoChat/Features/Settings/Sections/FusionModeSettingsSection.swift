import SwiftUI

struct FusionModeSettingsSection: View {
    @ObservedObject var viewModel: SettingsViewModel
    @State private var panelPendingDeletion: PanelModelConfig?
    @State private var bulkProvider = ""
    @State private var bulkModel = ""

    private var chatVisibleProviderPresets: [ModelPreset] {
        viewModel.settings.chatVisibleGlobalProviderPresets()
    }

    var body: some View {
        Group {
            Section {
                Toggle(L10n.text("Enable Fusion mode"), isOn: Binding(
                    get: { viewModel.settings.isFusionModeEnabled },
                    set: { viewModel.setFusionModeEnabled($0) }
                ))

                Text(L10n.text("Fusion は複数モデルを並列実行し、ジャッジと合成で最終回答を生成します。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)

            } header: {
                Text(L10n.text("Fusion モード"))
            } footer: {
                Text(L10n.text("Fusion・デュアル・自動会話は同時に有効化できません。"))
            }

            if viewModel.settings.isFusionModeEnabled {
                Section(L10n.text("Fusion 設定")) {
                    DisclosureGroup(L10n.text("詳細設定")) {
                        Toggle(L10n.text("Debug mode"), isOn: $viewModel.settings.fusionDebugModeEnabled)
                        Toggle(L10n.text("Log prompts in trace"), isOn: $viewModel.settings.fusionLogPromptsEnabled)
                    }
                }

                Section(L10n.text("モデルを一括設定")) {
                    FusionModelSlotForm(
                        providerTitleKey: "Provider",
                        provider: $bulkProvider,
                        modelTitleKey: "Model",
                        model: $bulkModel,
                        providerPresets: chatVisibleProviderPresets,
                        catalogProviders: viewModel.modelsDevCatalogState.providers,
                        onProviderPresetSelected: { preset in
                            bulkProvider = preset.apiProvider
                            bulkModel = preset.model
                        },
                        openRouterModels: viewModel.openRouterModels,
                        openRouterModelsLoading: viewModel.openRouterModelsLoading,
                        openRouterModelsError: viewModel.openRouterModelsError,
                        onRefreshOpenRouterModels: refreshOpenRouterModels,
                        onProviderChanged: handleProviderChanged
                    )

                    Button {
                        viewModel.applyFusionModelToAllSlots(
                            provider: bulkProvider,
                            modelId: bulkModel
                        )
                    } label: {
                        Label(L10n.text("すべてのモデルに適用"), systemImage: "square.stack.3d.up.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(
                        bulkProvider.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                        bulkModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )

                    Text(L10n.text("Panel・Judge・Synthesizerを同じモデルにまとめて設定します。"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .onAppear(perform: initializeBulkModelIfNeeded)

                modelSections
            }
        }
    }

    @ViewBuilder
    private var modelSections: some View {
        ForEach(Array(viewModel.fusionCustomPreset.panelModels.enumerated()), id: \.element.id) { index, panel in
            Section {
                FusionModelSlotForm(
                    providerTitleKey: "Provider",
                    provider: panelProviderBinding(at: index, fallback: panel.provider),
                    modelTitleKey: "Model",
                    model: panelModelBinding(at: index, fallback: panel.modelId),
                    providerPresets: chatVisibleProviderPresets,
                    catalogProviders: viewModel.modelsDevCatalogState.providers,
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
                            panelPendingDeletion = panel
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
                catalogProviders: viewModel.modelsDevCatalogState.providers,
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
                catalogProviders: viewModel.modelsDevCatalogState.providers,
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
        .alert(
            L10n.text("このパネルを削除しますか？"),
            isPresented: Binding(
                get: { panelPendingDeletion != nil },
                set: { if !$0 { panelPendingDeletion = nil } }
            ),
            presenting: panelPendingDeletion
        ) { panel in
            Button(L10n.text("削除"), role: .destructive) {
                guard let index = viewModel.fusionCustomPreset.panelModels.firstIndex(where: { $0.id == panel.id }) else { return }
                viewModel.removeFusionPanel(at: index)
                panelPendingDeletion = nil
            }
            Button(L10n.text("キャンセル"), role: .cancel) {
                panelPendingDeletion = nil
            }
        }

    }

    private func refreshOpenRouterModels() {
        Task { await viewModel.refreshOpenRouterModels(force: false) }
    }

    private func handleProviderChanged(_ provider: String) {
        guard provider.caseInsensitiveCompare("OPENROUTER") == .orderedSame,
              viewModel.openRouterModels.isEmpty else { return }
        refreshOpenRouterModels()
    }

    private func initializeBulkModelIfNeeded() {
        guard bulkProvider.isEmpty, bulkModel.isEmpty,
              let firstPanel = viewModel.fusionCustomPreset.panelModels.first else { return }
        bulkProvider = firstPanel.provider
        bulkModel = firstPanel.modelId
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

}

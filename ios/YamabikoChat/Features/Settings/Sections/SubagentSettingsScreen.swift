import SwiftUI

struct SubagentSettingsSection: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        Section("サブエージェント") {
            NavigationLink {
                SubagentSettingsScreen(viewModel: viewModel)
            } label: {
                HStack {
                    Label("サブエージェント", systemImage: "person.3")
                    Spacer()
                    Text(viewModel.settings.subagents.enabled ? "有効" : "無効").foregroundStyle(.secondary)
                }
            }
            .accessibilityIdentifier("settings-subagents")
        }
    }
}

private struct SubagentSettingsScreen: View {
    @EnvironmentObject private var container: AppContainer
    @ObservedObject var viewModel: SettingsViewModel
    @State private var reasons: [String: String] = [:]
    @State private var verified: Set<String> = []

    private var options: Binding<SubagentSettings> {
        Binding(get: { viewModel.settings.subagents }, set: { viewModel.settings.subagents = $0 })
    }

    var body: some View {
        AMOLEDForm {
            Section {
                Toggle("サブエージェントを利用", isOn: options.enabled)
                    .accessibilityIdentifier("subagents-enabled")
            } footer: {
                Text("依頼に応じて、Piが作業を子エージェントへ委譲します。実行状況はチャット内のコンパクトなサマリーから確認できます。")
            }
            Section {
                Picker("指定がない場合のモデル", selection: Binding(
                    get: { options.wrappedValue.defaultModelID ?? "inherit" },
                    set: { options.wrappedValue.defaultModelID = $0 == "inherit" ? nil : $0 }
                )) {
                    Text("親と同じモデル・effort").tag("inherit")
                    if let selected = options.wrappedValue.defaultModelID,
                       !options.wrappedValue.models.contains(where: { $0.id == selected }) {
                        Text("未登録の設定（利用不可）").tag(selected).disabled(true)
                    }
                    ForEach(options.wrappedValue.models) { profile in
                        Text(profile.name + (reasons[profile.id] == nil ? "" : "（利用不可）"))
                            .tag(profile.id)
                            .disabled(!verified.contains(profile.id) || reasons[profile.id] != nil)
                    }
                }
                .accessibilityIdentifier("subagents-default-model")
                if let selected = options.wrappedValue.defaultModelID, let reason = reasons[selected] {
                    Text(reason).font(.caption).foregroundStyle(.orange).textSelection(.enabled)
                }
            } footer: {
                Text("既定は親のモデルと推論レベルを引き継ぎます。チャットで特定のモデル設定を指定した場合は、その指定が優先されます。")
            }
            Section {
                ForEach(options.wrappedValue.models) { profile in
                    NavigationLink {
                        SubagentProfileEditor(viewModel: viewModel, profile: profileBinding(profile.id)) {
                            var updated = options.wrappedValue
                            updated.models.removeAll { $0.id == profile.id }
                            if updated.defaultModelID == profile.id { updated.defaultModelID = nil }
                            options.wrappedValue = updated
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(profile.name).foregroundStyle(.primary)
                            Text("\(ProviderCatalog.displayName(for: profile.provider)) · \(profile.model) · \(AppleIntelligenceModelCatalog.effortDisplayName(profile.effort, provider: profile.provider, model: profile.model))")
                                .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            if let reason = reasons[profile.id] {
                                Text(reason).font(.caption2).foregroundStyle(.orange).lineLimit(3)
                            }
                        }
                    }
                }
                Button {
                    let profile = SubagentModelProfile(
                        name: "モデル設定 \(options.wrappedValue.models.count + 1)",
                        provider: viewModel.settings.apiProvider, model: viewModel.settings.defaultModel)
                    options.wrappedValue.models.append(profile)
                } label: {
                    Label("モデル設定を追加", systemImage: "plus")
                }
                .accessibilityIdentifier("subagent-profile-add")
            } header: {
                Text("プロバイダー・モデル・effort")
            } footer: {
                Text("設定名で子エージェントを指定できます。複数の設定を作ると、並列の子エージェントごとに異なるモデルを使えます。認証には接続設定のAPIキー・ログインを利用します。Apple Intelligenceの実行経路には未対応です。")
            }
        }
        .navigationTitle("サブエージェント")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: options.wrappedValue.models) {
            verified = []
            reasons = [:]
            for profile in options.wrappedValue.models {
                do {
                    let config = try await container.providerGateway.subagentConfiguration(profile, settings: viewModel.settings, forModelResolution: true)
                    let resolution = try await PiAgentRuntime.shared.resolveModels([config]).first
                    try Task.checkCancellation()
                    if resolution?.supported != true { reasons[profile.id] = resolution?.reason ?? "pi_model_unavailable" }
                    else if resolution?.supportedThinkingLevels?.contains(profile.effort) != true { reasons[profile.id] = "subagent_effort_unsupported: \(profile.effort)" }
                } catch is CancellationError { return }
                catch { reasons[profile.id] = error.localizedDescription }
                verified.insert(profile.id)
            }
        }
    }

    private func profileBinding(_ id: String) -> Binding<SubagentModelProfile> {
        Binding(get: { options.wrappedValue.models.first { $0.id == id } ?? SubagentModelProfile(id: id) }, set: { value in
            guard let index = options.wrappedValue.models.firstIndex(where: { $0.id == id }) else { return }
            options.wrappedValue.models[index] = value
        })
    }
}

private struct SubagentProfileEditor: View {
    @EnvironmentObject private var container: AppContainer
    @ObservedObject var viewModel: SettingsViewModel
    @Binding var profile: SubagentModelProfile
    let onDelete: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var confirmsDeletion = false
    @State private var supportedEfforts: [String] = []
    @State private var resolutionError: String?

    var body: some View {
        AMOLEDForm {
            Section {
                TextField("名前", text: $profile.name)
                    .accessibilityIdentifier("subagent-profile-name")
                ModelSlotForm(providerTitleKey: "プロバイダー", provider: $profile.provider,
                    modelTitleKey: "モデル", model: $profile.model,
                    catalogProviders: viewModel.modelsDevCatalogState.providers, pccReasoningLevel: .constant(nil), showsPCCReasoning: false,
                    codexModels: viewModel.codexModels, initialModel: viewModel.initialModelForSlot,
                    openRouterModels: viewModel.openRouterModels, openRouterModelsLoading: viewModel.openRouterModelsLoading,
                    openRouterModelsError: viewModel.openRouterModelsError,
                    onRefreshOpenRouterModels: { Task { await viewModel.refreshOpenRouterModels(force: false) } })
                if profile.provider.uppercased() == "OPENAI_COMPAT" {
                    Picker("エンドポイント設定", selection: Binding(
                        get: { profile.endpointPresetName ?? viewModel.settings.selectedOpenAICompatPreset ?? "" },
                        set: { profile.endpointPresetName = $0 }
                    )) {
                        ForEach(viewModel.settings.openAICompatPresets()) { preset in Text(preset.name).tag(preset.name) }
                    }
                }
                Picker(profile.isPCC ? "PCC reasoning" : "Effort（推論レベル）", selection: $profile.effort) {
                    if !supportedEfforts.contains(profile.effort) {
                        Text("\(profile.effort)（非対応）").tag(profile.effort).disabled(true)
                    }
                    ForEach(supportedEfforts, id: \.self) { effort in
                        Text(effort == "off" ? "off（推論なし）" : AppleIntelligenceModelCatalog.effortDisplayName(effort, provider: profile.provider, model: profile.model)).tag(effort)
                    }
                }
                .disabled(supportedEfforts.isEmpty)
                .accessibilityIdentifier("subagent-effort-picker")
                if let resolutionError { Text(resolutionError).font(.caption).foregroundStyle(.orange).textSelection(.enabled) }
                if let error = profile.validationError { Text(error).font(.caption).foregroundStyle(.orange) }
            } header: {
                Text("モデル設定")
            } footer: {
                Text("モデルが対応する推論レベルを指定してください。非対応の組み合わせは実行せず、理由を表示します。")
            }
            Section {
                Button("モデル設定を削除", role: .destructive) { confirmsDeletion = true }
                    .accessibilityIdentifier("subagent-profile-delete")
                    .alert("このモデル設定を削除しますか？", isPresented: $confirmsDeletion) {
                        Button("削除", role: .destructive) {
                            dismiss()
                            onDelete()
                        }
                        Button("キャンセル", role: .cancel) {}
                    }
            }
            Section("チャットでの指定") {
                Text("「\(profile.name) で調査して」のように依頼できます。")
            }
        }
        .navigationTitle(profile.name)
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: profile.isPCC) { _, isPCC in
            if isPCC { profile.initializePCCEffortIfNeeded() }
        }
        .task(id: profile) {
            do {
                let config = try await container.providerGateway.subagentConfiguration(profile, settings: viewModel.settings, forModelResolution: true)
                let resolution = try await PiAgentRuntime.shared.resolveModels([config]).first
                try Task.checkCancellation()
                supportedEfforts = resolution?.supportedThinkingLevels ?? []
                resolutionError = resolution?.supported == true
                    ? (supportedEfforts.contains(profile.effort) ? nil : "subagent_effort_unsupported: \(profile.effort)")
                    : resolution?.reason ?? "pi_model_unavailable"
            } catch is CancellationError { return }
            catch { supportedEfforts = []; resolutionError = error.localizedDescription }
        }
    }
}

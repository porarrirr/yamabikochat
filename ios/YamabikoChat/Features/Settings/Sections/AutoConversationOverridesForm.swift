import SwiftUI

/// Per-model request overrides for auto conversation.
///
/// Auto turns execute with `AppSettings.ReasoningContext.autoA`/`.autoB`, so the
/// values edited here are the ones the request resolver applies to each speaker.
struct AutoConversationOverridesForm: View {
    @ObservedObject var viewModel: SettingsViewModel
    let side: DualModelSide

    private var keyPaths: AutoOverrideKeyPaths {
        side.keyPaths
    }

    private var settings: AppSettings {
        viewModel.settings
    }

    private var provider: String {
        settings[keyPath: keyPaths.provider].uppercased()
    }

    private var model: String {
        settings[keyPath: keyPaths.model]
    }

    private var prefix: String {
        side == .a ? "A" : "B"
    }

    var body: some View {
        Group {
            providerSpecificControls

            if modelsDevProviderID == nil,
               ["GEMINI", "OPENROUTER", "CODEX_AUTH", "SUPERGROK"].contains(provider) {
                Text(L10n.text("個別に指定しない項目は、プリセットの選択に関係なくプロバイダー設定を使用します。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button(L10n.text("個別設定をリセット")) {
                resetOverrides()
            }
            .accessibilityIdentifier("conversation-model-reset")
        }
    }

    @ViewBuilder
    private var providerSpecificControls: some View {
        if let catalogModel = modelsDevCatalogModel {
            modelsDevReasoningControls(model: catalogModel)
        } else {
            switch provider {
            case "GEMINI":
                geminiControls
            case "OPENROUTER":
                openRouterControls
            case "CODEX_AUTH", "SUPERGROK":
                reasoningEffortControls
            default:
                EmptyView()
            }
        }
    }

    @ViewBuilder
    private var geminiControls: some View {
        Toggle(L10n.text("Thinking enabled"), isOn: thinkingEnabledBinding)
        if GeminiModelUtils.isThinkingLevelSupported(model: model) {
            Picker(L10n.text("Thinking level"), selection: thinkingLevelBinding) {
                Text(verbatim: providerSettingLabel(providerThinkingLevel)).tag("")
                if !currentThinkingLevel.isEmpty,
                   !thinkingLevelOptions.contains(currentThinkingLevel) {
                    Text(verbatim: unsupportedValueLabel(currentThinkingLevel)).tag(currentThinkingLevel)
                }
                ForEach(thinkingLevelOptions, id: \.self) { option in
                    Text(verbatim: option).tag(option)
                }
            }
        } else {
            TextField(L10n.text("Thinking budget"), text: thinkingBudgetBinding)
                .keyboardType(.numberPad)
        }
        Toggle(L10n.text("Google Search"), isOn: googleSearchBinding)
        Toggle(L10n.text("Code Execution"), isOn: codeExecutionBinding)
        Toggle(L10n.text("URL Context"), isOn: urlContextBinding)
        Toggle(L10n.text("Google Maps"), isOn: googleMapsBinding)
    }

    @ViewBuilder
    private var openRouterControls: some View {
        if let capabilities = openRouterReasoningCapabilities {
            Picker(L10n.text("Reasoning mode"), selection: openRouterReasoningModeBinding) {
                Text(verbatim: providerSettingLabel(settings.openRouterReasoningMode)).tag("inherit")
                ForEach(openRouterReasoningModes, id: \.self) { mode in
                    Text(verbatim: mode).tag(mode)
                }
            }
            Toggle(L10n.text("Thinking enabled"), isOn: openRouterThinkingEnabledBinding)
                .disabled(capabilities.mandatory)
            if capabilities.supportsMaxTokens {
                TextField(L10n.text("Thinking budget"), text: openRouterBudgetBinding)
                    .keyboardType(.numberPad)
            }
            if !openRouterReasoningEfforts.isEmpty {
                Picker(L10n.text("Reasoning Effort"), selection: openRouterEffortBinding) {
                    Text(verbatim: providerSettingLabel(settings.openRouterReasoningEffort)).tag("")
                    ForEach(openRouterReasoningEfforts, id: \.self) { effort in
                        Text(verbatim: effort).tag(effort)
                    }
                }
            }
            Toggle(L10n.text("Exclude reasoning"), isOn: openRouterExcludeBinding)
        } else {
            Text(L10n.format("%@: このモデルはOpenRouter Reasoning設定に対応していません。", prefix))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var openRouterReasoningCapabilities: OpenRouterReasoningCapabilities? {
        viewModel.openRouterReasoningCapabilities(forModelId: model)
    }

    private var openRouterReasoningModes: [String] {
        viewModel.openRouterReasoningModes(forModelId: model)
    }

    private var openRouterReasoningEfforts: [String] {
        viewModel.openRouterReasoningEfforts(forModelId: model)
    }

    @ViewBuilder
    private var reasoningEffortControls: some View {
        let enabledLabel = L10n.text("Reasoning enabled")
        let effortLabel = L10n.text("Reasoning Effort")
        Toggle(enabledLabel, isOn: thinkingEnabledBinding)
        if reasoningEffortOptions.isEmpty {
            if provider == "CODEX_AUTH" {
                Text(L10n.format("%@: ChatGPTのモデル一覧を取得すると推論Effortを選択できます", prefix))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        } else {
            Picker(effortLabel, selection: reasoningEffortBinding) {
                Text(verbatim: providerSettingLabel(providerReasoningEffort)).tag("")
                if !currentReasoningEffort.isEmpty,
                   !reasoningEffortOptions.contains(currentReasoningEffort) {
                    Text(verbatim: unsupportedValueLabel(currentReasoningEffort)).tag(currentReasoningEffort)
                }
                ForEach(reasoningEffortOptions, id: \.self) { effort in
                    Text(verbatim: effort).tag(effort)
                }
            }
        }
    }

    /// models.dev providers store reasoning effort in the same per-model preference
    /// the provider settings and chat composer use.
    @ViewBuilder
    private func modelsDevReasoningControls(model catalogModel: CatalogModel) -> some View {
        let savedEffort = modelsDevReasoningEffort
        if catalogModel.shouldShowReasoningEffortPreference(savedEffort: savedEffort) {
            ModelsDevReasoningEffortPicker(
                model: catalogModel,
                currentEffort: savedEffort,
                onChange: { effort in
                    guard let providerID = modelsDevProviderID else { return }
                    viewModel.saveModelsDevReasoningEffort(
                        providerID: providerID,
                        modelID: catalogModel.id,
                        effort: effort
                    )
                }
            )
            .id("\(provider)\u{0}\(catalogModel.id)")
        }
    }

    private var modelsDevProviderID: String? {
        ProviderReference(persistedID: provider).modelsDevID
    }

    private var modelsDevCatalogModel: CatalogModel? {
        guard let providerID = modelsDevProviderID else { return nil }
        return viewModel.modelsDevCatalogState.providers
            .first { $0.id.caseInsensitiveCompare(providerID) == .orderedSame }?
            .models.first { $0.id == model }
    }

    private var modelsDevReasoningEffort: String {
        guard let providerID = modelsDevProviderID else { return "" }
        return viewModel.modelsDevReasoningEffort(providerID: providerID, modelID: model)
    }

    private var reasoningEffortOptions: [String] {
        switch provider {
        case "CODEX_AUTH":
            CodexModelCatalog.findPreset(model, in: viewModel.codexModels)?
                .supportedReasoningEfforts.map(\.effort) ?? []
        case "SUPERGROK":
            ["low", "medium", "high"]
        default:
            []
        }
    }

    private var providerThinkingLevel: String {
        GeminiModelUtils.normalizeThinkingLevel(model: model, level: settings.geminiThinkingLevel)
            ?? GeminiModelUtils.getDefaultThinkingLevel(model: model)
    }

    private var providerReasoningEffort: String {
        let effort = provider == "CODEX_AUTH"
            ? settings.codexReasoningEffort
            : settings.superGrokReasoningEffort
        return SettingsStringHelpers.nilIfBlank(effort) ?? "medium"
    }

    private func providerSettingLabel(_ value: String) -> String {
        let detail = SettingsStringHelpers.nilIfBlank(value) ?? L10n.text("モデルの既定値")
        return L10n.format("プロバイダー設定（%@）", detail)
    }

    private var currentReasoningEffort: String {
        settings[keyPath: keyPaths.codexReasoningEffort]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
    }

    private var thinkingLevelOptions: [String] {
        GeminiModelUtils.getThinkingLevelOptions(model: model)
    }

    private var currentThinkingLevel: String {
        settings[keyPath: keyPaths.thinkingLevel]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
    }

    private func unsupportedValueLabel(_ value: String) -> String {
        L10n.format("%@（現在は非対応）", value)
    }

    private var inheritedThinkingEnabled: Bool {
        switch provider {
        case "CODEX_AUTH":
            settings.codexReasoningEnabled
        case "SUPERGROK":
            settings.superGrokReasoningEnabled
        default:
            settings.geminiThinkingEnabled
        }
    }

    private var googleSearchBinding: Binding<Bool> {
        Binding(
            get: { settings[keyPath: keyPaths.googleSearch] ?? settings.geminiGoogleSearchEnabled },
            set: { viewModel.settings[keyPath: keyPaths.googleSearch] = $0 }
        )
    }

    private var codeExecutionBinding: Binding<Bool> {
        Binding(
            get: { settings[keyPath: keyPaths.codeExecution] ?? settings.geminiCodeExecutionEnabled },
            set: { viewModel.settings[keyPath: keyPaths.codeExecution] = $0 }
        )
    }

    private var urlContextBinding: Binding<Bool> {
        Binding(
            get: { settings[keyPath: keyPaths.urlContext] ?? settings.geminiURLContextEnabled },
            set: { viewModel.settings[keyPath: keyPaths.urlContext] = $0 }
        )
    }

    private var googleMapsBinding: Binding<Bool> {
        Binding(
            get: { settings[keyPath: keyPaths.googleMaps] ?? settings.geminiGoogleMapsEnabled },
            set: { viewModel.settings[keyPath: keyPaths.googleMaps] = $0 }
        )
    }

    private var thinkingEnabledBinding: Binding<Bool> {
        Binding(
            get: { settings[keyPath: keyPaths.thinkingEnabled] ?? inheritedThinkingEnabled },
            set: { viewModel.settings[keyPath: keyPaths.thinkingEnabled] = $0 }
        )
    }

    private var thinkingBudgetBinding: Binding<String> {
        Binding(
            get: { settings[keyPath: keyPaths.thinkingBudget].map(String.init) ?? "" },
            set: { value in
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    viewModel.settings[keyPath: keyPaths.thinkingBudget] = nil
                } else if let parsed = Int(trimmed) {
                    viewModel.settings[keyPath: keyPaths.thinkingBudget] = max(0, parsed)
                }
            }
        )
    }

    private var thinkingLevelBinding: Binding<String> {
        Binding(
            get: { currentThinkingLevel },
            set: { value in
                let level = SettingsStringHelpers.nilIfBlank(value)
                viewModel.settings[keyPath: keyPaths.thinkingLevel] = level
                guard level != nil else { return }
                enableThinkingOverride()
            }
        )
    }

    private var reasoningEffortBinding: Binding<String> {
        Binding(
            get: { currentReasoningEffort },
            set: { value in
                viewModel.settings[keyPath: keyPaths.codexReasoningEffort] = SettingsStringHelpers.nilIfBlank(value)
                guard SettingsStringHelpers.nilIfBlank(value) != nil else { return }
                enableThinkingOverride()
            }
        )
    }

    private var openRouterReasoningModeBinding: Binding<String> {
        Binding(
            get: {
                let stored = settings[keyPath: keyPaths.openRouterReasoningMode] ?? "inherit"
                let normalized = stored.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                return normalized == "inherit" || openRouterReasoningModes.contains(normalized)
                    ? normalized
                    : "inherit"
            },
            set: { newValue in
                let normalized = newValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                viewModel.settings[keyPath: keyPaths.openRouterReasoningMode] =
                    openRouterReasoningModes.contains(normalized) ? normalized : nil
            }
        )
    }

    private var openRouterThinkingEnabledBinding: Binding<Bool> {
        Binding(
            get: {
                openRouterReasoningCapabilities?.mandatory == true ||
                    (settings[keyPath: keyPaths.openRouterThinkingEnabled] ?? settings.openRouterThinkingEnabled)
            },
            set: {
                viewModel.settings[keyPath: keyPaths.openRouterThinkingEnabled] =
                    openRouterReasoningCapabilities?.mandatory == true ? true : $0
            }
        )
    }

    private var openRouterBudgetBinding: Binding<String> {
        Binding(
            get: { settings[keyPath: keyPaths.openRouterThinkingBudget].map(String.init) ?? "" },
            set: { value in
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    viewModel.settings[keyPath: keyPaths.openRouterThinkingBudget] = nil
                } else if let parsed = Int(trimmed) {
                    viewModel.settings[keyPath: keyPaths.openRouterThinkingBudget] = max(0, parsed)
                }
            }
        )
    }

    private var openRouterEffortBinding: Binding<String> {
        Binding(
            get: {
                let effort = settings[keyPath: keyPaths.openRouterReasoningEffort]?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased() ?? ""
                return openRouterReasoningEfforts.contains(effort) ? effort : ""
            },
            set: { newValue in
                let effort = newValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let selected = openRouterReasoningEfforts.contains(effort) ? effort : nil
                viewModel.settings[keyPath: keyPaths.openRouterReasoningEffort] = selected
                guard selected != nil else { return }
                // An effort override only applies in effort mode, so selecting one opts into it.
                viewModel.settings[keyPath: keyPaths.openRouterReasoningMode] = "effort"
                if openRouterReasoningCapabilities?.mandatory != true {
                    viewModel.settings[keyPath: keyPaths.openRouterThinkingEnabled] = true
                }
            }
        )
    }

    private var openRouterExcludeBinding: Binding<Bool> {
        Binding(
            get: { settings[keyPath: keyPaths.openRouterReasoningExclude] ?? settings.openRouterReasoningExclude },
            set: { viewModel.settings[keyPath: keyPaths.openRouterReasoningExclude] = $0 }
        )
    }

    /// A level/effort override is only sent while reasoning is enabled for the slot.
    private func enableThinkingOverride() {
        viewModel.settings[keyPath: keyPaths.thinkingEnabled] = true
    }

    private func resetOverrides() {
        if let providerID = modelsDevProviderID {
            viewModel.saveModelsDevReasoningEffort(providerID: providerID, modelID: model, effort: "")
        }
        viewModel.settings[keyPath: keyPaths.openRouterThinkingEnabled] = nil
        viewModel.settings[keyPath: keyPaths.openRouterThinkingBudget] = nil
        viewModel.settings[keyPath: keyPaths.openRouterReasoningMode] = nil
        viewModel.settings[keyPath: keyPaths.openRouterReasoningEffort] = nil
        viewModel.settings[keyPath: keyPaths.openRouterReasoningExclude] = nil
        viewModel.settings[keyPath: keyPaths.googleSearch] = nil
        viewModel.settings[keyPath: keyPaths.codeExecution] = nil
        viewModel.settings[keyPath: keyPaths.urlContext] = nil
        viewModel.settings[keyPath: keyPaths.googleMaps] = nil
        viewModel.settings[keyPath: keyPaths.thinkingEnabled] = nil
        viewModel.settings[keyPath: keyPaths.thinkingBudget] = nil
        viewModel.settings[keyPath: keyPaths.thinkingLevel] = nil
        viewModel.settings[keyPath: keyPaths.codexReasoningEffort] = nil
    }
}

/// `AppSettings` key paths for the auto conversation's per-model overrides.
struct AutoOverrideKeyPaths {
    let provider: WritableKeyPath<AppSettings, String>
    let model: WritableKeyPath<AppSettings, String>
    let googleSearch: WritableKeyPath<AppSettings, Bool?>
    let codeExecution: WritableKeyPath<AppSettings, Bool?>
    let urlContext: WritableKeyPath<AppSettings, Bool?>
    let googleMaps: WritableKeyPath<AppSettings, Bool?>
    let thinkingEnabled: WritableKeyPath<AppSettings, Bool?>
    let thinkingBudget: WritableKeyPath<AppSettings, Int?>
    let thinkingLevel: WritableKeyPath<AppSettings, String?>
    let codexReasoningEffort: WritableKeyPath<AppSettings, String?>
    let openRouterThinkingEnabled: WritableKeyPath<AppSettings, Bool?>
    let openRouterThinkingBudget: WritableKeyPath<AppSettings, Int?>
    let openRouterReasoningMode: WritableKeyPath<AppSettings, String?>
    let openRouterReasoningEffort: WritableKeyPath<AppSettings, String?>
    let openRouterReasoningExclude: WritableKeyPath<AppSettings, Bool?>
}

extension DualModelSide {
    var keyPaths: AutoOverrideKeyPaths {
        switch self {
        case .a:
            AutoOverrideKeyPaths(
                provider: \.autoProviderA,
                model: \.autoModelA,
                googleSearch: \.autoGoogleSearchEnabledA,
                codeExecution: \.autoCodeExecutionEnabledA,
                urlContext: \.autoURLContextEnabledA,
                googleMaps: \.autoGoogleMapsEnabledA,
                thinkingEnabled: \.autoThinkingEnabledA,
                thinkingBudget: \.autoThinkingBudgetA,
                thinkingLevel: \.autoThinkingLevelA,
                codexReasoningEffort: \.autoCodexReasoningEffortA,
                openRouterThinkingEnabled: \.autoOpenRouterThinkingEnabledA,
                openRouterThinkingBudget: \.autoOpenRouterThinkingBudgetA,
                openRouterReasoningMode: \.autoOpenRouterReasoningModeA,
                openRouterReasoningEffort: \.autoOpenRouterReasoningEffortA,
                openRouterReasoningExclude: \.autoOpenRouterReasoningExcludeA
            )
        case .b:
            AutoOverrideKeyPaths(
                provider: \.autoProviderB,
                model: \.autoModelB,
                googleSearch: \.autoGoogleSearchEnabledB,
                codeExecution: \.autoCodeExecutionEnabledB,
                urlContext: \.autoURLContextEnabledB,
                googleMaps: \.autoGoogleMapsEnabledB,
                thinkingEnabled: \.autoThinkingEnabledB,
                thinkingBudget: \.autoThinkingBudgetB,
                thinkingLevel: \.autoThinkingLevelB,
                codexReasoningEffort: \.autoCodexReasoningEffortB,
                openRouterThinkingEnabled: \.autoOpenRouterThinkingEnabledB,
                openRouterThinkingBudget: \.autoOpenRouterThinkingBudgetB,
                openRouterReasoningMode: \.autoOpenRouterReasoningModeB,
                openRouterReasoningEffort: \.autoOpenRouterReasoningEffortB,
                openRouterReasoningExclude: \.autoOpenRouterReasoningExcludeB
            )
        }
    }
}

import SwiftUI

enum DualModelSide: Hashable {
    case a
    case b
}

struct DualModeOverridesForm: View {
    @ObservedObject var viewModel: SettingsViewModel
    let side: DualModelSide

    private var provider: String {
        switch side {
        case .a: viewModel.settings.dualProviderA.uppercased()
        case .b: viewModel.settings.dualProviderB.uppercased()
        }
    }

    private var prefix: String {
        switch side {
        case .a: "A"
        case .b: "B"
        }
    }

    private var model: String {
        switch side {
        case .a: viewModel.settings.dualModelA
        case .b: viewModel.settings.dualModelB
        }
    }

    var body: some View {
        Group {
            providerSpecificControls

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
        Toggle(L10n.text("Google Search"), isOn: googleSearchBinding)
        Toggle(L10n.text("Code Execution"), isOn: codeExecutionBinding)
        Toggle(L10n.text("URL Context"), isOn: urlContextBinding)
        Toggle(L10n.text("Google Maps"), isOn: googleMapsBinding)
        Toggle(L10n.text("Thinking enabled"), isOn: thinkingEnabledBinding)
        if GeminiModelUtils.isThinkingLevelSupported(model: model) {
            Picker(L10n.text("Thinking level"), selection: thinkingLevelBinding) {
                Text(L10n.text("inherit")).tag("")
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
    }

    @ViewBuilder
    private var openRouterControls: some View {
        if let capabilities = openRouterReasoningCapabilities {
            Picker(L10n.text("Reasoning mode"), selection: openRouterReasoningModeBinding) {
                Text(L10n.text("inherit")).tag("inherit")
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
                    Text(L10n.text("inherit")).tag("")
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
                Text(L10n.text("inherit")).tag("")
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

    /// models.dev providers keep their reasoning effort in the same per-model
    /// preference the provider settings and the chat composer already use.
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
                },
                title: L10n.text("Reasoning Effort")
            )
            .id("\(provider)\u{0}\(catalogModel.id)")
        }
    }

    private var modelsDevProviderID: String? {
        ProviderReference(persistedID: provider).modelsDevID
    }

    private var modelsDevCatalogModel: CatalogModel? {
        guard let providerID = modelsDevProviderID else { return nil }
        return ReasoningEffortOptions.catalogModel(
            providerID: providerID,
            model: model,
            catalogProviders: viewModel.modelsDevCatalogState.providers
        )
    }

    private var modelsDevReasoningEffort: String {
        guard let providerID = modelsDevProviderID else { return "" }
        return viewModel.modelsDevReasoningEffort(providerID: providerID, modelID: model)
    }

    private var reasoningEffortOptions: [String] {
        ReasoningEffortOptions.options(
            provider: provider,
            model: model,
            codexModels: viewModel.codexModels,
            catalogProviders: viewModel.modelsDevCatalogState.providers
        )
    }

    private var currentReasoningEffort: String {
        switch side {
        case .a:
            viewModel.settings.dualCodexReasoningEffortA?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased() ?? ""
        case .b:
            viewModel.settings.dualCodexReasoningEffortB?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased() ?? ""
        }
    }

    private var thinkingLevelOptions: [String] {
        GeminiModelUtils.getThinkingLevelOptions(model: model)
    }

    private var currentThinkingLevel: String {
        switch side {
        case .a:
            viewModel.settings.dualThinkingLevelA?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased() ?? ""
        case .b:
            viewModel.settings.dualThinkingLevelB?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased() ?? ""
        }
    }

    private func unsupportedValueLabel(_ value: String) -> String {
        L10n.format("%@（現在は非対応）", value)
    }

    private var inheritedThinkingEnabled: Bool {
        switch provider {
        case "CODEX_AUTH":
            viewModel.settings.codexReasoningEnabled
        case "SUPERGROK":
            viewModel.settings.superGrokReasoningEnabled
        default:
            viewModel.settings.geminiThinkingEnabled
        }
    }

    private var googleSearchBinding: Binding<Bool> {
        switch side {
        case .a:
            Binding(
                get: { viewModel.settings.dualGoogleSearchEnabledA ?? viewModel.settings.geminiGoogleSearchEnabled },
                set: { viewModel.settings.dualGoogleSearchEnabledA = $0 }
            )
        case .b:
            Binding(
                get: { viewModel.settings.dualGoogleSearchEnabledB ?? viewModel.settings.geminiGoogleSearchEnabled },
                set: { viewModel.settings.dualGoogleSearchEnabledB = $0 }
            )
        }
    }

    private var codeExecutionBinding: Binding<Bool> {
        switch side {
        case .a:
            Binding(
                get: { viewModel.settings.dualCodeExecutionEnabledA ?? viewModel.settings.geminiCodeExecutionEnabled },
                set: { viewModel.settings.dualCodeExecutionEnabledA = $0 }
            )
        case .b:
            Binding(
                get: { viewModel.settings.dualCodeExecutionEnabledB ?? viewModel.settings.geminiCodeExecutionEnabled },
                set: { viewModel.settings.dualCodeExecutionEnabledB = $0 }
            )
        }
    }

    private var urlContextBinding: Binding<Bool> {
        switch side {
        case .a:
            Binding(
                get: { viewModel.settings.dualURLContextEnabledA ?? viewModel.settings.geminiURLContextEnabled },
                set: { viewModel.settings.dualURLContextEnabledA = $0 }
            )
        case .b:
            Binding(
                get: { viewModel.settings.dualURLContextEnabledB ?? viewModel.settings.geminiURLContextEnabled },
                set: { viewModel.settings.dualURLContextEnabledB = $0 }
            )
        }
    }

    private var googleMapsBinding: Binding<Bool> {
        switch side {
        case .a:
            Binding(
                get: { viewModel.settings.dualGoogleMapsEnabledA ?? viewModel.settings.geminiGoogleMapsEnabled },
                set: { viewModel.settings.dualGoogleMapsEnabledA = $0 }
            )
        case .b:
            Binding(
                get: { viewModel.settings.dualGoogleMapsEnabledB ?? viewModel.settings.geminiGoogleMapsEnabled },
                set: { viewModel.settings.dualGoogleMapsEnabledB = $0 }
            )
        }
    }

    private var thinkingEnabledBinding: Binding<Bool> {
        switch side {
        case .a:
            Binding(
                get: { viewModel.settings.dualThinkingEnabledA ?? inheritedThinkingEnabled },
                set: { viewModel.settings.dualThinkingEnabledA = $0 }
            )
        case .b:
            Binding(
                get: { viewModel.settings.dualThinkingEnabledB ?? inheritedThinkingEnabled },
                set: { viewModel.settings.dualThinkingEnabledB = $0 }
            )
        }
    }

    private var thinkingBudgetBinding: Binding<String> {
        Binding(
            get: {
                let value: Int? = switch side {
                case .a: viewModel.settings.dualThinkingBudgetA
                case .b: viewModel.settings.dualThinkingBudgetB
                }
                return value.map(String.init) ?? ""
            },
            set: { value in
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    switch side {
                    case .a: viewModel.settings.dualThinkingBudgetA = nil
                    case .b: viewModel.settings.dualThinkingBudgetB = nil
                    }
                } else if let parsed = Int(trimmed) {
                    switch side {
                    case .a: viewModel.settings.dualThinkingBudgetA = max(0, parsed)
                    case .b: viewModel.settings.dualThinkingBudgetB = max(0, parsed)
                    }
                }
            }
        )
    }

    private var thinkingLevelBinding: Binding<String> {
        switch side {
        case .a:
            Binding(
                get: { currentThinkingLevel },
                set: { viewModel.settings.dualThinkingLevelA = SettingsStringHelpers.nilIfBlank($0) }
            )
        case .b:
            Binding(
                get: { currentThinkingLevel },
                set: { viewModel.settings.dualThinkingLevelB = SettingsStringHelpers.nilIfBlank($0) }
            )
        }
    }

    private var reasoningEffortBinding: Binding<String> {
        switch side {
        case .a:
            Binding(
                get: { currentReasoningEffort },
                set: { viewModel.settings.dualCodexReasoningEffortA = SettingsStringHelpers.nilIfBlank($0) }
            )
        case .b:
            Binding(
                get: { currentReasoningEffort },
                set: { viewModel.settings.dualCodexReasoningEffortB = SettingsStringHelpers.nilIfBlank($0) }
            )
        }
    }

    private var openRouterReasoningModeBinding: Binding<String> {
        Binding(
            get: {
                let stored: String? = switch side {
                case .a: viewModel.settings.dualOpenRouterReasoningModeA ?? "inherit"
                case .b: viewModel.settings.dualOpenRouterReasoningModeB ?? "inherit"
                }
                guard let stored else { return "inherit" }
                let normalized = stored.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                return normalized == "inherit" || openRouterReasoningModes.contains(normalized)
                    ? normalized
                    : "inherit"
            },
            set: { newValue in
                let normalized = newValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let value = openRouterReasoningModes.contains(normalized) ? normalized : nil
                switch side {
                case .a: viewModel.settings.dualOpenRouterReasoningModeA = value
                case .b: viewModel.settings.dualOpenRouterReasoningModeB = value
                }
            }
        )
    }

    private var openRouterThinkingEnabledBinding: Binding<Bool> {
        switch side {
        case .a:
            Binding(
                get: {
                    openRouterReasoningCapabilities?.mandatory == true ||
                        (viewModel.settings.dualOpenRouterThinkingEnabledA ?? viewModel.settings.openRouterThinkingEnabled)
                },
                set: {
                    viewModel.settings.dualOpenRouterThinkingEnabledA =
                        openRouterReasoningCapabilities?.mandatory == true ? true : $0
                }
            )
        case .b:
            Binding(
                get: {
                    openRouterReasoningCapabilities?.mandatory == true ||
                        (viewModel.settings.dualOpenRouterThinkingEnabledB ?? viewModel.settings.openRouterThinkingEnabled)
                },
                set: {
                    viewModel.settings.dualOpenRouterThinkingEnabledB =
                        openRouterReasoningCapabilities?.mandatory == true ? true : $0
                }
            )
        }
    }

    private var openRouterBudgetBinding: Binding<String> {
        Binding(
            get: {
                let value: Int? = switch side {
                case .a: viewModel.settings.dualOpenRouterThinkingBudgetA
                case .b: viewModel.settings.dualOpenRouterThinkingBudgetB
                }
                return value.map(String.init) ?? ""
            },
            set: { value in
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    switch side {
                    case .a: viewModel.settings.dualOpenRouterThinkingBudgetA = nil
                    case .b: viewModel.settings.dualOpenRouterThinkingBudgetB = nil
                    }
                } else if let parsed = Int(trimmed) {
                    switch side {
                    case .a: viewModel.settings.dualOpenRouterThinkingBudgetA = max(0, parsed)
                    case .b: viewModel.settings.dualOpenRouterThinkingBudgetB = max(0, parsed)
                    }
                }
            }
        )
    }

    private var openRouterEffortBinding: Binding<String> {
        switch side {
        case .a:
            Binding(
                get: {
                    let effort = viewModel.settings.dualOpenRouterReasoningEffortA?
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .lowercased() ?? ""
                    return openRouterReasoningEfforts.contains(effort) ? effort : ""
                },
                set: {
                    let effort = $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    viewModel.settings.dualOpenRouterReasoningEffortA =
                        openRouterReasoningEfforts.contains(effort) ? effort : nil
                }
            )
        case .b:
            Binding(
                get: {
                    let effort = viewModel.settings.dualOpenRouterReasoningEffortB?
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .lowercased() ?? ""
                    return openRouterReasoningEfforts.contains(effort) ? effort : ""
                },
                set: {
                    let effort = $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    viewModel.settings.dualOpenRouterReasoningEffortB =
                        openRouterReasoningEfforts.contains(effort) ? effort : nil
                }
            )
        }
    }

    private var openRouterExcludeBinding: Binding<Bool> {
        switch side {
        case .a:
            Binding(
                get: { viewModel.settings.dualOpenRouterReasoningExcludeA ?? viewModel.settings.openRouterReasoningExclude },
                set: { viewModel.settings.dualOpenRouterReasoningExcludeA = $0 }
            )
        case .b:
            Binding(
                get: { viewModel.settings.dualOpenRouterReasoningExcludeB ?? viewModel.settings.openRouterReasoningExclude },
                set: { viewModel.settings.dualOpenRouterReasoningExcludeB = $0 }
            )
        }
    }

    private func resetOverrides() {
        if let providerID = modelsDevProviderID {
            viewModel.saveModelsDevReasoningEffort(providerID: providerID, modelID: model, effort: "")
        }
        switch side {
        case .a:
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
        case .b:
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
}

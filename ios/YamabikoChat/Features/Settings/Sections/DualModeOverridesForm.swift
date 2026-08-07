import SwiftUI

enum DualModelSide {
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

            Button(side == .a ? L10n.text("A override をリセット") : L10n.text("B override をリセット")) {
                resetOverrides()
            }
            .buttonStyle(.bordered)
        }
    }

    @ViewBuilder
    private var providerSpecificControls: some View {
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

    @ViewBuilder
    private var geminiControls: some View {
        Toggle(L10n.format("%@: Google Search", prefix), isOn: googleSearchBinding)
        Toggle(L10n.format("%@: Code Execution", prefix), isOn: codeExecutionBinding)
        Toggle(L10n.format("%@: URL Context", prefix), isOn: urlContextBinding)
        Toggle(L10n.format("%@: Google Maps", prefix), isOn: googleMapsBinding)
        Toggle(L10n.format("%@: Computer Use", prefix), isOn: computerUseBinding)
        Toggle(L10n.format("%@: Thinking enabled", prefix), isOn: thinkingEnabledBinding)
        if GeminiModelUtils.isThinkingLevelSupported(model: model) {
            TextField(L10n.format("%@: Thinking level override", prefix), text: thinkingLevelBinding)
        } else {
            TextField(L10n.format("%@: Thinking budget override", prefix), text: thinkingBudgetBinding)
                .keyboardType(.numberPad)
        }
    }

    @ViewBuilder
    private var openRouterControls: some View {
        if let capabilities = openRouterReasoningCapabilities {
            Picker(L10n.format("%@: OpenRouter reasoning mode", prefix), selection: openRouterReasoningModeBinding) {
                Text(L10n.text("inherit")).tag("inherit")
                ForEach(openRouterReasoningModes, id: \.self) { mode in
                    Text(verbatim: mode).tag(mode)
                }
            }
            Toggle(L10n.format("%@: OpenRouter thinking enabled", prefix), isOn: openRouterThinkingEnabledBinding)
                .disabled(capabilities.mandatory)
            if capabilities.supportsMaxTokens {
                TextField(L10n.format("%@: OpenRouter budget override", prefix), text: openRouterBudgetBinding)
                    .keyboardType(.numberPad)
            }
            if !openRouterReasoningEfforts.isEmpty {
                Picker(L10n.format("%@: OpenRouter effort override", prefix), selection: openRouterEffortBinding) {
                    Text(L10n.text("inherit")).tag("")
                    ForEach(openRouterReasoningEfforts, id: \.self) { effort in
                        Text(verbatim: effort).tag(effort)
                    }
                }
            }
            Toggle(L10n.format("%@: Exclude reasoning", prefix), isOn: openRouterExcludeBinding)
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
        let enabledLabel = provider == "SUPERGROK"
            ? L10n.format("%@: Reasoning enabled", prefix)
            : L10n.format("%@: Codex reasoning enabled", prefix)
        let effortLabel = provider == "SUPERGROK"
            ? L10n.format("%@: Reasoning effort override", prefix)
            : L10n.format("%@: Codex reasoning effort override", prefix)
        Toggle(enabledLabel, isOn: thinkingEnabledBinding)
        if provider == "SUPERGROK" {
            Picker(effortLabel, selection: codexReasoningEffortBinding) {
                Text(L10n.text("inherit")).tag("")
                ForEach(["low", "medium", "high"], id: \.self) { effort in
                    Text(effort).tag(effort)
                }
            }
        } else {
            TextField(effortLabel, text: codexReasoningEffortBinding)
        }
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

    private var computerUseBinding: Binding<Bool> {
        switch side {
        case .a:
            Binding(
                get: { viewModel.settings.dualComputerUseEnabledA ?? viewModel.settings.geminiComputerUseEnabled },
                set: { viewModel.settings.dualComputerUseEnabledA = $0 }
            )
        case .b:
            Binding(
                get: { viewModel.settings.dualComputerUseEnabledB ?? viewModel.settings.geminiComputerUseEnabled },
                set: { viewModel.settings.dualComputerUseEnabledB = $0 }
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
                get: { viewModel.settings.dualThinkingLevelA ?? "" },
                set: { viewModel.settings.dualThinkingLevelA = SettingsStringHelpers.nilIfBlank($0) }
            )
        case .b:
            Binding(
                get: { viewModel.settings.dualThinkingLevelB ?? "" },
                set: { viewModel.settings.dualThinkingLevelB = SettingsStringHelpers.nilIfBlank($0) }
            )
        }
    }

    private var codexReasoningEffortBinding: Binding<String> {
        switch side {
        case .a:
            Binding(
                get: { viewModel.settings.dualCodexReasoningEffortA ?? "" },
                set: { viewModel.settings.dualCodexReasoningEffortA = SettingsStringHelpers.nilIfBlank($0) }
            )
        case .b:
            Binding(
                get: { viewModel.settings.dualCodexReasoningEffortB ?? "" },
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

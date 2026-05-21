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

    var body: some View {
        Group {
            Toggle(L10n.format("%@: Google Search", prefix), isOn: googleSearchBinding)
            Toggle(L10n.format("%@: Code Execution", prefix), isOn: codeExecutionBinding)
            Toggle(L10n.format("%@: URL Context", prefix), isOn: urlContextBinding)
            Toggle(L10n.format("%@: Google Maps", prefix), isOn: googleMapsBinding)
            Toggle(L10n.format("%@: Computer Use", prefix), isOn: computerUseBinding)
            Toggle(L10n.format("%@: Thinking enabled", prefix), isOn: thinkingEnabledBinding)
            TextField(L10n.format("%@: Thinking budget override", prefix), text: thinkingBudgetBinding)
                .keyboardType(.numberPad)
            TextField(L10n.format("%@: Thinking level override", prefix), text: thinkingLevelBinding)
            TextField(L10n.format("%@: Codex reasoning effort override", prefix), text: codexReasoningEffortBinding)

            if provider == "OPENROUTER" {
                Picker(L10n.format("%@: OpenRouter reasoning mode", prefix), selection: openRouterReasoningModeBinding) {
                    Text(L10n.text("inherit")).tag("inherit")
                    Text(L10n.text("auto")).tag("auto")
                    Text(L10n.text("effort")).tag("effort")
                    Text(L10n.text("budget")).tag("budget")
                }
                Toggle(L10n.format("%@: OpenRouter thinking enabled", prefix), isOn: openRouterThinkingEnabledBinding)
                TextField(L10n.format("%@: OpenRouter budget override", prefix), text: openRouterBudgetBinding)
                    .keyboardType(.numberPad)
                TextField(L10n.format("%@: OpenRouter effort override", prefix), text: openRouterEffortBinding)
                Toggle(L10n.format("%@: Exclude reasoning", prefix), isOn: openRouterExcludeBinding)
            }

            Button(side == .a ? L10n.text("A override をリセット") : L10n.text("B override をリセット")) {
                resetOverrides()
            }
            .buttonStyle(.bordered)
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
                get: { viewModel.settings.dualThinkingEnabledA ?? viewModel.settings.geminiThinkingEnabled },
                set: { viewModel.settings.dualThinkingEnabledA = $0 }
            )
        case .b:
            Binding(
                get: { viewModel.settings.dualThinkingEnabledB ?? viewModel.settings.geminiThinkingEnabled },
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
                switch side {
                case .a: viewModel.settings.dualOpenRouterReasoningModeA ?? "inherit"
                case .b: viewModel.settings.dualOpenRouterReasoningModeB ?? "inherit"
                }
            },
            set: { newValue in
                let normalized = (newValue == "inherit") ? nil : newValue
                switch side {
                case .a: viewModel.settings.dualOpenRouterReasoningModeA = normalized
                case .b: viewModel.settings.dualOpenRouterReasoningModeB = normalized
                }
            }
        )
    }

    private var openRouterThinkingEnabledBinding: Binding<Bool> {
        switch side {
        case .a:
            Binding(
                get: { viewModel.settings.dualOpenRouterThinkingEnabledA ?? viewModel.settings.openRouterThinkingEnabled },
                set: { viewModel.settings.dualOpenRouterThinkingEnabledA = $0 }
            )
        case .b:
            Binding(
                get: { viewModel.settings.dualOpenRouterThinkingEnabledB ?? viewModel.settings.openRouterThinkingEnabled },
                set: { viewModel.settings.dualOpenRouterThinkingEnabledB = $0 }
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
                get: { viewModel.settings.dualOpenRouterReasoningEffortA ?? "" },
                set: { viewModel.settings.dualOpenRouterReasoningEffortA = SettingsStringHelpers.nilIfBlank($0) }
            )
        case .b:
            Binding(
                get: { viewModel.settings.dualOpenRouterReasoningEffortB ?? "" },
                set: { viewModel.settings.dualOpenRouterReasoningEffortB = SettingsStringHelpers.nilIfBlank($0) }
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

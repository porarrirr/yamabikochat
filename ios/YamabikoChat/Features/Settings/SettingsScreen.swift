import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct SettingsScreen: View {
    @EnvironmentObject private var container: AppContainer
    @Environment(\.dismiss) private var dismiss

    @ObservedObject var viewModel: SettingsViewModel
    @State private var selectedTab: SettingsTab = .api
    @State private var showDiagnosticsSheet = false
    @State private var showGeminiOAuthConfigImporter = false

    enum SettingsTab: String, CaseIterable, Identifiable {
        case api
        case systemPrompt
        case dual
        case auto
        case appearance

        var id: String { rawValue }

        var titleKey: String {
            switch self {
            case .api:
                return "API設定"
            case .systemPrompt:
                return "システムプロンプト"
            case .dual:
                return "デュアル"
            case .auto:
                return "自動会話"
            case .appearance:
                return "外観/診断"
            }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Settings tab", selection: $selectedTab) {
                    ForEach(SettingsTab.allCases) { tab in
                        Text(LocalizedStringKey(tab.titleKey)).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding([.horizontal, .top], 12)

                Form {
                    switch selectedTab {
                    case .api:
                        apiTabContent
                    case .systemPrompt:
                        systemPromptTabContent
                    case .dual:
                        dualTabContent
                    case .auto:
                        autoTabContent
                    case .appearance:
                        appearanceTabContent
                    }
                }
            }
            .navigationTitle("設定")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("閉じる") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") { viewModel.saveSettings() }
                }
            }
            .overlay(alignment: .bottom) {
                VStack(spacing: 4) {
                    if let status = viewModel.statusMessage {
                        Text(status)
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                    if let error = viewModel.errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                .padding(.bottom, 8)
            }
            .task {
                viewModel.bind(repository: container.chatRepository, credentialStore: container.credentialStore)
            }
            .fileImporter(
                isPresented: $showGeminiOAuthConfigImporter,
                allowedContentTypes: [.item],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case let .success(urls):
                    guard let url = urls.first else { return }
                    let secured = url.startAccessingSecurityScopedResource()
                    defer {
                        if secured {
                            url.stopAccessingSecurityScopedResource()
                        }
                    }
                    viewModel.importGeminiOAuthClientConfig(fileURL: url)
                case let .failure(error):
                    viewModel.errorMessage = error.localizedDescription
                }
            }
        }
    }

    private var apiTabContent: some View {
        Group {
            Section("API / モデル") {
                Picker("API Provider", selection: Binding(
                    get: { viewModel.settings.apiProvider.uppercased() },
                    set: { value in viewModel.setProvider(value.uppercased()) }
                )) {
                    ForEach(ProviderCatalog.options) { provider in
                        Text(provider.title).tag(provider.key)
                    }
                }

                providerModelEditor

                Toggle("ストリーミングを有効化", isOn: Binding(
                    get: { viewModel.settings.isStreamingEnabled },
                    set: { viewModel.settings.isStreamingEnabled = $0 }
                ))

                Toggle("チャットのプリセットにグローバル設定を表示", isOn: Binding(
                    get: {
                        viewModel.settings.shouldShowGlobalProviderPresetInChat(
                            provider: viewModel.settings.apiProvider
                        )
                    },
                    set: { isVisible in
                        viewModel.settings.setShowGlobalProviderPresetInChat(
                            provider: viewModel.settings.apiProvider,
                            visible: isVisible
                        )
                    }
                ))
                Text(L10n.format(
                    "現在のプロバイダー（%@）のグローバル設定をチャットプリセットに追加します。",
                    ProviderCatalog.displayName(for: viewModel.settings.apiProvider)
                ))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if currentProviderKey != "CODEX_AUTH" && currentProviderKey != "GEMINI_AUTH" {
                Section("APIキー") {
                    SecureField(currentProviderAPIKeyLabel, text: $viewModel.apiKeyDraft)
                    Button("Save API key") {
                        viewModel.saveAPIKey()
                    }
                    .buttonStyle(.bordered)
                }
            }

            if currentProviderKey == "OPENAI_COMPAT" {
                openAICompatSection
            }
            if currentProviderKey == "OPENROUTER" {
                openRouterSection
            }
            if currentProviderKey == "OPENAI" {
                openAIEndpointSection
            }
            if currentProviderKey == "MINIMAX" {
                miniMaxEndpointSection
            }
            codexProviderSettingsSection
            geminiProviderSettingsSection
            if currentProviderKey == "CODEX_AUTH" {
                codexAuthSection
            }
            if currentProviderKey == "GEMINI_AUTH" {
                geminiAuthSection
            }
        }
    }

    private var systemPromptTabContent: some View {
        Group {
            systemPromptPresetSection

            Section("システムプロンプト") {
                TextField("System prompt", text: Binding(
                    get: { viewModel.settings.systemPrompt ?? "" },
                    set: { viewModel.settings.systemPrompt = $0.nilIfBlank }
                ), axis: .vertical)
                .lineLimit(4 ... 12)
            }
        }
    }

    private var dualTabContent: some View {
        Group {
            dualSection
        }
    }

    private var autoTabContent: some View {
        Group {
            autoSection

            Section("数式") {
                Toggle("数式レンダリング", isOn: Binding(
                    get: { viewModel.settings.mathRenderingEnabled },
                    set: { viewModel.settings.mathRenderingEnabled = $0 }
                ))
            }
        }
    }

    private var appearanceTabContent: some View {
        Group {
            Section("外観") {
                Toggle("システムカラーを使用 (iOS)", isOn: Binding(
                    get: { viewModel.settings.dynamicColorEnabled },
                    set: { viewModel.settings.dynamicColorEnabled = $0 }
                ))

                Picker("表示モード", selection: Binding(
                    get: {
                        let normalized = viewModel.settings.themeMode.uppercased()
                        return ["SYSTEM", "LIGHT", "DARK"].contains(normalized) ? normalized : "SYSTEM"
                    },
                    set: { viewModel.settings.themeMode = $0.uppercased() }
                )) {
                    ForEach(themeModeOptions) { option in
                        Text(option.title).tag(option.key)
                    }
                }
                .pickerStyle(.segmented)

                if !viewModel.settings.dynamicColorEnabled {
                    Picker("アクセントカラー", selection: Binding(
                        get: {
                            let normalized = viewModel.settings.themeColor.uppercased()
                            return themeColorOptions.contains(where: { $0.key == normalized })
                                ? normalized
                                : "BLUE_PURPLE"
                        },
                        set: { viewModel.settings.themeColor = $0.uppercased() }
                    )) {
                        ForEach(themeColorOptions) { option in
                            Text(option.title).tag(option.key)
                        }
                    }
                }

                Text("iOSでは表示モード（自動/ライト/ダーク）とアクセントカラーを反映します。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            diagnosticsSection
        }
    }

    private var openAICompatSection: some View {
        Section("OpenAI (Custom) Presets") {
            TextField("Preset name", text: $viewModel.openAICompatPresetNameInput)
            TextField("Preset Base URL", text: $viewModel.openAICompatPresetBaseURLInput)
            Button("プリセット追加/更新") {
                viewModel.addOrUpdateOpenAICompatPreset()
            }
            .buttonStyle(.bordered)

            if !viewModel.openAICompatPresets.isEmpty {
                Picker("Selected preset", selection: Binding(
                    get: { viewModel.settings.selectedOpenAICompatPreset ?? "" },
                    set: { newValue in
                        viewModel.settings.selectedOpenAICompatPreset = newValue.nilIfBlank
                        viewModel.loadSelectedOpenAICompatApiKey()
                    }
                )) {
                    Text("-").tag("")
                    ForEach(viewModel.openAICompatPresets) { preset in
                        Text(preset.name).tag(preset.name)
                    }
                }

                SecureField("Selected preset API key", text: $viewModel.openAICompatApiKeyInput)
                Button("選択プリセットのAPIキー保存") {
                    viewModel.saveSelectedOpenAICompatApiKey()
                }
                .buttonStyle(.bordered)

                ForEach(viewModel.openAICompatPresets) { preset in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(preset.name)
                                .font(.caption)
                            Text(preset.baseURL)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(role: .destructive) {
                            viewModel.removeOpenAICompatPreset(name: preset.name)
                        } label: {
                            Image(systemName: "trash")
                        }
                    }
                }
            }
        }
    }

    private var openRouterSection: some View {
        Section("OpenRouterモデル / ルーティング") {
            if currentProviderKey != "OPENROUTER" {
                Text("OpenRouterを利用する場合に設定します。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            TextField("モデル検索", text: $viewModel.modelSearchQuery)

            HStack {
                Button("取得") {
                    Task { await viewModel.refreshOpenRouterModels(force: false) }
                }
                .buttonStyle(.bordered)

                Button("強制更新") {
                    Task { await viewModel.refreshOpenRouterModels(force: true) }
                }
                .buttonStyle(.bordered)
            }

            if viewModel.openRouterModelsLoading {
                ProgressView("読み込み中...")
            }

            if let err = viewModel.openRouterModelsError, !err.isEmpty {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            ForEach(viewModel.filteredOpenRouterModels.prefix(30)) { model in
                Button {
                    viewModel.setDefaultModel(model.id)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(model.name)
                                .font(.subheadline)
                            if model.id == viewModel.settings.defaultModel {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            }
                        }
                        Text(model.id)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Divider()

            Text("Thinking / Reasoning Tokens")
                .font(.subheadline)
                .fontWeight(.semibold)

            Toggle("Thinking", isOn: Binding(
                get: { viewModel.settings.openRouterThinkingEnabled },
                set: { viewModel.settings.openRouterThinkingEnabled = $0 }
            ))

            Picker("Reasoning mode", selection: Binding(
                get: {
                    let mode = viewModel.settings.openRouterReasoningMode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    return ["auto", "effort", "budget"].contains(mode) ? mode : "auto"
                },
                set: { value in
                    let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    viewModel.settings.openRouterReasoningMode = ["auto", "effort", "budget"].contains(normalized) ? normalized : "auto"
                    if viewModel.settings.openRouterReasoningMode == "effort" &&
                        viewModel.settings.openRouterReasoningEffort.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        viewModel.settings.openRouterReasoningEffort = "medium"
                    }
                }
            )) {
                Text("auto").tag("auto")
                Text("effort").tag("effort")
                Text("budget").tag("budget")
            }
            .pickerStyle(.segmented)
            .disabled(!viewModel.settings.openRouterThinkingEnabled)

            if viewModel.settings.openRouterReasoningMode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "effort" {
                Picker("Effort", selection: Binding(
                    get: {
                        let effort = viewModel.settings.openRouterReasoningEffort.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                        return ["low", "medium", "high"].contains(effort) ? effort : "medium"
                    },
                    set: { value in
                        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                        viewModel.settings.openRouterReasoningEffort = ["low", "medium", "high"].contains(normalized) ? normalized : "medium"
                    }
                )) {
                    Text("low").tag("low")
                    Text("medium").tag("medium")
                    Text("high").tag("high")
                }
                .disabled(!viewModel.settings.openRouterThinkingEnabled)
            }

            if viewModel.settings.openRouterReasoningMode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "budget" {
                TextField("Max reasoning tokens (0=auto)", text: Binding(
                    get: { String(max(0, viewModel.settings.openRouterThinkingBudget)) },
                    set: { value in
                        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                        if trimmed.isEmpty {
                            viewModel.settings.openRouterThinkingBudget = 0
                        } else if let intValue = Int(trimmed) {
                            viewModel.settings.openRouterThinkingBudget = max(0, intValue)
                        }
                    }
                ))
                .keyboardType(.numberPad)
                .disabled(!viewModel.settings.openRouterThinkingEnabled)
            }

            Toggle("Exclude reasoning from response", isOn: Binding(
                get: { viewModel.settings.openRouterReasoningExclude },
                set: { viewModel.settings.openRouterReasoningExclude = $0 }
            ))
            .disabled(!viewModel.settings.openRouterThinkingEnabled)

            Text("Reasoning tokens are billed as output tokens. Unsupported parameters may be ignored.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Divider()

            Text("高度なプロバイダー設定")
                .font(.subheadline)
                .fontWeight(.semibold)

            Picker("provider.sort", selection: Binding(
                get: {
                    let value = viewModel.settings.providerSort.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    return ["price", "throughput", "latency"].contains(value) ? value : "price"
                },
                set: {
                    let normalized = $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    viewModel.settings.providerSort = ["price", "throughput", "latency"].contains(normalized) ? normalized : "price"
                }
            )) {
                Text("price").tag("price")
                Text("throughput").tag("throughput")
                Text("latency").tag("latency")
            }

            Picker("provider selection max", selection: Binding(
                get: { viewModel.settings.providerSelectionMax },
                set: {
                    viewModel.settings.providerSelectionMax = $0
                    trimPreferredProvidersToSelectionMax()
                }
            )) {
                Text("無制限").tag(0)
                Text("3").tag(3)
                Text("5").tag(5)
                Text("10").tag(10)
                Text("12").tag(12)
                Text("20").tag(20)
                Text("30").tag(30)
            }

            if openRouterProviderOptions.isEmpty {
                Text("このモデルで選択可能なプロバイダー情報は未取得です。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("Preferred providers (\(viewModel.settings.preferredProvidersList().count))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                ForEach(openRouterProviderOptions, id: \.self) { provider in
                    Toggle(provider, isOn: preferredProviderBinding(provider))
                }
            }

            if openRouterQuantizationOptions.isEmpty {
                Text("選択可能なQuantization情報は未取得です。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("Quantizations (\(viewModel.settings.selectedQuantizationsList().count))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                ForEach(openRouterQuantizationOptions, id: \.self) { quantization in
                    Toggle(quantization, isOn: quantizationBinding(quantization))
                }
            }

            TextField("Max price (USD / 1M tokens, 0=unlimited)", text: Binding(
                get: {
                    let value = viewModel.settings.maxPricePerMillionTokens
                    return value <= 0 ? "" : String(value)
                },
                set: { value in
                    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.isEmpty {
                        viewModel.settings.maxPricePerMillionTokens = 0
                    } else if let doubleValue = Double(trimmed) {
                        viewModel.settings.maxPricePerMillionTokens = max(0, doubleValue)
                    }
                }
            ))
            .keyboardType(.decimalPad)

            Toggle("Allow fallbacks", isOn: Binding(
                get: { viewModel.settings.allowFallbacks },
                set: { viewModel.settings.allowFallbacks = $0 }
            ))
            Toggle("Require parameters", isOn: Binding(
                get: { viewModel.settings.requireParameters },
                set: { viewModel.settings.requireParameters = $0 }
            ))

            Text("`provider` payload is sent only for OpenRouter requests.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var openAIEndpointSection: some View {
        Section("OpenAI Endpoint") {
            TextField("OpenAI Base URL", text: Binding(
                get: { viewModel.settings.openAIBaseURL },
                set: { viewModel.settings.openAIBaseURL = $0 }
            ))
        }
    }

    private var miniMaxEndpointSection: some View {
        Section("MiniMax Endpoint") {
            HStack {
                Button("Global") {
                    viewModel.settings.miniMaxBaseURL = AppConstants.defaultMiniMaxBaseURL.absoluteString
                }
                .buttonStyle(.bordered)

                Button("China") {
                    viewModel.settings.miniMaxBaseURL = "https://api.minimaxi.com/v1/"
                }
                .buttonStyle(.bordered)
            }

            TextField("MiniMax Base URL", text: Binding(
                get: { viewModel.settings.miniMaxBaseURL },
                set: { viewModel.settings.miniMaxBaseURL = $0 }
            ))
        }
    }

    private var codexProviderSettingsSection: some View {
        Group {
            if currentProviderKey == "CODEX_AUTH" {
                Section("Codex Settings") {
                    Picker("User-Agent Preset", selection: Binding(
                        get: { viewModel.settings.codexUserAgentPreset.ifBlank(CodexUserAgentPresetCatalog.presetAndroid) },
                        set: { viewModel.settings.codexUserAgentPreset = $0 }
                    )) {
                        ForEach(CodexUserAgentPresetCatalog.options) { option in
                            Text(option.title).tag(option.key)
                        }
                    }

                    Toggle("Reasoning", isOn: Binding(
                        get: { viewModel.settings.codexReasoningEnabled },
                        set: { viewModel.settings.codexReasoningEnabled = $0 }
                    ))

                    Picker("Reasoning Effort", selection: Binding(
                        get: { viewModel.settings.codexReasoningEffort.ifBlank("medium") },
                        set: { viewModel.settings.codexReasoningEffort = $0 }
                    )) {
                        ForEach(codexReasoningEffortOptions, id: \.effort) { option in
                            Text(option.effort).tag(option.effort)
                        }
                    }
                    .disabled(!viewModel.settings.codexReasoningEnabled)

                    Toggle("Prompt Cache", isOn: Binding(
                        get: { viewModel.settings.codexPromptCacheEnabled },
                        set: { viewModel.settings.codexPromptCacheEnabled = $0 }
                    ))
                    if viewModel.settings.codexPromptCacheEnabled {
                        TextField("Cache min length", text: Binding(
                            get: { String(viewModel.settings.codexPromptCacheMinLength) },
                            set: { value in
                                if let intValue = Int(value) {
                                    viewModel.settings.codexPromptCacheMinLength = max(0, intValue)
                                }
                            }
                        ))
                        Picker("Cache Type", selection: Binding(
                            get: { viewModel.settings.codexPromptCacheType.ifBlank("ephemeral") },
                            set: { viewModel.settings.codexPromptCacheType = $0 }
                        )) {
                            Text("ephemeral").tag("ephemeral")
                            Text("persistent").tag("persistent")
                        }
                    }

                    Picker("Reasoning Summary", selection: Binding(
                        get: { viewModel.settings.codexReasoningSummary.ifBlank("auto") },
                        set: { viewModel.settings.codexReasoningSummary = $0 }
                    )) {
                        Text("auto").tag("auto")
                        Text("concise").tag("concise")
                        Text("detailed").tag("detailed")
                        Text("none").tag("none")
                    }
                    .disabled(!viewModel.settings.codexReasoningEnabled)

                    Toggle("Show Reasoning Summary", isOn: Binding(
                        get: { viewModel.settings.codexShowReasoningSummary },
                        set: { viewModel.settings.codexShowReasoningSummary = $0 }
                    ))
                    .disabled(!viewModel.settings.codexReasoningEnabled)

                    Toggle("Assume model supports summaries", isOn: Binding(
                        get: { viewModel.settings.codexSupportsReasoningSummaries },
                        set: { viewModel.settings.codexSupportsReasoningSummaries = $0 }
                    ))

                    Picker("Verbosity", selection: Binding(
                        get: { viewModel.settings.codexVerbosity.ifBlank("medium") },
                        set: { viewModel.settings.codexVerbosity = $0 }
                    )) {
                        Text("low").tag("low")
                        Text("medium").tag("medium")
                        Text("high").tag("high")
                    }

                    Toggle("Web Search (Codex)", isOn: Binding(
                        get: { viewModel.settings.codexWebSearchEnabled },
                        set: { viewModel.settings.codexWebSearchEnabled = $0 }
                    ))
                    if viewModel.settings.codexWebSearchEnabled {
                        Picker("Search Context Size", selection: Binding(
                            get: { viewModel.settings.codexWebSearchContextSize.ifBlank("medium") },
                            set: { viewModel.settings.codexWebSearchContextSize = $0 }
                        )) {
                            Text("low").tag("low")
                            Text("medium").tag("medium")
                            Text("high").tag("high")
                        }
                    }
                }
            }
        }
    }

    private var geminiProviderSettingsSection: some View {
        Group {
            if isGeminiProvider {
                Section("Gemini Thinking") {
                    let model = viewModel.settings.defaultModel
                    let supportsThinking = GeminiModelUtils.isThinkingSupported(model: model)
                    let supportsLevel = GeminiModelUtils.isThinkingLevelSupported(model: model)
                    let alwaysOn = GeminiModelUtils.isThinkingAlwaysOn(model: model)

                    Toggle("Thinking", isOn: Binding(
                        get: { viewModel.settings.geminiThinkingEnabled },
                        set: { viewModel.settings.geminiThinkingEnabled = $0 }
                    ))
                    .disabled(alwaysOn || !supportsThinking)

                    if supportsLevel {
                        Picker("Thinking Level", selection: Binding(
                            get: {
                                GeminiModelUtils.normalizeThinkingLevel(
                                    model: model,
                                    level: viewModel.settings.geminiThinkingLevel
                                ) ?? GeminiModelUtils.getDefaultThinkingLevel(model: model)
                            },
                            set: { viewModel.settings.geminiThinkingLevel = $0 }
                        )) {
                            ForEach(GeminiModelUtils.getThinkingLevelOptions(model: model), id: \.self) { option in
                                Text(option).tag(option)
                            }
                        }
                    } else {
                        TextField("Thinking Budget", text: Binding(
                            get: { String(max(0, viewModel.settings.geminiThinkingBudget)) },
                            set: { value in
                                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                                if trimmed.isEmpty {
                                    viewModel.settings.geminiThinkingBudget = 0
                                } else if let intValue = Int(trimmed) {
                                    viewModel.settings.geminiThinkingBudget = max(0, intValue)
                                }
                            }
                        ))
                        .disabled(!supportsThinking)
                    }

                    Text(GeminiModelUtils.getThinkingDescription(model: model))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Section("Gemini Tools") {
                    Toggle("Google Search", isOn: Binding(
                        get: { viewModel.settings.geminiGoogleSearchEnabled },
                        set: { viewModel.settings.geminiGoogleSearchEnabled = $0 }
                    ))
                    Toggle("URL Context", isOn: Binding(
                        get: { viewModel.settings.geminiURLContextEnabled },
                        set: { viewModel.settings.geminiURLContextEnabled = $0 }
                    ))
                    Toggle("Code Execution", isOn: Binding(
                        get: { viewModel.settings.geminiCodeExecutionEnabled },
                        set: { viewModel.settings.geminiCodeExecutionEnabled = $0 }
                    ))
                    Toggle("Google Maps", isOn: Binding(
                        get: { viewModel.settings.geminiGoogleMapsEnabled },
                        set: { viewModel.settings.geminiGoogleMapsEnabled = $0 }
                    ))
                    Toggle("Computer Use", isOn: Binding(
                        get: { viewModel.settings.geminiComputerUseEnabled },
                        set: { viewModel.settings.geminiComputerUseEnabled = $0 }
                    ))
                }

                Section("Gemini Advanced (JSON)") {
                    TextField("Response MIME Type", text: Binding(
                        get: { viewModel.settings.geminiResponseMimeType },
                        set: { viewModel.settings.geminiResponseMimeType = $0 }
                    ))
                    TextField("Response JSON Schema", text: Binding(
                        get: { viewModel.settings.geminiResponseJSONSchema },
                        set: { viewModel.settings.geminiResponseJSONSchema = $0 }
                    ), axis: .vertical)
                    .lineLimit(4 ... 10)

                    TextField("Function Declarations (JSON Array)", text: Binding(
                        get: { viewModel.settings.geminiFunctionDeclarations },
                        set: { viewModel.settings.geminiFunctionDeclarations = $0 }
                    ), axis: .vertical)
                    .lineLimit(4 ... 10)

                    Text("空欄は送信されません。JSONが不正な場合は無視されます。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var codexAuthSection: some View {
        Section("Codex Auth") {
            Text(codexSummary)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Button("Sign in") {
                    Task { await viewModel.loginCodexAuth() }
                }
                .buttonStyle(.borderedProminent)

                Button("Refresh") {
                    Task { await viewModel.refreshCodexAuth(force: true) }
                }
                .buttonStyle(.bordered)

                Button("Sign out") {
                    Task { await viewModel.logoutCodexAuth() }
                }
                .buttonStyle(.bordered)
            }
            .disabled(viewModel.isCodexAuthActionRunning)

            if viewModel.isCodexAuthActionRunning {
                ProgressView("Codex認証処理中...")
                    .font(.caption2)
            }

            if !viewModel.codexEmailInput.isEmpty {
                Text("Email: \(viewModel.codexEmailInput)")
                    .font(.caption2)
            }
            if !viewModel.codexPlanTypeInput.isEmpty {
                Text("Plan: \(viewModel.codexPlanTypeInput)")
                    .font(.caption2)
            }
            if !viewModel.codexAccountIdInput.isEmpty {
                Text("Account ID: \(viewModel.codexAccountIdInput)")
                    .font(.caption2)
                    .textSelection(.enabled)
            }
            Text("User-Agent: \(CodexUserAgentPresetCatalog.displayName(for: viewModel.settings.codexUserAgentPreset.ifBlank(CodexUserAgentPresetCatalog.presetAndroid)))")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Button("使用量を取得") {
                Task { await viewModel.retrieveCodexUsage() }
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.isCodexAuthActionRunning)

            if let usage = viewModel.codexUsageStatus {
                Text("plan: \(usage.planType ?? "-")")
                    .font(.caption2)
                if let primary = usage.primaryWindow {
                    Text("primary: \(primary.usedPercent ?? 0, specifier: "%.1f")%")
                        .font(.caption2)
                }
            }
        }
    }

    private var geminiAuthSection: some View {
        Section("Gemini Auth (CLI)") {
            Text(geminiSummary)
                .font(.caption)
                .foregroundStyle(.secondary)

            if !viewModel.isGeminiOAuthConfigured {
                Text("Gemini OAuth client ID/secret が未設定です。GeminiAuthInfo.plist（または Info.plist）を設定するか、下の「設定ファイルを取り込む」を実行してください。")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }

            HStack {
                Button("設定ファイルを取り込む") {
                    showGeminiOAuthConfigImporter = true
                }
                .buttonStyle(.bordered)

                if viewModel.hasImportedGeminiOAuthClientConfig {
                    Button("取り込み設定をクリア") {
                        viewModel.clearImportedGeminiOAuthClientConfig()
                    }
                    .buttonStyle(.bordered)
                }
            }
            .disabled(viewModel.isGeminiAuthActionRunning)

            Text(
                viewModel.hasImportedGeminiOAuthClientConfig
                    ? L10n.text("ファイル取り込み済みのOAuth設定を使用中です。")
                    : L10n.text("FilesからGeminiAuthInfo.plistを選択すると、アプリ内にOAuth設定を保存します。")
            )
            .font(.caption2)
            .foregroundStyle(.secondary)

            TextField("OAuth Client ID", text: $viewModel.geminiOAuthClientIDInput)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            SecureField("OAuth Client Secret", text: $viewModel.geminiOAuthClientSecretInput)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            Button("手動入力を保存") {
                viewModel.saveGeminiOAuthClientConfigManually()
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.isGeminiAuthActionRunning)

            Text("ファイル選択がうまく動作しない場合は、上の入力欄に手動で貼り付けて保存できます。")
                .font(.caption2)
                .foregroundStyle(.secondary)

            HStack {
                Button("Sign in") {
                    Task { await viewModel.loginGeminiAuth() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isGeminiAuthActionRunning || !viewModel.isGeminiOAuthConfigured)

                Button("Refresh") {
                    Task { await viewModel.refreshGeminiAuth(force: true) }
                }
                .buttonStyle(.bordered)

                Button("Sign out") {
                    Task { await viewModel.logoutGeminiAuth() }
                }
                .buttonStyle(.bordered)
            }
            .disabled(viewModel.isGeminiAuthActionRunning)

            if viewModel.isGeminiAuthActionRunning {
                ProgressView("Gemini認証処理中...")
                    .font(.caption2)
            }

            TextField("Project ID", text: $viewModel.geminiProjectIdInput)
            Button("Project ID保存") {
                viewModel.saveGeminiProjectId()
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.isGeminiAuthActionRunning)

            if !viewModel.geminiEmailInput.isEmpty {
                Text("Email: \(viewModel.geminiEmailInput)")
                    .font(.caption2)
            }
            if !viewModel.geminiTierInput.isEmpty {
                Text("Tier: \(viewModel.geminiTierInput)")
                    .font(.caption2)
            }
            if !viewModel.geminiTierNameInput.isEmpty {
                Text("Tier Name: \(viewModel.geminiTierNameInput)")
                    .font(.caption2)
            }

            Button("クォータ取得") {
                Task { await viewModel.retrieveGeminiQuota() }
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.isGeminiAuthActionRunning)

            if let quota = viewModel.geminiUserQuota {
                ForEach(quota.buckets.prefix(5)) { bucket in
                    Text("\(bucket.modelId ?? "-") : \(bucket.remainingAmount ?? "-")")
                        .font(.caption2)
                }
            }
        }
    }

    private var dualSection: some View {
        Section("デュアルモード") {
            Toggle("Enable dual mode", isOn: Binding(
                get: { viewModel.settings.isDualModeEnabled },
                set: { viewModel.setDualModeEnabled($0) }
            ))
            .disabled(viewModel.settings.isAutoConversationEnabled && !viewModel.settings.isDualModeEnabled)

            if viewModel.settings.isAutoConversationEnabled && !viewModel.settings.isDualModeEnabled {
                Text("自動会話が有効な間はデュアルモードをONにできません。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            TextField("Model A", text: Binding(
                get: { viewModel.settings.dualModelA },
                set: { viewModel.settings.dualModelA = $0 }
            ))
            providerPickerRow(
                title: "Provider A",
                selection: Binding(
                    get: { viewModel.settings.dualProviderA.uppercased() },
                    set: { viewModel.settings.dualProviderA = $0.uppercased() }
                )
            )
            TextField("Model B", text: Binding(
                get: { viewModel.settings.dualModelB },
                set: { viewModel.settings.dualModelB = $0 }
            ))
            providerPickerRow(
                title: "Provider B",
                selection: Binding(
                    get: { viewModel.settings.dualProviderB.uppercased() },
                    set: { viewModel.settings.dualProviderB = $0.uppercased() }
                )
            )

            TextField("Dual system prompt A", text: Binding(
                get: { viewModel.settings.dualSystemPromptA ?? "" },
                set: { viewModel.settings.dualSystemPromptA = $0.nilIfBlank }
            ), axis: .vertical)
            .lineLimit(2 ... 8)

            TextField("Dual system prompt B", text: Binding(
                get: { viewModel.settings.dualSystemPromptB ?? "" },
                set: { viewModel.settings.dualSystemPromptB = $0.nilIfBlank }
            ), axis: .vertical)
            .lineLimit(2 ... 8)

            Picker("Split layout", selection: Binding(
                get: {
                    let normalized = viewModel.settings.dualSplitLayout.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                    return normalized == "HORIZONTAL" ? "HORIZONTAL" : "VERTICAL"
                },
                set: { viewModel.settings.dualSplitLayout = $0 }
            )) {
                Text("左右").tag("VERTICAL")
                Text("上下").tag("HORIZONTAL")
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Split ratio: \(Int(viewModel.settings.dualSplitRatio * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Slider(
                    value: Binding(
                        get: { min(max(viewModel.settings.dualSplitRatio, 0.1), 0.9) },
                        set: { viewModel.settings.dualSplitRatio = $0 }
                    ),
                    in: 0.1 ... 0.9
                )
            }

            Divider()
            Text("Dual A Overrides")
                .font(.subheadline)
                .fontWeight(.semibold)

            Toggle("A: Google Search", isOn: Binding(
                get: { viewModel.settings.dualGoogleSearchEnabledA ?? viewModel.settings.geminiGoogleSearchEnabled },
                set: { viewModel.settings.dualGoogleSearchEnabledA = $0 }
            ))
            Toggle("A: Code Execution", isOn: Binding(
                get: { viewModel.settings.dualCodeExecutionEnabledA ?? viewModel.settings.geminiCodeExecutionEnabled },
                set: { viewModel.settings.dualCodeExecutionEnabledA = $0 }
            ))
            Toggle("A: URL Context", isOn: Binding(
                get: { viewModel.settings.dualURLContextEnabledA ?? viewModel.settings.geminiURLContextEnabled },
                set: { viewModel.settings.dualURLContextEnabledA = $0 }
            ))
            Toggle("A: Google Maps", isOn: Binding(
                get: { viewModel.settings.dualGoogleMapsEnabledA ?? viewModel.settings.geminiGoogleMapsEnabled },
                set: { viewModel.settings.dualGoogleMapsEnabledA = $0 }
            ))
            Toggle("A: Computer Use", isOn: Binding(
                get: { viewModel.settings.dualComputerUseEnabledA ?? viewModel.settings.geminiComputerUseEnabled },
                set: { viewModel.settings.dualComputerUseEnabledA = $0 }
            ))
            Toggle("A: Thinking enabled", isOn: Binding(
                get: { viewModel.settings.dualThinkingEnabledA ?? viewModel.settings.geminiThinkingEnabled },
                set: { viewModel.settings.dualThinkingEnabledA = $0 }
            ))
            TextField("A: Thinking budget override", text: Binding(
                get: { viewModel.settings.dualThinkingBudgetA.map(String.init) ?? "" },
                set: { value in
                    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.isEmpty {
                        viewModel.settings.dualThinkingBudgetA = nil
                    } else if let parsed = Int(trimmed) {
                        viewModel.settings.dualThinkingBudgetA = max(0, parsed)
                    }
                }
            ))
            .keyboardType(.numberPad)
            TextField("A: Thinking level override", text: Binding(
                get: { viewModel.settings.dualThinkingLevelA ?? "" },
                set: { viewModel.settings.dualThinkingLevelA = $0.nilIfBlank }
            ))
            TextField("A: Codex reasoning effort override", text: Binding(
                get: { viewModel.settings.dualCodexReasoningEffortA ?? "" },
                set: { viewModel.settings.dualCodexReasoningEffortA = $0.nilIfBlank }
            ))

            if viewModel.settings.dualProviderA.uppercased() == "OPENROUTER" {
                Picker("A: OpenRouter reasoning mode", selection: Binding(
                    get: { viewModel.settings.dualOpenRouterReasoningModeA ?? "inherit" },
                    set: { viewModel.settings.dualOpenRouterReasoningModeA = ($0 == "inherit") ? nil : $0 }
                )) {
                    Text("inherit").tag("inherit")
                    Text("auto").tag("auto")
                    Text("effort").tag("effort")
                    Text("budget").tag("budget")
                }

                Toggle("A: OpenRouter thinking enabled", isOn: Binding(
                    get: { viewModel.settings.dualOpenRouterThinkingEnabledA ?? viewModel.settings.openRouterThinkingEnabled },
                    set: { viewModel.settings.dualOpenRouterThinkingEnabledA = $0 }
                ))
                TextField("A: OpenRouter budget override", text: Binding(
                    get: { viewModel.settings.dualOpenRouterThinkingBudgetA.map(String.init) ?? "" },
                    set: { value in
                        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                        if trimmed.isEmpty {
                            viewModel.settings.dualOpenRouterThinkingBudgetA = nil
                        } else if let parsed = Int(trimmed) {
                            viewModel.settings.dualOpenRouterThinkingBudgetA = max(0, parsed)
                        }
                    }
                ))
                .keyboardType(.numberPad)
                TextField("A: OpenRouter effort override", text: Binding(
                    get: { viewModel.settings.dualOpenRouterReasoningEffortA ?? "" },
                    set: { viewModel.settings.dualOpenRouterReasoningEffortA = $0.nilIfBlank }
                ))
                Toggle("A: Exclude reasoning", isOn: Binding(
                    get: { viewModel.settings.dualOpenRouterReasoningExcludeA ?? viewModel.settings.openRouterReasoningExclude },
                    set: { viewModel.settings.dualOpenRouterReasoningExcludeA = $0 }
                ))
            }

            Button("A override をリセット") {
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
            .buttonStyle(.bordered)

            Divider()
            Text("Dual B Overrides")
                .font(.subheadline)
                .fontWeight(.semibold)

            Toggle("B: Google Search", isOn: Binding(
                get: { viewModel.settings.dualGoogleSearchEnabledB ?? viewModel.settings.geminiGoogleSearchEnabled },
                set: { viewModel.settings.dualGoogleSearchEnabledB = $0 }
            ))
            Toggle("B: Code Execution", isOn: Binding(
                get: { viewModel.settings.dualCodeExecutionEnabledB ?? viewModel.settings.geminiCodeExecutionEnabled },
                set: { viewModel.settings.dualCodeExecutionEnabledB = $0 }
            ))
            Toggle("B: URL Context", isOn: Binding(
                get: { viewModel.settings.dualURLContextEnabledB ?? viewModel.settings.geminiURLContextEnabled },
                set: { viewModel.settings.dualURLContextEnabledB = $0 }
            ))
            Toggle("B: Google Maps", isOn: Binding(
                get: { viewModel.settings.dualGoogleMapsEnabledB ?? viewModel.settings.geminiGoogleMapsEnabled },
                set: { viewModel.settings.dualGoogleMapsEnabledB = $0 }
            ))
            Toggle("B: Computer Use", isOn: Binding(
                get: { viewModel.settings.dualComputerUseEnabledB ?? viewModel.settings.geminiComputerUseEnabled },
                set: { viewModel.settings.dualComputerUseEnabledB = $0 }
            ))
            Toggle("B: Thinking enabled", isOn: Binding(
                get: { viewModel.settings.dualThinkingEnabledB ?? viewModel.settings.geminiThinkingEnabled },
                set: { viewModel.settings.dualThinkingEnabledB = $0 }
            ))
            TextField("B: Thinking budget override", text: Binding(
                get: { viewModel.settings.dualThinkingBudgetB.map(String.init) ?? "" },
                set: { value in
                    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.isEmpty {
                        viewModel.settings.dualThinkingBudgetB = nil
                    } else if let parsed = Int(trimmed) {
                        viewModel.settings.dualThinkingBudgetB = max(0, parsed)
                    }
                }
            ))
            .keyboardType(.numberPad)
            TextField("B: Thinking level override", text: Binding(
                get: { viewModel.settings.dualThinkingLevelB ?? "" },
                set: { viewModel.settings.dualThinkingLevelB = $0.nilIfBlank }
            ))
            TextField("B: Codex reasoning effort override", text: Binding(
                get: { viewModel.settings.dualCodexReasoningEffortB ?? "" },
                set: { viewModel.settings.dualCodexReasoningEffortB = $0.nilIfBlank }
            ))

            if viewModel.settings.dualProviderB.uppercased() == "OPENROUTER" {
                Picker("B: OpenRouter reasoning mode", selection: Binding(
                    get: { viewModel.settings.dualOpenRouterReasoningModeB ?? "inherit" },
                    set: { viewModel.settings.dualOpenRouterReasoningModeB = ($0 == "inherit") ? nil : $0 }
                )) {
                    Text("inherit").tag("inherit")
                    Text("auto").tag("auto")
                    Text("effort").tag("effort")
                    Text("budget").tag("budget")
                }

                Toggle("B: OpenRouter thinking enabled", isOn: Binding(
                    get: { viewModel.settings.dualOpenRouterThinkingEnabledB ?? viewModel.settings.openRouterThinkingEnabled },
                    set: { viewModel.settings.dualOpenRouterThinkingEnabledB = $0 }
                ))
                TextField("B: OpenRouter budget override", text: Binding(
                    get: { viewModel.settings.dualOpenRouterThinkingBudgetB.map(String.init) ?? "" },
                    set: { value in
                        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                        if trimmed.isEmpty {
                            viewModel.settings.dualOpenRouterThinkingBudgetB = nil
                        } else if let parsed = Int(trimmed) {
                            viewModel.settings.dualOpenRouterThinkingBudgetB = max(0, parsed)
                        }
                    }
                ))
                .keyboardType(.numberPad)
                TextField("B: OpenRouter effort override", text: Binding(
                    get: { viewModel.settings.dualOpenRouterReasoningEffortB ?? "" },
                    set: { viewModel.settings.dualOpenRouterReasoningEffortB = $0.nilIfBlank }
                ))
                Toggle("B: Exclude reasoning", isOn: Binding(
                    get: { viewModel.settings.dualOpenRouterReasoningExcludeB ?? viewModel.settings.openRouterReasoningExclude },
                    set: { viewModel.settings.dualOpenRouterReasoningExcludeB = $0 }
                ))
            }

            Button("B override をリセット") {
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
            .buttonStyle(.bordered)
        }
    }

    private var autoSection: some View {
        Section("自動会話") {
            Toggle("Enable auto conversation", isOn: Binding(
                get: { viewModel.settings.isAutoConversationEnabled },
                set: { viewModel.setAutoConversationEnabled($0) }
            ))
            .disabled(viewModel.settings.isDualModeEnabled && !viewModel.settings.isAutoConversationEnabled)

            if viewModel.settings.isDualModeEnabled && !viewModel.settings.isAutoConversationEnabled {
                Text("デュアルモードが有効な間は自動会話をONにできません。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            TextField("Auto model A", text: Binding(
                get: { viewModel.settings.autoModelA },
                set: { viewModel.settings.autoModelA = $0 }
            ))
            providerPickerRow(
                title: "Auto provider A",
                selection: Binding(
                    get: { viewModel.settings.autoProviderA.uppercased() },
                    set: { viewModel.settings.autoProviderA = $0.uppercased() }
                )
            )
            TextField("Auto model B", text: Binding(
                get: { viewModel.settings.autoModelB },
                set: { viewModel.settings.autoModelB = $0 }
            ))
            providerPickerRow(
                title: "Auto provider B",
                selection: Binding(
                    get: { viewModel.settings.autoProviderB.uppercased() },
                    set: { viewModel.settings.autoProviderB = $0.uppercased() }
                )
            )
            TextField("Auto system prompt A", text: Binding(
                get: { viewModel.settings.autoSystemPromptA },
                set: { viewModel.settings.autoSystemPromptA = $0 }
            ), axis: .vertical)
            .lineLimit(2 ... 6)
            TextField("Auto system prompt B", text: Binding(
                get: { viewModel.settings.autoSystemPromptB },
                set: { viewModel.settings.autoSystemPromptB = $0 }
            ), axis: .vertical)
            .lineLimit(2 ... 6)
            Stepper(
                viewModel.settings.autoMaxTurns <= 0
                    ? L10n.text("Max turns: Unlimited")
                    : L10n.format("Max turns: %d", viewModel.settings.autoMaxTurns),
                value: Binding(
                    get: { viewModel.settings.autoMaxTurns },
                    set: { viewModel.settings.autoMaxTurns = $0 }
                ),
                in: 0 ... 200
            )
            Text("`0` を指定すると無制限で実行します。")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text("デュアルモードと自動会話は同時に有効化できません。")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func providerPickerRow(title: String, selection: Binding<String>) -> some View {
        Picker(title, selection: selection) {
            ForEach(ProviderCatalog.options) { provider in
                Text(provider.title).tag(provider.key)
            }
        }
    }

    private var currentProviderAPIKeyLabel: String {
        let providerLabel = ProviderCatalog.displayName(for: viewModel.settings.apiProvider)
        return L10n.format("%@ API Key", providerLabel)
    }

    private var codexSummary: String {
        "loggedIn=\(viewModel.codexAuthState.isLoggedIn ? "yes" : "no"), hasApiKey=\(viewModel.codexAuthState.hasApiKey ? "yes" : "no")"
    }

    private var geminiSummary: String {
        "loggedIn=\(viewModel.geminiAuthState.isLoggedIn ? "yes" : "no"), project=\(viewModel.geminiAuthState.projectId ?? "-")"
    }

    private var systemPromptPresetSection: some View {
        Section("System Prompt Preset") {
            Picker("選択中のプリセット", selection: Binding(
                get: { viewModel.settings.selectedSystemPromptPreset ?? "" },
                set: { newValue in
                    viewModel.selectSystemPromptPreset(newValue.nilIfBlank)
                }
            )) {
                Text("Custom").tag("")
                ForEach(viewModel.systemPromptPresets) { preset in
                    Text(preset.name).tag(preset.name)
                }
            }

            TextField("Preset Name", text: $viewModel.systemPromptPresetNameInput)

            HStack {
                Button("Save/Update Preset") {
                    viewModel.addOrUpdateSystemPromptPreset()
                }
                .buttonStyle(.bordered)

                Button("Remove Selected") {
                    viewModel.removeSelectedSystemPromptPreset()
                }
                .buttonStyle(.bordered)
                .disabled((viewModel.settings.selectedSystemPromptPreset ?? "").isEmpty)
            }

            if viewModel.systemPromptPresets.isEmpty {
                Text("プリセットは未登録です。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var providerModelEditor: some View {
        Group {
            if isCodexProvider {
                Picker("Codex Model", selection: Binding(
                    get: { viewModel.settings.defaultModel },
                    set: { value in
                        viewModel.setDefaultModel(value)
                        if let preset = CodexModelCatalog.findPreset(value) {
                            let supported = preset.supportedReasoningEfforts.map(\.effort)
                            if !supported.contains(viewModel.settings.codexReasoningEffort) {
                                viewModel.settings.codexReasoningEffort = preset.defaultReasoningEffort
                            } else if viewModel.settings.codexReasoningEffort.isEmpty {
                                viewModel.settings.codexReasoningEffort = preset.defaultReasoningEffort
                            }
                        }
                    }
                )) {
                    ForEach(CodexModelCatalog.visiblePresets()) { preset in
                        Text(preset.displayName).tag(preset.model)
                    }
                }

                if let preset = CodexModelCatalog.findPreset(viewModel.settings.defaultModel) {
                    Text(preset.description)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                TextField("Custom Model ID", text: Binding(
                    get: { viewModel.settings.defaultModel },
                    set: { viewModel.setDefaultModel($0) }
                ))
            } else if isGeminiProvider {
                Picker("Gemini Model", selection: Binding(
                    get: { viewModel.settings.defaultModel },
                    set: { viewModel.setDefaultModel($0) }
                )) {
                    ForEach(geminiModelOptions, id: \.self) { model in
                        Text(model).tag(model)
                    }
                }

                TextField("Model", text: Binding(
                    get: { viewModel.settings.defaultModel },
                    set: { viewModel.setDefaultModel($0) }
                ))
            } else {
                TextField("Default model", text: Binding(
                    get: { viewModel.settings.defaultModel },
                    set: { viewModel.setDefaultModel($0) }
                ))
            }
        }
    }

    private var diagnosticsSection: some View {
        Section("診断ログ") {
            HStack {
                Button("更新") {
                    viewModel.refreshDiagnosticsLog()
                }
                .buttonStyle(.bordered)

                Button("コピー") {
                    UIPasteboard.general.string = viewModel.diagnosticsLogText
                    viewModel.statusMessage = L10n.text("診断ログをコピーしました")
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.diagnosticsLogText.isEmpty)

                Button("クリア") {
                    viewModel.clearDiagnosticsLog()
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.diagnosticsLogText.isEmpty)

                Button("表示") {
                    showDiagnosticsSheet = true
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.diagnosticsLogText.isEmpty)

                ShareLink(item: viewModel.diagnosticsLogText) {
                    Text("共有")
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.diagnosticsLogText.isEmpty)
            }

            if viewModel.diagnosticsLogText.isEmpty {
                Text("ログはありません。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text(String(viewModel.diagnosticsLogText.suffix(2000)))
                    .font(.caption2)
                    .textSelection(.enabled)
            }
        }
        .sheet(isPresented: $showDiagnosticsSheet) {
            NavigationStack {
                ScrollView {
                    Text(viewModel.diagnosticsLogText)
                        .font(.caption)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
                .navigationTitle("診断ログ")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("閉じる") { showDiagnosticsSheet = false }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("コピー") {
                            UIPasteboard.general.string = viewModel.diagnosticsLogText
                            viewModel.statusMessage = L10n.text("診断ログをコピーしました")
                        }
                    }
                }
            }
        }
    }

    private var currentProviderKey: String {
        viewModel.settings.apiProvider.uppercased()
    }

    private var isGeminiProvider: Bool {
        currentProviderKey == "GEMINI" || currentProviderKey == "GEMINI_AUTH"
    }

    private var isCodexProvider: Bool {
        currentProviderKey == "CODEX_AUTH"
    }

    private var geminiModelOptions: [String] {
        var list = [viewModel.settings.defaultModel] + GeminiModelCatalog.suggestedModels
        var seen: Set<String> = []
        list = list.filter {
            let normalized = $0.lowercased()
            guard !normalized.isEmpty, !seen.contains(normalized) else { return false }
            seen.insert(normalized)
            return true
        }
        return list
    }

    private var codexReasoningEffortOptions: [CodexReasoningEffortPreset] {
        if let preset = CodexModelCatalog.findPreset(viewModel.settings.defaultModel) {
            return preset.supportedReasoningEfforts
        }
        return [
            CodexReasoningEffortPreset(effort: "low", description: ""),
            CodexReasoningEffortPreset(effort: "medium", description: ""),
            CodexReasoningEffortPreset(effort: "high", description: ""),
            CodexReasoningEffortPreset(effort: "xhigh", description: "")
        ]
    }

    private var selectedOpenRouterModel: SimpleModel? {
        viewModel.openRouterModels.first { $0.id == viewModel.settings.defaultModel }
    }

    private var openRouterProviderOptions: [String] {
        let fromModel = selectedOpenRouterModel?.availableProviders ?? []
        let raw = fromModel.isEmpty ? [selectedOpenRouterModel?.provider ?? ""] : fromModel
        var seen: Set<String> = []
        return raw
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
            .sorted()
    }

    private var openRouterQuantizationOptions: [String] {
        let raw = selectedOpenRouterModel?.availableQuantizations ?? []
        var seen: Set<String> = []
        return raw
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
            .sorted()
    }

    private func preferredProviderBinding(_ provider: String) -> Binding<Bool> {
        Binding(
            get: { viewModel.settings.preferredProvidersList().contains(provider.lowercased()) },
            set: { isSelected in
                var selected = viewModel.settings.preferredProvidersList()
                let normalized = provider.lowercased()
                if isSelected {
                    if !selected.contains(normalized) {
                        selected.append(normalized)
                    }
                } else {
                    selected.removeAll { $0 == normalized }
                }
                viewModel.settings.setPreferredProvidersList(selected)
            }
        )
    }

    private func quantizationBinding(_ quantization: String) -> Binding<Bool> {
        Binding(
            get: { viewModel.settings.selectedQuantizationsList().contains(quantization) },
            set: { isSelected in
                var selected = viewModel.settings.selectedQuantizationsList()
                if isSelected {
                    if !selected.contains(quantization) {
                        selected.append(quantization)
                    }
                } else {
                    selected.removeAll { $0 == quantization }
                }
                viewModel.settings.setSelectedQuantizationsList(selected)
            }
        )
    }

    private func trimPreferredProvidersToSelectionMax() {
        let current = viewModel.settings.preferredProvidersList()
        viewModel.settings.setPreferredProvidersList(current)
    }

    private var themeModeOptions: [AppearanceOption] {
        [
            AppearanceOption(key: "SYSTEM", titleKey: "自動"),
            AppearanceOption(key: "LIGHT", titleKey: "ライト"),
            AppearanceOption(key: "DARK", titleKey: "ダーク")
        ]
    }

    private var themeColorOptions: [AppearanceOption] {
        [
            AppearanceOption(key: "BLUE_PURPLE", titleKey: "青紫"),
            AppearanceOption(key: "BLUE", titleKey: "青"),
            AppearanceOption(key: "GREEN", titleKey: "緑"),
            AppearanceOption(key: "YELLOW", titleKey: "黄"),
            AppearanceOption(key: "PINK", titleKey: "ピンク"),
            AppearanceOption(key: "ORANGE", titleKey: "オレンジ"),
            AppearanceOption(key: "BLACK", titleKey: "黒")
        ]
    }
}

private struct AppearanceOption: Identifiable {
    let key: String
    let titleKey: String
    var title: String { L10n.text(titleKey) }

    var id: String { key }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func ifBlank(_ fallback: String) -> String {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }
}

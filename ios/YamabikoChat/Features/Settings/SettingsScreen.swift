import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct SettingsScreen: View {
    @EnvironmentObject private var container: AppContainer
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    let viewModel: SettingsViewModel
    var initialTab: SettingsTab? = nil
    @State private var navigationPath: [SettingsCategory] = []
    @State private var hasPrefetchedConnectionCatalogs = false
    @State private var modelsDevFieldDrafts: [String: String] = [:]

    enum SettingsTab: String, Identifiable {
        case api
        case systemPrompt
        case dual
        case auto
        case appearance

        var id: String { rawValue }

        var category: SettingsCategory {
            switch self {
            case .api:
                return .connection
            case .systemPrompt, .dual, .auto:
                return .conversation
            case .appearance:
                return .display
            }
        }
    }

    enum SettingsCategory: String, CaseIterable, Hashable, Identifiable {
        case connection
        case conversation
        case display
        case management

        var id: String { rawValue }

        var title: String {
            switch self {
            case .connection:
                return "接続"
            case .conversation:
                return "会話"
            case .display:
                return "表示"
            case .management:
                return "管理"
            }
        }

        var subtitle: String {
            switch self {
            case .connection:
                return "API・モデル"
            case .conversation:
                return "プロンプト・モード"
            case .display:
                return "テーマ・プリセット"
            case .management:
                return "使用状況・診断"
            }
        }
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            settingsIndex
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: SettingsCategory.self) { category in
                SettingsDetailScreen(
                    viewModel: viewModel,
                    category: category,
                    hasPrefetchedConnectionCatalogs: $hasPrefetchedConnectionCatalogs,
                    modelsDevFieldDrafts: $modelsDevFieldDrafts
                )
            }
            .toolbar {
                if navigationPath.isEmpty {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("閉じる") { dismiss() }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                SettingsStatusFooter(viewModel: viewModel)
            }
        }
        .task {
            viewModel.bind(
                repository: container.chatRepository,
                credentialStore: container.credentialStore,
                modelsDevCatalogRepository: container.modelsDevCatalogRepository,
                skillRepository: container.skillRepository
            )
        }
        .onDisappear {
            viewModel.flushPendingSettingsSave()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { viewModel.flushPendingSettingsSave() }
        }
        .onAppear {
            if let initialTab {
                navigationPath = [initialTab.category]
            }
        }
    }

    private var settingsIndex: some View {
        AMOLEDForm {
            Section {
                ForEach(SettingsCategory.allCases) { category in
                    NavigationLink(value: category) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(category.title)
                            Text(category.subtitle)
                                .font(.caption)
                                .foregroundStyle(Color(uiColor: .amoledSecondaryLabel))
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
    }
}

// Model/usage updates should redraw the detail, without rebuilding navigation.
struct SettingsDetailScreen: View {
    @ObservedObject var viewModel: SettingsViewModel
    let category: SettingsScreen.SettingsCategory
    var onboardingStep: OnboardingConnectionStep? = nil
    var onOnboardingContinue: (() -> Void)? = nil
    var isOnboardingFinishing = false
    @Binding var hasPrefetchedConnectionCatalogs: Bool
    @Binding var modelsDevFieldDrafts: [String: String]
    #if DEBUG
    @State private var showDiagnosticsSheet = false
    #endif
    @FocusState private var systemPromptFocusedField: SystemPromptSettingsSection.Field?
    @State private var showAgentSkillImporter = false
    @State private var selectedAgentSkill: InstalledAgentSkill?

    var body: some View {
        Group {
            if onboardingStep == .model {
                onboardingModelSelection
            } else {
                settingsForm
            }
        }
        .onDisappear { viewModel.flushPendingSettingsSave() }
        .navigationTitle(onboardingStep?.title ?? category.title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if category == .connection, !hasPrefetchedConnectionCatalogs {
                hasPrefetchedConnectionCatalogs = true
                await viewModel.prefetchLatestModelCatalogs()
            }
            #if DEBUG
            if category == .management {
                viewModel.refreshDiagnosticsLog()
            }
            #endif
        }
        .fileImporter(
            isPresented: $showAgentSkillImporter,
            allowedContentTypes: [UTType(filenameExtension: "md")!, .zip, .folder],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case let .success(urls):
                if let url = urls.first { viewModel.inspectAgentSkill(at: url) }
            case let .failure(error):
                viewModel.errorMessage = error.localizedDescription
            }
        }
        .sheet(item: $viewModel.agentSkillInstallPreview, onDismiss: viewModel.discardAgentSkillPreview) { preview in
            AgentSkillInstallReview(
                preview: preview,
                onCancel: viewModel.discardAgentSkillPreview,
                onInstall: { trusted in
                    viewModel.installAgentSkill(trusted: trusted, allowReplacement: preview.replacesExisting)
                }
            )
        }
        .sheet(item: $selectedAgentSkill) { skill in
            AgentSkillDetailScreen(viewModel: viewModel, skillName: skill.manifest.name)
        }
    }

    private var settingsForm: some View {
        AMOLEDForm {
            if let onboardingStep {
                onboardingContent(onboardingStep)
                if let onOnboardingContinue {
                    Section {
                        Button(action: onOnboardingContinue) {
                            HStack(spacing: 10) {
                                if isOnboardingFinishing { ProgressView() }
                                Text(onboardingStep == .model ? "チャットを開く" : "次へ")
                                    .font(.headline)
                            }
                            .frame(maxWidth: .infinity, minHeight: 28)
                        }
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.roundedRectangle(radius: 14))
                        .controlSize(.large)
                        .disabled(isOnboardingFinishing)
                        .accessibilityIdentifier("onboarding-continue")
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                    }
                }
            } else {
                switch category {
                case .connection:
                    connectionCategoryContent
                case .conversation:
                    conversationCategoryContent
                case .display:
                    displayCategoryContent
                case .management:
                    managementCategoryContent
                }
            }
        }
    }

    private var onboardingModelBinding: Binding<String> {
        Binding(
            get: { viewModel.settings.defaultModel },
            set: { viewModel.setDefaultModel($0) }
        )
    }

    private var onboardingModelSelection: some View {
        Group {
            if currentProviderKey == "OPENROUTER" {
                OpenRouterModelListView(
                    titleKey: "モデルを選ぶ",
                    model: onboardingModelBinding,
                    models: viewModel.openRouterModels,
                    isLoading: viewModel.openRouterModelsLoading,
                    onRefresh: { Task { await viewModel.refreshOpenRouterModels(force: false) } },
                    dismissOnSelection: false,
                    error: viewModel.openRouterModelsError
                )
            } else if let provider = currentCatalogModelProvider,
                      currentProviderKey != "OPENAI_COMPAT", currentProviderKey != "SARASHINA" {
                CatalogModelListView(
                    modelID: onboardingModelBinding,
                    provider: provider,
                    dismissOnSelection: false,
                    title: "モデルを選ぶ"
                )
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("更新") { viewModel.refreshModelsDevCatalog() }
                    }
                }
            } else {
                AMOLEDForm {
                    Section("モデル") {
                        providerModelEditor
                            .pickerStyle(.inline)
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let onOnboardingContinue {
                Button(action: onOnboardingContinue) {
                    HStack(spacing: 10) {
                        if isOnboardingFinishing { ProgressView() }
                        Text("チャットを開く").font(.headline)
                    }
                    .frame(maxWidth: .infinity, minHeight: 28)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.roundedRectangle(radius: 14))
                .controlSize(.large)
                .disabled(isOnboardingFinishing || viewModel.settings.defaultModel.trimmedNonEmpty == nil)
                .accessibilityIdentifier("onboarding-continue")
                .padding(20)
                .background(Color(uiColor: .amoledSystemGroupedBackground))
            }
        }
    }

    private var apiTabContent: some View {
        Group {
            Section("API / モデル") {
                CatalogProviderPickerField(providerID: Binding(
                    get: { viewModel.settings.apiProvider.uppercased() },
                    set: { value in viewModel.setProvider(value.uppercased()) }
                ), catalogProviders: viewModel.modelsDevCatalogState.providers)

                providerModelEditor

                Toggle("ストリーミングを有効化", isOn: Binding(
                    get: { viewModel.settings.isStreamingEnabled },
                    set: { viewModel.setStreamingEnabled($0) }
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
            }

            Section(L10n.text("クライアントツール")) {
                Toggle(
                    L10n.text("クライアント側Web検索"),
                    isOn: Binding(
                        get: { viewModel.settings.clientWebSearchToolEnabled },
                        set: { viewModel.setClientWebSearchToolEnabled($0) }
                    )
                )

                Toggle(
                    L10n.text("ローカルPython実行"),
                    isOn: Binding(
                        get: { viewModel.settings.pythonToolEnabled },
                        set: { viewModel.setPythonToolEnabled($0) }
                    )
                )

                Toggle(
                    L10n.text("GenUI（インタラクティブUI）"),
                    isOn: Binding(
                        get: { viewModel.settings.genUIToolEnabled },
                        set: { viewModel.setGenUIToolEnabled($0) }
                    )
                )
                .accessibilityIdentifier("settings-genui-toggle")

            }

            if isOpenCodeGoProvider {
                openCodeGoUsageSection
            }

            providerConnectionContent
        }
    }

    private var providerConnectionContent: some View {
        Group {
            providerCredentialContent

            if isGeminiProvider {
                geminiRotationSection
            }
            if currentProviderKey == "OPENAI_COMPAT" {
                openAICompatSection
            }
            if currentProviderKey == "OPENROUTER" {
                openRouterSection
            }
            if isOpenCodeGoProvider {
                openCodeGoSection
            }
            if currentProviderKey == "CLINEPASS" {
                clinePassSection
            }
            if currentProviderKey == "ALIBABA_CODING_PLAN" {
                alibabaCodingPlanSection
            }
            codexProviderSettingsSection
            geminiProviderSettingsSection
            if currentProviderKey == "CODEX_AUTH" {
                codexAuthSection
            }
            if currentProviderKey == "SUPERGROK" {
                superGrokAuthSection
            }
            superGrokProviderSettingsSection
        }
    }

    private var providerCredentialContent: some View {
        Group {
            if currentModelsDevProvider == nil,
               currentProviderKey != "CODEX_AUTH", currentProviderKey != "SUPERGROK", currentProviderKey != "APPLE_INTELLIGENCE", currentProviderKey != "OPENAI_COMPAT" {
                Section("APIキー") {
                    SecureField(currentProviderAPIKeyLabel, text: $viewModel.apiKeyDraft)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }

            if let provider = currentModelsDevProvider {
                modelsDevConnectionSection(provider)
            }
        }
    }

    @ViewBuilder
    private func onboardingContent(_ step: OnboardingConnectionStep) -> some View {
        switch step {
        case .credentials:
            providerCredentialContent
            if currentProviderKey == "OPENAI_COMPAT" { openAICompatSection }
        case .model:
            Section("モデル") { providerModelEditor }
        }
    }

    private var systemPromptTabContent: some View {
        SystemPromptSettingsSection(viewModel: viewModel, focusedField: $systemPromptFocusedField)
    }

    private var dualTabContent: some View {
        DualModeSettingsSection(viewModel: viewModel)
    }

    private var connectionCategoryContent: some View {
        apiTabContent
    }

    private var conversationCategoryContent: some View {
        Group {
            systemPromptTabContent
            SubagentSettingsSection(viewModel: viewModel)
            dualTabContent
            AutoConversationSettingsSection(viewModel: viewModel)
        }
    }

    private var displayCategoryContent: some View {
        Group {
            appearanceSection
            globalProviderPresetManagementSection
            chatStatsSection
        }
    }

    private var globalProviderPresetManagementSection: some View {
        Section {
            NavigationLink {
                GlobalProviderPresetManagementScreen(viewModel: viewModel)
            } label: {
                Label("グローバルプリセット管理", systemImage: "switch.2")
            }
        }
    }

    private var chatStatsSection: some View {
        Section {
            ForEach(ChatStatsField.allCases) { field in
                Toggle(L10n.text(chatStatsTitle(for: field)), isOn: chatStatsBinding(field))
            }
        } header: {
            Text(L10n.text("チャットスタッツ"))
        }
    }

    private func chatStatsBinding(_ field: ChatStatsField) -> Binding<Bool> {
        Binding(
            get: { viewModel.settings.visibleChatStatsFields().contains(field) },
            set: { isVisible in
                var fields = viewModel.settings.visibleChatStatsFields()
                if isVisible {
                    fields.insert(field)
                } else {
                    fields.remove(field)
                }
                viewModel.settings.setVisibleChatStatsFields(fields)
            }
        )
    }

    private func chatStatsTitle(for field: ChatStatsField) -> String {
        switch field {
        case .turns: return "ターン"
        case .steps: return "ステップ"
        case .llmDuration: return "LLM時間"
        case .toolDuration: return "ツール時間"
        case .averageTTFT: return "平均TTFT"
        case .tokensPerSecond: return "tok/s"
        case .cacheHit: return "キャッシュヒット率"
        case .tokens: return "入力・出力token"
        }
    }

    private var managementCategoryContent: some View {
        Group {
            agentSkillsSection
            tokenUsageSection
            #if DEBUG
            diagnosticsSection
            #endif
            legalSection
        }
    }

    private var agentSkillsSection: some View {
        Group {
            Section {
                Button {
                    showAgentSkillImporter = true
                } label: {
                    Label("Skillをインストール", systemImage: "square.and.arrow.down")
                }

                if viewModel.installedAgentSkills.isEmpty {
                    ContentUnavailableView(
                        "インストール済みSkillはありません",
                        systemImage: "puzzlepiece.extension"
                    )
                }
            } header: {
                Text("Agent Skills")
            }

            if !viewModel.installedAgentSkills.isEmpty {
                Section("インストール済み (\(viewModel.installedAgentSkills.count))") {
                    ForEach(viewModel.installedAgentSkills) { skill in
                        agentSkillRow(skill)
                    }
                }
            }

        }
    }

    private func agentSkillRow(_ skill: InstalledAgentSkill) -> some View {
        HStack(spacing: 12) {
            Button {
                selectedAgentSkill = skill
            } label: {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("$\(skill.manifest.name)")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text(skill.manifest.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color(uiColor: .amoledTertiaryLabel))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("$\(skill.manifest.name)の詳細")
            .accessibilityHint("説明・ファイル・削除操作を表示します")

            Toggle("$\(skill.manifest.name)を有効化", isOn: Binding(
                get: { skill.isEnabled },
                set: { viewModel.setAgentSkillEnabled($0, name: skill.manifest.name) }
            ))
            .labelsHidden()
        }
    }

    private var appearanceSection: some View {
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

        }
    }

    private var legalSection: some View {
        Section("法的情報") {
            Link(destination: AppConstants.privacyPolicyURL) {
                Label(L10n.text("プライバシーポリシー"), systemImage: "hand.raised")
            }
            Link(destination: AppConstants.termsOfUseURL) {
                Label(L10n.text("利用規約"), systemImage: "doc.text")
            }
            Link(destination: AppConstants.supportURL) {
                Label(L10n.text("サポート"), systemImage: "questionmark.circle")
            }
            NavigationLink {
                OpenSourceLicensesView()
            } label: {
                Label(L10n.text("オープンソースライセンス"), systemImage: "doc.badge.gearshape")
            }
        }
    }

    private var geminiRotationSection: some View {
        Group {
            Section("Gemini APIキー一覧（ローテーション）") {
                TextField("キー名", text: $viewModel.geminiKeySlotNameInput)
                SecureField("APIキー", text: $viewModel.geminiKeySlotValueInput)
                Button("キーを追加") {
                    viewModel.addGeminiKeySlot()
                }
                .buttonStyle(.bordered)

                ForEach(viewModel.geminiKeySlots, id: \.self) { name in
                    HStack {
                        Text(name)
                        Spacer()
                        Button(role: .destructive) {
                            viewModel.removeGeminiKeySlot(name: name)
                        } label: {
                            Image(systemName: "trash")
                        }
                    }
                }
            }

            Section("ローテーションモデル一覧") {
                if let provider = viewModel.geminiRotationCatalogProvider {
                    CatalogModelPickerField(
                        modelID: Binding(
                            get: { "" },
                            set: { modelID in
                                viewModel.addGeminiRotationModel(modelID)
                            }
                        ),
                        provider: provider,
                        title: "モデルを追加"
                    )
                }

                ForEach(viewModel.geminiRotationModels, id: \.self) { model in
                    HStack {
                        Text(model)
                        Spacer()
                        Button(role: .destructive) {
                            viewModel.removeGeminiRotationModel(model)
                        } label: {
                            Image(systemName: "trash")
                        }
                    }
                }

                switch viewModel.modelsDevCatalogState.availability {
                case .loading:
                    ProgressView("models.devからモデル一覧を読み込み中...")
                case .stale:
                    Text("保存済み一覧を表示中: \(viewModel.modelsDevCatalogState.error ?? "更新失敗")")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                case .error:
                    Text(viewModel.modelsDevCatalogState.error ?? "models.devからモデル一覧を取得できませんでした")
                        .font(.caption2)
                        .foregroundStyle(.red)
                default:
                    EmptyView()
                }

                Button("モデル一覧を更新") {
                    viewModel.refreshModelsDevCatalog()
                }
            }
        }
    }

    private var openAICompatSection: some View {
        Section("カスタムエンドポイント") {
            if !viewModel.openAICompatPresets.isEmpty {
                Picker("プリセット", selection: Binding(
                    get: { viewModel.settings.selectedOpenAICompatPreset ?? "" },
                    set: { viewModel.selectCustomEndpointPreset($0) }
                )) {
                    Text("新規").tag("")
                    ForEach(viewModel.openAICompatPresets) { Text($0.name).tag($0.name) }
                }
            }
            TextField("プリセット名", text: $viewModel.customEndpointDraft.name)
            Picker("APIプロトコル", selection: $viewModel.customEndpointDraft.apiProtocol) {
                Text("選択してください").tag("")
                Text("Anthropic Messages").tag("anthropic-messages")
                Text("OpenAI Chat Completions").tag("openai-completions")
                Text("OpenAI Responses").tag("openai-responses")
                Text("Gemini (Google Generative AI)").tag("google-generative-ai")
                Text("Mistral Native").tag("mistral-conversations")
            }
            .onChange(of: viewModel.customEndpointDraft.apiProtocol) { _, api in
                if api != "anthropic-messages" { viewModel.customEndpointDraft.thinkingBudget = nil }
            }
            TextField("Base URL", text: $viewModel.customEndpointDraft.baseURL)
                .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
            TextField("モデルID", text: $viewModel.customEndpointDraft.modelId)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
            LabeledContent("コンテキスト上限") {
                TextField("tokens", value: $viewModel.customEndpointDraft.contextWindow, format: .number)
                    .keyboardType(.numberPad).multilineTextAlignment(.trailing)
            }
            LabeledContent("最大出力") {
                TextField("tokens", value: $viewModel.customEndpointDraft.maxTokens, format: .number)
                    .keyboardType(.numberPad).multilineTextAlignment(.trailing)
            }
            Toggle("画像入力に対応", isOn: $viewModel.customEndpointDraft.vision)
            Toggle("ツール呼び出しに対応", isOn: $viewModel.customEndpointDraft.toolCall)
            Toggle("Reasoningに対応", isOn: $viewModel.customEndpointDraft.reasoning)
                .onChange(of: viewModel.customEndpointDraft.reasoning) { _, enabled in
                    if !enabled {
                        viewModel.customEndpointDraft.reasoningEffort = "off"
                        viewModel.customEndpointDraft.thinkingBudget = nil
                    }
                }
            if viewModel.customEndpointDraft.reasoning {
                Picker("Reasoning effort", selection: $viewModel.customEndpointDraft.reasoningEffort) {
                    ForEach(["off", "minimal", "low", "medium", "high", "xhigh", "max"], id: \.self) { Text($0).tag($0) }
                }
                .onChange(of: viewModel.customEndpointDraft.reasoningEffort) { _, effort in
                    if effort == "off" { viewModel.customEndpointDraft.thinkingBudget = nil }
                }
                if viewModel.customEndpointDraft.apiProtocol == "anthropic-messages" {
                    LabeledContent("Thinking budget") {
                        TextField("省略可", value: $viewModel.customEndpointDraft.thinkingBudget, format: .number)
                            .keyboardType(.numberPad).multilineTextAlignment(.trailing)
                    }
                }
            }
            LabeledContent("Temperature") {
                TextField("省略可・0〜2", value: $viewModel.customEndpointDraft.temperature, format: .number)
                    .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
            }
            if viewModel.customEndpointDraft.apiProtocol == "openai-completions" {
                Picker("出力上限のパラメーター", selection: $viewModel.customEndpointDraft.maxTokensField) {
                    Text("max_completion_tokens").tag("max_completion_tokens")
                    Text("max_tokens").tag("max_tokens")
                }
                Toggle("storeパラメーターに対応", isOn: $viewModel.customEndpointDraft.supportsStore)
                Toggle("ストリーム内のusageに対応", isOn: $viewModel.customEndpointDraft.supportsUsageInStreaming)
            }
            if ["openai-completions", "openai-responses"].contains(viewModel.customEndpointDraft.apiProtocol) {
                Toggle("developerロールに対応", isOn: $viewModel.customEndpointDraft.supportsDeveloperRole)
            }
            Button("プリセット追加/更新") { viewModel.addOrUpdateOpenAICompatPreset() }
                .buttonStyle(.bordered)
            if let name = viewModel.settings.selectedOpenAICompatPreset, !name.isEmpty {
                SecureField("選択中のプリセットのAPIキー", text: $viewModel.openAICompatApiKeyInput)
                Button("APIキーを保存") { viewModel.saveSelectedOpenAICompatApiKey() }
                Button("選択中のプリセットを削除", role: .destructive) { viewModel.removeOpenAICompatPreset(name: name) }
            }
        }
        .onAppear {
            if viewModel.customEndpointDraft.name.isEmpty, let selected = viewModel.settings.selectedOpenAICompatPreset {
                viewModel.selectCustomEndpointPreset(selected)
            }
        }
    }

    private var openRouterSection: some View {
        OpenRouterSettingsSections(viewModel: viewModel)
    }

    private var alibabaCodingPlanSection: some View {
        Section("Alibaba Coding Plan") {
            Text("Base URL: \(AppConstants.defaultAlibabaCodingPlanBaseURL.absoluteString)")
                .font(.caption)
                .textSelection(.enabled)

            Toggle("Remote MCP を有効化", isOn: Binding(
                get: { viewModel.settings.alibabaMCPEnabled },
                set: { viewModel.settings.alibabaMCPEnabled = $0 }
            ))

            if viewModel.settings.alibabaMCPEnabled {
                TextField("MCP Server URL (https://...)", text: Binding(
                    get: { viewModel.settings.alibabaMCPServerURL },
                    set: { viewModel.setAlibabaMCPServerURL($0) }
                ))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

                TextField("MCP Server Name", text: Binding(
                    get: { viewModel.settings.alibabaMCPServerName },
                    set: { viewModel.settings.alibabaMCPServerName = $0 }
                ))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

                SecureField("Authorization Token (optional)", text: $viewModel.alibabaMCPAuthorizationTokenInput)

                TextField("Allowed tools (comma-separated, optional)", text: Binding(
                    get: { viewModel.settings.alibabaMCPAllowedToolsCSV },
                    set: { viewModel.settings.alibabaMCPAllowedToolsCSV = $0 }
                ), axis: .vertical)
                .lineLimit(2 ... 4)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

                Button("Firecrawl テンプレートを設定") {
                    viewModel.settings.alibabaMCPServerName = AppConstants.alibabaMCPDefaultServerName
                    if viewModel.settings.alibabaMCPServerURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        viewModel.setAlibabaMCPServerURL(AppConstants.firecrawlRemoteMCPURLTemplate)
                    }
                }
                .buttonStyle(.bordered)

            }
        }
    }

    private var openCodeGoSection: some View {
        Section("OpenCode Go") {
            Text("Endpoint: \(AppConstants.defaultOpenCodeGoBaseURL.absoluteString)")
                .font(.caption)
                .textSelection(.enabled)
        }
    }

    private var openCodeGoUsageSection: some View {
        let apiKey = openCodeGoUsageAPIKeyDraft
        let hasAPIKey = apiKey.trimmedNonEmpty != nil
        return Section {
            HStack(alignment: .center, spacing: 12) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Goプラン使用状況")
                            .font(.headline)
                        if let updatedAt = viewModel.openCodeGoUsageLastUpdated {
                            HStack(spacing: 3) {
                                Text("最終更新")
                                Text(updatedAt, style: .relative)
                            }
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        } else {
                            Text("rolling・weekly・monthly")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                } icon: {
                    Image(systemName: "chart.bar.fill")
                        .foregroundStyle(.tint)
                }

                Spacer(minLength: 8)

                Button {
                    Task { await viewModel.retrieveOpenCodeGoUsage(apiKey: apiKey) }
                } label: {
                    if viewModel.isOpenCodeGoUsageLoading {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityLabel("使用状況を更新中")
                    } else {
                        Label("更新", systemImage: "arrow.clockwise")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.isOpenCodeGoUsageLoading || !hasAPIKey)
            }

            if !hasAPIKey {
                Label("APIキーを入力すると使用状況を確認できます", systemImage: "key")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
            } else if viewModel.isOpenCodeGoUsageLoading,
                      viewModel.openCodeGoUsageStatus == nil {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("使用状況を取得中…")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 14)
            }

            if let usage = viewModel.openCodeGoUsageStatus {
                VStack(spacing: 0) {
                    ForEach(Array(usage.windows.enumerated()), id: \.element.period) { index, window in
                        if index > 0 { Divider() }
                        OpenCodeGoUsageWindowView(window: window)
                            .padding(.vertical, 12)
                    }
                }
            }

            if let error = viewModel.openCodeGoUsageError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.vertical, 4)
            }
        }
        .task {
            await viewModel.retrieveOpenCodeGoUsageIfNeeded(apiKey: apiKey)
        }
    }

    private var clinePassSection: some View {
        Section("Cline Pass") {
            Text("Endpoint: \(AppConstants.defaultClinePassBaseURL.absoluteString)chat/completions")
                .font(.caption)
                .textSelection(.enabled)

        }
    }

    private var codexProviderSettingsSection: some View {
        Group {
            if currentProviderKey == "CODEX_AUTH" {
                Section("Codex Settings") {
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

                    Toggle("Prompt Cache", isOn: Binding(
                        get: { viewModel.settings.codexPromptCacheEnabled },
                        set: { viewModel.settings.codexPromptCacheEnabled = $0 }
                    ))

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

                }

                Section("Gemini Tools") {
                    Toggle("Google Search", isOn: Binding(
                        get: { viewModel.settings.geminiGoogleSearchEnabled },
                        set: { viewModel.setGeminiGoogleSearchEnabled($0) }
                    ))
                    Toggle("URL Context", isOn: Binding(
                        get: { viewModel.settings.geminiURLContextEnabled },
                        set: { viewModel.setGeminiURLContextEnabled($0) }
                    ))
                    Toggle("Code Execution", isOn: Binding(
                        get: { viewModel.settings.geminiCodeExecutionEnabled },
                        set: { viewModel.setGeminiCodeExecutionEnabled($0) }
                    ))
                    Toggle("Google Maps", isOn: Binding(
                        get: { viewModel.settings.geminiGoogleMapsEnabled },
                        set: { viewModel.setGeminiGoogleMapsEnabled($0) }
                    ))
                }
            }
        }
    }

    private var superGrokProviderSettingsSection: some View {
        Group {
            if currentProviderKey == "SUPERGROK" {
                Section("SuperGrok Settings") {
                    Text("Endpoint: \(AppConstants.defaultSuperGrokBaseURL.absoluteString)")
                        .font(.caption)
                        .textSelection(.enabled)

                    Toggle("Reasoning", isOn: Binding(
                        get: { viewModel.settings.superGrokReasoningEnabled },
                        set: { viewModel.settings.superGrokReasoningEnabled = $0 }
                    ))

                    Picker("Reasoning Effort", selection: Binding(
                        get: {
                            let value = viewModel.settings.superGrokReasoningEffort.ifBlank("medium")
                            return superGrokReasoningEffortOptions.contains(value) ? value : "medium"
                        },
                        set: { viewModel.settings.superGrokReasoningEffort = $0 }
                    )) {
                        ForEach(superGrokReasoningEffortOptions, id: \.self) { effort in
                            Text(effort).tag(effort)
                        }
                    }
                    .disabled(!viewModel.settings.superGrokReasoningEnabled)

                }
            }
        }
    }

    private var superGrokAuthSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.title3.weight(.medium))
                        .frame(width: 44, height: 44)
                        .background(Color.amoledSubtleSurface(lightOpacity: 0.05), in: RoundedRectangle(cornerRadius: 12))
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("SuperGrok")
                            .font(.headline)
                        Label(
                            viewModel.superGrokAuthState.isLoggedIn ? "接続済み" : "未接続",
                            systemImage: viewModel.superGrokAuthState.isLoggedIn ? "checkmark.circle.fill" : "circle"
                        )
                        .font(.caption.weight(.medium))
                        .foregroundStyle(viewModel.superGrokAuthState.isLoggedIn ? Color.green : Color.secondary)

                        if !viewModel.superGrokEmailInput.isEmpty {
                            Text(viewModel.superGrokEmailInput)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                    Spacer(minLength: 0)
                }

                Button {
                    Task { await viewModel.loginSuperGrokWithBrowser() }
                } label: {
                    HStack(spacing: 10) {
                        Text(viewModel.superGrokAuthState.isLoggedIn ? "SuperGrokに再接続" : "SuperGrokに接続")
                            .font(.subheadline.weight(.semibold))
                            .multilineTextAlignment(.center)
                        Image(systemName: "arrow.up.right")
                            .font(.caption.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .padding(.vertical, 4)
                    .foregroundStyle(Color(uiColor: .amoledSystemBackground))
                    .background(Color.primary, in: RoundedRectangle(cornerRadius: 14))
                    .contentShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isSuperGrokAuthActionRunning)

                VStack(spacing: 0) {
                    Button {
                        Task { await viewModel.loginSuperGrokWithDeviceCode() }
                    } label: {
                        accountActionLabel("デバイスコードで接続", systemImage: "number.square", trailingImage: "arrow.up.right")
                    }

                    if viewModel.superGrokAuthState.isLoggedIn {
                        Divider()
                        Button {
                            Task { await viewModel.refreshSuperGrok(force: true) }
                        } label: {
                            accountActionLabel("接続を更新", systemImage: "arrow.clockwise")
                        }

                        Divider()
                        Button(role: .destructive) {
                            Task { await viewModel.logoutSuperGrok() }
                        } label: {
                            accountActionLabel("サインアウト", systemImage: "rectangle.portrait.and.arrow.right")
                                .foregroundStyle(.red)
                        }
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.primary)
                .disabled(viewModel.isSuperGrokAuthActionRunning)

                if viewModel.isSuperGrokAuthActionRunning {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("接続を処理中…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                if let challenge = viewModel.superGrokAuthState.pendingDeviceCode {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("ブラウザで次のコードを入力してください。")
                            .font(.subheadline)
                        Text(challenge.userCode)
                            .font(.title2.monospaced().weight(.semibold))
                            .textSelection(.enabled)
                        if let url = URL(string: challenge.browserURL) {
                            Link(destination: url) {
                                Label("認証ページを開く", systemImage: "arrow.up.right.square")
                                    .font(.subheadline)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(Color.amoledSubtleSurface(lightOpacity: 0.05), in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding(.vertical, 6)
            .listRowSeparator(.hidden)
        }
    }

    private var codexAuthSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top, spacing: 12) {
                    ChatGPTBrandIcon()
                        .frame(width: 24, height: 24)
                        .foregroundStyle(.primary)
                        .frame(width: 44, height: 44)
                        .background(Color.amoledSubtleSurface(lightOpacity: 0.05), in: RoundedRectangle(cornerRadius: 12))

                    VStack(alignment: .leading, spacing: 6) {
                        Text("ChatGPT プラン")
                            .font(.headline)
                        Label(codexSummary, systemImage: viewModel.codexAuthState.planUsageEnabled ? "checkmark.circle.fill" : "circle")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(viewModel.codexAuthState.planUsageEnabled ? Color.green : Color.secondary)

                        if !viewModel.codexEmailInput.isEmpty {
                            Text(viewModel.codexEmailInput)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                    Spacer(minLength: 0)
                }

                if viewModel.codexAuthState.requiresReauthentication {
                    Label {
                        Text("ChatGPT連携が更新されました。再接続してプランの利用を許可してください。")
                    } icon: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }

                Button {
                    Task { await viewModel.loginCodexAuth() }
                } label: {
                    HStack(spacing: 10) {
                        if viewModel.isCodexAuthActionRunning {
                            ProgressView()
                                .tint(Color(uiColor: .amoledSystemBackground))
                        }
                        if !viewModel.isCodexAuthActionRunning {
                            ChatGPTBrandIcon(inverse: true).frame(width: 21, height: 21)
                        }
                        Text(viewModel.isCodexAuthActionRunning ? "接続中…" :
                            viewModel.codexAuthState.isLoggedIn ? "ChatGPTに再接続" : "ChatGPTに接続")
                            .font(.subheadline.weight(.semibold))
                        if !viewModel.isCodexAuthActionRunning {
                            Image(systemName: "arrow.up.right")
                                .font(.caption.weight(.semibold))
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .foregroundStyle(Color(uiColor: .amoledSystemBackground))
                    .background(Color.primary, in: RoundedRectangle(cornerRadius: 14))
                    .contentShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isCodexAuthActionRunning)

                VStack(spacing: 0) {
                    Link(destination: URL(string: "https://chatgpt.com/settings/usage")!) {
                        accountActionLabel("使用状況を確認", systemImage: "chart.bar", trailingImage: "arrow.up.right")
                    }

                    if viewModel.codexAuthState.isLoggedIn || viewModel.codexAuthState.requiresReauthentication {
                        Divider()

                        Button(role: .destructive) {
                            Task { await viewModel.logoutCodexAuth() }
                        } label: {
                            accountActionLabel("サインアウト", systemImage: "rectangle.portrait.and.arrow.right")
                                .foregroundStyle(.red)
                        }
                        .disabled(viewModel.isCodexAuthActionRunning)
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.primary)
            }
            .padding(.top, 6)
            .listRowSeparator(.hidden)
        }
    }

    private func accountActionLabel(_ title: String, systemImage: String, trailingImage: String? = nil) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.body)
                .frame(width: 22)
            Text(title)
                .font(.subheadline)
            Spacer(minLength: 8)
            if let trailingImage {
                Image(systemName: trailingImage)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color(uiColor: .amoledTertiaryLabel))
            }
        }
        .frame(minHeight: 48)
        .contentShape(Rectangle())
    }

    private var currentProviderAPIKeyLabel: String {
        let providerLabel = ProviderCatalog.displayName(for: viewModel.settings.apiProvider)
        return L10n.format("%@ API Key", providerLabel)
    }

    private var codexSummary: String {
        viewModel.codexAuthState.planUsageEnabled ? "プラン利用中" :
            viewModel.codexAuthState.isLoggedIn ? "接続済み・プラン利用は未許可" : "未接続"
    }

    private var providerModelEditor: some View {
        Group {
            if currentProviderKey == "OPENAI_COMPAT" {
                Text("Model: \(viewModel.settings.defaultModel)")
            } else if currentProviderKey == "SARASHINA" {
                Picker("Model", selection: Binding(get: { viewModel.settings.defaultModel }, set: { viewModel.setDefaultModel($0) })) {
                    ForEach(["sarashina3-mini", "sarashina3-nano", "sarashina3-guard"], id: \.self) { Text($0).tag($0) }
                    if !["sarashina3-mini", "sarashina3-nano", "sarashina3-guard"].contains(viewModel.settings.defaultModel) {
                        Text(viewModel.settings.defaultModel).tag(viewModel.settings.defaultModel).disabled(true)
                    }
                }
                Link("Sarashina API ドキュメント", destination: URL(string: "https://docs.sarashina.ai/")!)
            } else if currentProviderKey == "OPENROUTER" {
                OpenRouterModelPickerField(
                    titleKey: "Model",
                    model: Binding(
                        get: { viewModel.settings.defaultModel },
                        set: { viewModel.setDefaultModel($0) }
                    ),
                    models: viewModel.openRouterModels,
                    isLoading: viewModel.openRouterModelsLoading,
                    error: viewModel.openRouterModelsError,
                    onRefresh: {
                        Task { await viewModel.refreshOpenRouterModels(force: false) }
                    }
                )
            } else if let provider = currentCatalogModelProvider {
                CatalogModelPickerField(
                    modelID: Binding(
                        get: { viewModel.settings.defaultModel },
                        set: { viewModel.setDefaultModel($0) }
                    ),
                    provider: provider
                )
                if let dynamicProvider = currentModelsDevProvider,
                   let selectedModel = dynamicProvider.models.first(where: { $0.id == viewModel.settings.defaultModel }) {
                    let savedReasoningEffort = viewModel.modelsDevReasoningEffort(
                        providerID: dynamicProvider.id,
                        modelID: selectedModel.id
                    )
                    if selectedModel.shouldShowReasoningEffortPreference(savedEffort: savedReasoningEffort) {
                        ModelsDevReasoningEffortPicker(
                            model: selectedModel,
                            currentEffort: savedReasoningEffort,
                            onChange: { effort in
                                viewModel.saveModelsDevReasoningEffort(
                                    providerID: dynamicProvider.id,
                                    modelID: selectedModel.id,
                                    effort: effort
                                )
                            }
                        )
                        .id("\(dynamicProvider.id)\u{0}\(selectedModel.id)")
                    }
                }
                if viewModel.settings.defaultModel.isEmpty {
                    Text("モデルを明示的に選択してください。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else if !provider.models.contains(where: { $0.id == viewModel.settings.defaultModel }) {
                    Text("このモデルは現在のカタログでは利用できません。自動変更は行いません。")
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
                switch viewModel.modelsDevCatalogState.availability {
                case .loading:
                    ProgressView("モデル一覧を読み込み中...")
                case .stale:
                    Text("保存済み一覧を表示中: \(viewModel.modelsDevCatalogState.error ?? "更新失敗")")
                        .font(.caption2).foregroundStyle(.orange)
                case .error:
                    Text(viewModel.modelsDevCatalogState.error ?? "モデル一覧を取得できませんでした")
                        .font(.caption2).foregroundStyle(.red)
                default:
                    EmptyView()
                }
                Button("モデル一覧を更新") { viewModel.refreshModelsDevCatalog() }
            } else if isCodexProvider {
                Picker("ChatGPT Model", selection: Binding(
                    get: { viewModel.settings.defaultModel },
                    set: { value in
                        viewModel.setDefaultModel(value)
                        if let preset = CodexModelCatalog.findPreset(value, in: viewModel.codexModels) {
                            let supported = preset.supportedReasoningEfforts.map(\.effort)
                            if !supported.contains(viewModel.settings.codexReasoningEffort) {
                                viewModel.settings.codexReasoningEffort = preset.defaultReasoningEffort
                            } else if viewModel.settings.codexReasoningEffort.isEmpty {
                                viewModel.settings.codexReasoningEffort = preset.defaultReasoningEffort
                            }
                        }
                    }
                )) {
                    if !viewModel.codexModels.contains(where: { $0.id == viewModel.settings.defaultModel }) {
                        Text(viewModel.settings.defaultModel)
                            .tag(viewModel.settings.defaultModel)
                            .disabled(true)
                    }
                    ForEach(CodexModelCatalog.visiblePresets(from: viewModel.codexModels)) { preset in
                        Text(preset.isSupported ? preset.displayName : "\(preset.displayName) · \(preset.unsupportedReason ?? "unsupported")")
                            .tag(preset.model)
                            .disabled(!preset.isSupported)
                    }
                }

                if viewModel.codexModelsLoading {
                    ProgressView("モデル一覧を読み込み中...")
                } else if let error = viewModel.codexModelsError {
                    Text("モデル一覧を取得できませんでした: \(error)")
                        .font(.caption2)
                        .foregroundStyle(.red)
                }

                Button("モデル一覧を更新") {
                    Task { await viewModel.refreshCodexModels(forceRefresh: true) }
                }
                .disabled(viewModel.codexModelsLoading || viewModel.isCodexAuthActionRunning || !viewModel.codexAuthState.planUsageEnabled)

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
            } else if isAlibabaCodingPlanProvider {
                Picker("Alibaba Model", selection: Binding(
                    get: { viewModel.settings.defaultModel },
                    set: { viewModel.setDefaultModel($0) }
                )) {
                    ForEach(alibabaCodingPlanModelOptions, id: \.self) { model in
                        Text(model).tag(model)
                    }
                }

                TextField("Model", text: Binding(
                    get: { viewModel.settings.defaultModel },
                    set: { viewModel.setDefaultModel($0) }
                ))
            } else if isSuperGrokProvider {
                Picker("SuperGrok Model", selection: Binding(
                    get: { viewModel.settings.defaultModel },
                    set: { viewModel.setDefaultModel($0) }
                )) {
                    ForEach(superGrokModelOptions) { model in
                        Text(model.displayName).tag(model.id)
                    }
                }

                TextField("Model", text: Binding(
                    get: { viewModel.settings.defaultModel },
                    set: { viewModel.setDefaultModel($0) }
                ))
            } else if isOpenCodeGoProvider {
                Picker("OpenCode Go Model", selection: Binding(
                    get: { viewModel.settings.defaultModel },
                    set: { viewModel.setDefaultModel($0) }
                )) {
                    ForEach(openCodeGoModelOptions) { model in
                        Text(model.displayName).tag(model.id)
                    }
                }

                TextField("Model", text: Binding(
                    get: { viewModel.settings.defaultModel },
                    set: { viewModel.setDefaultModel($0) }
                ))
            } else if isClinePassProvider {
                Picker("Cline Pass Model", selection: Binding(
                    get: { viewModel.settings.defaultModel },
                    set: { viewModel.setDefaultModel($0) }
                )) {
                    ForEach(clinePassModelOptions) { model in
                        Text(model.displayName).tag(model.id)
                    }
                }

                TextField("Model", text: Binding(
                    get: { viewModel.settings.defaultModel },
                    set: { viewModel.setDefaultModel($0) }
                ))
            } else if currentProviderKey == "ZAI" {
                Picker("Z.ai Coding Plan Model", selection: Binding(
                    get: { viewModel.settings.defaultModel },
                    set: { viewModel.setDefaultModel($0) }
                )) {
                    ForEach(ZAICodingPlanModelCatalog.supportedModels, id: \.self) { model in
                        Text(model).tag(model)
                    }
                }
            } else if isAppleIntelligenceProvider {
                AppleIntelligenceModelPicker(model: Binding(
                    get: { viewModel.settings.defaultModel },
                    set: { viewModel.setDefaultModel($0) }
                ))
                if viewModel.settings.defaultModel == AppleIntelligenceModelCatalog.pccModel {
                    Picker("PCC reasoning", selection: Binding(
                        get: {
                            viewModel.settings.pccReasoningLevel
                                ?? AppleIntelligenceModelCatalog.defaultPCCReasoningLevel
                        },
                        set: { viewModel.settings.pccReasoningLevel = $0 }
                    )) {
                        ForEach(AppleIntelligenceModelCatalog.pccReasoningLevels, id: \.self) { level in
                            Text(level.capitalized).tag(level)
                        }
                    }
                }
            } else {
                TextField("Default model", text: Binding(
                    get: { viewModel.settings.defaultModel },
                    set: { viewModel.setDefaultModel($0) }
                ))
            }
        }
    }

    #if DEBUG
    private var diagnosticsSection: some View {
        Section {
            Button {
                showDiagnosticsSheet = true
            } label: {
                Label("表示", systemImage: "doc.text.magnifyingglass")
            }
            .disabled(viewModel.diagnosticsLogText.isEmpty)

            Button {
                viewModel.refreshDiagnosticsLog()
            } label: {
                Label("更新", systemImage: "arrow.clockwise")
            }

            Button {
                UIPasteboard.general.string = viewModel.diagnosticsLogText
                viewModel.statusMessage = L10n.text("診断ログをコピーしました")
            } label: {
                Label("コピー", systemImage: "doc.on.doc")
            }
            .disabled(viewModel.diagnosticsLogText.isEmpty)

            ShareLink(item: viewModel.diagnosticsLogText) {
                Label("共有", systemImage: "square.and.arrow.up")
            }
            .disabled(viewModel.diagnosticsLogText.isEmpty)

            Button(role: .destructive) {
                viewModel.clearDiagnosticsLog()
            } label: {
                Label("クリア", systemImage: "trash")
            }
            .disabled(viewModel.diagnosticsLogText.isEmpty)

            if viewModel.diagnosticsLogText.isEmpty {
                Text("ログはありません。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text(String(viewModel.diagnosticsLogText.suffix(2000)))
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        } header: {
            Text("診断ログ")
        }
        .sheet(isPresented: $showDiagnosticsSheet) {
            NavigationStack {
                ScrollablePlainTextView(text: viewModel.diagnosticsLogText, textStyle: .caption1,
                                        inset: 16, lineSpacing: 0,
                                        accessibilityIdentifier: "diagnostics-log-reader")
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
    #endif

    private var tokenUsageSection: some View {
        TokenUsageSection(state: viewModel.tokenUsageState)
    }

    private var currentProviderKey: String {
        viewModel.settings.apiProvider.uppercased()
    }

    private var currentModelsDevProvider: CatalogProvider? {
        let reference = ProviderReference(persistedID: viewModel.settings.apiProvider)
        guard let id = reference.modelsDevID else { return nil }
        return viewModel.modelsDevCatalogState.providers.first { $0.id == id }
    }

    private var currentCatalogModelProvider: CatalogProvider? {
        guard currentProviderKey != "OPENROUTER",
              let id = ModelsDevMergedProvider.catalogID(for: viewModel.settings.apiProvider)
        else { return nil }
        return viewModel.modelsDevCatalogState.providers.first { $0.id == id }
    }

    @ViewBuilder
    private func modelsDevConnectionSection(_ provider: CatalogProvider) -> some View {
        Section("\(provider.name) 接続設定") {
            ForEach(provider.connectionFields, id: \.self) { field in
                let draftKey = modelsDevDraftKey(providerID: provider.id, fieldName: field)
                let binding = Binding(
                    get: { modelsDevFieldDrafts[draftKey] ?? viewModel.modelsDevField(providerID: provider.id, fieldName: field) },
                    set: {
                        modelsDevFieldDrafts[draftKey] = $0
                        if provider.id == "opencode-go", field == "OPENCODE_API_KEY" {
                            viewModel.openCodeGoUsageCredentialDidChange()
                        }
                    }
                )
                if isSecretModelsDevField(field) {
                    SecureField(field, text: binding)
                } else {
                    TextField(field, text: binding, axis: field == "GOOGLE_APPLICATION_CREDENTIALS" ? .vertical : .horizontal)
                }
            }
            if provider.id == "azure" {
                Text("AZURE_AUTH_TOKEN は Entra ID 認証用です。Mythos では必須、ほかのモデルでは API キーも使用できます。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let api = provider.api {
                Text(api).font(.caption2).foregroundStyle(.secondary)
            }
            Button("接続設定をKeychainへ保存") {
                let fields = Dictionary(uniqueKeysWithValues: provider.connectionFields.map { field in
                    let key = modelsDevDraftKey(providerID: provider.id, fieldName: field)
                    return (field, modelsDevFieldDrafts[key] ?? viewModel.modelsDevField(providerID: provider.id, fieldName: field))
                })
                viewModel.saveModelsDevFields(providerID: provider.id, fields: fields)
            }
        }
    }

    private func isSecretModelsDevField(_ field: String) -> Bool {
        ["KEY", "TOKEN", "SECRET", "PASSWORD", "CREDENTIAL"].contains { field.contains($0) }
    }

    private func modelsDevDraftKey(providerID: String, fieldName: String) -> String {
        "\(providerID)\u{0}\(fieldName)"
    }

    private var isGeminiProvider: Bool {
        currentProviderKey == "GEMINI"
    }

    private var isCodexProvider: Bool {
        currentProviderKey == "CODEX_AUTH"
    }

    private var isAlibabaCodingPlanProvider: Bool {
        currentProviderKey == "ALIBABA_CODING_PLAN"
    }

    private var isOpenCodeGoProvider: Bool {
        ModelsDevMergedProvider.isOpenCodeGo(viewModel.settings.apiProvider)
    }

    private var openCodeGoUsageAPIKeyDraft: String {
        guard ProviderReference(persistedID: viewModel.settings.apiProvider).modelsDevID == "opencode-go" else {
            return viewModel.apiKeyDraft
        }
        let key = modelsDevDraftKey(providerID: "opencode-go", fieldName: "OPENCODE_API_KEY")
        return modelsDevFieldDrafts[key]
            ?? viewModel.modelsDevField(providerID: "opencode-go", fieldName: "OPENCODE_API_KEY")
    }

    private var isSuperGrokProvider: Bool {
        currentProviderKey == "SUPERGROK"
    }

    private var isClinePassProvider: Bool {
        currentProviderKey == "CLINEPASS"
    }

    private var isAppleIntelligenceProvider: Bool {
        currentProviderKey == "APPLE_INTELLIGENCE"
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

    private var alibabaCodingPlanModelOptions: [String] {
        var list = [viewModel.settings.defaultModel] + AlibabaCodingPlanModelCatalog.supportedModels
        var seen: Set<String> = []
        list = list.filter {
            let normalized = $0.lowercased()
            guard !normalized.isEmpty, !seen.contains(normalized) else { return false }
            seen.insert(normalized)
            return true
        }
        return list
    }

    private var openCodeGoModelOptions: [OpenCodeGoModel] {
        OpenCodeGoModelCatalog.supportedModels
    }

    private var superGrokModelOptions: [SuperGrokModel] {
        SuperGrokModelCatalog.supportedModels
    }

    private var clinePassModelOptions: [ClinePassModel] {
        ClinePassModelCatalog.supportedModels
    }

    private var codexReasoningEffortOptions: [CodexReasoningEffortPreset] {
        if let preset = CodexModelCatalog.findPreset(viewModel.settings.defaultModel, in: viewModel.codexModels) {
            return preset.supportedReasoningEfforts
        }
        return []
    }

    private var superGrokReasoningEffortOptions: [String] {
        ["low", "medium", "high"]
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
            AppearanceOption(key: "WHITE", titleKey: "白"),
            AppearanceOption(key: "BLACK", titleKey: "黒")
        ]
    }


}

private struct OpenCodeGoUsageWindowView: View {
    let window: OpenCodeGoUsageWindow

    private var title: String {
        switch window.period {
        case .rolling: return L10n.text("ローリング")
        case .weekly: return L10n.text("週間")
        case .monthly: return L10n.text("月間")
        }
    }

    private var usageColor: Color {
        switch window.boundedUsedPercent {
        case 85...: return .red
        case 60 ..< 85: return .orange
        default: return .green
        }
    }

    private var remainingText: String {
        window.remainingPercent.formatted(.number.precision(.fractionLength(0 ... 1)))
    }

    private var usedText: String {
        window.usedPercent.formatted(.number.precision(.fractionLength(0 ... 1)))
    }

    private var resetText: String {
        L10n.format(
            "リセット %@",
            window.resetsAt.formatted(date: .abbreviated, time: .shortened)
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.subheadline.weight(.semibold))

                if window.status.caseInsensitiveCompare("ok") == .orderedSame {
                    Label("正常", systemImage: "checkmark.circle.fill")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.green)
                        .labelStyle(.titleAndIcon)
                } else {
                    Text(window.status)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(.orange.opacity(0.12), in: Capsule())
                }

                Spacer()

                Text(L10n.format("残り %@%%", remainingText))
                    .font(.subheadline.monospacedDigit().weight(.bold))
                    .foregroundStyle(usageColor)
            }

            ProgressView(value: window.boundedUsedPercent, total: 100)
                .tint(usageColor)
                .accessibilityLabel(L10n.format("%@の使用済み割合", title))
                .accessibilityValue(L10n.format("%@パーセント", usedText))

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    usedLabel
                    Spacer()
                    resetLabel
                }

                VStack(alignment: .leading, spacing: 4) {
                    usedLabel
                    resetLabel
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var usedLabel: some View {
        Text(L10n.format("使用済み %@%%", usedText))
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
    }

    private var resetLabel: some View {
        Label(resetText, systemImage: "clock.arrow.circlepath")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

private struct GlobalProviderPresetManagementScreen: View {
    @ObservedObject var viewModel: SettingsViewModel

    private var presets: [ModelPreset] {
        viewModel.settings.buildGlobalProviderPresets()
    }

    var body: some View {
        AMOLEDForm {
            Section {
                if presets.isEmpty {
                    ContentUnavailableView(
                        "グローバルプリセットがありません",
                        systemImage: "slider.horizontal.3"
                    )
                } else {
                    ForEach(presets, id: \.apiProvider) { preset in
                        Toggle(isOn: visibilityBinding(for: preset.apiProvider)) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(ProviderCatalog.displayName(for: preset.apiProvider))
                                Text(preset.model)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            } header: {
                Text("チャットに表示")
            }
        }
        .navigationTitle("グローバルプリセット管理")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func visibilityBinding(for provider: String) -> Binding<Bool> {
        Binding(
            get: {
                viewModel.settings.shouldShowGlobalProviderPresetInChat(provider: provider)
            },
            set: { isVisible in
                viewModel.settings.setShowGlobalProviderPresetInChat(
                    provider: provider,
                    visible: isVisible
                )
            }
        )
    }
}

private struct AppearanceOption: Identifiable {
    let key: String
    let titleKey: String
    var title: String { L10n.text(titleKey) }

    var id: String { key }
}

private extension String {
    func ifBlank(_ fallback: String) -> String {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }
}

private struct SettingsStatusFooter: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        VStack(spacing: 4) {
            if let status = viewModel.statusMessage {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.green)
            }
            if let error = viewModel.errorMessage {
                HStack(alignment: .top) {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                    Spacer()
                    Button {
                        viewModel.errorMessage = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel(Text(L10n.text("エラーを閉じる")))
                }
                .padding(.horizontal, 12)
                .background(AMOLEDMaterial(material: .regularMaterial))
                .accessibilityElement(children: .combine)
            }
        }
    }
}

private struct AgentSkillDetailScreen: View {
    @ObservedObject var viewModel: SettingsViewModel
    let skillName: String
    @Environment(\.dismiss) private var dismiss
    @State private var pendingAgentSkillDeletionName: String?

    var body: some View {
        NavigationStack {
            AMOLEDForm {
                if let skill = viewModel.installedAgentSkills.first(where: { $0.manifest.name == skillName }) {
                    agentSkillSection(skill)
                }
            }
            .navigationTitle("Skillの詳細")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
            .alert(
                "Agent Skillを削除しますか？",
                isPresented: Binding(
                    get: { pendingAgentSkillDeletionName != nil },
                    set: { isPresented in
                        if !isPresented {
                            pendingAgentSkillDeletionName = nil
                        }
                    }
                ),
                presenting: pendingAgentSkillDeletionName
            ) { skillName in
                Button("削除", role: .destructive) {
                    viewModel.deleteAgentSkill(name: skillName)
                    pendingAgentSkillDeletionName = nil
                }
                Button("キャンセル", role: .cancel) {
                    pendingAgentSkillDeletionName = nil
                }
            }
        }
        .onChange(of: viewModel.installedAgentSkills) { _, skills in
            if !skills.contains(where: { $0.manifest.name == skillName }) {
                dismiss()
            }
        }
    }

    private func agentSkillSection(_ skill: InstalledAgentSkill) -> some View {
        Section {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("$\(skill.manifest.name)")
                        .font(.headline)
                        .textSelection(.enabled)
                    Text(skill.isEnabled ? "有効" : "無効")
                        .font(.caption)
                        .foregroundStyle(skill.isEnabled ? Color.green : Color.secondary)
                }

                Spacer(minLength: 8)

                Toggle("", isOn: Binding(
                    get: { skill.isEnabled },
                    set: { viewModel.setAgentSkillEnabled($0, name: skill.manifest.name) }
                ))
                .labelsHidden()
                .accessibilityLabel("$\(skill.manifest.name)を有効化")
            }
            .padding(.vertical, 2)

            Text(skill.manifest.description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            HStack(spacing: 16) {
                Label("\(skill.files.count)ファイル", systemImage: "doc.on.doc")
                Label(
                    skill.hasScripts ? "スクリプトあり・実行対象外" : "指示・資料のみ",
                    systemImage: skill.hasScripts ? "exclamationmark.triangle" : "doc.text"
                )
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            DisclosureGroup("技術情報") {
                VStack(alignment: .leading, spacing: 8) {
                    Group {
                        Text("SHA-256: \(skill.contentHash)")
                        if let license = skill.manifest.license { Text("license: \(license)") }
                        if let compatibility = skill.manifest.compatibility { Text("compatibility: \(compatibility)") }
                        Text("allowed-tools: \(skill.manifest.allowedTools.isEmpty ? "なし" : skill.manifest.allowedTools.joined(separator: ", "))")
                        ForEach(skill.manifest.metadata.sorted(by: { $0.key < $1.key }), id: \.key) { entry in
                            Text("\(entry.key): \(entry.value)")
                        }
                    }
                    .font(.caption2.monospaced())

                    Divider()

                    ForEach(skill.files) { file in
                        Text("\(file.isScript ? "⚠ " : "")\(file.path) · \(ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file))")
                            .font(.caption2.monospaced())
                    }
                }
                .foregroundStyle(.secondary)
                .padding(.top, 8)
            }

            Button(role: .destructive) {
                pendingAgentSkillDeletionName = skill.manifest.name
            } label: {
                Label("このSkillを削除", systemImage: "trash")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityHint("確認後にこのSkillを削除します")
        }
    }

}

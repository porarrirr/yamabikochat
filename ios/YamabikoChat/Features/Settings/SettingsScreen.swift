import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct SettingsScreen: View {
    @EnvironmentObject private var container: AppContainer
    @Environment(\.dismiss) private var dismiss

    @ObservedObject var viewModel: SettingsViewModel
    var initialTab: SettingsTab? = nil
    @State private var navigationPath: [SettingsCategory] = []
    @State private var showDiagnosticsSheet = false
    @State private var modelsDevFieldDrafts: [String: String] = [:]
    @State private var showAgentSkillImporter = false
    @State private var pendingAgentSkillDeletionName: String?

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
                return "テーマ・プリセット・数式"
            case .management:
                return "使用状況・診断"
            }
        }
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            settingsIndex
            .navigationTitle("設定")
            .navigationDestination(for: SettingsCategory.self) { category in
                settingsDetail(for: category)
            }
            .toolbar {
                if navigationPath.isEmpty {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("閉じる") { dismiss() }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
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
                        .background(.regularMaterial)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            .task {
                viewModel.bind(
                    repository: container.chatRepository,
                    credentialStore: container.credentialStore,
                    modelsDevCatalogRepository: container.modelsDevCatalogRepository,
                    skillRepository: container.skillRepository
                )
                viewModel.prefetchLatestModelCatalogs()
            }
            .onDisappear {
                viewModel.flushPendingSettingsSave()
            }
            .onAppear {
                if let initialTab {
                    navigationPath = [initialTab.category]
                }
            }
        }
    }

    private var settingsIndex: some View {
        Form {
            Section {
                ForEach(SettingsCategory.allCases) { category in
                    NavigationLink(value: category) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(category.title)
                            Text(category.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            } footer: {
                Text("詳細は各項目で設定できます")
            }
        }
    }

    @ViewBuilder
    private func settingsDetail(for category: SettingsCategory) -> some View {
        Form {
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
        .navigationTitle(category.title)
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(
            isPresented: $showAgentSkillImporter,
            allowedContentTypes: [.zip, .folder],
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
        } message: { skillName in
            Text("$\(skillName) を完全に削除します。この操作は取り消せません。")
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
                Text(L10n.format(
                    "現在のプロバイダー（%@）のグローバル設定をチャットプリセットに追加します。",
                    ProviderCatalog.displayName(for: viewModel.settings.apiProvider)
                ))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Section(L10n.text("クライアントツール")) {
                Toggle(
                    L10n.text("クライアント側Web検索"),
                    isOn: Binding(
                        get: { viewModel.settings.clientWebSearchToolEnabled },
                        set: { viewModel.setClientWebSearchToolEnabled($0) }
                    )
                )
                Text(L10n.text("LLMが必要に応じてWeb検索とページ取得を実行します。外部検索APIキーは不要です。"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Toggle(
                    L10n.text("ローカルPython実行"),
                    isOn: Binding(
                        get: { viewModel.settings.pythonToolEnabled },
                        set: { viewModel.setPythonToolEnabled($0) }
                    )
                )
                Text(L10n.text("LLMが必要に応じて会話専用のPython 3.14環境でコードを実行します。ネットワーク、シェル、会話外のファイルにはアクセスできません。"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                if !LLMProvider(rawOrDefault: viewModel.settings.apiProvider).supportsClientWebSearchTool {
                    Text(L10n.text("現在のプロバイダーではこのツールは使用されません。"))
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
                if isGeminiProvider {
                    Text(L10n.text("Geminiツールとクライアント側Web検索・ローカルPython実行は同時に有効化できません。"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if currentModelsDevProvider == nil,
               currentProviderKey != "CODEX_AUTH", currentProviderKey != "SUPERGROK", currentProviderKey != "APPLE_INTELLIGENCE" {
                Section("APIキー") {
                    SecureField(currentProviderAPIKeyLabel, text: $viewModel.apiKeyDraft)
                }
            }

            if let provider = currentModelsDevProvider {
                modelsDevConnectionSection(provider)
            }

            if isGeminiProvider {
                geminiRotationSection
            }
            if currentProviderKey == "OPENAI_COMPAT" {
                openAICompatSection
            }
            if currentProviderKey == "OPENROUTER" {
                openRouterSection
            }
            if currentProviderKey == "OPENCODE_GO" {
                openCodeGoSection
            }
            if currentProviderKey == "CLINEPASS" {
                clinePassSection
            }
            if currentProviderKey == "OPENAI" {
                openAIEndpointSection
            }
            if currentProviderKey == "ALIBABA_CODING_PLAN" {
                alibabaCodingPlanSection
            }
            if currentProviderKey == "MINIMAX" {
                miniMaxEndpointSection
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

    private var systemPromptTabContent: some View {
        Group {
            systemPromptPresetSection

            if viewModel.settings.isSystemPromptEnabled {
                Section("システムプロンプト") {
                    TextField("システムプロンプトを入力", text: Binding(
                        get: { viewModel.settings.systemPrompt ?? "" },
                        set: { viewModel.settings.systemPrompt = $0.nilIfBlank }
                    ), axis: .vertical)
                    .lineLimit(4 ... 12)
                }
            }
        }
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
            dualTabContent
            FusionModeSettingsSection(viewModel: viewModel)
            AutoConversationSettingsSection(viewModel: viewModel)
        }
    }

    private var displayCategoryContent: some View {
        Group {
            appearanceSection
            globalProviderPresetManagementSection
            mathRenderingSection
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
        } footer: {
            Text("チャットのプリセット一覧に表示するグローバル設定を、プロバイダーごとに管理します。")
        }
    }

    private var chatStatsSection: some View {
        Section {
            ForEach(ChatStatsField.allCases) { field in
                Toggle(L10n.text(chatStatsTitle(for: field)), isOn: chatStatsBinding(field))
            }
        } header: {
            Text(L10n.text("チャットスタッツ"))
        } footer: {
            Text(L10n.text("入力欄の上に表示する項目を選択します。計測は非表示中も継続します。"))
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
            diagnosticsSection
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
                        systemImage: "puzzlepiece.extension",
                        description: Text("ZIPまたはフォルダから追加できます。")
                    )
                }
            } header: {
                Text("Agent Skills")
            } footer: {
                Text("端末内のZIPまたはフォルダを選択してインストールします。")
            }

            ForEach(viewModel.installedAgentSkills) { skill in
                agentSkillSection(skill)
            }

            if !viewModel.installedAgentSkills.isEmpty {
                Section {
                    Label {
                        Text("Pi AgentにはSkillの指示とUTF-8資料だけを提供します。同梱スクリプトは実行しません。")
                    } icon: {
                        Image(systemName: "checkmark.shield")
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
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
                .lineLimit(3)

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
                    Text(skill.manifest.description)
                        .font(.caption)

                    Divider()

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

            Text("iOSでは表示モード（自動/ライト/ダーク）とアクセントカラーを反映します。")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var mathRenderingSection: some View {
        Section("数式") {
            Toggle("数式レンダリング", isOn: Binding(
                get: { viewModel.settings.mathRenderingEnabled },
                set: { viewModel.settings.mathRenderingEnabled = $0 }
            ))
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
                Text("複数キーを登録すると、レート制限や認証エラー時に自動で次のキー/モデルへ切り替えます。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

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

                if viewModel.geminiRotationModels.isEmpty {
                    Text("未設定の場合は現在選択中のモデルのみを使用します（既存動作と同じ）。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
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

            Divider()

            Text("Thinking / Reasoning Tokens")
                .font(.subheadline)
                .fontWeight(.semibold)

            if let capabilities = selectedOpenRouterModel?.reasoning {
                Toggle("Thinking", isOn: Binding(
                    get: { capabilities.mandatory || viewModel.settings.openRouterThinkingEnabled },
                    set: {
                        viewModel.setOpenRouterThinkingEnabled(
                            $0,
                            modelId: viewModel.settings.defaultModel
                        )
                    }
                ))
                .disabled(capabilities.mandatory)

                if capabilities.mandatory {
                    Text("このモデルではReasoningを無効にできません。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Picker("Reasoning mode", selection: Binding(
                    get: {
                        let mode = viewModel.settings.openRouterReasoningMode
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                            .lowercased()
                        return openRouterReasoningModes.contains(mode) ? mode : "auto"
                    },
                    set: {
                        viewModel.setOpenRouterReasoningMode(
                            $0,
                            modelId: viewModel.settings.defaultModel
                        )
                    }
                )) {
                    ForEach(openRouterReasoningModes, id: \.self) { mode in
                        Text(verbatim: mode).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(!viewModel.settings.openRouterThinkingEnabled)

                if viewModel.settings.openRouterReasoningMode == "effort" {
                    Picker("Effort", selection: Binding(
                        get: { viewModel.settings.openRouterReasoningEffort },
                        set: {
                            viewModel.setOpenRouterReasoningEffort(
                                $0,
                                modelId: viewModel.settings.defaultModel
                            )
                        }
                    )) {
                        ForEach(openRouterReasoningEffortOptions, id: \.self) { effort in
                            Text(verbatim: effort).tag(effort)
                        }
                    }
                    .disabled(!viewModel.settings.openRouterThinkingEnabled)
                }

                if viewModel.settings.openRouterReasoningMode == "budget",
                   capabilities.supportsMaxTokens {
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

                Text("Reasoning tokens are billed as output tokens.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("このモデルはReasoning effort選択に対応していません。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

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

            if viewModel.openRouterEndpointsLoading {
                ProgressView("Endpointを読み込み中...")
            }

            if let error = viewModel.openRouterEndpointsError, !error.isEmpty {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red)
            }

            if viewModel.openRouterEndpointOptions.isEmpty {
                if !viewModel.openRouterEndpointsLoading,
                   viewModel.openRouterEndpointsError == nil {
                    Text("このモデルで選択可能なendpoint情報はありません。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Preferred endpoints (\(viewModel.settings.preferredProvidersList().count))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                ForEach(viewModel.openRouterEndpointOptions) { endpoint in
                    Toggle(isOn: preferredProviderBinding(endpoint.tag)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(endpoint.providerName)
                            HStack(spacing: 6) {
                                Text(verbatim: endpoint.tag)
                                    .font(.caption2.monospaced())
                                if let quantization = endpoint.quantization,
                                   quantization != "unknown" {
                                    Text(verbatim: quantization)
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Text(openRouterEndpointPricingText(endpoint))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if viewModel.openRouterEndpointQuantizations.isEmpty,
               !viewModel.openRouterEndpointsLoading,
               viewModel.openRouterEndpointsError == nil {
                Text("選択可能なQuantization情報は未取得です。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else if !viewModel.openRouterEndpointQuantizations.isEmpty {
                Text("Quantizations (\(viewModel.settings.selectedQuantizationsList().count))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                ForEach(viewModel.openRouterEndpointQuantizations, id: \.self) { quantization in
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

    private var alibabaCodingPlanSection: some View {
        Section("Alibaba Coding Plan") {
            Text("Base URL: \(AppConstants.defaultAlibabaCodingPlanBaseURL.absoluteString)")
                .font(.caption)
                .textSelection(.enabled)

            Text("Coding Plan 専用キーは `sk-sp-` で始まります。iOS版は Anthropic 互換の `/v1/messages` を固定 URL で使います。MCP は remote HTTPS server のみ対応し、Claude Code の `npx`/stdio MCP は iOS アプリ内では利用できません。")
                .font(.caption2)
                .foregroundStyle(.secondary)

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

                Text("例: Firecrawl の hosted MCP は `\(AppConstants.firecrawlRemoteMCPURLTemplate)` 形式です。ツール名を空欄にするとサーバーが公開する全ツールを許可し、指定するとそのツールだけ有効化します。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var openCodeGoSection: some View {
        Section("OpenCode Go") {
            Text("Endpoint: \(AppConstants.defaultOpenCodeGoBaseURL.absoluteString)")
                .font(.caption)
                .textSelection(.enabled)

            Text("OpenCode Go の API key を保存してください。MiniMax M2.7/M2.5 と Qwen3.5/3.6 Plus、Qwen3.7 Max は `/messages`、それ以外の公式 Go モデルは `/chat/completions` に送信します。Chat Completions 系には会話単位の prompt cache key を付けて、同じ長い prefix が同じ cache route に乗りやすいようにします。")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var clinePassSection: some View {
        Section("Cline Pass") {
            Text("Endpoint: \(AppConstants.defaultClinePassBaseURL.absoluteString)chat/completions")
                .font(.caption)
                .textSelection(.enabled)

            Text("Cline dashboard の Settings > API Keys で発行したキーを保存してください。すべてのモデルは `/chat/completions` に送信します。")
                .font(.caption2)
                .foregroundStyle(.secondary)
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

                    Toggle("Prompt Cache", isOn: Binding(
                        get: { viewModel.settings.codexPromptCacheEnabled },
                        set: { viewModel.settings.codexPromptCacheEnabled = $0 }
                    ))

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

                    Text(GeminiModelUtils.getThinkingDescription(model: model))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
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
                    Toggle("Computer Use", isOn: Binding(
                        get: { viewModel.settings.geminiComputerUseEnabled },
                        set: { viewModel.setGeminiComputerUseEnabled($0) }
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

                    Text("pi-grok の OAuth 経路で SuperGrok / X Premium+ サブスクリプションに接続します。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var superGrokAuthSection: some View {
        Section("SuperGrok Auth") {
            Text(superGrokSummary)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Button("Sign in (Browser)") {
                    Task { await viewModel.loginSuperGrokWithBrowser() }
                }
                .buttonStyle(.borderedProminent)

                Button("Sign in (Device Code)") {
                    Task { await viewModel.loginSuperGrokWithDeviceCode() }
                }
                .buttonStyle(.bordered)
            }
            .disabled(viewModel.isSuperGrokAuthActionRunning)

            HStack {
                Button("Refresh") {
                    Task { await viewModel.refreshSuperGrok(force: true) }
                }
                .buttonStyle(.bordered)

                Button("Sign out") {
                    Task { await viewModel.logoutSuperGrok() }
                }
                .buttonStyle(.bordered)
            }
            .disabled(viewModel.isSuperGrokAuthActionRunning)

            if viewModel.isSuperGrokAuthActionRunning {
                ProgressView("SuperGrok認証処理中...")
                    .font(.caption2)
            }

            if let challenge = viewModel.superGrokAuthState.pendingDeviceCode {
                Text("Verification URL: \(challenge.browserURL)")
                    .font(.caption2)
                    .textSelection(.enabled)
                Text("User code: \(challenge.userCode)")
                    .font(.caption2)
                    .textSelection(.enabled)
            }

            if !viewModel.superGrokEmailInput.isEmpty {
                Text("Email: \(viewModel.superGrokEmailInput)")
                    .font(.caption2)
            }

            Text("認証・トークン更新・リクエスト整形は pi-grok が処理します。Device Code ログインではローカル待受ポートを使用しません。")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var codexAuthSection: some View {
        Section("Codex Auth") {
            Text(codexSummary)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("Codex OAuth は Pi 標準の openai-codex 認証を使用します。")
                .font(.caption2)
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

    private var currentProviderAPIKeyLabel: String {
        let providerLabel = ProviderCatalog.displayName(for: viewModel.settings.apiProvider)
        return L10n.format("%@ API Key", providerLabel)
    }

    private var codexSummary: String {
        "loggedIn=\(viewModel.codexAuthState.isLoggedIn ? "yes" : "no"), hasApiKey=\(viewModel.codexAuthState.hasApiKey ? "yes" : "no")"
    }

    private var superGrokSummary: String {
        "loggedIn=\(viewModel.superGrokAuthState.isLoggedIn ? "yes" : "no")"
    }

    private var systemPromptPresetSection: some View {
        Section("システムプロンプトプリセット") {
            Picker("選択中のプリセット", selection: Binding(
                get: { viewModel.systemPromptPickerSelection },
                set: viewModel.selectSystemPromptOption
            )) {
                Text("設定しない（オフ）").tag(SettingsViewModel.disabledSystemPromptSelection)
                Text("新規作成").tag(SettingsViewModel.newSystemPromptSelection)
                ForEach(viewModel.systemPromptPresets) { preset in
                    Text(preset.name).tag(preset.name)
                }
            }

            if viewModel.settings.isSystemPromptEnabled {
                TextField("プリセット名", text: $viewModel.systemPromptPresetNameInput)

                HStack {
                    Button(viewModel.settings.selectedSystemPromptPreset == nil ? "プリセットを作成" : "変更を保存") {
                        viewModel.addOrUpdateSystemPromptPreset()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("選択中を削除", role: .destructive) {
                        viewModel.removeSelectedSystemPromptPreset()
                    }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.settings.selectedSystemPromptPreset == nil)
                }
            } else {
                Text("新しい会話にシステムプロンプトを設定しません。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
            if currentProviderKey == "OPENROUTER" {
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
                        Text("models.devがこのモデルについて公開している対応値だけを表示します。")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
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

                if let model = SuperGrokModelCatalog.model(for: viewModel.settings.defaultModel) {
                    Text(model.description)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
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

                if let model = OpenCodeGoModelCatalog.model(for: viewModel.settings.defaultModel) {
                    Text(model.description)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                TextField("Model", text: Binding(
                    get: { viewModel.settings.defaultModel },
                    set: { viewModel.setDefaultModel($0) }
                ))
                Text("未掲載モデルは endpoint を安全に判定できないため、実行時に明示エラーで停止します。新しい Go モデルを使う場合は catalog 更新が必要です。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else if isClinePassProvider {
                Picker("Cline Pass Model", selection: Binding(
                    get: { viewModel.settings.defaultModel },
                    set: { viewModel.setDefaultModel($0) }
                )) {
                    ForEach(clinePassModelOptions) { model in
                        Text(model.displayName).tag(model.id)
                    }
                }

                if let model = ClinePassModelCatalog.model(for: viewModel.settings.defaultModel) {
                    Text(model.description)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
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
                Text("Coding Plan 専用 endpoint で利用可能なモデルだけを表示しています。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else if isAppleIntelligenceProvider {
                Text(AppleIntelligenceModelCatalog.displayModel)
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

    private var tokenUsageSection: some View {
        let state = viewModel.tokenUsageState
        return Section("トークン統計（直近\(state.rangeDays)日）") {
            if state.totals.requestCount <= 0 {
                Text("まだトークン使用履歴がありません。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                HStack {
                    usageStatCell(label: "Spend", value: formatUsd(state.totals.totalCostUsd))
                    usageStatCell(label: "Requests", value: formatCompactCount(state.totals.requestCount))
                    usageStatCell(label: "Tokens", value: formatCompactCount(state.totals.totalTokens))
                }

                HStack {
                    usageStatCell(label: "Input", value: formatCompactCount(state.totals.inputTokens))
                    usageStatCell(label: "Output", value: formatCompactCount(state.totals.outputTokens))
                    usageStatCell(label: "Cached", value: formatCompactCount(state.totals.cachedInputTokens))
                }

                HStack {
                    usageStatCell(label: "Cache Create", value: formatCompactCount(state.totals.cacheCreationInputTokens))
                    usageStatCell(label: "Reasoning", value: formatCompactCount(state.totals.reasoningTokens))
                }

                if !state.daily.isEmpty {
                    tokenUsageMiniBars(points: state.daily)
                        .frame(height: 48)
                }

                if !state.byModel.isEmpty {
                    Text("Requests By Model")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    let maxTokens = max(1, state.byModel.map(\.totalTokens).max() ?? 1)
                    ForEach(state.byModel.prefix(8)) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(item.model)
                                    .font(.caption)
                                    .lineLimit(1)
                                Spacer()
                                Text(
                                    "\(formatCompactCount(item.requestCount)) req • " +
                                    "\(formatCompactCount(item.totalTokens)) tok • " +
                                    "\(formatUsd(item.totalCostUsd))"
                                )
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            }

                            GeometryReader { proxy in
                                let ratio = max(
                                    0.02,
                                    min(1.0, Double(item.totalTokens) / Double(maxTokens))
                                )
                                ZStack(alignment: .leading) {
                                    Capsule()
                                        .fill(Color.secondary.opacity(0.15))
                                    Capsule()
                                        .fill(Color.accentColor.opacity(0.8))
                                        .frame(width: proxy.size.width * ratio)
                                }
                            }
                            .frame(height: 4)

                            Text(
                                "in \(formatCompactCount(item.inputTokens)) / " +
                                "out \(formatCompactCount(item.outputTokens)) / " +
                                "cache \(formatCompactCount(item.cachedInputTokens)) / " +
                                "cache+ \(formatCompactCount(item.cacheCreationInputTokens)) / " +
                                "reason \(formatCompactCount(item.reasoningTokens))"
                            )
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }

                if let lastUpdated = state.lastUpdated {
                    Text("更新: \(RelativeDateTimeFormatter().localizedString(for: lastUpdated, relativeTo: Date()))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func usageStatCell(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func tokenUsageMiniBars(points: [TokenUsageDailyPoint]) -> some View {
        let sampled = Array(points.suffix(24))
        let maxTokens = max(1, sampled.map(\.totalTokens).max() ?? 1)
        return HStack(alignment: .bottom, spacing: 2) {
            ForEach(sampled) { point in
                let ratio = max(0.08, min(1.0, Double(point.totalTokens) / Double(maxTokens)))
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color.accentColor.opacity(0.7))
                    .frame(maxWidth: .infinity)
                    .frame(height: 48 * ratio)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
            ForEach(provider.env, id: \.self) { field in
                let draftKey = modelsDevDraftKey(providerID: provider.id, fieldName: field)
                let binding = Binding(
                    get: { modelsDevFieldDrafts[draftKey] ?? viewModel.modelsDevField(providerID: provider.id, fieldName: field) },
                    set: { modelsDevFieldDrafts[draftKey] = $0 }
                )
                if isSecretModelsDevField(field) {
                    SecureField(field, text: binding)
                } else {
                    TextField(field, text: binding, axis: field == "GOOGLE_APPLICATION_CREDENTIALS" ? .vertical : .horizontal)
                }
            }
            if let api = provider.api {
                Text(api).font(.caption2).foregroundStyle(.secondary)
            }
            Button("接続設定をKeychainへ保存") {
                let fields = Dictionary(uniqueKeysWithValues: provider.env.map { field in
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
        currentProviderKey == "OPENCODE_GO"
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

    private var superGrokReasoningEffortOptions: [String] {
        ["low", "medium", "high"]
    }

    private var selectedOpenRouterModel: SimpleModel? {
        viewModel.openRouterModels.first { $0.id == viewModel.settings.defaultModel }
    }

    private var openRouterReasoningModes: [String] {
        viewModel.openRouterReasoningModes(forModelId: viewModel.settings.defaultModel)
    }

    private var openRouterReasoningEffortOptions: [String] {
        viewModel.openRouterReasoningEfforts(forModelId: viewModel.settings.defaultModel)
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

    private func openRouterEndpointPricingText(_ endpoint: OpenRouterEndpointOption) -> String {
        guard endpoint.promptPricePerMillion != nil ||
                endpoint.cachedInputPricePerMillion != nil ||
                endpoint.completionPricePerMillion != nil
        else {
            return L10n.text("Price unavailable")
        }
        let prompt = endpoint.promptPricePerMillion.map(formatOpenRouterPrice) ?? "—"
        let cachedInput = endpoint.cachedInputPricePerMillion.map(formatOpenRouterPrice) ?? "—"
        let completion = endpoint.completionPricePerMillion.map(formatOpenRouterPrice) ?? "—"
        return L10n.format(
            "Input %@ · Cached input %@ · Output %@ / 1M tokens",
            prompt,
            cachedInput,
            completion
        )
    }

    private func formatOpenRouterPrice(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.currencySymbol = "$"
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 6
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "$%.6f", value)
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

    private func formatUsd(_ value: Double) -> String {
        String(format: "$%.5f", value)
    }

    private func formatCompactCount(_ value: Int64) -> String {
        let absValue = abs(Double(value))
        if absValue >= 1_000_000_000 {
            return String(format: "%.1fB", Double(value) / 1_000_000_000)
        }
        if absValue >= 1_000_000 {
            return String(format: "%.1fM", Double(value) / 1_000_000)
        }
        if absValue >= 1_000 {
            return String(format: "%.1fK", Double(value) / 1_000)
        }
        return "\(value)"
    }
}

private struct GlobalProviderPresetManagementScreen: View {
    @ObservedObject var viewModel: SettingsViewModel

    private var presets: [ModelPreset] {
        viewModel.settings.buildGlobalProviderPresets()
    }

    var body: some View {
        Form {
            Section {
                if presets.isEmpty {
                    ContentUnavailableView(
                        "グローバルプリセットがありません",
                        systemImage: "slider.horizontal.3",
                        description: Text("接続設定でプロバイダーとモデルを設定すると、ここから表示を管理できます。")
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
            } footer: {
                Text("オンにしたプロバイダーのグローバル設定が、チャットのプリセット一覧に表示されます。")
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
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func ifBlank(_ fallback: String) -> String {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }
}

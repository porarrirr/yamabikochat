import SwiftUI

struct AutoConversationSettingsSection: View {
    @ObservedObject var viewModel: SettingsViewModel

    private var isUnlimitedTurns: Bool {
        viewModel.settings.autoMaxTurns <= 0
    }

    private var maxTurnsLabel: String {
        if isUnlimitedTurns {
            return L10n.text("最大ターン数: 無制限")
        }
        return L10n.format("最大ターン数: %d回", viewModel.settings.autoMaxTurns)
    }

    private var endRuleDescription: String {
        if isUnlimitedTurns {
            return L10n.text("[END]シグナルまたは手動停止")
        }
        return L10n.text("[END]シグナルまたは最大ターン数")
    }

    var body: some View {
        Group {
            Section {
                Toggle(L10n.text("Enable auto conversation"), isOn: Binding(
                    get: { viewModel.settings.isAutoConversationEnabled },
                    set: { viewModel.setAutoConversationEnabled($0) }
                ))
                .disabled(viewModel.settings.isDualModeEnabled && !viewModel.settings.isAutoConversationEnabled)

                Text(L10n.text("自動会話はモデルA/Bの応答を交互に実行します。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if viewModel.settings.isDualModeEnabled && !viewModel.settings.isAutoConversationEnabled {
                    Text(L10n.text("デュアルモードが有効な間は自動会話をONにできません。"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text(L10n.text("自動会話"))
            } footer: {
                Text(L10n.text("デュアルモードと自動会話は同時に有効化できません。"))
            }

            if viewModel.settings.isAutoConversationEnabled {
                Section(L10n.text("AI モデル A（会話開始側）")) {
                    DualAutoModelSideForm(
                        providerTitleKey: "Auto provider A",
                        provider: $viewModel.settings.autoProviderA,
                        modelTitleKey: "Auto model A",
                        model: $viewModel.settings.autoModelA,
                        systemPromptTitleKey: "Auto system prompt A",
                        systemPrompt: $viewModel.settings.autoSystemPromptA,
                        systemPromptLineLimit: 2 ... 6
                    )
                }

                Section(L10n.text("AI モデル B（応答側）")) {
                    DualAutoModelSideForm(
                        providerTitleKey: "Auto provider B",
                        provider: $viewModel.settings.autoProviderB,
                        modelTitleKey: "Auto model B",
                        model: $viewModel.settings.autoModelB,
                        systemPromptTitleKey: "Auto system prompt B",
                        systemPrompt: $viewModel.settings.autoSystemPromptB,
                        systemPromptLineLimit: 2 ... 6
                    )
                }

                Section(L10n.text("会話設定")) {
                    Text(maxTurnsLabel)
                        .font(.subheadline)

                    Toggle(L10n.text("無制限"), isOn: Binding(
                        get: { isUnlimitedTurns },
                        set: { unlimited in
                            if unlimited {
                                viewModel.settings.autoMaxTurns = 0
                            } else if viewModel.settings.autoMaxTurns <= 0 {
                                viewModel.settings.autoMaxTurns = 20
                            }
                        }
                    ))

                    Slider(
                        value: Binding(
                            get: {
                                if isUnlimitedTurns { return 200 }
                                return Double(viewModel.settings.autoMaxTurns)
                            },
                            set: { viewModel.settings.autoMaxTurns = Int($0.rounded()) }
                        ),
                        in: 5 ... 200,
                        step: 1
                    )
                    .disabled(isUnlimitedTurns)

                    Text(L10n.text("`0` を指定すると無制限で実行します。"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Section(L10n.text("使用方法")) {
                    Text(L10n.format("Auto conversation usage guide", endRuleDescription))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

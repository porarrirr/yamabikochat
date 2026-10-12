import SwiftUI

struct SystemPromptSettingsSection: View {
    @ObservedObject var viewModel: SettingsViewModel
    @State private var showsPresetPicker = false
    @State private var confirmsDeletion = false
    @State private var pendingSelection: String?
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case prompt
        case name
    }

    private var selectedPreset: SystemPromptPreset? {
        viewModel.systemPromptPresets.first {
            $0.name == viewModel.settings.selectedSystemPromptPreset
        }
    }

    private var hasPresetChanges: Bool {
        if let selectedPreset {
            return SettingsStringHelpers.nilIfBlank(viewModel.settings.systemPrompt ?? "") != SettingsStringHelpers.nilIfBlank(selectedPreset.prompt)
                || SettingsStringHelpers.nilIfBlank(viewModel.systemPromptPresetNameInput) != selectedPreset.name
        }
        return SettingsStringHelpers.nilIfBlank(viewModel.settings.systemPrompt ?? "") != nil
            || SettingsStringHelpers.nilIfBlank(viewModel.systemPromptPresetNameInput) != nil
    }

    var body: some View {
        Group {
            enableSection

            if viewModel.settings.isSystemPromptEnabled {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("システムプロンプト", systemImage: "text.alignleft")
                            .font(.headline)
                        TextField("例：日本語で、要点を簡潔に答えてください。", text: Binding(
                            get: { viewModel.settings.systemPrompt ?? "" },
                            set: { viewModel.settings.systemPrompt = SettingsStringHelpers.nilIfBlank($0) }
                        ), axis: .vertical)
                        .lineLimit(5 ... 14)
                        .focused($focusedField, equals: .prompt)
                        .accessibilityLabel("システムプロンプト本文")
                        .accessibilityIdentifier("system-prompt-editor")
                    }
                    .padding(.vertical, 6)
                } footer: {
                    Text(selectedPreset == nil
                         ? "本文は自動保存され、新しい会話に使われます。繰り返し使う指示はプリセットにも保存できます。"
                         : "本文の変更を新しい会話に適用するには、下の「このプリセットを更新」を押してください。")
                }

                Section {
                    Button {
                        focusedField = nil
                        showsPresetPicker = true
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "square.stack")
                            VStack(alignment: .leading, spacing: 4) {
                                Text("保存済みのプリセットから選ぶ")
                                Text(selectedPreset.map { "選択中：\($0.name)" } ?? "プリセット未選択")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .accessibilityIdentifier("system-prompt-presets")

                    VStack(alignment: .leading, spacing: 8) {
                        Text("プリセット名")
                            .font(.subheadline.weight(.medium))
                        TextField("例：日本語・簡潔な回答", text: $viewModel.systemPromptPresetNameInput)
                            .textInputAutocapitalization(.never)
                            .focused($focusedField, equals: .name)
                            .accessibilityIdentifier("system-prompt-preset-name")
                    }
                    .padding(.vertical, 4)

                    Button {
                        focusedField = nil
                        viewModel.addOrUpdateSystemPromptPreset()
                    } label: {
                        Label(selectedPreset == nil ? "新しいプリセットとして保存" : "このプリセットを更新",
                              systemImage: "square.and.arrow.down")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(SettingsStringHelpers.nilIfBlank(viewModel.systemPromptPresetNameInput) == nil
                              || SettingsStringHelpers.nilIfBlank(viewModel.settings.systemPrompt ?? "") == nil
                              || !hasPresetChanges)
                    .accessibilityIdentifier("system-prompt-save-preset")

                    HStack {
                        if selectedPreset != nil {
                            Label(hasPresetChanges ? "プリセットに未保存の変更あり" : "プリセット保存済み",
                                  systemImage: hasPresetChanges ? "pencil.circle" : "checkmark.circle")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        Menu {
                            Button("空のプロンプトから作成", systemImage: "plus") {
                                requestSelection(SettingsViewModel.newSystemPromptSelection)
                            }
                            if selectedPreset != nil {
                                Button("選択中のプリセットを削除", systemImage: "trash", role: .destructive) {
                                    confirmsDeletion = true
                                }
                            }
                        } label: {
                            Label("その他", systemImage: "ellipsis.circle")
                                .font(.subheadline)
                                .frame(minHeight: 44)
                        }
                    }
                } header: {
                    Text("プリセット")
                } footer: {
                    Text("プリセットを選択中は、その保存済みの内容が新しい会話に使われます。")
                }
            }
        }
    }

    private var enableSection: some View {
        Section {
            Toggle("システムプロンプトを使う", isOn: $viewModel.settings.isSystemPromptEnabled)
                .accessibilityIdentifier("system-prompt-enabled")
        } header: {
            Text("AIへの指示")
        } footer: {
            Text("話し方や回答のルールを指定します。設定は新しい会話に適用されます。")
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("完了") { focusedField = nil }
            }
        }
        .sheet(isPresented: $showsPresetPicker) {
            NavigationStack {
                List {
                    if viewModel.systemPromptPresets.isEmpty {
                        ContentUnavailableView("プリセットはまだありません", systemImage: "square.stack",
                                               description: Text("本文とプリセット名を入力して保存すると、ここから選べます。"))
                    } else {
                        Section {
                            ForEach(viewModel.systemPromptPresets) { preset in
                                Button {
                                    requestSelection(preset.name)
                                } label: {
                                    HStack(spacing: 12) {
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text(preset.name).font(.headline)
                                            Text(preset.prompt)
                                                .font(.subheadline)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(3)
                                        }
                                        Spacer(minLength: 0)
                                        if preset.name == selectedPreset?.name {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundStyle(.tint)
                                                .accessibilityLabel("選択中")
                                        }
                                    }
                                    .foregroundStyle(.primary)
                                    .padding(.vertical, 6)
                                }
                            }
                        } footer: {
                            Text("選ぶと、編集中の本文がプリセットの内容に置き換わります。")
                        }
                    }
                }
                .navigationTitle("プリセットを選ぶ")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("閉じる") { showsPresetPicker = false }
                    }
                }
                .confirmationDialog("編集中の内容を置き換えますか？", isPresented: selectionConfirmation,
                                    titleVisibility: .visible) {
                    replacePromptButton
                } message: {
                    Text("プリセットに保存していない本文と名前の変更は失われます。")
                }
            }
        }
        .confirmationDialog("編集中の内容を置き換えますか？", isPresented: Binding(
            get: { pendingSelection != nil && !showsPresetPicker },
            set: { if !$0 { pendingSelection = nil } }
        ), titleVisibility: .visible) {
            replacePromptButton
        } message: {
            Text("プリセットに保存していない本文と名前の変更は失われます。")
        }
        .alert("選択中のプリセットを削除しますか？", isPresented: $confirmsDeletion) {
            Button("削除", role: .destructive) { viewModel.removeSelectedSystemPromptPreset() }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("プリセット「\(selectedPreset?.name ?? "")」を削除し、編集中の本文と名前を空にします。")
        }
    }

    private var selectionConfirmation: Binding<Bool> {
        Binding(get: { pendingSelection != nil }, set: { if !$0 { pendingSelection = nil } })
    }

    private var replacePromptButton: some View {
        Button("置き換える", role: .destructive) {
            guard let selection = pendingSelection else { return }
            viewModel.selectSystemPromptOption(selection)
            pendingSelection = nil
            showsPresetPicker = false
        }
    }

    private func requestSelection(_ selection: String) {
        if hasPresetChanges {
            pendingSelection = selection
        } else {
            viewModel.selectSystemPromptOption(selection)
            showsPresetPicker = false
        }
    }
}

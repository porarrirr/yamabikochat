import SwiftUI

struct SystemPromptSettingsSection: View {
    @ObservedObject var viewModel: SettingsViewModel
    @State private var showsPresetPicker = false
    @State private var confirmsDeletion = false
    @State private var pendingSelection: String?
    @FocusState.Binding var focusedField: Field?

    enum Field: Hashable {
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
                Section("使用するプロンプト") {
                    Button {
                        focusedField = nil
                        showsPresetPicker = true
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "square.stack")
                            Text(selectedPreset?.name ?? "プリセットを選ぶ")
                                .foregroundStyle(.primary)
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color(uiColor: .amoledTertiaryLabel))
                        }
                    }
                    .accessibilityIdentifier("system-prompt-presets")

                    Button {
                        focusedField = nil
                        requestSelection(SettingsViewModel.newSystemPromptSelection)
                    } label: {
                        Label("新しいプリセットを作成", systemImage: "plus")
                    }
                }

                Section {
                    LabeledContent("名前") {
                        TextField("プリセット名", text: Binding(
                            get: { viewModel.systemPromptPresetNameInput },
                            set: { viewModel.updateSystemPromptName($0) }
                        ))
                            .textInputAutocapitalization(.never)
                            .focused($focusedField, equals: .name)
                            .accessibilityLabel("プリセット名")
                            .accessibilityIdentifier("system-prompt-preset-name")
                    }

                    TextEditor(text: Binding(
                        get: { viewModel.settings.systemPrompt ?? "" },
                        set: { viewModel.updateSystemPromptText($0) }
                    ))
                    .frame(height: 200)
                    .focused($focusedField, equals: .prompt)
                    .accessibilityLabel("システムプロンプト本文")
                    .accessibilityIdentifier("system-prompt-editor")
                } header: {
                    Text(selectedPreset == nil ? "新しいプリセット" : "プリセットを編集")
                } footer: {
                    if let message = viewModel.systemPromptPresetValidationMessage {
                        Text(message).foregroundStyle(.red)
                    }
                }

                if selectedPreset != nil {
                    Section {
                        Button("このプリセットを削除", systemImage: "trash", role: .destructive) {
                            focusedField = nil
                            confirmsDeletion = true
                        }
                    }
                }
            }
        }
    }

    private var enableSection: some View {
        Section {
            Toggle("システムプロンプトを使う", isOn: $viewModel.settings.isSystemPromptEnabled)
                .accessibilityIdentifier("system-prompt-enabled")
                .sheet(isPresented: $showsPresetPicker) {
                    NavigationStack {
                        AMOLEDList {
                            if viewModel.systemPromptPresets.isEmpty {
                                ContentUnavailableView("プリセットはまだありません", systemImage: "square.stack")
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
                        }
                    }
                }
                .confirmationDialog("編集中の内容を置き換えますか？", isPresented: Binding(
                    get: { pendingSelection != nil && !showsPresetPicker },
                    set: { if !$0 { pendingSelection = nil } }
                ), titleVisibility: .visible) {
                    replacePromptButton
                }
                .alert("選択中のプリセットを削除しますか？", isPresented: $confirmsDeletion) {
                    Button("削除", role: .destructive) { viewModel.removeSelectedSystemPromptPreset() }
                    Button("キャンセル", role: .cancel) {}
                }
        } header: {
            Text("AIへの指示")
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

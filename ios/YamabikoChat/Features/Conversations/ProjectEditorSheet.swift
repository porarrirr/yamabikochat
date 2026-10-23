import SwiftUI

/// Shared editor for creating and editing projects.
///
/// Both entry points use this view so the available fields (name, color, instructions)
/// stay identical and cannot drift apart.
struct ProjectEditorSheet: View {
    enum Mode {
        case create
        case edit(ChatProject)

        var navigationTitle: String {
            switch self {
            case .create: L10n.text("新しいプロジェクト")
            case .edit: L10n.text("プロジェクトを編集")
            }
        }

        var confirmationTitle: String {
            switch self {
            case .create: L10n.text("作成")
            case .edit: L10n.text("保存")
            }
        }
    }

    private struct ColorOption: Identifiable {
        let hex: String
        let nameKey: String

        var id: String { hex }
    }

    private static let availableColors: [ColorOption] = [
        ColorOption(hex: "#3A7AFE", nameKey: "青"),
        ColorOption(hex: "#34C759", nameKey: "緑"),
        ColorOption(hex: "#FF9500", nameKey: "オレンジ"),
        ColorOption(hex: "#FF2D55", nameKey: "ピンク"),
        ColorOption(hex: "#AF52DE", nameKey: "紫"),
        ColorOption(hex: "#FF3B30", nameKey: "赤"),
        ColorOption(hex: "#5856D6", nameKey: "インディゴ"),
        ColorOption(hex: "#8E8E93", nameKey: "グレー")
    ]

    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: ConversationListViewModel

    let mode: Mode
    var onSubmit: (String, String?, String, String) -> Bool

    @State private var title: String
    @State private var instructions: String
    @State private var selectedColorHex: String
    @State private var selectedIcon: String

    init(
        viewModel: ConversationListViewModel,
        mode: Mode,
        onSubmit: @escaping (String, String?, String, String) -> Bool
    ) {
        self.viewModel = viewModel
        self.mode = mode
        self.onSubmit = onSubmit

        switch mode {
        case .create:
            _title = State(initialValue: "")
            _instructions = State(initialValue: "")
            _selectedColorHex = State(initialValue: Self.availableColors[0].hex)
            _selectedIcon = State(initialValue: "folder.fill")
        case let .edit(project):
            _title = State(initialValue: project.title)
            _instructions = State(initialValue: project.instructions ?? "")
            _selectedColorHex = State(initialValue: project.colorHex)
            _selectedIcon = State(initialValue: project.iconName)
        }
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            AMOLEDForm {
                Section(L10n.text("プロジェクト名")) {
                    TextField(L10n.text("例: iOS移植"), text: $title)
                        .accessibilityIdentifier("project-editor-title")
                }

                Section(L10n.text("カラー")) {
                    colorPicker
                }

                Section(L10n.text("プロジェクト指示（任意）")) {
                    TextEditor(text: $instructions)
                        .frame(minHeight: 120)
                        .accessibilityIdentifier("project-editor-instructions")
                }

                if let error = viewModel.visibleErrorMessage {
                    Section {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(mode.navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.text("キャンセル")) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(mode.confirmationTitle) {
                        let trimmedInstructions = instructions
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        if onSubmit(
                            trimmedTitle,
                            trimmedInstructions.isEmpty ? nil : trimmedInstructions,
                            selectedIcon,
                            selectedColorHex
                        ) {
                            dismiss()
                        }
                    }
                    .disabled(trimmedTitle.isEmpty)
                }
            }
        }
        .onAppear {
            viewModel.errorMessage = nil
        }
    }

    private var colorPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(Self.availableColors) { option in
                    Button {
                        selectedColorHex = option.hex
                    } label: {
                        Circle()
                            .fill(Color(hex: option.hex))
                            .frame(width: 32, height: 32)
                            .overlay(
                                Circle()
                                    .stroke(
                                        Color.primary,
                                        lineWidth: selectedColorHex == option.hex ? 2.5 : 0
                                    )
                                    .padding(-3)
                            )
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(L10n.text(option.nameKey)))
                    .accessibilityAddTraits(selectedColorHex == option.hex ? .isSelected : [])
                }
            }
            .padding(.vertical, 4)
        }
    }
}

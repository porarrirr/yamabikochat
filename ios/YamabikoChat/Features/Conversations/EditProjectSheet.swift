import SwiftUI

struct EditProjectSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: ConversationListViewModel

    var onSave: (String, String?, String, String) -> Bool

    @State private var title: String
    @State private var instructions: String
    @State private var selectedColorHex: String
    @State private var selectedIcon: String

    private let availableColors = [
        "#3A7AFE", // Blue
        "#34C759", // Green
        "#FF9500", // Orange
        "#FF2D55", // Pink
        "#AF52DE", // Purple
        "#FF3B30", // Red
        "#5856D6", // Indigo
        "#8E8E93"  // Gray
    ]

    init(
        project: ChatProject,
        viewModel: ConversationListViewModel,
        onSave: @escaping (String, String?, String, String) -> Bool
    ) {
        self.viewModel = viewModel
        self.onSave = onSave
        _title = State(initialValue: project.title)
        _instructions = State(initialValue: project.instructions ?? "")
        _selectedColorHex = State(initialValue: project.colorHex)
        _selectedIcon = State(initialValue: project.iconName)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(L10n.text("プロジェクト名")) {
                    TextField(L10n.text("例: iOS移植"), text: $title)
                }

                Section(L10n.text("カラー")) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(availableColors, id: \.self) { colorHex in
                                Button {
                                    selectedColorHex = colorHex
                                } label: {
                                    Circle()
                                        .fill(Color(hex: colorHex))
                                        .frame(width: 32, height: 32)
                                        .overlay(
                                            Circle()
                                                .stroke(Color.primary, lineWidth: selectedColorHex == colorHex ? 2.5 : 0)
                                                .padding(-3)
                                        )
                                        .frame(width: 44, height: 44)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(colorName(for: colorHex))
                                .accessibilityAddTraits(selectedColorHex == colorHex ? .isSelected : [])
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section(L10n.text("プロジェクト指示（任意）")) {
                    TextEditor(text: $instructions)
                        .frame(minHeight: 120)
                }

                if let error = viewModel.errorMessage {
                    Section {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(L10n.text("プロジェクトを編集"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.text("キャンセル")) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.text("保存")) {
                        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
                        let trimmedInstructions = instructions.trimmingCharacters(in: .whitespacesAndNewlines)
                        if onSave(
                            trimmedTitle,
                            trimmedInstructions.isEmpty ? nil : trimmedInstructions,
                            selectedIcon,
                            selectedColorHex
                        ) {
                            dismiss()
                        }
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .onAppear {
            viewModel.errorMessage = nil
        }
    }

    private func colorName(for hex: String) -> Text {
        let names = [
            "#3A7AFE": "青", "#34C759": "緑", "#FF9500": "オレンジ", "#FF2D55": "ピンク",
            "#AF52DE": "紫", "#FF3B30": "赤", "#5856D6": "インディゴ", "#8E8E93": "グレー"
        ]
        return Text(L10n.text(names[hex] ?? hex))
    }
}

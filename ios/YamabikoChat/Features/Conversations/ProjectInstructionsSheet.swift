import SwiftUI

struct ProjectInstructionsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: ConversationListViewModel

    var onSave: (String?) -> Bool

    @State private var instructions: String

    init(
        viewModel: ConversationListViewModel,
        initialInstructions: String?,
        onSave: @escaping (String?) -> Bool
    ) {
        self.viewModel = viewModel
        self.onSave = onSave
        _instructions = State(initialValue: initialInstructions ?? "")
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                TextEditor(text: $instructions)
                    .font(.system(size: 15))
                    .lineSpacing(4)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 20)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                Spacer()

                // Save button
                VStack(spacing: 0) {
                    if let error = viewModel.visibleErrorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .padding(.horizontal, 20)
                            .padding(.bottom, 8)
                    }

                    Divider()
                        .opacity(0.3)
                        .padding(.bottom, 12)

                    Button {
                        let trimmed = instructions.trimmingCharacters(in: .whitespacesAndNewlines)
                        if onSave(trimmed.isEmpty ? nil : trimmed) {
                            dismiss()
                        }
                    } label: {
                        Text(L10n.text("保存する"))
                            .font(.system(size: 16, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 24, style: .continuous)
                                    .fill(Color(uiColor: .amoledTertiarySystemFill))
                            )
                            .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
                }
            }
            .background(Color(uiColor: .amoledSystemBackground).ignoresSafeArea())
            .navigationTitle(L10n.text("指示"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.secondary)
                            .padding(7)
                            .background(
                                Circle()
                                    .fill(Color(uiColor: .amoledSecondarySystemFill))
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(L10n.text("閉じる")))
                }
            }
        }
        .onAppear {
            viewModel.errorMessage = nil
        }
    }
}

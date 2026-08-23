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

    private var placeholderText: String {
        L10n.text("例:「スペイン語で回答してください。最新の JavaScript ドキュメントを参照してください。回答は短く、的確にしてください。」")
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                // Header description
                VStack(alignment: .leading, spacing: 16) {
                    Text(L10n.text("YamabikoChat に対して、このプロジェクトにおいて、あるトピックに集中するように依頼するか、回答に特定の形式を使用するように依頼します。"))
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(.secondary)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)

                    Divider()
                        .opacity(0.4)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 12)

                // Text input area
                ZStack(alignment: .topLeading) {
                    if instructions.isEmpty {
                        Text(placeholderText)
                            .font(.system(size: 15))
                            .foregroundStyle(Color.secondary.opacity(0.7))
                            .lineSpacing(4)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 8)
                            .allowsHitTesting(false)
                    }

                    TextEditor(text: $instructions)
                        .font(.system(size: 15))
                        .lineSpacing(4)
                        .scrollContentBackground(.hidden)
                        .padding(.horizontal, 20)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                Spacer()

                // Save button
                VStack(spacing: 0) {
                    if let error = viewModel.errorMessage {
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
                                    .fill(Color(uiColor: .tertiarySystemFill))
                            )
                            .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
                }
            }
            .background(Color(uiColor: .systemBackground).ignoresSafeArea())
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
                                    .fill(Color(uiColor: .secondarySystemFill))
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

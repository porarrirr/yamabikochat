import SwiftUI

private struct AskUserQuestionDraft: Equatable {
    var selected: [String] = []
    var custom = ""
    var skipped = false

    var isAnswered: Bool {
        !selected.isEmpty || !custom.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var isComplete: Bool { isAnswered || skipped }
}

struct AskUserQuestionCard: View {
    @ObservedObject var coordinator: UserQuestionCoordinator
    var rendersEditableField = true

    var body: some View {
        if let pending = coordinator.pending {
            AskUserQuestionFlow(
                coordinator: coordinator,
                pending: pending,
                rendersEditableField: rendersEditableField
            )
                .id(pending.id)
        }
    }
}

private struct AskUserQuestionFlow: View {
    @ObservedObject var coordinator: UserQuestionCoordinator
    let pending: UserQuestionCoordinator.PendingRequest
    let rendersEditableField: Bool

    @State private var index = 0
    @State private var drafts: [AskUserQuestionDraft]
    @State private var feedback: String?
    @FocusState private var customFieldFocused: Bool

    init(
        coordinator: UserQuestionCoordinator,
        pending: UserQuestionCoordinator.PendingRequest,
        rendersEditableField: Bool
    ) {
        self.coordinator = coordinator
        self.pending = pending
        self.rendersEditableField = rendersEditableField
        _drafts = State(initialValue: pending.questions.map { _ in AskUserQuestionDraft() })
    }

    private var question: AskUserQuestionItem { pending.questions[index] }
    private var draft: AskUserQuestionDraft { drafts[index] }

    var body: some View {
        VStack(spacing: 0) {
            headerControls
            questionPanel

            if rendersEditableField {
                ScrollViewReader { proxy in
                    ScrollView {
                        answerContent
                    }
                    .frame(minHeight: 96, maxHeight: 310)
                    .scrollDismissesKeyboard(.interactively)
                    .id(question.id)
                    .onChange(of: customFieldFocused) { _, focused in
                        guard focused else { return }
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(Self.customAnswerID, anchor: .bottom)
                        }
                    }
                }
            } else {
                answerContent
            }

            footer
        }
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color(uiColor: .separator).opacity(0.45), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        .accessibilityElement(children: .contain)
    }

    private var answerContent: some View {
        VStack(spacing: 4) {
            ForEach(Array(question.options.enumerated()), id: \.offset) { optionIndex, option in
                optionRow(option, optionIndex: optionIndex)
            }
            customAnswerRow
                .id(Self.customAnswerID)
        }
        .padding(.horizontal, 10)
        .padding(.top, 12)
        .padding(.bottom, 6)
    }

    private var headerControls: some View {
        HStack(spacing: 10) {
            if let header = question.header?.trimmingCharacters(in: .whitespacesAndNewlines), !header.isEmpty {
                Text(header)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Spacer(minLength: 0)
            }

            HStack(spacing: 2) {
                pagerButton("chevron.left", label: L10n.text("前の質問"), disabled: index == 0) {
                    move(to: index - 1)
                }
                Text("\(index + 1) / \(pending.questions.count)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 44)
                pagerButton("chevron.right", label: L10n.text("次の質問"), disabled: index == pending.questions.count - 1) {
                    move(to: index + 1)
                }
                Button {
                    coordinator.cancel(requestID: pending.id)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .medium))
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel(Text(L10n.text("質問をキャンセル")))
            }
        }
        .padding(.leading, 18)
        .padding(.trailing, 8)
        .padding(.top, 10)
    }

    private var questionPanel: some View {
        ScrollView {
            Text(question.question)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
        }
        .frame(maxHeight: 108)
        .scrollBounceBehavior(.basedOnSize)
        .id(question.id)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    private func optionRow(_ option: AskUserQuestionOption, optionIndex: Int) -> some View {
        let selected = draft.selected.contains(option.label)
        let display = Self.recommendedDisplay(for: option.label)
        return Button {
            choose(option.label)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                selectionIndicator(index: optionIndex, selected: selected)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(display.label)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.primary)
                        if display.recommended {
                            Text(L10n.text("推奨"))
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(Color.accentColor)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.12), in: Capsule())
                        }
                    }
                    if let description = option.description?.trimmingCharacters(in: .whitespacesAndNewlines), !description.isEmpty {
                        Text(description)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if selected && !question.multiSelect {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.top, 7)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .background(selected ? Color(uiColor: .tertiarySystemFill) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(display.label))
        .accessibilityValue(Text(selected ? L10n.text("選択済み") : L10n.text("未選択")))
    }

    @ViewBuilder
    private func selectionIndicator(index: Int, selected: Bool) -> some View {
        if question.multiSelect {
            Image(systemName: selected ? "checkmark.square.fill" : "square")
                .font(.system(size: 23, weight: .medium))
                .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                .frame(width: 34, height: 34)
        } else {
            Text("\(index + 1)")
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundStyle(selected ? Color.primary : Color.secondary)
                .frame(width: 40, height: 40)
                .background(Color(uiColor: selected ? .quaternarySystemFill : .tertiarySystemFill))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var customAnswerRow: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "pencil")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 40, height: 40)
                .background(Color(uiColor: .tertiarySystemFill))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            if rendersEditableField {
                TextField(
                    question.options.isEmpty ? L10n.text("回答を入力") : L10n.text("その他"),
                    text: customBinding
                )
                .font(.system(size: 16))
                .focused($customFieldFocused)
                .submitLabel(index == pending.questions.count - 1 ? .done : .next)
                .onSubmit { continueFlow() }
                .padding(.vertical, 9)
            } else {
                Text(question.options.isEmpty ? L10n.text("回答を入力") : L10n.text("その他"))
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 9)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(!draft.custom.isEmpty || customFieldFocused ? Color(uiColor: .tertiarySystemFill) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private static let customAnswerID = "ask-user-question-custom-answer"

    private var footer: some View {
        VStack(spacing: 6) {
            if let feedback {
                Text(feedback)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            HStack(spacing: 10) {
                Spacer(minLength: 0)
                Button(L10n.text("スキップ")) { skip() }
                    .buttonStyle(.bordered)
                    .tint(.secondary)
                Button(index == pending.questions.count - 1 ? L10n.text("回答") : L10n.text("次へ")) {
                    continueFlow()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!draft.isAnswered)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 12)
    }

    private var customBinding: Binding<String> {
        Binding(
            get: { drafts[index].custom },
            set: { value in
                drafts[index].custom = value
                drafts[index].skipped = false
                if !question.multiSelect { drafts[index].selected = [] }
                feedback = nil
            }
        )
    }

    private func pagerButton(
        _ systemName: String,
        label: String,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .medium))
                .frame(width: 32, height: 36)
        }
        .buttonStyle(.plain)
        .foregroundStyle(disabled ? Color.secondary.opacity(0.35) : Color.secondary)
        .disabled(disabled)
        .accessibilityLabel(Text(label))
    }

    private func choose(_ label: String) {
        if question.multiSelect {
            if let selectedIndex = drafts[index].selected.firstIndex(of: label) {
                drafts[index].selected.remove(at: selectedIndex)
            } else {
                drafts[index].selected.append(label)
            }
        } else {
            drafts[index].selected = [label]
            drafts[index].custom = ""
        }
        drafts[index].skipped = false
        feedback = nil
        if !question.multiSelect, index < pending.questions.count - 1 {
            move(to: index + 1)
        }
    }

    private func continueFlow() {
        guard draft.isAnswered else {
            feedback = L10n.text("回答を選択または入力してください。")
            return
        }
        if index < pending.questions.count - 1 {
            move(to: index + 1)
        } else {
            submit()
        }
    }

    private func skip() {
        drafts[index] = AskUserQuestionDraft(skipped: true)
        feedback = nil
        if index < pending.questions.count - 1 {
            move(to: index + 1)
        } else {
            submit()
        }
    }

    private func move(to nextIndex: Int) {
        index = min(max(nextIndex, 0), pending.questions.count - 1)
        customFieldFocused = false
        feedback = nil
    }

    private func submit() {
        guard let missing = drafts.firstIndex(where: { !$0.isComplete }) else {
            let answers = zip(pending.questions, drafts).map { question, value in
                let custom = value.custom.trimmingCharacters(in: .whitespacesAndNewlines)
                return AskUserQuestionAnswerItem(
                    id: question.id,
                    selected: value.skipped || (!question.multiSelect && !custom.isEmpty) ? [] : value.selected,
                    custom: value.skipped || custom.isEmpty ? nil : custom
                )
            }
            coordinator.answer(AskUserQuestionAnswer(answers: answers), requestID: pending.id)
            return
        }
        move(to: missing)
        feedback = L10n.text("未回答の質問があります。回答するかスキップしてください。")
    }

    static func recommendedDisplay(for label: String) -> (label: String, recommended: Bool) {
        let suffixes = ["(Recommended)", "（Recommended）", "(推奨)", "（推奨）"]
        for suffix in suffixes where label.lowercased().hasSuffix(suffix.lowercased()) {
            return (String(label.dropLast(suffix.count)).trimmingCharacters(in: .whitespaces), true)
        }
        return (label, false)
    }
}

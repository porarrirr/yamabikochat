import SwiftUI
import Photos
import PhotosUI
import UniformTypeIdentifiers
import UIKit
import ImageIO
import QuickLook

private let maximumPhotoSelectionCount = 10

private struct SpeechWaveformView: View {
    let levels: [Float]

    var body: some View {
        HStack(spacing: 2.5) {
            ForEach(Array(levels.enumerated()), id: \.offset) { _, level in
                Capsule()
                    .fill(Color.white.opacity(0.34 + (Double(level) * 0.56)))
                    .frame(
                        width: 3,
                        height: max(3, 3 + (CGFloat(level) * 27))
                    )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .animation(.linear(duration: 0.08), value: levels)
    }
}

enum ChatComposerFocusPolicy {
    static func focusState(current: Bool, isSending: Bool) -> Bool {
        isSending ? false : current
    }
}

enum ChatComposerSelectionPolicy {
    static let minimumEditorWidth: CGFloat = 120
    static let maximumSelectionWidthFraction: CGFloat = 0.5

    static func initialInput(for selectedText: String, preserving existingInput: String = "") -> String {
        selectedText + " " + existingInput
    }

    static func editableSuffix(in input: String, selectedText: String?) -> String {
        guard let selectedText, input.hasPrefix(selectedText) else { return input }
        return String(input.dropFirst(selectedText.count))
    }

    static func combinedInput(selectedText: String?, suffix: String) -> String {
        (selectedText ?? "") + suffix
    }

    static func accessibilityValue(selectedText: String?, suffix: String) -> String {
        guard let selectedText, suffix == " " else {
            return combinedInput(selectedText: selectedText, suffix: suffix)
        }
        return selectedText
    }

    static func editorWidth(totalWidth: CGFloat, selectedTextWidth: CGFloat?) -> CGFloat {
        guard totalWidth.isFinite, totalWidth > 0 else { return 0 }
        guard let selectedTextWidth else { return totalWidth }
        let iconAndSpacingWidth: CGFloat = 26
        let availableWidth = max(totalWidth - iconAndSpacingWidth, 0)
        let reservedEditorWidth = min(minimumEditorWidth, availableWidth)
        let maximumSelectionWidth = min(
            totalWidth * maximumSelectionWidthFraction,
            max(availableWidth - reservedEditorWidth, 0)
        )
        return max(totalWidth - iconAndSpacingWidth - min(selectedTextWidth, maximumSelectionWidth), 0)
    }
}

enum ChatComposerSynchronizationPolicy {
    enum Action: Equatable {
        case none
        case replaceText(moveCaretToEnd: Bool, endMarkedText: Bool)
        case moveCaretToEnd
    }

    static func action(
        isInitialConfiguration: Bool,
        hasMarkedText: Bool,
        isFirstResponder: Bool,
        isExternalChange: Bool,
        nativeTextMatchesBinding: Bool
    ) -> Action {
        if hasMarkedText {
            guard isExternalChange, !nativeTextMatchesBinding else { return .none }
            return .replaceText(moveCaretToEnd: true, endMarkedText: true)
        }
        if !nativeTextMatchesBinding, !isFirstResponder || isExternalChange {
            return .replaceText(
                moveCaretToEnd: isInitialConfiguration || (isExternalChange && isFirstResponder),
                endMarkedText: false
            )
        }
        return isInitialConfiguration && nativeTextMatchesBinding ? .moveCaretToEnd : .none
    }
}

struct ChatComposerTextView: UIViewRepresentable {
    @Environment(\.isEnabled) private var isEnabled
    @Binding var text: String
    @Binding var selectedText: String?
    @Binding var isFocused: Bool
    let placeholder: String

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> ComposerContainerView {
        let container = ComposerContainerView()
        container.textView.delegate = context.coordinator
        container.textView.onDeleteAtBeginning = { [weak coordinator = context.coordinator] in
            coordinator?.deleteSelectedText()
        }
        context.coordinator.lastReportedText = text
        configure(container, context: context, placeCursorAtEnd: true)
        return container
    }

    func updateUIView(_ container: ComposerContainerView, context: Context) {
        context.coordinator.parent = self
        // Preserve firstResponder across isEditable toggles to avoid spurious resign.
        if container.textView.isEditable != isEnabled {
            let wasFirstResponder = container.textView.isFirstResponder
            container.textView.isEditable = isEnabled
            if wasFirstResponder, isEnabled, !container.textView.isFirstResponder, isFocused {
                context.coordinator.requestFocus(for: container)
            }
        }
        configure(container, context: context, placeCursorAtEnd: false)

        if !isEnabled {
            context.coordinator.cancelFocusRequest()
            if container.textView.isFirstResponder {
                container.textView.resignFirstResponder()
            }
        } else if isFocused, !container.textView.isFirstResponder {
            context.coordinator.requestFocus(for: container)
        } else if !isFocused, container.textView.isFirstResponder {
            context.coordinator.cancelFocusRequest()
            container.textView.resignFirstResponder()
        }
    }

    static func dismantleUIView(_ uiView: ComposerContainerView, coordinator: Coordinator) {
        coordinator.cancelFocusRequest()
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiView: ComposerContainerView,
        context: Context
    ) -> CGSize? {
        guard let width = proposal.width, width.isFinite, width > 0 else { return nil }
        uiView.prepareForMeasurement(width: width)
        let fittingSize = uiView.textView.sizeThatFits(
            CGSize(width: width, height: .greatestFiniteMagnitude)
        )
        let lineHeight = uiView.textView.font?.lineHeight ?? 19
        return CGSize(width: width, height: min(max(fittingSize.height, lineHeight), lineHeight * 8))
    }

    private func configure(_ container: ComposerContainerView, context: Context, placeCursorAtEnd: Bool) {
        container.setSelectedText(selectedText)
        container.textView.placeholderLabel.text = placeholder
        let suffix = ChatComposerSelectionPolicy.editableSuffix(in: text, selectedText: selectedText)
        let isExternalChange = context.coordinator.lastReportedText != text
        let synchronizationAction = ChatComposerSynchronizationPolicy.action(
            isInitialConfiguration: placeCursorAtEnd,
            hasMarkedText: container.textView.markedTextRange != nil,
            isFirstResponder: container.textView.isFirstResponder,
            isExternalChange: isExternalChange,
            nativeTextMatchesBinding: container.textView.text == suffix
        )
        switch synchronizationAction {
        case let .replaceText(moveCaretToEnd, endMarkedText):
            context.coordinator.replaceNativeText(
                in: container.textView,
                with: suffix,
                fullText: text,
                moveCaretToEnd: moveCaretToEnd,
                endMarkedText: endMarkedText
            )
        case .moveCaretToEnd:
            let desiredRange = NSRange(location: (suffix as NSString).length, length: 0)
            if container.textView.selectedRange != desiredRange {
                container.textView.selectedRange = desiredRange
            }
        case .none:
            break
        }
        container.textView.placeholderLabel.isHidden = selectedText != nil || !suffix.isEmpty
        let accessibilityValue = ChatComposerSelectionPolicy.accessibilityValue(
            selectedText: selectedText,
            suffix: suffix
        )
        container.textView.accessibilityValue = accessibilityValue
        container.accessibilityValue = accessibilityValue
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: ChatComposerTextView
        var lastReportedText: String?
        private var focusRequest: DispatchWorkItem?
        private var isSynchronizingExternalText = false

        init(parent: ChatComposerTextView) {
            self.parent = parent
        }

        func requestFocus(for container: ComposerContainerView) {
            guard focusRequest == nil else { return }
            // If window is available, becomeFirstResponder synchronously to avoid stale Binding race.
            if container.window != nil,
               parent.isFocused,
               parent.isEnabled,
               container.textView.isEditable,
               container.textView.becomeFirstResponder() {
                return
            }
            let request = DispatchWorkItem { [weak self, weak container] in
                guard let self, let container else { return }
                self.focusRequest = nil
                guard self.parent.isFocused,
                      self.parent.isEnabled,
                      container.window != nil,
                      container.textView.isEditable else { return }
                container.textView.becomeFirstResponder()
            }
            focusRequest = request
            DispatchQueue.main.async(execute: request)
        }

        func cancelFocusRequest() {
            focusRequest?.cancel()
            focusRequest = nil
        }

        func replaceNativeText(
            in textView: UITextView,
            with suffix: String,
            fullText: String,
            moveCaretToEnd: Bool,
            endMarkedText: Bool
        ) {
            isSynchronizingExternalText = true
            defer { isSynchronizingExternalText = false }
            if endMarkedText {
                textView.unmarkText()
            }
            textView.text = suffix
            lastReportedText = fullText
            if moveCaretToEnd {
                textView.selectedRange = NSRange(
                    location: (suffix as NSString).length,
                    length: 0
                )
            }
        }

        func deleteSelectedText() {
            guard parent.selectedText != nil else { return }
            lastReportedText = ""
            parent.text = ""
            parent.selectedText = nil
            parent.isFocused = true
        }

        func textViewDidChange(_ textView: UITextView) {
            guard !isSynchronizingExternalText else { return }
            let suffix = textView.text ?? ""
            let combined = ChatComposerSelectionPolicy.combinedInput(
                selectedText: parent.selectedText,
                suffix: suffix
            )
            lastReportedText = combined
            parent.text = combined
            (textView as? ComposerTextView)?.placeholderLabel.isHidden = parent.selectedText != nil || !suffix.isEmpty
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            cancelFocusRequest()
            parent.isFocused = true
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            parent.isFocused = false
        }
    }

    final class ComposerTextView: UITextView {
        let placeholderLabel = UILabel()
        var onDeleteAtBeginning: (() -> Void)?

        override init(frame: CGRect, textContainer: NSTextContainer?) {
            super.init(frame: frame, textContainer: textContainer)
            backgroundColor = .clear
            font = .systemFont(ofSize: 16)
            textColor = .label
            tintColor = UIColor(Color.chatAccent)
            textContainerInset = .zero
            self.textContainer.lineFragmentPadding = 0
            isScrollEnabled = true
            keyboardDismissMode = .interactive
            placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
            placeholderLabel.font = .systemFont(ofSize: 16)
            placeholderLabel.textColor = .placeholderText
            addSubview(placeholderLabel)
            NSLayoutConstraint.activate([
                placeholderLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
                placeholderLabel.topAnchor.constraint(equalTo: topAnchor)
            ])
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func deleteBackward() {
            if text.isEmpty, let onDeleteAtBeginning {
                onDeleteAtBeginning()
                return
            }
            super.deleteBackward()
        }
    }

    final class ComposerContainerView: UIView {
        let textView = ComposerTextView()
        private let iconView = UIImageView()
        private let selectionLabel = UILabel()
        private let selectionContainer = UIView()
        private var selectedText: String?

        override init(frame: CGRect) {
            super.init(frame: frame)
            let focusRecognizer = UITapGestureRecognizer(target: self, action: #selector(focusTextView))
            focusRecognizer.cancelsTouchesInView = false
            addGestureRecognizer(focusRecognizer)

            let configuration = UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
            iconView.image = UIImage(systemName: "bubble.left", withConfiguration: configuration)
            iconView.tintColor = UIColor(Color.chatAccent)
            iconView.contentMode = .scaleAspectFit

            selectionLabel.font = .systemFont(ofSize: 16)
            selectionLabel.textColor = UIColor(Color.chatAccent)
            selectionLabel.numberOfLines = 1
            selectionLabel.lineBreakMode = .byTruncatingTail

            selectionContainer.isUserInteractionEnabled = false
            selectionContainer.addSubview(iconView)
            selectionContainer.addSubview(selectionLabel)
            addSubview(textView)
            addSubview(selectionContainer)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        func setSelectedText(_ selectedText: String?) {
            self.selectedText = selectedText
            let isHidden = selectedText == nil
            selectionContainer.isHidden = isHidden
            selectionLabel.text = selectedText?
                .replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: "\r", with: " ")
            setNeedsLayout()
        }

        func selectionWidth(for selectedText: String) -> CGFloat {
            let normalized = selectedText
                .replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: "\r", with: " ")
            let font = selectionLabel.font ?? UIFont.systemFont(ofSize: 16)
            let attributes: [NSAttributedString.Key: Any] = [.font: font]
            let size = (normalized as NSString).boundingRect(
                with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: attributes,
                context: nil
            ).size
            return ceil(size.width)
        }

        func prepareForMeasurement(width: CGFloat) {
            guard width.isFinite, width > 0 else { return }
            let measurementHeight = max(bounds.height, textView.font?.lineHeight ?? 19)
            bounds.size = CGSize(width: width, height: measurementHeight)
            setNeedsLayout()
            layoutIfNeeded()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            textView.frame = bounds

            guard let selectedText, !selectedText.isEmpty, bounds.width > 0 else {
                selectionContainer.frame = .zero
                textView.textContainer.exclusionPaths = []
                return
            }

            let iconWidth: CGFloat = 18
            let spacing: CGFloat = 4
            let naturalTextWidth = selectionWidth(for: selectedText)
            let editorWidth = ChatComposerSelectionPolicy.editorWidth(
                totalWidth: bounds.width,
                selectedTextWidth: naturalTextWidth
            )
            let prefixWidth = max(bounds.width - editorWidth, 0)
            let lineHeight = textView.font?.lineHeight ?? 19
            let labelWidth = max(prefixWidth - iconWidth - spacing, 0)

            selectionContainer.frame = CGRect(x: 0, y: 0, width: prefixWidth, height: lineHeight)
            iconView.frame = CGRect(x: 0, y: 0, width: iconWidth, height: lineHeight)
            selectionLabel.frame = CGRect(x: iconWidth + spacing, y: 0, width: labelWidth, height: lineHeight)

            // Reserve only the first line for the selection preview. The editor still
            // owns the full width, so subsequent question lines wrap across the card.
            textView.textContainer.exclusionPaths = [
                UIBezierPath(rect: CGRect(x: 0, y: 0, width: prefixWidth, height: lineHeight))
            ]
        }

        @objc private func focusTextView() {
            guard textView.isEditable, textView.isUserInteractionEnabled else { return }
            textView.becomeFirstResponder()
        }
    }
}

struct ChatScreen: View {
    @ObservedObject var viewModel: ChatViewModel
    @ObservedObject var questionCoordinator: UserQuestionCoordinator
    var onNavigateToConversation: ((Int64) -> Void)? = nil

    @Environment(\.scenePhase) private var scenePhase
    @State private var showFileImporter = false
    @State private var showPhotoPicker = false
    @State private var showRecentPhotoSheet = false
    @State private var showCameraPicker = false
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var isFollowingTail = true
    @State private var unreadCount = 0
    @State private var scrollToLatestRequest = 0
    @State private var workspaceRoute: ChatWorkspaceRoute?
    @State private var addingRecentPhotoIDs: Set<String> = []
    @State private var recentPhotoSelection = RecentPhotoSelection(limit: maximumPhotoSelectionCount)
    @State private var composerSelection: String?
    @StateObject private var recentPhotoLibrary = RecentPhotoLibrary()
    @State private var isComposerFocused = false
    @State private var isSoftwareKeyboardVisible = false
    @State private var isReasoningEffortPanelPresented = false

    var body: some View {
        VStack(spacing: 0) {
            ChatTimelineCollectionView(
                store: viewModel.timelineStore,
                isFollowingTail: $isFollowingTail,
                unreadCount: $unreadCount,
                scrollToLatestRequest: scrollToLatestRequest,
                regeneratableMessageID: viewModel.canRegenerateLastAssistant
                    ? viewModel.fullMessages.last?.id
                    : nil,
                mathRenderingEnabled: viewModel.settings.mathRenderingEnabled,
                fusionDebugModeEnabled: viewModel.settings.fusionDebugModeEnabled,
                dualSplitLayout: viewModel.settings.dualSplitLayout,
                dualSplitRatio: viewModel.settings.dualSplitRatio,
                fusionTraceForMessage: { viewModel.fusionTrace(for: $0) },
                onRoute: { workspaceRoute = $0 },
                onPreviousVariant: { viewModel.showPrevVariant(messageId: $0) },
                onNextVariant: { viewModel.showNextVariant(messageId: $0) },
                onBranch: { messageID in
                    guard let newID = viewModel.branchConversation(from: messageID) else { return }
                    onNavigateToConversation?(newID)
                },
                onRegenerate: { viewModel.regenerateLastAssistantVariant() },
                onAskChatWithSelection: { selectedText in
                    let existingInput = viewModel.inputText
                    composerSelection = selectedText
                    viewModel.inputText = ChatComposerSelectionPolicy.initialInput(
                        for: selectedText,
                        preserving: existingInput
                    )
                    DispatchQueue.main.async {
                        isComposerFocused = true
                    }
                }
            )
            .overlay {
                if viewModel.timelineStore.orderedIDs.isEmpty {
                    ChatEmptyState(
                        title: emptyStateTitle,
                        systemImage: emptyStateSystemImage,
                        description: emptyStateDescription
                    )
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if !isFollowingTail {
                    Button {
                        scrollToLatestRequest &+= 1
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.down")
                            if unreadCount > 0 {
                                Text("\(unreadCount)")
                                    .font(.caption.monospacedDigit().weight(.semibold))
                            }
                        }
                        .foregroundStyle(.primary)
                        .frame(minWidth: 44, minHeight: 44)
                        .padding(.horizontal, unreadCount > 0 ? 8 : 0)
                        .background(.regularMaterial, in: Capsule())
                        .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
                    }
                    .buttonStyle(.plain)
                    .padding(14)
                    .accessibilityLabel(Text(L10n.text("最新メッセージへ移動")))
                    .accessibilityIdentifier("chat-latest-button")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if !viewModel.attachments.isEmpty {
                AttachmentPreviewRow(
                    attachments: viewModel.attachments,
                    onRemove: { id in viewModel.removeAttachment(id: id) }
                )
                .padding(.horizontal, 14)
                .padding(.bottom, 4)
            }

            if !viewModel.chatStatsGroups.isEmpty {
                ChatStatsLine(groups: viewModel.chatStatsGroups)
                    .padding(.horizontal, 12)
                    .padding(.top, 5)
            }

            if let error = viewModel.errorMessage {
                ChatErrorToast(
                    formatted: UserFacingErrorFormatter.format(error),
                    onDismiss: { viewModel.clearErrorMessage() }
                )
                .id(error)
                .padding(.horizontal, 12)
                .padding(.top, 8)
            }

            composerBar
                .padding(.horizontal, 14)
                .padding(.top, 4)
                .padding(.bottom, 8)
                .background(Color.chatScreenBackground)
                .opacity(showsReasoningEffortPanel ? 0 : 1)
        }
        .background(Color.chatScreenBackground)
        .overlay {
            if showsReasoningEffortPanel,
               let configuration = viewModel.reasoningEffortConfiguration {
                reasoningEffortOverlay(configuration: configuration)
                    .transition(.opacity)
                    .zIndex(10)
            }
        }
        .onChange(of: viewModel.isSending) { _, isSending in
            isComposerFocused = ChatComposerFocusPolicy.focusState(
                current: isComposerFocused,
                isSending: isSending
            )
            if isSending {
                isReasoningEffortPanelPresented = false
            }
        }
        .onChange(of: isComposerFocused) { _, isFocused in
            if !isFocused {
                isReasoningEffortPanelPresented = false
            }
        }
        .onChange(of: viewModel.reasoningEffortConfiguration) { _, configuration in
            if configuration == nil {
                isReasoningEffortPanelPresented = false
            }
        }
        .onChange(of: viewModel.inputText) { _, inputText in
            guard let composerSelection else { return }
            if !inputText.hasPrefix(composerSelection) {
                self.composerSelection = nil
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            isSoftwareKeyboardVisible = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            isSoftwareKeyboardVisible = false
            isReasoningEffortPanelPresented = false
        }
        .task {
            recentPhotoLibrary.refresh()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            recentPhotoLibrary.refresh()
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.image, .pdf, .plainText, .utf8PlainText],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case let .success(urls):
                for url in urls {
                    viewModel.addAttachment(url: url)
                }
            case let .failure(error):
                viewModel.errorMessage = error.localizedDescription
            }
        }
        .photosPicker(
            isPresented: $showPhotoPicker,
            selection: $photoItems,
            maxSelectionCount: maximumPhotoSelectionCount,
            selectionBehavior: .ordered,
            matching: .images
        )
        .onChange(of: photoItems) { _, items in
            guard !items.isEmpty else { return }
            Task {
                await importSelectedPhotos(items)
            }
        }
        .sheet(isPresented: $showRecentPhotoSheet, onDismiss: {
            recentPhotoSelection.removeAll()
        }) {
            RecentPhotoSheet(
                library: recentPhotoLibrary,
                selection: $recentPhotoSelection,
                isAdding: !addingRecentPhotoIDs.isEmpty,
                onAddSelected: {
                    addSelectedRecentPhotos()
                },
                onOpenFullLibrary: {
                    openPhotoPicker()
                }
            )
            .presentationDetents([.fraction(0.55), .large])
            .presentationDragIndicator(.hidden)
            .presentationCornerRadius(26)
            .presentationBackground(Color.chatScreenBackground)
        }
        .fullScreenCover(isPresented: $showCameraPicker) {
            CameraPicker(isPresented: $showCameraPicker) { capturedImage in
                handleCapturedCameraImage(capturedImage)
            }
            .ignoresSafeArea()
        }
        .sheet(item: $workspaceRoute) { route in
            ChatWorkspaceRouteSheet(route: route)
        }
        .sheet(isPresented: Binding(
            get: { questionCoordinator.pending != nil },
            set: { _ in }
        )) {
            AskUserQuestionCard(coordinator: questionCoordinator)
                .padding(16)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    private var canSend: Bool {
        guard !isPreparingPhotoAttachments else { return false }
        return !viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !viewModel.attachments.isEmpty
    }

    private var isPreparingPhotoAttachments: Bool {
        !addingRecentPhotoIDs.isEmpty || !photoItems.isEmpty
    }

    private var emptyStateTitle: String {
        viewModel.isSecretConversation ? L10n.text("シークレットチャット") : L10n.text("会話がありません")
    }

    private var emptyStateSystemImage: String {
        viewModel.isSecretConversation ? "lock.shield" : "bubble.left.and.bubble.right"
    }

    private var emptyStateDescription: String {
        viewModel.isSecretConversation
            ? L10n.text("このチャットは別の会話を開くと破棄されます。")
            : L10n.text("メッセージを入力して会話を開始してください。")
    }

    private var isComposerExpanded: Bool {
        isComposerFocused || !viewModel.inputText.isEmpty || !viewModel.attachments.isEmpty
    }

    private var isSpeechRecordingBarPresented: Bool {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-showSpeechRecordingBarForScreenshots") {
            return true
        }
#endif
        return viewModel.isSpeechRecording
    }

    private var displayedSpeechAudioLevels: [Float] {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-showSpeechRecordingBarForScreenshots") {
            return [
                0.02, 0.04, 0.03, 0.05, 0.04, 0.07, 0.05, 0.08, 0.06,
                0.09, 0.12, 0.16, 0.22, 0.31, 0.48, 0.66, 0.88,
                0.62, 0.44, 0.35, 0.27, 0.21, 0.17, 0.12, 0.09,
                0.07, 0.06, 0.05, 0.04, 0.03, 0.04, 0.03, 0.02, 0.02
            ]
        }
#endif
        return viewModel.speechAudioLevels
    }

    private var isSpeechSendButtonEnabled: Bool {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-showSpeechRecordingBarForScreenshots") {
            return true
        }
#endif
        return canSend
    }

    private var showsReasoningEffortMeter: Bool {
        !viewModel.isSending && ChatReasoningEffortPresentationPolicy.showsMeter(
            isComposerFocused: isComposerFocused,
            isSoftwareKeyboardVisible: isSoftwareKeyboardVisible,
            configuration: viewModel.reasoningEffortConfiguration
        )
    }

    private var showsReasoningEffortPanel: Bool {
        isReasoningEffortPanelPresented && showsReasoningEffortMeter
    }

    private var composerBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            if viewModel.isSecretConversation {
                HStack(spacing: 5) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10, weight: .semibold))
                    Text(viewModel.composerContextLabel)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .font(.caption)
                .foregroundStyle(Color.chatAccent)
                .padding(.horizontal, 10)
            }

            if viewModel.showsAutoConversationStatusBanner,
               let status = viewModel.autoConversationStatus,
               !status.isEmpty {
                HStack(spacing: 5) {
                    Image(systemName: viewModel.isAutoConversationRunning ? "arrow.triangle.2.circlepath" : "pause.circle")
                        .font(.system(size: 10, weight: .semibold))
                    Text(status)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
            }

            if let fusionProgress = viewModel.fusionProgress {
                FusionProgressView(snapshot: fusionProgress)
            } else if let fusionStatus = viewModel.fusionAnalyzingStatus {
                HStack(spacing: 5) {
                    ProgressView()
                        .controlSize(.mini)
                    Text(fusionStatus)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
            }

            if !viewModel.skillAutocompleteSuggestions.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(viewModel.skillAutocompleteSuggestions.enumerated()), id: \.element.id) { index, skill in
                        Button {
                            viewModel.selectSkillAutocomplete(skill.name)
                            isComposerFocused = true
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "wand.and.stars")
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundStyle(Color.chatAccent)
                                    .frame(width: 24)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(skill.name)
                                        .font(.body.weight(.medium))
                                        .foregroundStyle(.primary)
                                    Text(skill.description)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 0)
                            }
                            .contentShape(Rectangle())
                            .padding(.horizontal, 14)
                            .padding(.vertical, 11)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("@\(skill.name)"))
                        .accessibilityIdentifier("chat-skill-suggestion-\(skill.name)")

                        if index < viewModel.skillAutocompleteSuggestions.count - 1 {
                            Divider().padding(.leading, 50)
                        }
                    }
                }
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color(uiColor: .separator).opacity(0.24), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.12), radius: 12, y: 5)
            }

            composerInputCard
        }
    }

    private var composerInputCard: some View {
        Group {
            if isSpeechRecordingBarPresented {
                speechRecordingBar
                    .transition(.scale(scale: 0.97).combined(with: .opacity))
            } else {
                standardComposerInputCard
                    .transition(.opacity)
            }
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.86), value: isSpeechRecordingBarPresented)
    }

    private var standardComposerInputCard: some View {
        VStack(spacing: 0) {
            HStack(alignment: isComposerExpanded ? .top : .center, spacing: isComposerExpanded ? 0 : 8) {
                composerPlusMenuButton
                    .opacity(isComposerExpanded ? 0 : 1)
                    .frame(width: isComposerExpanded ? 0 : nil, height: isComposerExpanded ? 0 : nil)
                    .clipped()
                    .allowsHitTesting(!isComposerExpanded)
                    .accessibilityHidden(isComposerExpanded)

                ChatComposerTextView(
                    text: $viewModel.inputText,
                    selectedText: $composerSelection,
                    isFocused: $isComposerFocused,
                    placeholder: viewModel.composerPlaceholder
                )
                    .id("chat.composer")
                    .accessibilityIdentifier("chat-composer")
                    .padding(.horizontal, isComposerExpanded ? 14 : 0)
                    .padding(.top, isComposerExpanded ? 12 : 9)
                    .padding(.bottom, isComposerExpanded ? 6 : 9)
                    .disabled(viewModel.isSpeechRecording || viewModel.isSending)
                    .transaction { transaction in transaction.animation = nil }
                    .animation(nil, value: isComposerExpanded)

                HStack(spacing: 6) {
                    if let contextUsage = viewModel.visibleContextUsage {
                        ContextUsageMeter(usage: contextUsage)
                    }
                    composerCollapsedVoiceButton
                }
                .opacity(isComposerExpanded ? 0 : 1)
                .frame(width: isComposerExpanded ? 0 : nil, height: isComposerExpanded ? 0 : nil)
                .clipped()
                .allowsHitTesting(!isComposerExpanded)
                .accessibilityHidden(isComposerExpanded)
            }
            .padding(.horizontal, isComposerExpanded ? 0 : 8)
            .padding(.vertical, isComposerExpanded ? 0 : 2)

            if isComposerExpanded {
                HStack(alignment: .center, spacing: 6) {
                    composerPlusMenuButton
                    Spacer(minLength: 4)
                    if let contextUsage = viewModel.visibleContextUsage {
                        ContextUsageMeter(usage: contextUsage)
                    }
                    if showsReasoningEffortMeter {
                        composerReasoningEffortButton
                    }
                    composerMicButton
                    composerExpandedSendButton
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 7)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: isComposerExpanded ? 22 : 26, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: isComposerExpanded ? 22 : 26, style: .continuous)
                .stroke(Color(uiColor: .separator).opacity(0.16), lineWidth: 1)
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: isComposerExpanded)
    }

    private var speechRecordingBar: some View {
        HStack(spacing: 10) {
            Button {
                viewModel.cancelSpeechRecognition()
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.13))
                        .frame(width: 34, height: 34)
                    Image(systemName: "xmark")
                        .font(.system(size: 23, weight: .medium))
                        .foregroundStyle(.white)
                }
                .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(L10n.text("音声入力をキャンセル")))
            .accessibilityIdentifier("chat-speech-cancel-button")

            SpeechWaveformView(levels: displayedSpeechAudioLevels)
                .frame(maxWidth: .infinity, minHeight: 32, maxHeight: 32)
                .accessibilityHidden(true)

            Button {
                viewModel.stopSpeechRecognition()
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.13))
                        .frame(width: 34, height: 34)
                    RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                        .fill(.white)
                        .frame(width: 17, height: 17)
                }
                .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(L10n.text("音声入力を停止")))
            .accessibilityIdentifier("chat-speech-stop-button")

            Button {
                isComposerFocused = false
                scrollToLatestRequest &+= 1
                viewModel.sendMessage()
            } label: {
                ZStack {
                    Circle()
                        .fill(.white)
                        .frame(width: 34, height: 34)
                    Image(systemName: "arrow.up")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.black)
                }
                .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .disabled(!isSpeechSendButtonEnabled)
            .opacity(isSpeechSendButtonEnabled ? 1 : 0.45)
            .accessibilityLabel(Text(L10n.text("音声入力を送信")))
            .accessibilityIdentifier("chat-speech-send-button")
        }
        .padding(.horizontal, 8)
        .frame(height: 56)
        .background(Color(uiColor: UIColor(white: 0.12, alpha: 1)))
        .clipShape(Capsule())
        .overlay {
            Capsule()
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.22), radius: 8, y: 3)
    }

    @ViewBuilder
    private var composerPlusMenuButton: some View {
        Menu {
            if viewModel.canAttachImages {
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button {
                        openCamera()
                    } label: {
                        Label(L10n.text("カメラ"), systemImage: "camera")
                    }
                }

                Button {
                    openRecentPhotosSheet()
                } label: {
                    Label(L10n.text("写真"), systemImage: "photo")
                }
            }
            Button {
                openFileImporter()
            } label: {
                Label(L10n.text("ファイル"), systemImage: "paperclip")
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isSending)
        .accessibilityLabel(Text("添付を追加"))
    }

    private var composerMicButton: some View {
        Button {
            viewModel.toggleSpeechRecognition()
        } label: {
            Image(systemName: viewModel.isSpeechRecording ? "mic.fill" : "mic")
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(viewModel.isSpeechRecording ? Color.red : Color.primary)
                .symbolEffect(.pulse, isActive: viewModel.isSpeechRecording)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isSending)
        .accessibilityLabel(Text("音声入力"))
    }

    @ViewBuilder
    private var composerReasoningEffortButton: some View {
        if let configuration = viewModel.reasoningEffortConfiguration {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
                    isReasoningEffortPanelPresented.toggle()
                }
            } label: {
                Image(systemName: ChatReasoningEffortPresentationPolicy.gaugeSymbolName(
                    selectedValue: configuration.selectedValue,
                    options: configuration.options
                ))
                .font(.system(size: 21, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("推論エフォート"))
            .accessibilityValue(Text(verbatim: configuration.selectedValue))
            .accessibilityIdentifier("chat-reasoning-effort-button")
        }
    }

    private func reasoningEffortOverlay(
        configuration: ChatReasoningEffortConfiguration
    ) -> some View {
        ZStack(alignment: .bottom) {
            Button {
                withAnimation(.easeOut(duration: 0.2)) {
                    isReasoningEffortPanelPresented = false
                }
            } label: {
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("推論エフォートを閉じる"))

            Rectangle()
                .fill(Color.black.opacity(0.12))
                .background(.ultraThinMaterial)
                .mask {
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.92), .black],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
                .frame(height: 250)
                .allowsHitTesting(false)

            ChatReasoningEffortPanel(
                configuration: configuration,
                onSelect: viewModel.setReasoningEffort
            )
            .padding(.horizontal, 18)
            .padding(.bottom, 12)
        }
    }

    private var composerCollapsedVoiceButton: some View {
        Button {
            viewModel.toggleSpeechRecognition()
        } label: {
            ZStack {
                Circle()
                    .fill(viewModel.isSpeechRecording ? Color.red : Color.chatOrange)
                    .frame(width: 44, height: 44)

                if viewModel.isSending {
                    ProgressView()
                        .tint(.white)
                        .controlSize(.small)
                } else {
                    Image(systemName: viewModel.isSpeechRecording ? "waveform" : "mic.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .symbolEffect(.pulse, isActive: viewModel.isSpeechRecording)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isSending)
        .accessibilityLabel(viewModel.isSending ? Text("生成中") : Text("音声入力"))
    }

    private var composerExpandedSendButton: some View {
        Button {
            if viewModel.isSending {
                viewModel.cancelActiveRun()
            } else if canSend {
                isComposerFocused = ChatComposerFocusPolicy.focusState(
                    current: isComposerFocused,
                    isSending: true
                )
                scrollToLatestRequest &+= 1
                viewModel.sendMessage()
            }
        } label: {
            ZStack {
                Circle()
                    .fill((canSend || viewModel.isSending) ? Color.primary : Color(uiColor: .tertiaryLabel))
                    .frame(width: 44, height: 44)

                if viewModel.isSending {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color(uiColor: .systemBackground))
                } else {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Color(uiColor: .systemBackground))
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(!viewModel.isSending && !canSend)
        .accessibilityLabel(viewModel.isSending ? Text("生成を停止") : Text("送信"))
        .accessibilityIdentifier("chat-send-button")
    }

    private struct ContextUsageMeter: View {
        let usage: ContextUsage
        @State private var showsDetails = false

        var body: some View {
            Button {
                showsDetails.toggle()
            } label: {
                HStack(spacing: 4) {
                    ZStack {
                        Circle()
                            .stroke(Color.chatComposerIcon.opacity(0.2), lineWidth: 2)
                        Circle()
                            .trim(from: 0, to: usage.fraction)
                            .stroke(Color.chatOrange, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                    }
                    .frame(width: 14, height: 14)

                    Text("\(usage.percent)%")
                        .font(.caption2.monospacedDigit().weight(.semibold))
                }
                .foregroundStyle(Color.chatComposerIcon)
                .frame(minWidth: 32, minHeight: 36)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(L10n.format("コンテキストの%d%%を使用中", usage.percent)))
            .popover(isPresented: $showsDetails) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.text("コンテキスト使用量"))
                        .font(.headline)
                    Text("\(usage.percent)%")
                        .font(.title2.monospacedDigit().bold())
                    Text(L10n.format(
                        "最新リクエスト: %@ / %@ token",
                        ChatStatsFormatter.tokens(Int64(usage.usedTokens)),
                        ChatStatsFormatter.tokens(Int64(usage.contextWindow))
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(16)
                .presentationCompactAdaptation(.popover)
            }
        }
    }

    private func importSelectedPhotos(_ items: [PhotosPickerItem]) async {
        var importedCount = 0
        var failedCount = 0

        for item in items {
            do {
                let attachment = try await loadTemporaryPhotoAttachment(from: item)
                let wasAdded = await MainActor.run {
                    viewModel.addAttachment(
                        url: attachment.url,
                        displayName: attachment.displayName,
                        deleteSourceWhenHandled: true
                    )
                }
                if wasAdded {
                    importedCount += 1
                } else {
                    failedCount += 1
                }
            } catch {
                failedCount += 1
                DiagnosticsLogger.log("Photos picker import failed", category: .chat, error: error)
            }
        }

        await MainActor.run {
            photoItems = []
            if failedCount > 0 {
                viewModel.errorMessage = importedCount == 0
                    ? L10n.text("写真を読み込めませんでした。")
                    : L10n.text("一部の写真を読み込めませんでした。")
            }
        }
    }

    private func loadTemporaryPhotoAttachment(
        from item: PhotosPickerItem
    ) async throws -> (url: URL, displayName: String) {
        guard let data = try await item.loadTransferable(type: Data.self) else {
            throw CocoaError(.fileReadUnknown)
        }
        let preferredExtension = item.supportedContentTypes
            .compactMap(\.preferredFilenameExtension)
            .first ?? "jpg"
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(preferredExtension)
        try data.write(to: fileURL)
        return (fileURL, "photo.\(preferredExtension)")
    }

    private func addSelectedRecentPhotos() {
        let itemsByID = Dictionary(
            uniqueKeysWithValues: recentPhotoLibrary.items.map { ($0.id, $0) }
        )
        let selectedItems = recentPhotoSelection.orderedIDs.compactMap { itemsByID[$0] }
        guard !selectedItems.isEmpty, addingRecentPhotoIDs.isEmpty else { return }

        addingRecentPhotoIDs.formUnion(selectedItems.map(\.id))
        Task {
            var importedCount = 0
            var failedCount = 0

            for item in selectedItems {
                do {
                    let fileURL = try await recentPhotoLibrary.exportFileURL(for: item.asset)
                    let wasAdded = await MainActor.run {
                        viewModel.addAttachment(
                            url: fileURL,
                            displayName: recentPhotoLibrary.suggestedFilename(for: item.asset),
                            deleteSourceWhenHandled: true
                        )
                    }
                    if wasAdded {
                        importedCount += 1
                    } else {
                        failedCount += 1
                    }
                } catch {
                    failedCount += 1
                    DiagnosticsLogger.log(
                        "Recent photo import failed asset=\(item.id)",
                        category: .chat,
                        error: error
                    )
                }
                await MainActor.run {
                    _ = addingRecentPhotoIDs.remove(item.id)
                }
            }

            await MainActor.run {
                recentPhotoSelection.removeAll()
                if importedCount > 0 {
                    showRecentPhotoSheet = false
                }
                if failedCount > 0 {
                    viewModel.errorMessage = importedCount == 0
                        ? L10n.text("写真を読み込めませんでした。")
                        : L10n.text("一部の写真を読み込めませんでした。")
                }
            }
        }
    }

    private func handleCapturedCameraImage(_ image: UIImage) {
        guard let data = image.jpegData(compressionQuality: 0.85) else { return }
        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".jpg")
        do {
            try data.write(to: temporaryURL)
            viewModel.addAttachment(
                url: temporaryURL,
                displayName: "photo.jpg",
                deleteSourceWhenHandled: true
            )
        } catch {
            DiagnosticsLogger.log("Camera image capture write failed", category: .chat, error: error)
            viewModel.errorMessage = L10n.text("写真を読み込めませんでした。")
        }
    }

    private func openAppSettings() {
        guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(settingsURL)
    }

    private func openRecentPhotosSheet() {
        isComposerFocused = false
        recentPhotoLibrary.refresh()
        showRecentPhotoSheet = true
    }

    private func openCamera() {
        isComposerFocused = false
        showCameraPicker = true
    }

    private func openPhotoPicker() {
        recentPhotoSelection.removeAll()
        showRecentPhotoSheet = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            showPhotoPicker = true
        }
    }

    private func openFileImporter() {
        isComposerFocused = false
        showFileImporter = true
    }

}

private struct ChatReasoningEffortPanel: View {
    let configuration: ChatReasoningEffortConfiguration
    let onSelect: (String) -> Void
    @State private var previewValue: String?

    private var displayedValue: String {
        ChatReasoningEffortPresentationPolicy.matchingOption(
            previewValue,
            in: configuration.options
        ) ?? configuration.selectedValue
    }

    var body: some View {
        VStack(spacing: 18) {
            Text(verbatim: "\(configuration.modelLabel)  \(displayedValue)")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .accessibilityIdentifier("chat-reasoning-effort-value")

            ChatDiscreteReasoningEffortSlider(
                options: configuration.options,
                selectedValue: displayedValue,
                onPreview: { previewValue = $0 },
                onCommit: { value in
                    onSelect(value)
                    previewValue = nil
                }
            )
        }
        .padding(.horizontal, 18)
        .padding(.top, 20)
        .padding(.bottom, 18)
        .sensoryFeedback(.selection, trigger: displayedValue)
    }
}

private struct ChatDiscreteReasoningEffortSlider: View {
    let options: [String]
    let selectedValue: String
    let onPreview: (String) -> Void
    let onCommit: (String) -> Void

    @State private var dragFraction: CGFloat?
    @State private var previewedIndex: Int?

    private let trackHeight: CGFloat = 72
    private let thumbDiameter: CGFloat = 58

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let horizontalInset = trackHeight / 2
            let selectedIndex = options.firstIndex(of: selectedValue) ?? 0
            let restingFraction = fraction(index: selectedIndex)
            let visualFraction = dragFraction ?? restingFraction
            let thumbCenterX = centerX(
                fraction: visualFraction,
                width: width,
                horizontalInset: horizontalInset
            )

            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(Color(uiColor: .tertiarySystemFill))

                Capsule(style: .continuous)
                    .fill(Color.primary)
                    .frame(
                        width: min(width, thumbCenterX + trackHeight / 2),
                        height: trackHeight
                    )

                ForEach(options.indices, id: \.self) { index in
                    let optionFraction = fraction(index: index)
                    Circle()
                        .fill(optionFraction <= visualFraction
                            ? Color(uiColor: .systemBackground).opacity(0.42)
                            : Color(uiColor: .secondaryLabel).opacity(0.5))
                        .frame(width: 8, height: 8)
                        .position(
                            x: centerX(
                                fraction: optionFraction,
                                width: width,
                                horizontalInset: horizontalInset
                            ),
                            y: trackHeight / 2
                        )
                }

                Circle()
                    .fill(Color(uiColor: .systemBackground))
                    .frame(width: thumbDiameter, height: thumbDiameter)
                    .overlay {
                        Circle()
                            .stroke(Color.primary, lineWidth: 3)
                    }
                    .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
                    .position(x: thumbCenterX, y: trackHeight / 2)
            }
            .frame(height: trackHeight)
            .contentShape(Capsule(style: .continuous))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        updateDrag(
                            at: value.location.x,
                            width: width,
                            horizontalInset: horizontalInset
                        )
                    }
                    .onEnded { value in
                        finishDrag(
                            at: value.location.x,
                            width: width,
                            horizontalInset: horizontalInset
                        )
                    }
            )
            .animation(
                dragFraction == nil ? .smooth(duration: 0.22) : nil,
                value: selectedValue
            )
        }
        .frame(height: trackHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("推論エフォート"))
        .accessibilityValue(Text(verbatim: selectedValue))
        .accessibilityAdjustableAction { direction in
            guard let currentIndex = options.firstIndex(of: selectedValue) else { return }
            let nextIndex: Int
            switch direction {
            case .increment:
                nextIndex = min(currentIndex + 1, options.count - 1)
            case .decrement:
                nextIndex = max(currentIndex - 1, 0)
            @unknown default:
                return
            }
            guard nextIndex != currentIndex else { return }
            withAnimation(.smooth(duration: 0.22)) {
                onCommit(options[nextIndex])
            }
        }
        .accessibilityIdentifier("chat-reasoning-effort-slider")
    }

    private func fraction(index: Int) -> CGFloat {
        guard options.count > 1 else { return 0.5 }
        return CGFloat(index) / CGFloat(options.count - 1)
    }

    private func centerX(fraction: CGFloat, width: CGFloat, horizontalInset: CGFloat) -> CGFloat {
        let usableWidth = max(width - horizontalInset * 2, 1)
        return horizontalInset + usableWidth * fraction
    }

    private func updateDrag(at locationX: CGFloat, width: CGFloat, horizontalInset: CGFloat) {
        guard let fraction = ChatReasoningEffortPresentationPolicy.sliderFraction(
            for: locationX,
            width: width,
            horizontalInset: horizontalInset
        ),
        let index = ChatReasoningEffortPresentationPolicy.optionIndex(
            for: locationX,
            width: width,
            optionCount: options.count,
            horizontalInset: horizontalInset
        ) else { return }

        let previousIndex = previewedIndex ?? options.firstIndex(of: selectedValue)
        dragFraction = fraction
        previewedIndex = index
        guard index != previousIndex else { return }
        onPreview(options[index])
    }

    private func finishDrag(at locationX: CGFloat, width: CGFloat, horizontalInset: CGFloat) {
        guard let index = ChatReasoningEffortPresentationPolicy.optionIndex(
            for: locationX,
            width: width,
            optionCount: options.count,
            horizontalInset: horizontalInset
        ) else {
            withAnimation(.smooth(duration: 0.22)) {
                dragFraction = nil
            }
            previewedIndex = nil
            return
        }

        let value = options[index]
        if previewedIndex != index {
            onPreview(value)
        }
        onCommit(value)
        previewedIndex = nil
        withAnimation(.smooth(duration: 0.22)) {
            dragFraction = nil
        }
    }
}

private struct AttachmentPreviewRow: View {
    let attachments: [AttachmentDraft]
    let onRemove: (UUID) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(attachments) { item in
                    if item.url.isImageAttachment {
                        ZStack(alignment: .topTrailing) {
                            AttachmentThumbnail(url: item.url, sideLength: 78)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(Color.chatBubbleBorder.opacity(0.35), lineWidth: 1)
                                }

                            Button {
                                onRemove(item.id)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 20, height: 20)
                                    .background(Color.black.opacity(0.6))
                                    .clipShape(Circle())
                                    .padding(4)
                            }
                            .buttonStyle(.plain)
                        }
                    } else {
                        HStack(spacing: 6) {
                            Image(systemName: "paperclip")
                                .font(.caption2)
                            Text(item.displayName)
                                .lineLimit(1)
                                .font(.caption)
                            Button {
                                onRemove(item.id)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.chatInputBackground)
                        .clipShape(Capsule())
                    }
                }
            }
        }
    }
}

struct ChatAttachmentItem: Identifiable, Equatable {
    let rawValue: String

    var id: String { rawValue }

    var url: URL? {
        if let parsedURL = URL(string: rawValue), parsedURL.scheme != nil {
            return parsedURL
        }
        return URL(fileURLWithPath: rawValue)
    }

    var displayName: String {
        guard let url else { return rawValue }
        return url.lastPathComponent.isEmpty ? rawValue : url.lastPathComponent
    }

    var isImage: Bool {
        guard let url else { return false }
        return url.isImageAttachment
    }

    var isSVG: Bool { url?.pathExtension.lowercased() == "svg" }
    var isHTML: Bool { ["html", "htm"].contains(url?.pathExtension.lowercased() ?? "") }
}

struct MessageAttachmentList: View {
    let attachments: [ChatAttachmentItem]
    let isOutgoing: Bool
    @State private var previewURL: URL?

    private var imageAttachments: [ChatAttachmentItem] {
        attachments.filter { $0.isImage && !$0.isSVG }
    }

    private var svgAttachments: [ChatAttachmentItem] {
        attachments.filter(\.isSVG)
    }

    private var htmlAttachments: [ChatAttachmentItem] {
        attachments.filter(\.isHTML)
    }

    private var fileAttachments: [ChatAttachmentItem] {
        attachments.filter { !$0.isImage && !$0.isHTML && !$0.isSVG }
    }

    private var horizontalAlignment: HorizontalAlignment {
        isOutgoing ? .trailing : .leading
    }

    private var frameAlignment: Alignment {
        isOutgoing ? .trailing : .leading
    }

    var body: some View {
        VStack(alignment: horizontalAlignment, spacing: 6) {
            if imageAttachments.count == 1, let attachment = imageAttachments.first,
               let url = attachment.url {
                AttachmentImageCard(
                    url: url,
                    displayName: attachment.displayName
                )
                .frame(maxWidth: .infinity, alignment: frameAlignment)
            } else if !imageAttachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(imageAttachments) { attachment in
                            if let url = attachment.url {
                                AttachmentImageCard(
                                    url: url,
                                    displayName: attachment.displayName
                                )
                            }
                        }
                    }
                }
                .defaultScrollAnchor(isOutgoing ? .trailing : .leading)
                .frame(maxWidth: .infinity, alignment: frameAlignment)
            }

            ForEach(svgAttachments) { attachment in
                if let url = attachment.url {
                    GeneratedSVGAttachmentCard(url: url, displayName: attachment.displayName)
                }
            }

            ForEach(htmlAttachments) { attachment in
                if let url = attachment.url {
                    GeneratedHTMLAttachmentCard(url: url, displayName: attachment.displayName)
                }
            }

            ForEach(fileAttachments) { attachment in
                if let url = attachment.url {
                    Button {
                        previewURL = url
                    } label: {
                        Label(attachment.displayName, systemImage: "doc")
                            .font(.caption)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(Color(uiColor: .secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: 300, alignment: frameAlignment)
                }
            }
        }
        .quickLookPreview($previewURL)
    }
}

private struct AttachmentImageCard: View {
    let url: URL
    let displayName: String
    @State private var previewURL: URL?

    var body: some View {
        Button {
            previewURL = url
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                AttachmentThumbnail(url: url, sideLength: 128)
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.chatBubbleBorder.opacity(0.45), lineWidth: 1)
                    }

                Text(displayName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: 128, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
        .quickLookPreview($previewURL)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L10n.format("添付画像: %@", displayName))
    }
}

private struct GeneratedSVGAttachmentCard: View {
    let url: URL
    let displayName: String

    @State private var content: String?
    @State private var loadFailed = false
    @State private var renderError: String?
    @State private var previewURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            attachmentHeader(icon: "photo", title: displayName, url: url) {
                previewURL = url
            }
            if let content {
                SvgPreviewWebView(svgContent: content, onError: { error in
                    renderError = error
                })
                .frame(maxWidth: .infinity)
                .frame(height: 240)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color(uiColor: .separator).opacity(0.4), lineWidth: 1)
                }
                if let renderError {
                    Text(renderError)
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
            } else if loadFailed {
                Text(L10n.text("SVGを読み込めませんでした"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 80)
            }
        }
        .generatedAttachmentCardStyle()
        .task(id: url.path) {
            content = Self.loadTextFile(url)
            loadFailed = content == nil
        }
        .quickLookPreview($previewURL)
    }

    private static func loadTextFile(_ url: URL) -> String? {
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size <= AppConstants.maxAttachmentSizeBytes else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }
}

private struct GeneratedHTMLAttachmentCard: View {
    let url: URL
    let displayName: String

    @State private var content: String?
    @State private var loadFailed = false
    @State private var pageTitle = ""
    @State private var isBrowserPresented = false
    @State private var previewURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            attachmentHeader(icon: "globe", title: displayName, url: url) {
                isBrowserPresented = content != nil
                if content == nil { previewURL = url }
            }
            if let content {
                HtmlPreviewWebView(html: content, pageTitle: $pageTitle)
                    .frame(maxWidth: .infinity)
                    .frame(height: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color(uiColor: .separator).opacity(0.4), lineWidth: 1)
                    }
            } else if loadFailed {
                Text(L10n.text("HTMLを読み込めませんでした"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 80)
            }
        }
        .generatedAttachmentCardStyle()
        .task(id: url.path) {
            content = Self.loadTextFile(url)
            loadFailed = content == nil
        }
        .sheet(isPresented: $isBrowserPresented) {
            if let content {
                HtmlPreviewBrowser(html: content, filename: displayName)
            }
        }
        .quickLookPreview($previewURL)
    }

    private static func loadTextFile(_ url: URL) -> String? {
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size <= AppConstants.maxAttachmentSizeBytes else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }
}

private func attachmentHeader(
    icon: String,
    title: String,
    url: URL,
    onOpen: @escaping () -> Void
) -> some View {
    HStack(spacing: 8) {
        Image(systemName: icon)
            .foregroundStyle(.secondary)
        Text(title)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
        Spacer(minLength: 8)
        ShareLink(item: url) {
            Image(systemName: "square.and.arrow.up")
                .font(.caption)
        }
        .buttonStyle(.plain)
        Button(action: onOpen) {
            Label(L10n.text("表示"), systemImage: "eye")
                .font(.caption)
        }
        .buttonStyle(.plain)
    }
}

private extension View {
    func generatedAttachmentCardStyle() -> some View {
        padding(10)
            .background(Color(uiColor: .secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color(uiColor: .separator).opacity(0.4), lineWidth: 1)
            }
    }
}


private struct AttachmentThumbnail: View {
    @Environment(\.displayScale) private var displayScale
    let url: URL
    let sideLength: CGFloat
    @State private var image: UIImage?
    @State private var didAttemptLoad = false

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if didAttemptLoad {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.chatInputBackground)
                    Image(systemName: "photo")
                        .foregroundStyle(.secondary)
                }
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.chatInputBackground)
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
        .frame(width: sideLength, height: sideLength)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .task(id: url.absoluteString) {
            guard image == nil else { return }
            image = await ImageThumbnailGenerator.thumbnail(
                for: url,
                maxPixelSize: Int(sideLength * displayScale * 1.6)
            )
            didAttemptLoad = true
        }
    }
}

private enum ImageThumbnailGenerator {
    private static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 160
        return cache
    }()

    static func thumbnail(for url: URL, maxPixelSize: Int) async -> UIImage? {
        let key = "\(url.path)_\(maxPixelSize)"
        if let cached = cache.object(forKey: key as NSString) { return cached }
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let result = generateThumbnail(for: url, maxPixelSize: maxPixelSize)
                if let result { cache.setObject(result, forKey: key as NSString) }
                continuation.resume(returning: result)
            }
        }
    }

    private static func generateThumbnail(for url: URL, maxPixelSize: Int) -> UIImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(maxPixelSize, 48),
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: image)
    }
}

private extension URL {
    var isImageAttachment: Bool {
        if let type = try? resourceValues(forKeys: [.contentTypeKey]).contentType,
           type.conforms(to: .image) {
            return true
        }
        let ext = pathExtension.lowercased()
        return ["jpg", "jpeg", "png", "gif", "webp", "bmp", "heic", "heif"].contains(ext)
    }
}

private struct ChatStatsLine: View {
    let groups: [String]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(Array(groups.enumerated()), id: \.offset) { index, group in
                    if index > 0 {
                        Text("|")
                            .foregroundStyle(.tertiary)
                    }
                    Text(group)
                }
            }
            .font(.caption2)
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: true, vertical: false)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, 10)
        }
        .frame(minHeight: 18)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(groups.joined(separator: ", ")))
    }
}

extension Color {
    static let chatScreenBackground = Color(uiColor: .systemBackground)
    static let chatInputBackground = Color(uiColor: .systemBackground)
    static let chatInputCardBackground = Color(uiColor: .secondarySystemBackground)
    static let chatInputChipBackground = Color(uiColor: .tertiarySystemFill)
    static let chatUserBubble = Color(uiColor: .secondarySystemFill)
    static let chatUserText = Color(uiColor: .label)
    static let chatAccent = Color(uiColor: .systemBlue)
    static let chatOrange = Color(red: 235 / 255, green: 94 / 255, blue: 40 / 255)
    static let chatDualCard = Color(uiColor: .secondarySystemBackground)
    static let chatComposerText = Color(uiColor: .label)
    static let chatComposerIcon = Color(uiColor: .secondaryLabel)
    static let chatAssistantBubble = Color(uiColor: .systemBackground)
    static let chatAssistantMark = Color(uiColor: .secondaryLabel)
    static let chatBubbleBorder = Color(uiColor: .separator)
    static let chatSendDisabled = Color(uiColor: .systemGray4)
}

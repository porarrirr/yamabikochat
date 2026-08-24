import SwiftUI
import Photos
import PhotosUI
import UniformTypeIdentifiers
import UIKit
import ImageIO
import QuickLook

enum ChatTimelineItem: Identifiable, Equatable {
    case message(FullChatMessage)
    case dual(DualChatMessage)

    var id: String {
        switch self {
        case let .message(item):
            return "m-\(item.id)"
        case let .dual(item):
            return "d-\(item.id ?? 0)"
        }
    }

    var createdAtMs: Int64 {
        switch self {
        case let .message(item):
            return item.message.createdAtMs
        case let .dual(item):
            return item.createdAtMs
        }
    }
}

struct ChatTimelineSnapshot: Equatable {
    let items: [ChatTimelineItem]

    init(messages: [FullChatMessage], dualMessages: [DualChatMessage]) {
        items = (messages.map(ChatTimelineItem.message) + dualMessages.map(ChatTimelineItem.dual))
            .sorted { $0.createdAtMs < $1.createdAtMs }
    }
}

private struct ChatBottomAnchorMaxYPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = .infinity

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private let chatTimelineHorizontalPadding: CGFloat = 20
private let chatTimelineVerticalPadding: CGFloat = 24
private let maximumPhotoSelectionCount = 10

struct ChatScreen: View {
    @ObservedObject var viewModel: ChatViewModel
    var onNavigateToConversation: ((Int64) -> Void)? = nil

    @Environment(\.scenePhase) private var scenePhase
    @State private var showFileImporter = false
    @State private var showPhotoPicker = false
    @State private var showRecentPhotoSheet = false
    @State private var showCameraPicker = false
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var isUserNearBottom = true
    @State private var bottomAnchorMaxY: CGFloat = .infinity
    @State private var isUserDraggingScroll = false
    @State private var scrollInteractionToken = 0
    @State private var addingRecentPhotoIDs: Set<String> = []
    @State private var recentPhotoSelection = RecentPhotoSelection(limit: maximumPhotoSelectionCount)
    @StateObject private var recentPhotoLibrary = RecentPhotoLibrary()
    @FocusState private var isComposerFocused: Bool
    private let bottomAnchorID = "chat-bottom-anchor"
    private let scrollCoordinateSpace = "chat-scroll-coordinate-space"
    private let bottomProximityThreshold: CGFloat = 96

    private var timeline: [ChatTimelineItem] {
        ChatTimelineSnapshot(
            messages: viewModel.fullMessages,
            dualMessages: viewModel.dualMessages
        ).items
    }

    var body: some View {
        GeometryReader { rootGeometry in
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    GeometryReader { scrollGeometry in
                        let measuredWidth = rootGeometry.size.width
                        let timelineWidth = max(measuredWidth - chatTimelineHorizontalPadding * 2, 0)
                        let timelineMinHeight = max(scrollGeometry.size.height - chatTimelineVerticalPadding * 2, 0)

                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 24) {
                                if timeline.isEmpty {
                                    ContentUnavailableView(
                                        emptyStateTitle,
                                        systemImage: emptyStateSystemImage,
                                        description: Text(emptyStateDescription)
                                    )
                                    .frame(maxWidth: .infinity)
                                    .padding(.top, 56)
                                } else {
                                    ForEach(timeline) { item in
                                        switch item {
                                        case let .message(message):
                                            MessageBubble(
                                                message: message,
                                                rowWidth: timelineWidth,
                                                mathRenderingEnabled: viewModel.settings.mathRenderingEnabled,
                                                streamingSnapshot: viewModel.streamingSnapshot(for: message.id),
                                                isActivelyStreaming: viewModel.isMessageStreaming(message.id),
                                                canRegenerate: viewModel.canRegenerateLastAssistant && message.id == viewModel.fullMessages.last?.id,
                                                fusionDebugModeEnabled: viewModel.settings.fusionDebugModeEnabled,
                                                fusionTrace: viewModel.fusionTrace(for: message.message),
                                                onPrevVariant: { viewModel.showPrevVariant(messageId: message.id) },
                                                onNextVariant: { viewModel.showNextVariant(messageId: message.id) },
                                                onCopy: {
                                                    UIPasteboard.general.string = message.displayText
                                                },
                                                onBranch: {
                                                    guard let newConversationId = viewModel.branchConversation(from: message.id) else { return }
                                                    onNavigateToConversation?(newConversationId)
                                                },
                                                onRegenerate: {
                                                    viewModel.regenerateLastAssistantVariant()
                                                }
                                            )
                                            .equatable()
                                            .id(item.id)
                                        case let .dual(message):
                                            DualMessageCard(
                                                message: message,
                                                rowWidth: timelineWidth,
                                                settings: viewModel.settings,
                                                mathRenderingEnabled: viewModel.settings.mathRenderingEnabled
                                            )
                                            .equatable()
                                            .id(item.id)
                                        }
                                    }
                                }

                                Color.clear
                                    .frame(height: 1)
                                    .id(bottomAnchorID)
                                    .background {
                                        GeometryReader { anchorGeometry in
                                            Color.clear.preference(
                                                key: ChatBottomAnchorMaxYPreferenceKey.self,
                                                value: anchorGeometry.frame(in: .named(scrollCoordinateSpace)).maxY
                                            )
                                        }
                                    }
                            }
                            .frame(width: timelineWidth, alignment: .topLeading)
                            .frame(
                                minHeight: timeline.isEmpty ? nil : timelineMinHeight,
                                alignment: .topLeading
                            )
                            .scrollTargetLayout()
                            .padding(.horizontal, chatTimelineHorizontalPadding)
                            .padding(.vertical, chatTimelineVerticalPadding)
                        }
                        .coordinateSpace(name: scrollCoordinateSpace)
                        .background(Color.chatScreenBackground)
                        .overlay(alignment: .bottomTrailing) {
                            if !isUserNearBottom {
                                Button {
                                    scrollToBottom(proxy: proxy, animated: true)
                                } label: {
                                    Image(systemName: "arrow.down")
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(.primary)
                                        .frame(width: 42, height: 42)
                                        .background(.regularMaterial, in: Circle())
                                        .shadow(color: .black.opacity(0.14), radius: 5, y: 2)
                                }
                                .buttonStyle(.plain)
                                .padding(.trailing, 14)
                                .padding(.bottom, 12)
                                .accessibilityLabel(Text(L10n.text("最新メッセージへ移動")))
                            }
                        }
                        .scrollDismissesKeyboard(.interactively)
                        .simultaneousGesture(
                            TapGesture().onEnded {
                                dismissComposerChrome()
                            }
                        )
                        .simultaneousGesture(
                            DragGesture(minimumDistance: 8)
                                .onChanged { _ in
                                    beginScrollInteraction()
                                }
                                .onEnded { _ in
                                    endScrollInteraction()
                                }
                        )
                        .onPreferenceChange(ChatBottomAnchorMaxYPreferenceKey.self) { maxY in
                            handleBottomAnchorChange(
                                maxY: maxY,
                                viewportHeight: scrollGeometry.size.height,
                                proxy: proxy
                            )
                        }
                        .onAppear {
                            isUserNearBottom = true
                            scrollToBottom(proxy: proxy, animated: false)
                        }
                        .onChange(of: timeline.count) { _, _ in
                            scrollToBottomIfNeeded(proxy: proxy)
                        }
                        .onChange(of: viewModel.streamingSnapshots) { _, _ in
                            scrollToBottomIfNeeded(proxy: proxy, animated: false)
                        }
                        .onChange(of: isComposerFocused) { _, focused in
                            guard !focused else { return }
                            scrollToBottomIfNeeded(proxy: proxy)
                        }
                        .onChange(of: viewModel.isSending) { oldValue, newValue in
                            guard !oldValue, newValue else { return }
                            scrollToBottom(proxy: proxy, animated: true)
                        }
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
            }
            .frame(width: rootGeometry.size.width, height: rootGeometry.size.height)
            .background(Color.chatScreenBackground)
        }
        .background(Color.chatScreenBackground)
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
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(viewModel.skillAutocompleteSuggestions, id: \.self) { name in
                            Button("$\(name)") { viewModel.selectSkillAutocomplete(name) }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                        }
                    }
                    .padding(.horizontal, 10)
                }
            }

            composerInputCard
        }
    }

    private var composerInputCard: some View {
        VStack(spacing: 0) {
            HStack(alignment: isComposerExpanded ? .top : .center, spacing: 8) {
                if !isComposerExpanded {
                    composerPlusMenuButton
                }

                TextField(viewModel.composerPlaceholder, text: $viewModel.inputText, axis: .vertical)
                    .lineLimit(isComposerExpanded ? 8 : 1)
                    .focused($isComposerFocused)
                    .font(.system(size: 16))
                    .padding(.horizontal, isComposerExpanded ? 14 : 0)
                    .padding(.top, isComposerExpanded ? 12 : 9)
                    .padding(.bottom, isComposerExpanded ? 6 : 9)
                    .foregroundStyle(Color.chatComposerText)
                    .tint(Color.chatOrange)
                    .disabled(viewModel.isSpeechRecording || viewModel.isSending)

                if !isComposerExpanded {
                    if let contextUsage = viewModel.visibleContextUsage {
                        ContextUsageMeter(usage: contextUsage)
                    }

                    composerCollapsedVoiceButton
                }
            }
            .padding(.horizontal, isComposerExpanded ? 0 : 8)
            .padding(.vertical, isComposerExpanded ? 0 : 2)

            if isComposerExpanded {
                HStack(alignment: .center, spacing: 8) {
                    composerPlusMenuButton

                    Spacer(minLength: 4)

                    if let contextUsage = viewModel.visibleContextUsage {
                        ContextUsageMeter(usage: contextUsage)
                    }

                    composerMicButton

                    composerExpandedSendButton
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .background(Color.chatInputCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: isComposerExpanded ? 22 : 26, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: isComposerExpanded ? 22 : 26, style: .continuous)
                .stroke(Color.chatBubbleBorder.opacity(0.14), lineWidth: 1)
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: isComposerExpanded)
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
                .foregroundStyle(Color.chatComposerIcon)
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
                .foregroundStyle(viewModel.isSpeechRecording ? Color.red : Color.chatComposerIcon)
                .symbolEffect(.pulse, isActive: viewModel.isSpeechRecording)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isSending)
        .accessibilityLabel(Text("音声入力"))
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
                viewModel.sendMessage()
            }
        } label: {
            ZStack {
                Circle()
                    .fill((canSend || viewModel.isSending) ? Color.chatOrange : Color.chatSendDisabled)
                    .frame(width: 44, height: 44)

                if viewModel.isSending {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                } else {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(!viewModel.isSending && !canSend)
        .accessibilityLabel(viewModel.isSending ? Text("生成を停止") : Text("送信"))
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

    private func dismissComposerChrome() {
        isComposerFocused = false
    }

    private func beginScrollInteraction() {
        isUserDraggingScroll = true
        scrollInteractionToken += 1
    }

    private func endScrollInteraction() {
        scrollInteractionToken += 1
        let token = scrollInteractionToken
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            guard scrollInteractionToken == token else { return }
            isUserDraggingScroll = false
        }
    }

    private func handleBottomAnchorChange(maxY: CGFloat, viewportHeight: CGFloat, proxy _: ScrollViewProxy) {
        bottomAnchorMaxY = maxY
        updateIsUserNearBottom(bottomAnchorMaxY: maxY, viewportHeight: viewportHeight)
    }

    private func updateIsUserNearBottom(bottomAnchorMaxY: CGFloat, viewportHeight: CGFloat) {
        isUserNearBottom = timeline.isEmpty || bottomAnchorMaxY <= viewportHeight + bottomProximityThreshold
    }

    private func scrollToBottomIfNeeded(proxy: ScrollViewProxy, animated: Bool = true) {
        guard ChatScrollPolicy.shouldFollowContentGrowth(
            isNearBottom: isUserNearBottom,
            isUserInteracting: isUserDraggingScroll
        ) else { return }
        DispatchQueue.main.async {
            scrollToBottom(proxy: proxy, animated: animated)
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy, animated: Bool) {
        let scrollAction = {
            proxy.scrollTo(bottomAnchorID, anchor: .bottom)
            isUserNearBottom = true
        }
        if animated {
            withAnimation {
                scrollAction()
            }
        } else {
            scrollAction()
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

private struct ChatAttachmentItem: Identifiable, Equatable {
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

private struct MessageAttachmentList: View {
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
                SvgPreviewWebView(svgContent: content) { error in
                    renderError = error
                }
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

private struct MessageBubble: View, Equatable {
    let message: FullChatMessage
    let rowWidth: CGFloat
    let mathRenderingEnabled: Bool
    let streamingSnapshot: ChatStreamingSnapshot?
    let isActivelyStreaming: Bool
    let canRegenerate: Bool
    let fusionDebugModeEnabled: Bool
    let fusionTrace: FusionTrace?
    let onPrevVariant: () -> Void
    let onNextVariant: () -> Void
    let onCopy: () -> Void
    let onBranch: () -> Void
    let onRegenerate: () -> Void
    @State private var isThinkingSheetPresented = false
    @State private var isFusionDetailPresented = false

    static func == (lhs: MessageBubble, rhs: MessageBubble) -> Bool {
        lhs.message == rhs.message &&
            lhs.rowWidth == rhs.rowWidth &&
            lhs.mathRenderingEnabled == rhs.mathRenderingEnabled &&
            lhs.streamingSnapshot == rhs.streamingSnapshot &&
            lhs.isActivelyStreaming == rhs.isActivelyStreaming &&
            lhs.canRegenerate == rhs.canRegenerate &&
            lhs.fusionDebugModeEnabled == rhs.fusionDebugModeEnabled &&
            lhs.fusionTrace == rhs.fusionTrace
    }

    private var isUser: Bool {
        message.message.role == "user"
    }

    private var responseText: String {
        if let overlay = streamingSnapshot?.text, !overlay.isEmpty {
            return overlay
        }
        return message.displayText
    }

    private var thinkingText: String? {
        if let overlay = streamingSnapshot?.thinking.trimmingCharacters(in: .whitespacesAndNewlines),
           !overlay.isEmpty {
            return overlay
        }
        guard let value = message.displayThinkingStream?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !value.isEmpty
        else {
            return nil
        }
        return value
    }

    private var attachmentItems: [ChatAttachmentItem] {
        guard let data = message.displayAttachmentsJSON.data(using: .utf8),
              let values = try? JSONDecoder().decode([String].self, from: data)
        else {
            return []
        }
        return values.map { ChatAttachmentItem(rawValue: $0) }
    }

    private var toolActivitySteps: [ToolActivityStep] {
        if let live = streamingSnapshot?.toolActivity?.steps, !live.isEmpty {
            return live
        }
        return message.displayToolActivity?.steps ?? []
    }

    private var toolSources: [ToolSource] {
        var seen: Set<String> = []
        return toolActivitySteps
            .flatMap(\.sources)
            .filter { seen.insert($0.url).inserted }
    }

    var body: some View {
        let userContentWidth = min(300, rowWidth)
        let userLeadingWidth = max(rowWidth - userContentWidth, 0)

        HStack(alignment: .top, spacing: 0) {
            if isUser {
                Spacer(minLength: userLeadingWidth)
            }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 8) {
                if isUser {
                    if !attachmentItems.isEmpty {
                        MessageAttachmentList(
                            attachments: attachmentItems,
                            isOutgoing: true
                        )
                    }

                    if !responseText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(responseText)
                            .textSelection(.enabled)
                            .foregroundStyle(Color.chatUserText)
                            .font(.body)
                            .lineSpacing(2)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(Color.chatUserBubble)
                            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }
                } else {
                    if !toolActivitySteps.isEmpty {
                        ToolActivityDisclosure(steps: toolActivitySteps)
                    }

                    if thinkingText != nil {
                        Button {
                            isThinkingSheetPresented = true
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "brain.head.profile")
                                    .font(.caption)
                                Text("Thinking")
                                    .font(.caption)
                                Spacer()
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.caption2)
                            }
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    }

                    let isChatError = UserFacingErrorFormatter.looksLikeChatError(responseText)
                    let svgBlocks = isChatError ? [] : SvgCodeExtractor.extract(from: responseText)
                    let htmlBlocks = HtmlPreviewPolicy.blocks(
                        from: responseText,
                        isChatError: isChatError,
                        isActivelyStreaming: isActivelyStreaming
                    )
                    let mediaBlocks = (
                        svgBlocks.map(ExtractedMediaBlock.svg) +
                        htmlBlocks.map(ExtractedMediaBlock.html)
                    ).sorted { $0.startIndex < $1.startIndex }
                    let markdownText = isChatError
                        ? ""
                        : ExtractedFenceRemover.remove(
                            from: responseText,
                            ranges: mediaBlocks.map { (start: $0.startIndex, end: $0.endIndex) }
                        )
                    let hasAssistantBubbleContent = isChatError
                        || !attachmentItems.isEmpty
                        || !mediaBlocks.isEmpty
                        || !markdownText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

                    if hasAssistantBubbleContent {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(Color.chatAssistantMark)
                                .frame(width: 32, height: 32)
                                .background(Color.chatInputChipBackground)
                                .clipShape(Circle())
                                .padding(.top, 2)

                            VStack(alignment: .leading, spacing: 10) {
                                if !attachmentItems.isEmpty {
                                    MessageAttachmentList(
                                        attachments: attachmentItems,
                                        isOutgoing: false
                                    )
                                }

                                if isChatError {
                                    ChatErrorCard(text: responseText)
                                } else {
                                    if !mediaBlocks.isEmpty {
                                        ForEach(mediaBlocks) { block in
                                            switch block {
                                            case .html(let htmlBlock):
                                                HtmlPreviewCard(block: htmlBlock)
                                            case .svg(let svgBlock):
                                                SvgPreviewCard(block: svgBlock)
                                            }
                                        }
                                    }

                                    if !markdownText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                        MathMarkdownView(
                                            markdownText: markdownText,
                                            mathRenderingEnabled: mathRenderingEnabled,
                                            isStreaming: isActivelyStreaming
                                        )
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    if let fusionTrace, !isActivelyStreaming {
                        FusionMessageSummary(trace: fusionTrace) {
                            isFusionDetailPresented = true
                        }
                    }

                    if message.variantCount > 1 {
                        HStack(spacing: 10) {
                            Button {
                                onPrevVariant()
                            } label: {
                                Image(systemName: "chevron.left")
                                    .font(.caption.weight(.semibold))
                            }
                            .buttonStyle(.plain)
                            .disabled(!message.canSelectPreviousVariant)

                            Text("\(message.selectedVariantOrdinal)/\(message.variantCount)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()

                            Button {
                                onNextVariant()
                            } label: {
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                            }
                            .buttonStyle(.plain)
                            .disabled(!message.canSelectNextVariant)
                        }
                        .padding(.horizontal, 4)
                        .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(width: isUser ? userContentWidth : rowWidth, alignment: isUser ? .trailing : .leading)

            if !isUser {
                Spacer(minLength: 0)
            }
        }
        .frame(width: rowWidth, alignment: isUser ? .trailing : .leading)
        .modifier(MessageBubbleContextMenuModifier(
            isEnabled: !isActivelyStreaming,
            canRegenerate: canRegenerate,
            showsFusionDetail: fusionTrace != nil,
            onCopy: onCopy,
            onBranch: onBranch,
            onRegenerate: onRegenerate,
            onShowFusionDetail: { isFusionDetailPresented = true }
        ))
        .sheet(isPresented: $isThinkingSheetPresented) {
            if let thinkingText {
                ThinkingSheet(thinkingText: thinkingText)
            }
        }
        .sheet(isPresented: $isFusionDetailPresented) {
            if let fusionTrace {
                FusionDetailSheet(
                    trace: fusionTrace,
                    debugModeEnabled: fusionDebugModeEnabled
                )
            }
        }
    }
}

private struct DualMessageCard: View, Equatable {
    let message: DualChatMessage
    let rowWidth: CGFloat
    let settings: AppSettings
    let mathRenderingEnabled: Bool
    @State private var showThinkingA = false
    @State private var showThinkingB = false

    static func == (lhs: DualMessageCard, rhs: DualMessageCard) -> Bool {
        lhs.message == rhs.message &&
            lhs.rowWidth == rhs.rowWidth &&
            lhs.settings == rhs.settings &&
            lhs.mathRenderingEnabled == rhs.mathRenderingEnabled
    }

    private var resolvedLayout: String {
        let normalized = settings.dualSplitLayout.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return normalized == "HORIZONTAL" ? "HORIZONTAL" : "VERTICAL"
    }

    private var splitRatio: Double {
        if settings.dualSplitRatio.isNaN || !settings.dualSplitRatio.isFinite {
            return 0.5
        }
        return min(max(settings.dualSplitRatio, 0.1), 0.9)
    }

    private var modelAText: String {
        message.modelAText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var modelBText: String {
        message.modelBText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var userText: String {
        message.userText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var attachmentItems: [ChatAttachmentItem] {
        message.attachments.map { ChatAttachmentItem(rawValue: $0) }
    }

    var body: some View {
        let userContentWidth = min(300, rowWidth)
        let userLeadingWidth = max(rowWidth - userContentWidth, 0)

        Group {
            switch message.parsedRole {
            case .user:
                HStack(alignment: .top, spacing: 0) {
                    Spacer(minLength: userLeadingWidth)

                    VStack(alignment: .trailing, spacing: 8) {
                        if !attachmentItems.isEmpty {
                            MessageAttachmentList(
                                attachments: attachmentItems,
                                isOutgoing: true
                            )
                        }
                        if !userText.isEmpty {
                            Text(userText)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(12)
                    .background(Color.chatUserBubble)
                    .foregroundStyle(Color.chatUserText)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .frame(width: userContentWidth, alignment: .trailing)
                }
                .frame(width: rowWidth, alignment: .trailing)
            case .dualModel:
                VStack(alignment: .leading, spacing: 10) {
                    DualSplitContainer(
                        layout: resolvedLayout,
                        splitRatio: splitRatio
                    ) {
                        DualResponsePane(
                            title: "A · \(ProviderCatalog.displayName(for: message.providerA)) · \(message.modelAName)",
                            content: modelAText,
                            status: message.parsedModelAStatus,
                            error: message.modelAError,
                            thinking: message.modelAThinking,
                            toolSteps: message.modelAToolActivity?.steps ?? [],
                            attachments: message.modelAToolActivity?.attachmentPaths.map { ChatAttachmentItem(rawValue: $0) } ?? [],
                            showThinking: $showThinkingA,
                            mathRenderingEnabled: mathRenderingEnabled
                        )
                    } second: {
                        DualResponsePane(
                            title: "B · \(ProviderCatalog.displayName(for: message.providerB)) · \(message.modelBName)",
                            content: modelBText,
                            status: message.parsedModelBStatus,
                            error: message.modelBError,
                            thinking: message.modelBThinking,
                            toolSteps: message.modelBToolActivity?.steps ?? [],
                            attachments: message.modelBToolActivity?.attachmentPaths.map { ChatAttachmentItem(rawValue: $0) } ?? [],
                            showThinking: $showThinkingB,
                            mathRenderingEnabled: mathRenderingEnabled
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color.chatDualCard)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .frame(width: rowWidth, alignment: .leading)
            case .legacy:
                VStack(alignment: .leading, spacing: 10) {
                    if !userText.isEmpty {
                        Text(userText)
                            .font(.body)
                    }
                    Divider()
                    Text("A · \(ProviderCatalog.displayName(for: message.providerA)) · \(message.modelAName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if UserFacingErrorFormatter.looksLikeChatError(modelAText) {
                        ChatErrorCard(text: modelAText)
                    } else {
                        Text(modelAText)
                            .textSelection(.enabled)
                    }
                    Divider()
                    Text("B · \(ProviderCatalog.displayName(for: message.providerB)) · \(message.modelBName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if UserFacingErrorFormatter.looksLikeChatError(modelBText) {
                        ChatErrorCard(text: modelBText)
                    } else {
                        Text(modelBText)
                            .textSelection(.enabled)
                    }
                }
                .padding(12)
                .background(Color.chatDualCard)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .frame(width: rowWidth, alignment: .leading)
            }
        }
    }
}

private struct DualSplitContainer<First: View, Second: View>: View {
    let layout: String
    let splitRatio: Double
    let first: () -> First
    let second: () -> Second

    init(
        layout: String,
        splitRatio: Double,
        @ViewBuilder first: @escaping () -> First,
        @ViewBuilder second: @escaping () -> Second
    ) {
        self.layout = layout
        self.splitRatio = splitRatio
        self.first = first
        self.second = second
    }

    var body: some View {
        if layout == "HORIZONTAL" {
            VStack(alignment: .leading, spacing: 8) {
                first()
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                second()
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        } else {
            ViewThatFits(in: .horizontal) {
                DualRatioLayout(ratio: splitRatio, spacing: 8) {
                    first()
                    second()
                }
                VStack(alignment: .leading, spacing: 8) {
                    first()
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    second()
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
        }
    }
}

private struct DualRatioLayout: Layout {
    let ratio: Double
    let spacing: CGFloat
    private let minimumPaneWidth: CGFloat = 220

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        guard subviews.count == 2 else { return .zero }
        let minimumWidth = minimumPaneWidth * 2 + spacing
        let width = max(proposal.width ?? minimumWidth, minimumWidth)
        let paneWidths = resolvedPaneWidths(totalWidth: width)
        let firstSize = subviews[0].sizeThatFits(.init(width: paneWidths.0, height: proposal.height))
        let secondSize = subviews[1].sizeThatFits(.init(width: paneWidths.1, height: proposal.height))
        return CGSize(width: width, height: max(firstSize.height, secondSize.height))
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        guard subviews.count == 2 else { return }
        let paneWidths = resolvedPaneWidths(totalWidth: bounds.width)
        subviews[0].place(
            at: bounds.origin,
            anchor: .topLeading,
            proposal: .init(width: paneWidths.0, height: proposal.height)
        )
        subviews[1].place(
            at: CGPoint(x: bounds.minX + paneWidths.0 + spacing, y: bounds.minY),
            anchor: .topLeading,
            proposal: .init(width: paneWidths.1, height: proposal.height)
        )
    }

    private func resolvedPaneWidths(totalWidth: CGFloat) -> (CGFloat, CGFloat) {
        let available = max(0, totalWidth - spacing)
        let minimumRatio = available > 0 ? min(0.5, minimumPaneWidth / available) : 0.5
        let clampedRatio = min(max(CGFloat(ratio), minimumRatio), 1 - minimumRatio)
        return (available * clampedRatio, available * (1 - clampedRatio))
    }
}

private struct DualResponsePane: View {
    let title: String
    let content: String
    let status: DualChatMessage.SideStatus
    let error: String?
    let thinking: String?
    let toolSteps: [ToolActivityStep]
    let attachments: [ChatAttachmentItem]
    @Binding var showThinking: Bool
    let mathRenderingEnabled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity, alignment: .leading)

            if !toolSteps.isEmpty {
                ToolActivityDisclosure(steps: toolSteps)
            }

            if !attachments.isEmpty {
                MessageAttachmentList(attachments: attachments, isOutgoing: false)
            }

            if let thinking = thinking?.trimmingCharacters(in: .whitespacesAndNewlines),
               !thinking.isEmpty {
                Button {
                    showThinking.toggle()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "brain.head.profile")
                            .font(.caption2)
                        Text(showThinking ? L10n.text("Thinkingを隠す") : L10n.text("Thinkingを表示"))
                            .font(.caption2)
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                if showThinking {
                    ThinkingStreamTextView(text: thinking)
                        .frame(minHeight: 80, maxHeight: 220)
                        .padding(8)
                        .background(Color.chatInputBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }

            switch status {
            case .pending:
                HStack(spacing: 8) {
                    ProgressView()
                    Text(L10n.text("応答待ち"))
                        .foregroundStyle(.secondary)
                }
            case .failed:
                ChatErrorCard(text: error ?? L10n.text("応答の生成に失敗しました。"))
            case .canceled:
                Text(L10n.text("キャンセルしました"))
                    .foregroundStyle(.secondary)
            case .completed:
                MathMarkdownView(
                    markdownText: content.isEmpty ? L10n.text("応答がありません") : content,
                    mathRenderingEnabled: mathRenderingEnabled,
                    isStreaming: false
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .topLeading)
        .padding(10)
        .background(Color.chatAssistantBubble)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.chatBubbleBorder.opacity(0.4), lineWidth: 1)
        }
    }
}

private struct MessageBubbleContextMenuModifier: ViewModifier {
    let isEnabled: Bool
    let canRegenerate: Bool
    let showsFusionDetail: Bool
    let onCopy: () -> Void
    let onBranch: () -> Void
    let onRegenerate: () -> Void
    let onShowFusionDetail: () -> Void

    func body(content: Content) -> some View {
        if isEnabled {
            content.contextMenu {
                Button {
                    onCopy()
                } label: {
                    Label("コピー", systemImage: "doc.on.doc")
                }

                Button("ここからブランチ") {
                    onBranch()
                }

                Button("再生成") {
                    onRegenerate()
                }
                .disabled(!canRegenerate)

                if showsFusionDetail {
                    Button {
                        onShowFusionDetail()
                    } label: {
                        Label(L10n.text("Fusion 詳細"), systemImage: "arrow.triangle.merge")
                    }
                }
            }
        } else {
            content
        }
    }
}

private enum ExtractedMediaBlock: Identifiable {
    case svg(ExtractedSvgBlock)
    case html(ExtractedHtmlBlock)

    var id: String {
        switch self {
        case .svg(let block):
            return "svg-\(block.id)"
        case .html(let block):
            return "html-\(block.id)"
        }
    }

    var startIndex: Int {
        switch self {
        case .svg(let block):
            return block.startIndex
        case .html(let block):
            return block.startIndex
        }
    }

    var endIndex: Int {
        switch self {
        case .svg(let block):
            return block.endIndex
        case .html(let block):
            return block.endIndex
        }
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

import SwiftUI
import Photos
import PhotosUI
import UniformTypeIdentifiers
import UIKit
import ImageIO

private enum ChatTimelineItem: Identifiable {
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

private struct ChatBottomAnchorMaxYPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = .infinity

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private let chatTimelineHorizontalPadding: CGFloat = 20
private let chatTimelineVerticalPadding: CGFloat = 24

struct ChatScreen: View {
    @ObservedObject var viewModel: ChatViewModel
    var onNavigateToConversation: ((Int64) -> Void)? = nil

    @Environment(\.scenePhase) private var scenePhase
    @State private var showFileImporter = false
    @State private var showPhotoPicker = false
    @State private var isAttachmentPanelVisible = false
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var isUserNearBottom = true
    @State private var bottomAnchorMaxY: CGFloat = .infinity
    @State private var isUserDraggingScroll = false
    @State private var scrollInteractionToken = 0
    @State private var addingRecentPhotoIDs: Set<String> = []
    @StateObject private var recentPhotoLibrary = RecentPhotoLibrary()
    @FocusState private var isComposerFocused: Bool
    private let bottomAnchorID = "chat-bottom-anchor"
    private let scrollCoordinateSpace = "chat-scroll-coordinate-space"
    private let bottomProximityThreshold: CGFloat = 96

    private var timeline: [ChatTimelineItem] {
        (viewModel.fullMessages.map { ChatTimelineItem.message($0) } +
            viewModel.dualMessages.map { ChatTimelineItem.dual($0) })
            .sorted(by: { $0.createdAtMs < $1.createdAtMs })
    }

    var body: some View {
        GeometryReader { rootGeometry in
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    GeometryReader { scrollGeometry in
                        let measuredWidth = rootGeometry.size.width
                        let viewportWidth = measuredWidth < 300
                            ? UIScreen.main.bounds.width
                            : measuredWidth
                        let timelineWidth = max(viewportWidth - chatTimelineHorizontalPadding * 2, 0)
                        let timelineMinHeight = max(scrollGeometry.size.height - chatTimelineVerticalPadding * 2, 0)
                        let timelineAlignment: Alignment = timeline.isEmpty ? .topLeading : .bottomLeading

                        ScrollView {
                            VStack(alignment: .leading, spacing: 24) {
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
                                            .id(item.id)
                                        case let .dual(message):
                                            DualMessageCard(
                                                message: message,
                                                rowWidth: timelineWidth,
                                                settings: viewModel.settings,
                                                mathRenderingEnabled: viewModel.settings.mathRenderingEnabled
                                            )
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
                                alignment: timelineAlignment
                            )
                            .scrollTargetLayout()
                            .padding(.horizontal, chatTimelineHorizontalPadding)
                            .padding(.vertical, chatTimelineVerticalPadding)
                        }
                        .coordinateSpace(name: scrollCoordinateSpace)
                        .background(Color.chatScreenBackground)
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

                composerBar
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .padding(.bottom, 10)
                    .background {
                        Rectangle()
                            .fill(Color.chatInputBackground)
                            .overlay(alignment: .top) {
                                Divider()
                                    .opacity(0.14)
                            }
                    }
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
            maxSelectionCount: 10,
            matching: .images
        )
        .onChange(of: photoItems) { _, items in
            guard !items.isEmpty else { return }
            Task {
                await importSelectedPhotos(items)
            }
        }
        .overlay(alignment: .bottomLeading) {
            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.red.opacity(0.86))
                    .clipShape(Capsule())
                    .padding(.horizontal, 16)
                    .padding(.bottom, 86)
            }
        }
    }

    private var canSend: Bool {
        !viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !viewModel.attachments.isEmpty
    }

    private var emptyStateTitle: String {
        viewModel.isSecretConversation ? L10n.text("シークレットチャット") : L10n.text("会話がありません")
    }

    private var emptyStateSystemImage: String {
        viewModel.isSecretConversation ? "lock.shield" : "bubble.left.and.bubble.right"
    }

    private var emptyStateDescription: String {
        viewModel.isSecretConversation
            ? L10n.text("このチャットは閉じると破棄されます。")
            : L10n.text("メッセージを入力して会話を開始してください。")
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

            if viewModel.canAttachImages, isAttachmentPanelVisible {
                attachmentPanel
            }

            HStack(alignment: .bottom, spacing: 8) {
                if viewModel.canAttachImages {
                    Button {
                        toggleAttachmentPanel()
                    } label: {
                        Image(systemName: isAttachmentPanelVisible ? "xmark" : "plus")
                            .font(.system(size: 20, weight: .regular))
                            .foregroundStyle(Color.chatComposerIcon)
                            .frame(width: 42, height: 42)
                            .background(Color.chatInputChipBackground)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(isAttachmentPanelVisible ? "添付を閉じる" : "添付を追加"))
                }

                TextField(viewModel.composerPlaceholder, text: $viewModel.inputText, axis: .vertical)
                    .lineLimit(1 ... 6)
                    .focused($isComposerFocused)
                    .padding(.vertical, 11)
                    .foregroundStyle(Color.chatComposerText)
                    .tint(Color.chatAccent)

                Button {
                    viewModel.toggleSpeechRecognition()
                } label: {
                    Image(systemName: viewModel.isSpeechRecording ? "mic.fill" : "mic")
                        .font(.system(size: 22, weight: .regular))
                        .foregroundStyle(viewModel.isSpeechRecording ? Color.red : Color.chatComposerIcon)
                        .symbolEffect(.pulse, isActive: viewModel.isSpeechRecording)
                        .frame(width: 38, height: 42)
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isSending)
                .accessibilityLabel(Text("音声入力"))

                Button {
                    if canSend {
                        isAttachmentPanelVisible = false
                        viewModel.sendMessage()
                    }
                } label: {
                    if viewModel.isSending {
                        ProgressView()
                            .tint(.white)
                            .controlSize(.small)
                            .frame(width: 42, height: 42)
                    } else {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 42, height: 42)
                    }
                }
                .background(canSend ? Color.chatAccent : Color.chatSendDisabled)
                .clipShape(Circle())
                .disabled(viewModel.isSending || !canSend)
                .accessibilityLabel(Text("送信"))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color.chatInputBackground)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .shadow(color: .black.opacity(0.08), radius: 18, x: 0, y: 6)
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(Color.chatBubbleBorder.opacity(0.16), lineWidth: 1)
            }
        }
    }

    @ViewBuilder
    private var attachmentPanel: some View {
        Button {
            openFileImporter()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "paperclip")
                Text("ファイルを追加")
                    .font(.subheadline.weight(.semibold))
                Spacer()
            }
            .foregroundStyle(Color.chatComposerIcon)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.chatInputBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)

        recentPhotoStrip
    }

    @ViewBuilder
    private var recentPhotoStrip: some View {
        if recentPhotoLibrary.canShowRecentPhotos, !recentPhotoLibrary.items.isEmpty {
            RecentPhotoStrip(
                items: recentPhotoLibrary.items,
                loadingIDs: addingRecentPhotoIDs,
                onOpenLibrary: {
                    openPhotoPicker()
                },
                onSelect: { item in
                    addRecentPhoto(item)
                }
            )
        } else if recentPhotoLibrary.isLoading {
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text("最近の写真を読み込み中...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.chatInputBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        } else if recentPhotoLibrary.needsAuthorizationPrompt {
            HStack(spacing: 10) {
                Image(systemName: "photo.stack")
                    .foregroundStyle(Color.chatAccent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("最近の写真を表示")
                        .font(.subheadline.weight(.semibold))
                    Text("許可するとここからすぐ添付できます。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Button("許可する") {
                    recentPhotoLibrary.requestAuthorization()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.chatInputBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        } else if recentPhotoLibrary.isAccessDenied {
            HStack(spacing: 10) {
                Image(systemName: "photo.stack")
                    .foregroundStyle(.secondary)
                Text("写真アクセスを許可すると、最近の写真をここに表示できます。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Button("設定") {
                    openAppSettings()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.chatInputBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private func importSelectedPhotos(_ items: [PhotosPickerItem]) async {
        var importedCount = 0
        var failedCount = 0

        for item in items {
            do {
                let attachment = try await loadTemporaryPhotoAttachment(from: item)
                await MainActor.run {
                    viewModel.addAttachment(
                        url: attachment.url,
                        displayName: attachment.displayName,
                        deleteSourceWhenHandled: true
                    )
                }
                importedCount += 1
            } catch {
                failedCount += 1
                DiagnosticsLogger.log("Photos picker import failed", category: .chat, error: error)
            }
        }

        await MainActor.run {
            photoItems = []
            if importedCount > 0 {
                isAttachmentPanelVisible = false
            }
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

    private func addRecentPhoto(_ item: RecentPhotoItem) {
        guard !addingRecentPhotoIDs.contains(item.id) else { return }
        addingRecentPhotoIDs.insert(item.id)
        Task {
            do {
                let fileURL = try await recentPhotoLibrary.exportFileURL(for: item.asset)
                await MainActor.run {
                    viewModel.addAttachment(
                        url: fileURL,
                        displayName: recentPhotoLibrary.suggestedFilename(for: item.asset),
                        deleteSourceWhenHandled: true
                    )
                    isAttachmentPanelVisible = false
                }
            } catch {
                await MainActor.run {
                    viewModel.errorMessage = L10n.text("写真を読み込めませんでした。")
                }
            }
            await MainActor.run {
                _ = addingRecentPhotoIDs.remove(item.id)
            }
        }
    }

    private func openAppSettings() {
        guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(settingsURL)
    }

    private func toggleAttachmentPanel() {
        isAttachmentPanelVisible.toggle()
        if isAttachmentPanelVisible {
            recentPhotoLibrary.refresh()
        }
    }

    private func openPhotoPicker() {
        isAttachmentPanelVisible = false
        showPhotoPicker = true
    }

    private func openFileImporter() {
        isAttachmentPanelVisible = false
        showFileImporter = true
    }

    private func dismissComposerChrome() {
        isComposerFocused = false
        isAttachmentPanelVisible = false
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

    private func handleBottomAnchorChange(maxY: CGFloat, viewportHeight: CGFloat, proxy: ScrollViewProxy) {
        let wasNearBottom = isUserNearBottom
        bottomAnchorMaxY = maxY
        updateIsUserNearBottom(bottomAnchorMaxY: maxY, viewportHeight: viewportHeight)

        if wasNearBottom,
           !isUserDraggingScroll,
           maxY > viewportHeight + bottomProximityThreshold {
            DispatchQueue.main.async {
                scrollToBottom(proxy: proxy, animated: false)
            }
        }
    }

    private func updateIsUserNearBottom(bottomAnchorMaxY: CGFloat, viewportHeight: CGFloat) {
        isUserNearBottom = timeline.isEmpty || bottomAnchorMaxY <= viewportHeight + bottomProximityThreshold
    }

    private func scrollToBottomIfNeeded(proxy: ScrollViewProxy, animated: Bool = true) {
        guard isUserNearBottom else { return }
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
                            AttachmentThumbnail(url: item.url, sideLength: 82)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(Color.chatBubbleBorder.opacity(0.45), lineWidth: 1)
                                }

                            Button {
                                onRemove(item.id)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 18))
                                    .symbolRenderingMode(.hierarchical)
                                    .foregroundStyle(.white)
                                    .shadow(radius: 1.5, y: 0.5)
                            }
                            .buttonStyle(.plain)
                            .offset(x: 4, y: -4)
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
}

private struct MessageAttachmentList: View {
    let attachments: [ChatAttachmentItem]
    let isOutgoing: Bool

    private var imageAttachments: [ChatAttachmentItem] {
        attachments.filter(\.isImage)
    }

    private var fileAttachments: [ChatAttachmentItem] {
        attachments.filter { !$0.isImage }
    }

    private var horizontalAlignment: HorizontalAlignment {
        isOutgoing ? .trailing : .leading
    }

    private var frameAlignment: Alignment {
        isOutgoing ? .trailing : .leading
    }

    var body: some View {
        VStack(alignment: horizontalAlignment, spacing: 6) {
            if !imageAttachments.isEmpty {
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
                    .frame(maxWidth: .infinity, alignment: frameAlignment)
                }
            }

            ForEach(fileAttachments) { attachment in
                Label(attachment.displayName, systemImage: "paperclip")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: 260, alignment: frameAlignment)
            }
        }
    }
}

private struct AttachmentImageCard: View {
    let url: URL
    let displayName: String

    var body: some View {
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
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L10n.format("添付画像: %@", displayName))
    }
}

private struct RecentPhotoStrip: View {
    let items: [RecentPhotoItem]
    let loadingIDs: Set<String>
    let onOpenLibrary: () -> Void
    let onSelect: (RecentPhotoItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("最近の写真")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("すべての写真") {
                    onOpenLibrary()
                }
                .font(.caption.weight(.semibold))
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    Button {
                        onOpenLibrary()
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: "photo.on.rectangle.angled")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundStyle(Color.chatComposerIcon)
                            Text("すべて")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .frame(width: 68, height: 68)
                        .background(Color.chatInputChipBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.chatBubbleBorder.opacity(0.45), lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)

                    ForEach(items) { item in
                        RecentPhotoButton(
                            asset: item.asset,
                            isLoading: loadingIDs.contains(item.id),
                            onTap: {
                                onSelect(item)
                            }
                        )
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 2)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background(Color.chatInputBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct RecentPhotoButton: View {
    let asset: PHAsset
    let isLoading: Bool
    let onTap: () -> Void

    var body: some View {
        Button {
            onTap()
        } label: {
                ZStack {
                    RecentPhotoThumbnail(asset: asset, sideLength: 68)
                if isLoading {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.black.opacity(0.28))
                    ProgressView()
                        .tint(.white)
                        .controlSize(.small)
                }
            }
            .frame(width: 68, height: 68)
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.chatBubbleBorder.opacity(0.35), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }
}

private struct RecentPhotoThumbnail: View {
    @Environment(\.displayScale) private var displayScale
    let asset: PHAsset
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
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.chatInputChipBackground)
                    Image(systemName: "photo")
                        .foregroundStyle(.secondary)
                }
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.chatInputChipBackground)
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
        .frame(width: sideLength, height: sideLength)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .task(id: asset.localIdentifier) {
            guard image == nil else { return }
            image = await RecentPhotoThumbnailLoader.thumbnail(
                for: asset,
                maxPixelSize: sideLength * displayScale * 1.6
            )
            didAttemptLoad = true
        }
    }
}

private enum RecentPhotoThumbnailLoader {
    static func thumbnail(for asset: PHAsset, maxPixelSize: CGFloat) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = true

            let target = CGSize(
                width: max(maxPixelSize, 48),
                height: max(maxPixelSize, 48)
            )

            var didResume = false
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: target,
                contentMode: .aspectFill,
                options: options
            ) { image, info in
                guard !didResume else { return }
                let isCancelled = (info?[PHImageCancelledKey] as? NSNumber)?.boolValue ?? false
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? NSNumber)?.boolValue ?? false
                if isCancelled {
                    didResume = true
                    continuation.resume(returning: nil)
                    return
                }
                if let error = info?[PHImageErrorKey] as? Error {
                    didResume = true
                    DiagnosticsLogger.log("Recent photo thumbnail load failed", category: .chat, error: error)
                    continuation.resume(returning: nil)
                    return
                }
                guard !isDegraded else { return }
                didResume = true
                continuation.resume(returning: image)
            }
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
            image = ImageThumbnailGenerator.thumbnail(
                for: url,
                maxPixelSize: Int(sideLength * displayScale * 1.6)
            )
            didAttemptLoad = true
        }
    }
}

private enum ImageThumbnailGenerator {
    static func thumbnail(for url: URL, maxPixelSize: Int) -> UIImage? {
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

private struct MessageBubble: View {
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
        message.displayToolActivity?.steps ?? []
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

                    let svgBlocks = SvgCodeExtractor.extract(from: responseText)
                    let markdownText = SvgCodeExtractor.removeExtractedBlocks(from: responseText, blocks: svgBlocks)
                    let hasAssistantBubbleContent = !attachmentItems.isEmpty
                        || !svgBlocks.isEmpty
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

                                if !svgBlocks.isEmpty {
                                    ForEach(svgBlocks) { block in
                                        SvgPreviewCard(block: block)
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
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    if !toolSources.isEmpty {
                        ToolSourcesView(sources: toolSources)
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

private struct DualMessageCard: View {
    let message: DualChatMessage
    let rowWidth: CGFloat
    let settings: AppSettings
    let mathRenderingEnabled: Bool
    @State private var showThinkingA = false
    @State private var showThinkingB = false

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
                            content: modelAText.isEmpty ? L10n.text("（応答待ち）") : modelAText,
                            thinking: message.modelAThinking,
                            showThinking: $showThinkingA,
                            mathRenderingEnabled: mathRenderingEnabled
                        )
                    } second: {
                        DualResponsePane(
                            title: "B · \(ProviderCatalog.displayName(for: message.providerB)) · \(message.modelBName)",
                            content: modelBText.isEmpty ? L10n.text("（応答待ち）") : modelBText,
                            thinking: message.modelBThinking,
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
                    Text(modelAText)
                        .textSelection(.enabled)
                    Divider()
                    Text("B · \(ProviderCatalog.displayName(for: message.providerB)) · \(message.modelBName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(modelBText)
                        .textSelection(.enabled)
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
            HStack(alignment: .top, spacing: 8) {
                first()
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .topLeading)
                    .layoutPriority(splitRatio)
                second()
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .topLeading)
                    .layoutPriority(1 - splitRatio)
            }
        }
    }
}

private struct DualResponsePane: View {
    let title: String
    let content: String
    let thinking: String?
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

            MathMarkdownView(
                markdownText: content,
                mathRenderingEnabled: mathRenderingEnabled,
                isStreaming: false
            )
            .frame(maxWidth: .infinity, alignment: .leading)
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

private extension Color {
    static let chatScreenBackground = Color(uiColor: .systemBackground)
    static let chatInputBackground = Color(uiColor: .systemBackground)
    static let chatInputChipBackground = Color(uiColor: .tertiarySystemFill)
    static let chatUserBubble = Color(uiColor: .secondarySystemFill)
    static let chatUserText = Color(uiColor: .label)
    static let chatAccent = Color(uiColor: .systemBlue)
    static let chatDualCard = Color(uiColor: .secondarySystemBackground)
    static let chatComposerText = Color(uiColor: .label)
    static let chatComposerIcon = Color(uiColor: .label)
    static let chatAssistantBubble = Color(uiColor: .systemBackground)
    static let chatAssistantMark = Color(uiColor: .secondaryLabel)
    static let chatBubbleBorder = Color(uiColor: .separator)
    static let chatSendDisabled = Color(uiColor: .systemGray3)
}

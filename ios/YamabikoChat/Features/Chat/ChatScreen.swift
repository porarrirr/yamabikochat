import SwiftUI
import Photos
import PhotosUI
import UniformTypeIdentifiers
import UIKit
import ImageIO
import QuickLook

private let maximumPhotoSelectionCount = 10

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
    @StateObject private var recentPhotoLibrary = RecentPhotoLibrary()
    @FocusState private var isComposerFocused: Bool

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
                onRegenerate: { viewModel.regenerateLastAssistantVariant() }
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
                    .accessibilityIdentifier("chat-composer")
                    .lineLimit(isComposerExpanded ? 8 : 1)
                    .focused($isComposerFocused)
                    .font(.system(size: 16))
                    .padding(.horizontal, isComposerExpanded ? 14 : 0)
                    .padding(.top, isComposerExpanded ? 12 : 9)
                    .padding(.bottom, isComposerExpanded ? 6 : 9)
                    .foregroundStyle(.primary)
                    .tint(.accentColor)
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
                HStack(alignment: .center, spacing: 6) {
                    composerPlusMenuButton
                    Spacer(minLength: 4)
                    if let contextUsage = viewModel.visibleContextUsage {
                        ContextUsageMeter(usage: contextUsage)
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

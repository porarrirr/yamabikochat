import SwiftUI
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

struct ChatScreen: View {
    @ObservedObject var viewModel: ChatViewModel

    @State private var showFileImporter = false
    @State private var showPhotoPicker = false
    @State private var photoItems: [PhotosPickerItem] = []
    @FocusState private var isComposerFocused: Bool

    private var timeline: [ChatTimelineItem] {
        (viewModel.fullMessages.map { ChatTimelineItem.message($0) } +
            viewModel.dualMessages.map { ChatTimelineItem.dual($0) })
            .sorted(by: { $0.createdAtMs < $1.createdAtMs })
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        if timeline.isEmpty {
                            ContentUnavailableView(
                                "会話がありません",
                                systemImage: "bubble.left.and.bubble.right",
                                description: Text("メッセージを入力して会話を開始してください。")
                            )
                            .frame(maxWidth: .infinity)
                            .padding(.top, 56)
                        } else {
                            ForEach(timeline) { item in
                                switch item {
                                case let .message(message):
                                    MessageBubble(
                                        message: message,
                                        mathRenderingEnabled: viewModel.settings.mathRenderingEnabled,
                                        canRegenerate: viewModel.canRegenerateLastAssistant && message.id == viewModel.fullMessages.last?.id,
                                        onPrevVariant: { viewModel.showPrevVariant(messageId: message.id) },
                                        onNextVariant: { viewModel.showNextVariant(messageId: message.id) },
                                        onCopy: {
                                            UIPasteboard.general.string = message.displayText
                                        },
                                        onRegenerate: {
                                            viewModel.regenerateLastAssistantVariant()
                                        }
                                    )
                                        .id(item.id)
                                case let .dual(message):
                                    DualMessageCard(
                                        message: message,
                                        settings: viewModel.settings,
                                        mathRenderingEnabled: viewModel.settings.mathRenderingEnabled
                                    )
                                        .id(item.id)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 18)
                }
                .background(Color.chatScreenBackground)
                .scrollDismissesKeyboard(.interactively)
                .simultaneousGesture(
                    TapGesture().onEnded {
                        dismissComposerKeyboard()
                    }
                )
                .onChange(of: timeline.count) { _, _ in
                    guard let last = timeline.last else { return }
                    withAnimation {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }

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
                        .fill(.ultraThinMaterial)
                        .overlay(alignment: .top) {
                            Divider()
                                .opacity(0.35)
                        }
                }
        }
        .background(Color.chatScreenBackground)
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.image, .pdf, .plainText, .utf8PlainText],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case let .success(urls):
                for url in urls {
                    let secured = url.startAccessingSecurityScopedResource()
                    defer {
                        if secured {
                            url.stopAccessingSecurityScopedResource()
                        }
                    }
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
                for item in items {
                    if let url = await loadTemporaryFileURL(from: item) {
                        await MainActor.run {
                            viewModel.addAttachment(url: url)
                        }
                    }
                }
                await MainActor.run {
                    photoItems = []
                }
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

    private var composerBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(viewModel.systemPromptContextLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, 8)

            HStack(alignment: .bottom, spacing: 10) {
                Menu {
                    Button("写真を追加") {
                        showPhotoPicker = true
                    }
                    Button("ファイルを追加") {
                        showFileImporter = true
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.chatComposerIcon)
                        .frame(width: 34, height: 34)
                        .background(Color.chatInputChipBackground)
                        .overlay {
                            Circle()
                                .stroke(Color.chatBubbleBorder.opacity(0.5), lineWidth: 1)
                        }
                        .clipShape(Circle())
                }
                .menuStyle(.button)

                TextField("質問してみましょう", text: $viewModel.inputText, axis: .vertical)
                    .lineLimit(1 ... 6)
                    .focused($isComposerFocused)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .foregroundStyle(Color.chatComposerText)
                    .tint(Color.chatAccent)
                    .background(Color.chatInputBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                Button {} label: {
                    Image(systemName: "mic")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .disabled(true)

                Button {
                    if canSend {
                        viewModel.sendMessage()
                    }
                } label: {
                    if viewModel.isSending {
                        ProgressView()
                            .tint(.white)
                            .controlSize(.small)
                            .frame(width: 36, height: 36)
                    } else {
                        Image(systemName: canSend ? "arrow.up" : "waveform")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                    }
                }
                .background(canSend ? Color.chatAccent : Color.chatAccent.opacity(0.42))
                .clipShape(Circle())
                .disabled(viewModel.isSending || !canSend)
            }
        }
    }

    private func loadTemporaryFileURL(from item: PhotosPickerItem) async -> URL? {
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else { return nil }
            let fileURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString + ".jpg")
            try data.write(to: fileURL)
            return fileURL
        } catch {
            return nil
        }
    }

    private func dismissComposerKeyboard() {
        isComposerFocused = false
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

private struct AttachmentThumbnail: View {
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
                maxPixelSize: Int(sideLength * UIScreen.main.scale * 1.6)
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
    let mathRenderingEnabled: Bool
    let canRegenerate: Bool
    let onPrevVariant: () -> Void
    let onNextVariant: () -> Void
    let onCopy: () -> Void
    let onRegenerate: () -> Void
    @State private var isThinkingSheetPresented = false

    private var isUser: Bool {
        message.message.role == "user"
    }

    private var responseText: String {
        message.displayText
    }

    private var thinkingText: String? {
        guard let value = message.displayThinkingStream?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !value.isEmpty
        else {
            return nil
        }
        return value
    }

    private var attachmentNames: [String] {
        guard let data = message.displayAttachmentsJSON.data(using: .utf8),
              let values = try? JSONDecoder().decode([String].self, from: data)
        else {
            return []
        }
        return values.map { URL(string: $0)?.lastPathComponent ?? $0 }
    }

    var body: some View {
        VStack(alignment: isUser ? .trailing : .leading, spacing: 8) {
            if isUser {
                if !attachmentNames.isEmpty {
                    VStack(alignment: .trailing, spacing: 4) {
                        ForEach(attachmentNames, id: \.self) { name in
                            Label(name, systemImage: "paperclip")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Text(responseText)
                    .textSelection(.enabled)
                    .foregroundStyle(Color.chatUserText)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.chatUserBubble)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .frame(maxWidth: .infinity, alignment: .trailing)
            } else {
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

                VStack(alignment: .leading, spacing: 8) {
                    if !attachmentNames.isEmpty {
                        ForEach(attachmentNames, id: \.self) { name in
                            Label(name, systemImage: "paperclip")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if !svgBlocks.isEmpty {
                        ForEach(svgBlocks) { block in
                            SvgPreviewCard(block: block)
                        }
                    }

                    if !markdownText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        MathMarkdownView(
                            markdownText: markdownText,
                            mathRenderingEnabled: mathRenderingEnabled
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(12)
                .background(Color.chatAssistantBubble)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.chatBubbleBorder.opacity(0.45), lineWidth: 1)
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

            HStack(spacing: 14) {
                Button {
                    onCopy()
                } label: {
                    Label("コピー", systemImage: "doc.on.doc")
                }
                .buttonStyle(.plain)

                Button {
                    onRegenerate()
                } label: {
                    Label("再生成", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .disabled(!canRegenerate)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
        .sheet(isPresented: $isThinkingSheetPresented) {
            if let thinkingText {
                ThinkingSheet(
                    thinkingText: thinkingText,
                    mathRenderingEnabled: mathRenderingEnabled
                )
            }
        }
    }
}

private struct ThinkingSheet: View {
    let thinkingText: String
    let mathRenderingEnabled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "brain.head.profile")
                Text("Thinking")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 10)

            Divider()

            ScrollView {
                MathMarkdownView(
                    markdownText: thinkingText,
                    mathRenderingEnabled: mathRenderingEnabled
                )
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

private struct DualMessageCard: View {
    let message: DualChatMessage
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

    private var attachmentNames: [String] {
        message.attachments.map { URL(string: $0)?.lastPathComponent ?? $0 }
    }

    var body: some View {
        Group {
            switch message.parsedRole {
            case .user:
                VStack(alignment: .trailing, spacing: 8) {
                    if !attachmentNames.isEmpty {
                        VStack(alignment: .trailing, spacing: 4) {
                            ForEach(attachmentNames, id: \.self) { name in
                                Label(name, systemImage: "paperclip")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    if !userText.isEmpty {
                        Text(userText)
                            .textSelection(.enabled)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(12)
                .background(Color.chatUserBubble)
                .foregroundStyle(Color.chatUserText)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            case .dualModel:
                VStack(alignment: .leading, spacing: 10) {
                    DualSplitContainer(
                        layout: resolvedLayout,
                        splitRatio: splitRatio
                    ) {
                        DualResponsePane(
                            title: "A · \(ProviderCatalog.displayName(for: message.providerA)) · \(message.modelAName)",
                            content: modelAText.isEmpty ? "（応答待ち）" : modelAText,
                            thinking: message.modelAThinking,
                            showThinking: $showThinkingA,
                            mathRenderingEnabled: mathRenderingEnabled
                        )
                    } second: {
                        DualResponsePane(
                            title: "B · \(ProviderCatalog.displayName(for: message.providerB)) · \(message.modelBName)",
                            content: modelBText.isEmpty ? "（応答待ち）" : modelBText,
                            thinking: message.modelBThinking,
                            showThinking: $showThinkingB,
                            mathRenderingEnabled: mathRenderingEnabled
                        )
                    }
                }
                .padding(12)
                .background(Color.chatDualCard)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
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
        GeometryReader { proxy in
            if layout == "HORIZONTAL" {
                VStack(spacing: 8) {
                    first()
                        .frame(height: proxy.size.height * splitRatio, alignment: .top)
                    second()
                        .frame(height: proxy.size.height * (1 - splitRatio), alignment: .top)
                }
            } else {
                HStack(spacing: 8) {
                    first()
                        .frame(width: proxy.size.width * splitRatio, alignment: .topLeading)
                    second()
                        .frame(width: proxy.size.width * (1 - splitRatio), alignment: .topLeading)
                }
            }
        }
        .frame(minHeight: 220)
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

            if let thinking = thinking?.trimmingCharacters(in: .whitespacesAndNewlines),
               !thinking.isEmpty {
                Button {
                    showThinking.toggle()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "brain.head.profile")
                            .font(.caption2)
                        Text(showThinking ? "Thinkingを隠す" : "Thinkingを表示")
                            .font(.caption2)
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                if showThinking {
                    MathMarkdownView(
                        markdownText: thinking,
                        mathRenderingEnabled: mathRenderingEnabled
                    )
                    .padding(8)
                    .background(Color.chatInputBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }

            MathMarkdownView(
                markdownText: content,
                mathRenderingEnabled: mathRenderingEnabled
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .background(Color.chatAssistantBubble)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.chatBubbleBorder.opacity(0.4), lineWidth: 1)
        }
    }
}

private extension Color {
    static let chatScreenBackground = Color(uiColor: .systemGroupedBackground)
    static let chatInputBackground = Color(uiColor: .secondarySystemBackground)
    static let chatInputChipBackground = Color(uiColor: .tertiarySystemFill)
    static let chatUserBubble = Color(uiColor: .systemBlue)
    static let chatUserText = Color(uiColor: .white)
    static let chatAccent = Color(uiColor: .systemBlue)
    static let chatDualCard = Color(uiColor: .secondarySystemBackground)
    static let chatComposerText = Color(uiColor: .label)
    static let chatComposerIcon = Color(uiColor: .label)
    static let chatAssistantBubble = Color(uiColor: .systemBackground)
    static let chatBubbleBorder = Color(uiColor: .separator)
}

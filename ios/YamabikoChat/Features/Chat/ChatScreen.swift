import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import UIKit

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
                                        onPrevVariant: { viewModel.showPrevVariant(messageId: message.id) },
                                        onNextVariant: { viewModel.showNextVariant(messageId: message.id) }
                                    )
                                        .id(item.id)
                                case let .dual(message):
                                    DualMessageCard(message: message)
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
        HStack(alignment: .bottom, spacing: 10) {
            Menu {
                PhotosPicker(
                    selection: $photoItems,
                    maxSelectionCount: 10,
                    matching: .images,
                    photoLibrary: .shared()
                ) {
                    Label("写真を追加", systemImage: "photo")
                }
                Button {
                    showFileImporter = true
                } label: {
                    Label("ファイルを追加", systemImage: "doc")
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
                    HStack(spacing: 6) {
                        Image(systemName: "paperclip")
                            .font(.caption2)
                        Text(item.url.lastPathComponent)
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

private struct MessageBubble: View {
    let message: FullChatMessage
    let onPrevVariant: () -> Void
    let onNextVariant: () -> Void
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

                VStack(alignment: .leading, spacing: 8) {
                    if !attachmentNames.isEmpty {
                        ForEach(attachmentNames, id: \.self) { name in
                            Label(name, systemImage: "paperclip")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    MathMarkdownView(markdownText: responseText)
                        .frame(maxWidth: .infinity, alignment: .leading)
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
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
        .sheet(isPresented: $isThinkingSheetPresented) {
            if let thinkingText {
                ThinkingSheet(thinkingText: thinkingText)
            }
        }
    }
}

private struct ThinkingSheet: View {
    let thinkingText: String

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
                MathMarkdownView(markdownText: thinkingText)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(message.userText)
                .font(.body)
            Divider()
            Text("A · \(ProviderCatalog.displayName(for: message.providerA)) · \(message.modelAName)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(message.modelAText)
                .textSelection(.enabled)
            Divider()
            Text("B · \(ProviderCatalog.displayName(for: message.providerB)) · \(message.modelBName)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(message.modelBText)
                .textSelection(.enabled)
        }
        .padding(12)
        .background(Color.chatDualCard)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
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

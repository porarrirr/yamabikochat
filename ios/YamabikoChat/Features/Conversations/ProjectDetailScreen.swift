import SwiftUI
import UniformTypeIdentifiers

struct ProjectDetailScreen: View {
    private enum ProjectTab: String, CaseIterable, Identifiable {
        case chats
        case sources

        var id: String { rawValue }

        var title: String {
            switch self {
            case .chats: L10n.text("チャット")
            case .sources: L10n.text("情報源")
            }
        }
    }

    @EnvironmentObject private var appState: AppState
    @ObservedObject var viewModel: ConversationListViewModel
    let projectId: Int64
    var onBack: () -> Void
    var onSelectConversation: (Int64) -> Void

    @State private var draftMessage: String = ""
    @State private var isInstructionsPresented: Bool = false
    @State private var isEditProjectPresented: Bool = false
    @State private var isDeleteConfirmationPresented: Bool = false
    @State private var selectedTab: ProjectTab = .chats
    @State private var isFileImporterPresented: Bool = false

    private var project: ProjectListEntry? {
        viewModel.projects.first(where: { $0.id == projectId })
    }

    private var projectConversations: [ConversationListEntry] {
        viewModel.conversations.filter { $0.projectId == projectId }
    }

    private var projectFiles: [ProjectWorkspaceFile] {
        viewModel.projectWorkspaceFiles[projectId] ?? []
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar

            projectTabBar

            if selectedTab == .chats {
                projectContextSection
                conversationList
            } else {
                informationSources
            }

            bottomInputBar
        }
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
        .onAppear {
            viewModel.loadProjectWorkspaceFiles(projectId: projectId)
        }
        .fileImporter(
            isPresented: $isFileImporterPresented,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case let .success(urls):
                viewModel.importProjectWorkspaceFiles(projectId: projectId, urls: urls)
            case let .failure(error):
                viewModel.errorMessage = error.localizedDescription
            }
        }
        .alert(
            L10n.text("エラー"),
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )
        ) {
            Button(L10n.text("OK")) { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .sheet(isPresented: $isInstructionsPresented) {
            if let project {
                ProjectInstructionsSheet(
                    viewModel: viewModel,
                    initialInstructions: project.instructions
                ) { newInstructions in
                    viewModel.updateProjectInstructions(id: project.id, instructions: newInstructions)
                }
            }
        }
        .sheet(isPresented: $isEditProjectPresented) {
            if let project {
                let chatProject = ChatProject(
                    id: project.id,
                    title: project.title,
                    iconName: project.iconName,
                    colorHex: project.colorHex,
                    instructions: project.instructions,
                    updatedAtMs: project.updatedAtMs
                )
                EditProjectSheet(project: chatProject, viewModel: viewModel) { title, instructions, iconName, colorHex in
                    viewModel.updateProject(
                        id: project.id,
                        title: title,
                        instructions: instructions,
                        iconName: iconName,
                        colorHex: colorHex
                    )
                }
            }
        }
        .confirmationDialog(
            L10n.text("プロジェクトを削除"),
            isPresented: $isDeleteConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button(role: .destructive) {
                if viewModel.deleteProject(id: projectId, mode: .projectOnly) {
                    onBack()
                }
            } label: {
                Text(L10n.text("プロジェクトのみ削除"))
            }

            Button(role: .destructive) {
                if viewModel.deleteProject(id: projectId, mode: .withConversations) {
                    onBack()
                }
            } label: {
                Text(L10n.text("会話も削除"))
            }

            Button(L10n.text("キャンセル"), role: .cancel) {}
        } message: {
            if let project {
                Text(L10n.format("「%@」には %d 件の会話があります。削除方法を選択してください。", project.title, viewModel.projectConversationCount(projectId: projectId)))
            } else {
                Text(L10n.text("削除方法を選択してください。"))
            }
        }
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack(spacing: 12) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
                    .background(
                        Circle()
                            .fill(Color(uiColor: .secondarySystemFill))
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(L10n.text("戻る")))

            HStack(spacing: 6) {
                Image(systemName: project?.iconName ?? "folder.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(hex: project?.colorHex ?? "#3A7AFE"))

                Text(project?.title ?? L10n.text("プロジェクト"))
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }

            Spacer()

            Menu {
                Button {
                    isEditProjectPresented = true
                } label: {
                    Label(L10n.text("プロジェクトを編集する"), systemImage: "pencil")
                }

                Button {
                    isInstructionsPresented = true
                } label: {
                    Label(L10n.text("指示を編集"), systemImage: "slider.horizontal.3")
                }

                Divider()

                Button(role: .destructive) {
                    isDeleteConfirmationPresented = true
                } label: {
                    Label(L10n.text("プロジェクトを削除する"), systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
                    .background(
                        Circle()
                            .fill(Color(uiColor: .secondarySystemFill))
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(L10n.text("プロジェクトオプション")))
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }

    // MARK: - Project Context

    private var projectTabBar: some View {
        HStack(spacing: 12) {
            ForEach(ProjectTab.allCases) { tab in
                Button {
                    selectedTab = tab
                    if tab == .sources {
                        viewModel.loadProjectWorkspaceFiles(projectId: projectId)
                    }
                } label: {
                    Text(tab.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(selectedTab == tab ? Color.primary : Color.secondary)
                        .padding(.horizontal, 20)
                        .frame(height: 42)
                        .background(
                            Capsule(style: .continuous)
                                .fill(selectedTab == tab ? Color(uiColor: .secondarySystemFill) : .clear)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("project-tab-\(tab.rawValue)")
                .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
            }

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
    }

    private var projectContextSection: some View {
        Button {
            isInstructionsPresented = true
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "text.alignleft")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.text("プロジェクトの指示"))
                        .font(.subheadline.weight(.semibold))
                    Text(project?.instructions?.trimmedNonEmpty ?? L10n.text("指示はまだ設定されていません"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 7)
            }
            .padding(13)
            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    // MARK: - Conversation List

    private var conversationList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if projectConversations.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "bubble.left.and.bubble.right")
                            .font(.system(size: 36))
                            .foregroundStyle(.secondary.opacity(0.6))
                            .padding(.top, 48)

                        Text(L10n.text("チャットがありません"))
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.secondary)

                        Text(L10n.text("下の入力欄からメッセージを送信してチャットを開始してください。"))
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary.opacity(0.8))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    ForEach(projectConversations) { entry in
                        Button {
                            onSelectConversation(entry.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(entry.title)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)

                                if let preview = entry.lastMessagePreview, !preview.isEmpty {
                                    Text(preview)
                                        .font(.system(size: 13))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(role: .destructive) {
                                viewModel.deleteConversation(id: entry.id)
                            } label: {
                                Label(L10n.text("削除"), systemImage: "trash")
                            }

                            Button(L10n.text("プロジェクトから外す")) {
                                viewModel.assignConversation(id: entry.id, to: nil)
                            }
                        }

                        Divider()
                            .padding(.leading, 16)
                            .opacity(0.2)
                    }
                }
            }
            .padding(.bottom, 16)
        }
    }

    // MARK: - Information Sources

    private var informationSources: some View {
        Group {
            if projectFiles.isEmpty {
                GeometryReader { geometry in
                    addFileButton
                        .position(
                            x: geometry.size.width / 2,
                            y: geometry.size.height * 0.58
                        )
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 0) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(L10n.text("ワークスペースのファイル"))
                                .font(.system(size: 15, weight: .semibold))
                            Text(L10n.text("内容はチャットへ自動添付されません"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            isFileImporterPresented = true
                        } label: {
                            Label(L10n.text("追加"), systemImage: "plus")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.capsule)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 10)

                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(projectFiles) { file in
                                projectFileRow(file)
                                Divider()
                                    .padding(.leading, 58)
                                    .opacity(0.25)
                            }
                        }
                    }
                }
            }
        }
        .overlay {
            if viewModel.isImportingProjectFiles {
                ZStack {
                    Color(uiColor: .systemBackground).opacity(0.75)
                    ProgressView(L10n.text("ファイルを追加中…"))
                }
            }
        }
    }

    private var addFileButton: some View {
        Button {
            isFileImporterPresented = true
        } label: {
            Text(L10n.text("追加"))
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color(uiColor: .systemBackground))
                .padding(.horizontal, 26)
                .frame(height: 46)
                .background(Color.primary, in: Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("project-add-files")
    }

    private func projectFileRow(_ file: ProjectWorkspaceFile) -> some View {
        HStack(spacing: 12) {
            Image(systemName: fileIcon(for: file.name))
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 30, height: 38)

            VStack(alignment: .leading, spacing: 3) {
                Text(file.name)
                    .font(.system(size: 15, weight: .medium))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if file.relativePath != file.name {
                        Text(file.relativePath)
                            .lineLimit(1)
                    }
                    Text(ByteCountFormatter.string(fromByteCount: file.sizeBytes, countStyle: .file))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Menu {
                Button(role: .destructive) {
                    viewModel.removeProjectWorkspaceFile(
                        projectId: projectId,
                        relativePath: file.relativePath
                    )
                } label: {
                    Label(L10n.text("削除"), systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .foregroundStyle(.secondary)
                    .frame(width: 36, height: 36)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    private func fileIcon(for filename: String) -> String {
        switch URL(fileURLWithPath: filename).pathExtension.lowercased() {
        case "png", "jpg", "jpeg", "gif", "heic", "webp": "photo"
        case "pdf": "doc.richtext"
        case "zip": "doc.zipper"
        case "csv", "tsv", "xlsx", "xls": "tablecells"
        case "swift", "kt", "js", "ts", "py", "json", "yaml", "yml", "html", "css": "chevron.left.forwardslash.chevron.right"
        default: "doc"
        }
    }

    // MARK: - Bottom Input Bar

    private var bottomInputBar: some View {
        VStack(spacing: 0) {
            Divider()
                .opacity(0.2)

            HStack(spacing: 10) {
                Button {
                    if let conversationId = viewModel.createConversation(secret: false, projectId: projectId) {
                        onSelectConversation(conversationId)
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(L10n.text("新規チャット")))

                TextField(
                    project != nil
                        ? L10n.format("%@ にメッセージを送信する", project!.title)
                        : L10n.text("メッセージを送信する"),
                    text: $draftMessage
                )
                .font(.system(size: 15))
                .submitLabel(.send)
                .onSubmit {
                    submitMessage()
                }

                if !draftMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button {
                        submitMessage()
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(L10n.text("送信")))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(Color(uiColor: .secondarySystemFill))
            )
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(Color(uiColor: .systemBackground))
    }

    private func submitMessage() {
        let text = draftMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard let conversationId = viewModel.createConversation(initialMessage: text, projectId: projectId) else {
            return
        }
        draftMessage = ""
        onSelectConversation(conversationId)
    }
}

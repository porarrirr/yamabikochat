import SwiftUI

struct ProjectListScreen: View {
    private struct PendingProjectDeletion {
        let id: Int64
        let title: String
        let conversationCount: Int
    }

    @ObservedObject var viewModel: ConversationListViewModel
    var onBack: () -> Void
    var onSelectProject: (Int64) -> Void

    @State private var searchQuery: String = ""
    @State private var isCreateProjectPresented: Bool = false
    @State private var editingInstructionsProject: ProjectListEntry?
    @State private var editingDetailsProject: ProjectListEntry?
    @State private var pendingProjectDeletion: PendingProjectDeletion?
    @State private var isProjectDeleteOptionsPresented: Bool = false

    private var normalizedSearchQuery: String {
        searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasSearchQuery: Bool {
        !normalizedSearchQuery.isEmpty
    }

    private var filteredProjects: [ProjectListEntry] {
        if normalizedSearchQuery.isEmpty {
            return viewModel.projects
        }
        return viewModel.projects.filter {
            $0.title.localizedCaseInsensitiveContains(normalizedSearchQuery) ||
                ($0.instructions?.localizedCaseInsensitiveContains(normalizedSearchQuery) ?? false)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar

            projectListView

            bottomSearchBar
        }
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
        .sheet(isPresented: $isCreateProjectPresented) {
            CreateProjectSheet(viewModel: viewModel) { title, instructions in
                guard let projectId = viewModel.createProject(title: title, instructions: instructions) else {
                    return false
                }
                onSelectProject(projectId)
                return true
            }
        }
        .sheet(item: $editingInstructionsProject) { project in
            ProjectInstructionsSheet(
                viewModel: viewModel,
                initialInstructions: project.instructions
            ) { newInstructions in
                viewModel.updateProjectInstructions(id: project.id, instructions: newInstructions)
            }
        }
        .sheet(item: $editingDetailsProject) { project in
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
        .confirmationDialog(
            L10n.text("プロジェクトを削除"),
            isPresented: $isProjectDeleteOptionsPresented,
            titleVisibility: .visible
        ) {
            Button(role: .destructive) {
                guard let pending = pendingProjectDeletion else { return }
                if viewModel.deleteProject(id: pending.id, mode: .projectOnly) {
                    pendingProjectDeletion = nil
                }
            } label: {
                Text(L10n.text("プロジェクトのみ削除"))
            }

            Button(role: .destructive) {
                guard let pending = pendingProjectDeletion else { return }
                if viewModel.deleteProject(id: pending.id, mode: .withConversations) {
                    pendingProjectDeletion = nil
                }
            } label: {
                Text(L10n.text("会話も削除"))
            }

            Button(L10n.text("キャンセル"), role: .cancel) {
                pendingProjectDeletion = nil
            }
        } message: {
            if let pending = pendingProjectDeletion {
                Text(L10n.format("「%@」には %d 件の会話があります。削除方法を選択してください。", pending.title, pending.conversationCount))
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
                    .frame(width: 36, height: 36)
                    .background(
                        Circle()
                            .fill(Color(uiColor: .secondarySystemFill))
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(L10n.text("戻る")))

            Text(L10n.text("プロジェクト"))
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.primary)

            Spacer()

            Button {
                isCreateProjectPresented = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 36, height: 36)
                    .background(
                        Circle()
                            .fill(Color(uiColor: .secondarySystemFill))
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(L10n.text("新しいプロジェクト")))
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }

    // MARK: - Project List

    private var projectListView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if filteredProjects.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "folder")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary.opacity(0.6))
                            .padding(.top, 48)

                        Text(hasSearchQuery ? L10n.text("該当するプロジェクトがありません") : L10n.text("プロジェクトがありません"))
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.secondary)

                        if !hasSearchQuery {
                            Button {
                                isCreateProjectPresented = true
                            } label: {
                                Text(L10n.text("新しいプロジェクトを作成"))
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(Color.accentColor)
                            }
                            .padding(.top, 4)
                        }
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    ForEach(filteredProjects) { project in
                        projectRow(project)

                        Divider()
                            .padding(.leading, 72)
                            .opacity(0.2)
                    }
                }
            }
            .padding(.bottom, 16)
        }
    }

    private func projectRow(_ project: ProjectListEntry) -> some View {
        Button {
            onSelectProject(project.id)
        } label: {
            HStack(spacing: 14) {
                // Folder Icon Box
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(hex: project.colorHex).opacity(0.18))
                        .frame(width: 44, height: 44)

                    Image(systemName: project.iconName)
                        .font(.system(size: 20))
                        .foregroundStyle(Color(hex: project.colorHex))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(project.title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if project.updatedAtMs > 0 {
                        Text(RelativeDateFormatter.format(epochMs: project.updatedAtMs))
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                editingDetailsProject = project
            } label: {
                Label(L10n.text("プロジェクトを編集する"), systemImage: "pencil")
            }

            Button {
                editingInstructionsProject = project
            } label: {
                Label(L10n.text("指示を編集"), systemImage: "slider.horizontal.3")
            }

            Divider()

            Button(role: .destructive) {
                beginProjectDeletion(project)
            } label: {
                Label(L10n.text("プロジェクトを削除する"), systemImage: "trash")
            }
        }
    }

    // MARK: - Bottom Search Bar

    private var bottomSearchBar: some View {
        VStack(spacing: 0) {
            Divider()
                .opacity(0.2)

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)

                TextField(L10n.text("プロジェクトを検索"), text: $searchQuery)
                    .font(.system(size: 15))
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)

                if !searchQuery.isEmpty {
                    Button {
                        searchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(Color(uiColor: .secondarySystemFill))
            )
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(Color(uiColor: .systemBackground))
    }

    private func beginProjectDeletion(_ project: ProjectListEntry) {
        pendingProjectDeletion = PendingProjectDeletion(
            id: project.id,
            title: project.title,
            conversationCount: viewModel.projectConversationCount(projectId: project.id)
        )
        isProjectDeleteOptionsPresented = true
    }
}

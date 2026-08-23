import Foundation
import SwiftUI

struct ConversationListScreen: View {
    enum NavigationState: Equatable {
        case conversations
        case projectList
        case projectDetail(Int64)
    }

    @ObservedObject var viewModel: ConversationListViewModel
    @Binding var selection: Int64?

    var onSelect: (Int64) -> Void
    var onOpenSettings: () -> Void
    var onClose: (() -> Void)? = nil

    @State private var navigationState: NavigationState = .conversations
    @State private var isDeleteConfirmationPresented = false

    var body: some View {
        Group {
            switch navigationState {
            case .conversations:
                conversationsMainView
            case .projectList:
                ProjectListScreen(
                    viewModel: viewModel,
                    onBack: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            navigationState = .conversations
                        }
                    },
                    onSelectProject: { projectId in
                        withAnimation(.easeInOut(duration: 0.2)) {
                            navigationState = .projectDetail(projectId)
                        }
                    }
                )
            case .projectDetail(let projectId):
                ProjectDetailScreen(
                    viewModel: viewModel,
                    projectId: projectId,
                    onBack: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            navigationState = .projectList
                        }
                    },
                    onSelectConversation: { conversationId in
                        openConversation(id: conversationId)
                    }
                )
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .background(Color(uiColor: .systemBackground))
        .overlay(alignment: .bottom) {
            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(8)
            }
        }
        .alert(
            L10n.format("%d 件の会話を削除しますか？", viewModel.selectedConversationIds.count),
            isPresented: $isDeleteConfirmationPresented
        ) {
            Button(L10n.text("削除"), role: .destructive) {
                if let current = selection, viewModel.selectedConversationIds.contains(current) {
                    selection = nil
                }
                viewModel.deleteSelectedConversations()
            }
            Button(L10n.text("キャンセル"), role: .cancel) {}
        } message: {
            Text(L10n.format("選択した %d 件の会話を完全に削除します。この操作は取り消せません。", viewModel.selectedConversationIds.count))
        }
    }

    // MARK: - Conversations Main View

    private var conversationsMainView: some View {
        VStack(spacing: 0) {
            topHeader

            List {
                if !viewModel.isSelectionMode {
                    Section {
                        drawerActionRow(
                            title: L10n.text("プロジェクト"),
                            systemImage: "folder.fill",
                            badgeCount: viewModel.projects.count
                        ) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                navigationState = .projectList
                            }
                        }

                        drawerActionRow(
                            title: L10n.text("秘密チャット"),
                            systemImage: "lock"
                        ) {
                            createConversation(secret: true)
                        }
                    }
                }

                Section {
                    if viewModel.filteredConversations.isEmpty {
                        Text(L10n.text("会話がありません"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 6)
                            .listRowSeparator(.hidden)
                    } else {
                        ForEach(viewModel.filteredConversations) { entry in
                            conversationRow(entry)
                                .listRowInsets(
                                    EdgeInsets(
                                        top: 2,
                                        leading: 12,
                                        bottom: 2,
                                        trailing: 12
                                    )
                                )
                                .listRowSeparator(.hidden)
                        }
                    }
                } header: {
                    if !viewModel.filteredConversations.isEmpty && !viewModel.isSelectionMode {
                        Text(L10n.text("最近"))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .textCase(nil)
                            .padding(.leading, -4)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.clear)

            Divider()

            if viewModel.isSelectionMode {
                selectionActionBar
            } else {
                settingsFooter
            }
        }
    }

    // MARK: - Top Header

    private var topHeader: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField("検索", text: $viewModel.searchQuery)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)

                if !viewModel.searchQuery.isEmpty {
                    Button {
                        viewModel.searchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(Color(uiColor: .secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            if viewModel.isSelectionMode {
                Button {
                    viewModel.exitSelectionMode()
                } label: {
                    Text("キャンセル")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    viewModel.toggleSelectionMode()
                } label: {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.primary)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)

                Button {
                    createConversation(secret: false)
                } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.primary)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
            }

            if let onClose {
                Button {
                    onClose()
                } label: {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.primary)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    // MARK: - Settings Footer

    private var settingsFooter: some View {
        Button {
            onOpenSettings()
        } label: {
            HStack {
                Image(systemName: "gearshape")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("設定"))
        .accessibilityIdentifier("open-settings")
        .background(Color(uiColor: .systemBackground))
    }

    // MARK: - Selection Action Bar

    private var selectionActionBar: some View {
        HStack {
            Button {
                if viewModel.isAllSelected {
                    viewModel.deselectAll()
                } else {
                    viewModel.selectAll()
                }
            } label: {
                Text(viewModel.isAllSelected ? "全解除" : "すべて選択")
                    .font(.system(size: 14, weight: .medium))
            }
            .buttonStyle(.plain)

            Spacer()

            Text(L10n.format("%d 件選択中", viewModel.selectedConversationIds.count))
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                isDeleteConfirmationPresented = true
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(viewModel.selectedConversationIds.isEmpty ? Color.secondary : Color.red)
            }
            .buttonStyle(.plain)
            .disabled(viewModel.selectedConversationIds.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(uiColor: .systemBackground))
    }

    // MARK: - Drawer Action Row

    @ViewBuilder
    private func drawerActionRow(
        title: String,
        systemImage: String,
        badgeCount: Int? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.primary)
                    .frame(width: 24)

                Text(title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer()

                if let badgeCount, badgeCount > 0 {
                    Text("\(badgeCount)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(Color(uiColor: .secondarySystemFill))
                        )
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    // MARK: - Conversation Row

    @ViewBuilder
    private func conversationRow(_ entry: ConversationListEntry) -> some View {
        HStack(spacing: 8) {
            if viewModel.isSelectionMode {
                Image(systemName: viewModel.selectedConversationIds.contains(entry.id) ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(viewModel.selectedConversationIds.contains(entry.id) ? Color.accentColor : .secondary)
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 10) {
                    Text(entry.title)
                        .font(.body)
                        .lineLimit(1)
                        .foregroundStyle(.primary)

                    if entry.isSecret {
                        HStack(spacing: 4) {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 10, weight: .semibold))
                            Text(L10n.text("シークレット"))
                                .font(.caption2.weight(.semibold))
                        }
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.accentColor.opacity(0.12))
                        .clipShape(Capsule())
                    }

                    Spacer()
                }

                if let projectTitle = entry.projectTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !projectTitle.isEmpty {
                    Text(projectTitle)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(rowBackgroundColor(for: entry.id))
        )
        .onTapGesture {
            if viewModel.isSelectionMode {
                viewModel.toggleSelection(id: entry.id)
            } else {
                openConversation(id: entry.id)
            }
        }
        .contextMenu(viewModel.isSelectionMode ? nil : ContextMenu {
            Button {
                viewModel.isSelectionMode = true
                viewModel.selectedConversationIds.insert(entry.id)
            } label: {
                Label("選択", systemImage: "checkmark.circle")
            }

            if !viewModel.projects.isEmpty {
                ForEach(viewModel.projects) { project in
                    Button {
                        viewModel.assignConversation(id: entry.id, to: project.id)
                    } label: {
                        if entry.projectId == project.id {
                            Label(project.title, systemImage: "checkmark")
                        } else {
                            Text(project.title)
                        }
                    }
                }

                if entry.projectId != nil {
                    Button("プロジェクトから外す") {
                        viewModel.assignConversation(id: entry.id, to: nil)
                    }
                }
            }
        })
        .swipeActions(edge: .trailing, allowsFullSwipe: !viewModel.isSelectionMode) {
            if !viewModel.isSelectionMode {
                Button {
                    openConversation(id: entry.id)
                } label: {
                    Label("開く", systemImage: "arrow.up.forward.app")
                }
                .tint(.blue)

                Button(role: .destructive) {
                    viewModel.deleteConversation(id: entry.id)
                } label: {
                    Label("削除", systemImage: "trash")
                }
            }
        }
    }

    private func rowBackgroundColor(for id: Int64) -> Color {
        guard selection == id else { return Color.clear }
        return Color(uiColor: .secondarySystemFill)
    }

    private func createConversation(secret: Bool) {
        if let id = viewModel.createConversation(secret: secret) {
            openConversation(id: id)
        }
    }

    private func openConversation(id: Int64) {
        selection = id
        onSelect(id)
    }
}

struct CreateProjectSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: ConversationListViewModel

    @State private var title = ""
    @State private var instructions = ""

    var onCreate: (String, String?) -> Bool

    var body: some View {
        NavigationStack {
            Form {
                Section(L10n.text("プロジェクト名")) {
                    TextField(L10n.text("例: iOS移植"), text: $title)
                }
                Section(L10n.text("プロジェクト指示（任意）")) {
                    TextEditor(text: $instructions)
                        .frame(minHeight: 120)
                }

                if let error = viewModel.errorMessage {
                    Section {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(L10n.text("新しいプロジェクト"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.text("キャンセル")) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.text("作成")) {
                        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
                        let trimmedInstructions = instructions.trimmingCharacters(in: .whitespacesAndNewlines)
                        if onCreate(trimmedTitle, trimmedInstructions.isEmpty ? nil : trimmedInstructions) {
                            dismiss()
                        }
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .onAppear {
            viewModel.errorMessage = nil
        }
    }
}

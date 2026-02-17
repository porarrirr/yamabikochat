import Foundation
import SwiftUI

struct ConversationListScreen: View {
    private struct PendingProjectDeletion {
        let id: Int64
        let title: String
        let conversationCount: Int
    }

    @ObservedObject var viewModel: ConversationListViewModel
    @Binding var selection: Int64?

    var onSelect: (Int64) -> Void
    var onOpenSettings: () -> Void
    var onClose: (() -> Void)? = nil

    @State private var isCreateProjectPresented = false
    @State private var pendingProjectDeletion: PendingProjectDeletion?
    @State private var isProjectDeleteOptionsPresented = false

    var body: some View {
        VStack(spacing: 0) {
            topHeader

            List {
                Section {
                    drawerActionRow(
                        title: L10n.text("新しいプロジェクト"),
                        systemImage: "plus.square.on.square"
                    ) {
                        isCreateProjectPresented = true
                    }

                    drawerActionRow(
                        title: L10n.text("秘密チャット"),
                        systemImage: "lock"
                    ) {
                        createConversation(secret: true)
                    }
                }

                if !viewModel.projects.isEmpty {
                    Section {
                        projectFilterRow
                    }
                }

                Section {
                    if viewModel.filteredConversations.isEmpty {
                        Text("会話がありません")
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
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.clear)

            Divider()

            settingsFooter
        }
        .toolbar(.hidden, for: .navigationBar)
        .background(Color(uiColor: .systemBackground))
        .sheet(isPresented: $isCreateProjectPresented) {
            CreateProjectSheet { title, instructions in
                guard let projectId = viewModel.createProject(title: title, instructions: instructions) else { return }
                guard let conversationId = viewModel.createConversation(secret: false, projectId: projectId) else { return }
                openConversation(id: conversationId)
            }
        }
        .confirmationDialog(
            "プロジェクトを削除",
            isPresented: $isProjectDeleteOptionsPresented,
            titleVisibility: .visible
        ) {
            Button("プロジェクトのみ削除", role: .destructive) {
                guard let pending = pendingProjectDeletion else { return }
                viewModel.deleteProject(id: pending.id, mode: .projectOnly)
                clearPendingProjectDeletion()
            }

            Button("会話も削除", role: .destructive) {
                guard let pending = pendingProjectDeletion else { return }
                viewModel.deleteProject(id: pending.id, mode: .withConversations)
                clearPendingProjectDeletion()
            }

            Button("キャンセル", role: .cancel) {
                clearPendingProjectDeletion()
            }
        } message: {
            if let pending = pendingProjectDeletion {
                Text(L10n.format("「%@」には %d 件の会話があります。削除方法を選択してください。", pending.title, pending.conversationCount))
            } else {
                Text("削除方法を選択してください。")
            }
        }
        .overlay(alignment: .bottom) {
            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(8)
            }
        }
        .onChange(of: isProjectDeleteOptionsPresented) { _, isPresented in
            if !isPresented {
                clearPendingProjectDeletion()
            }
        }
    }

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

            Button {
                createConversation(secret: false)
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.primary)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)

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

    private var settingsFooter: some View {
        Button {
            onOpenSettings()
        } label: {
            HStack(spacing: 12) {
                Circle()
                    .fill(Color.orange)
                    .frame(width: 30, height: 30)
                    .overlay {
                        Text("GR")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundStyle(.white)
                    }

                Text("Gro")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer()

                Image(systemName: "gearshape")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Color(uiColor: .systemBackground))
    }

    private var projectFilterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                projectChip(
                    title: L10n.text("すべて"),
                    iconName: "tray.full",
                    colorHex: "#8B8B8B",
                    selected: viewModel.selectedProjectId == nil
                ) {
                    viewModel.selectProject(nil)
                }

                ForEach(viewModel.projects) { project in
                    projectChip(
                        title: project.title,
                        iconName: project.iconName,
                        colorHex: project.colorHex,
                        selected: viewModel.selectedProjectId == project.id
                    ) {
                        viewModel.selectProject(project.id)
                    }
                    .contextMenu {
                        Button(role: .destructive) {
                            beginProjectDeletion(project)
                        } label: {
                            Label("プロジェクトを削除", systemImage: "trash")
                        }
                    }
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 4)
        }
        .listRowInsets(EdgeInsets(top: 2, leading: 12, bottom: 2, trailing: 12))
        .listRowSeparator(.hidden)
    }

    @ViewBuilder
    private func projectChip(
        title: String,
        iconName: String,
        colorHex: String,
        selected: Bool,
        onTap: @escaping () -> Void
    ) -> some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Image(systemName: iconName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(selected ? .white : Color(hex: colorHex))
                Text(title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .foregroundStyle(selected ? .white : .primary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(selected ? Color(hex: colorHex) : Color(uiColor: .secondarySystemBackground))
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func drawerActionRow(
        title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.primary)
                    .frame(width: 20)

                Text(title)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    @ViewBuilder
    private func conversationRow(_ entry: ConversationListEntry) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 10) {
                Text(entry.title)
                    .font(.body)
                    .lineLimit(1)
                    .foregroundStyle(.primary)

                if entry.isSecret {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 12))
                }

                Spacer()
            }

            if let projectTitle = entry.projectTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !projectTitle.isEmpty {
                Text(projectTitle)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
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
            openConversation(id: entry.id)
        }
        .contextMenu {
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
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
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

    private func beginProjectDeletion(_ project: ProjectListEntry) {
        pendingProjectDeletion = PendingProjectDeletion(
            id: project.id,
            title: project.title,
            conversationCount: viewModel.projectConversationCount(projectId: project.id)
        )
        isProjectDeleteOptionsPresented = true
    }

    private func clearPendingProjectDeletion() {
        pendingProjectDeletion = nil
    }
}

private struct CreateProjectSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var instructions = ""

    var onCreate: (String, String?) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("プロジェクト名") {
                    TextField("例: iOS移植", text: $title)
                }
                Section("プロジェクト指示（任意）") {
                    TextEditor(text: $instructions)
                        .frame(minHeight: 120)
                }
            }
            .navigationTitle("新しいプロジェクト")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("作成") {
                        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
                        let trimmedInstructions = instructions.trimmingCharacters(in: .whitespacesAndNewlines)
                        onCreate(trimmedTitle, trimmedInstructions.isEmpty ? nil : trimmedInstructions)
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

private extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int = UInt64(0)
        Scanner(string: cleaned).scanHexInt64(&int)

        let r, g, b: UInt64
        switch cleaned.count {
        case 6:
            (r, g, b) = (int >> 16, int >> 8 & 0xFF, int & 0xFF)
        default:
            (r, g, b) = (58, 122, 254)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: 1
        )
    }
}

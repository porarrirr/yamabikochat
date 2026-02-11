import SwiftUI

struct ConversationListScreen: View {
    @ObservedObject var viewModel: ConversationListViewModel
    @Binding var selection: Int64?

    var onSelect: (Int64) -> Void
    var onOpenSettings: () -> Void
    var onClose: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            topHeader

            List {
                Section {
                    drawerActionRow(
                        title: "新しいプロジェクト",
                        systemImage: "plus.square.on.square"
                    ) {
                        createConversation(secret: false)
                    }

                    drawerActionRow(
                        title: "秘密チャット",
                        systemImage: "lock"
                    ) {
                        createConversation(secret: true)
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
        .overlay(alignment: .bottom) {
            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(8)
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
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(rowBackgroundColor(for: entry.id))
        )
        .onTapGesture {
            selection = entry.id
            onSelect(entry.id)
        }
        .swipeActions {
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
            selection = id
            onSelect(id)
        }
    }
}

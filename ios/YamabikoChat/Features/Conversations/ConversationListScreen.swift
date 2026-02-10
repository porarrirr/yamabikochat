import SwiftUI

struct ConversationListScreen: View {
    @ObservedObject var viewModel: ConversationListViewModel
    @Binding var selection: Int64?

    var onSelect: (Int64) -> Void
    var onOpenSettings: () -> Void

    var body: some View {
        List(selection: $selection) {
            ForEach(viewModel.filteredConversations) { entry in
                NavigationLink(value: entry.id) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(entry.title)
                                .font(.headline)
                                .lineLimit(1)
                            if entry.isSecret {
                                Image(systemName: "lock.fill")
                                    .foregroundStyle(.secondary)
                                    .imageScale(.small)
                            }
                        }
                        if let preview = entry.lastMessagePreview, !preview.isEmpty {
                            Text(preview)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                }
                .tag(entry.id)
                .swipeActions {
                    Button(role: .destructive) {
                        viewModel.deleteConversation(id: entry.id)
                    } label: {
                        Label("削除", systemImage: "trash")
                    }
                }
            }
        }
        .searchable(text: $viewModel.searchQuery, prompt: "検索")
        .toolbar {
            ToolbarItemGroup(placement: .topBarLeading) {
                Button {
                    if let id = viewModel.createConversation(secret: false) {
                        selection = id
                        onSelect(id)
                    }
                } label: {
                    Label("新規", systemImage: "plus")
                }

                Button {
                    if let id = viewModel.createConversation(secret: true) {
                        selection = id
                        onSelect(id)
                    }
                } label: {
                    Label("秘密", systemImage: "lock")
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    onOpenSettings()
                } label: {
                    Label("設定", systemImage: "gearshape")
                }
            }
        }
        .onChange(of: selection) { _, newValue in
            guard let id = newValue else { return }
            onSelect(id)
        }
        .overlay(alignment: .bottom) {
            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(8)
            }
        }
    }
}

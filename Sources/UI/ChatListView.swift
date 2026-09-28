import SwiftUI

struct ChatListView: View {
    @EnvironmentObject private var chats: ChatStore
    @EnvironmentObject private var models: ModelStore
    @EnvironmentObject private var session: Session
    @EnvironmentObject private var prompts: PromptStore

    @State private var query = ""
    @State private var renameTarget: Chat?
    @State private var renameText = ""
    @State private var deleteTarget: Chat?

    private var filtered: [Chat] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return chats.chats }
        return chats.chats.filter { chat in
            chat.title.lowercased().contains(trimmed) ||
            chat.messages.contains { $0.text.lowercased().contains(trimmed) }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if let chat = chats.currentChat {
                    Section {
                        NavigationLink {
                            ChatView(chatID: chat.id)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(chat.title).font(.body.weight(.semibold))
                                    Text("\(chat.messages.count) messages · \(prompts.selected?.name ?? "Assistant")")
                                        .font(.caption).foregroundStyle(Theme.textDim)
                                }
                                Spacer()
                                Image(systemName: "arrow.right.circle.fill").foregroundStyle(Theme.accent)
                            }
                        }
                    } header: { SectionHeader(title: "Current") }
                }

                Section {
                    ForEach(filtered) { chat in
                        Button {
                            chats.currentChatID = chat.id
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(chat.title)
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    Text(chat.messages.last?.text.prefix(60) ?? "empty")
                                        .font(.caption)
                                        .foregroundStyle(Theme.textDim)
                                        .lineLimit(1)
                                }
                                Spacer()
                                if chats.currentChatID == chat.id {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent)
                                }
                            }
                        }
                        .swipeActions(edge: .leading) {
                            Button {
                                renameTarget = chat
                                renameText = chat.title
                            } label: { Label("Rename", systemImage: "pencil") }
                            .tint(Theme.accent)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { deleteTarget = chat } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .contextMenu {
                            Button("Rename") { renameTarget = chat; renameText = chat.title }
                            ShareLink(item: chats.exportText(chat)) { Label("Export", systemImage: "square.and.arrow.up") }
                            Button("Delete", role: .destructive) { deleteTarget = chat }
                        }
                    }
                } header: { SectionHeader(title: "All chats (\(chats.chats.count))") }
            }
            .searchable(text: $query, prompt: "Search chats")
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Cortex")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(models.selectedModel?.name ?? "no model")
                            .font(.caption2).lineLimit(1)
                        Text(session.status.isEmpty ? "idle" : session.status)
                            .font(.caption2).foregroundStyle(Theme.textDim).lineLimit(1)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { chats.newChat() } label: { Image(systemName: "square.and.pencil") }
                }
            }
            .alert("Rename chat", isPresented: Binding(get: { renameTarget != nil }, set: { if !$0 { renameTarget = nil } })) {
                TextField("Title", text: $renameText)
                Button("Save") {
                    if let target = renameTarget { chats.rename(target, to: renameText) }
                    renameTarget = nil
                }
                Button("Cancel", role: .cancel) { renameTarget = nil }
            }
            .alert("Delete chat?", isPresented: Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } })) {
                Button("Delete", role: .destructive) {
                    if let target = deleteTarget { chats.delete(target) }
                    deleteTarget = nil
                }
                Button("Cancel", role: .cancel) { deleteTarget = nil }
            } message: {
                Text("This removes the conversation from the device.")
            }
        }
    }
}

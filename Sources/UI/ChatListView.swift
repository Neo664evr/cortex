import SwiftUI

struct ChatListView: View {
    @EnvironmentObject private var chats: ChatStore
    @EnvironmentObject private var models: ModelStore
    @EnvironmentObject private var session: Session

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(chats.chats) { chat in
                        Button {
                            chats.currentChatID = chat.id
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(chat.title)
                                        .font(.body.weight(chats.currentChatID == chat.id ? .semibold : .regular))
                                        .foregroundStyle(.primary)
                                    Text(chat.messages.isEmpty ? "empty" : "\(chat.messages.count) messages")
                                        .font(.caption)
                                        .foregroundStyle(Theme.textDim)
                                }
                                Spacer()
                                if chats.currentChatID == chat.id {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent)
                                }
                            }
                        }
                    }
                    .onDelete { indexSet in
                        for index in indexSet { chats.delete(chats.chats[index]) }
                    }
                } header: {
                    SectionHeader(title: "Conversations")
                }

                if let chat = chats.currentChat {
                    Section {
                        NavigationLink {
                            ChatView(chatID: chat.id)
                        } label: {
                            Label("Open \"\(chat.title)\"", systemImage: "arrow.right.circle")
                                .foregroundStyle(Theme.accent)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Cortex")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Text(models.selectedModel?.name ?? "no model")
                        .font(.caption)
                        .foregroundStyle(Theme.textDim)
                        .lineLimit(1)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        chats.newChat()
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                }
            }
        }
    }
}

import Foundation
import SwiftUI

struct Attachment: Identifiable, Codable, Hashable {
    enum Kind: String, Codable { case image, text }
    var id = UUID()
    var name: String
    var kind: Kind
    var text: String?
    var imagePath: String?

    var icon: String {
        switch kind {
        case .image: return "photo"
        case .text: return name.lowercased().hasSuffix(".pdf") ? "doc.richtext" : "doc.text"
        }
    }
}

struct ChatMessage: Identifiable, Codable, Hashable {
    enum Role: String, Codable { case user, assistant }
    var id = UUID()
    var role: Role
    var text: String
    var attachments: [Attachment] = []
    var stats: String? = nil
    var createdAt = Date()
}

struct Chat: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String = "New chat"
    var messages: [ChatMessage] = []
    var updatedAt = Date()
}

@MainActor
final class ChatStore: ObservableObject {
    @Published var chats: [Chat] = []
    @Published var currentChatID: UUID?

    private let storeURL: URL

    init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        storeURL = documents.appendingPathComponent("chats.json")
        load()
        if chats.isEmpty { newChat() }
        currentChatID = chats.first?.id
    }

    var currentChat: Chat? {
        guard let currentChatID else { return nil }
        return chats.first { $0.id == currentChatID }
    }

    func newChat() {
        var chat = Chat()
        chat.title = "New chat"
        chats.insert(chat, at: 0)
        currentChatID = chat.id
        save()
    }

    func delete(_ chat: Chat) {
        chats.removeAll { $0.id == chat.id }
        if currentChatID == chat.id { currentChatID = chats.first?.id }
        if chats.isEmpty { newChat() }
        save()
    }

    func rename(_ chat: Chat, to title: String) {
        guard let index = chats.firstIndex(where: { $0.id == chat.id }) else { return }
        chats[index].title = title
        save()
    }

    func retitle(_ chatID: UUID, with text: String) {
        guard let index = chats.firstIndex(where: { $0.id == chatID }) else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        chats[index].title = String(trimmed.prefix(40))
        save()
    }

    func replaceMessages(_ messages: [ChatMessage], in chatID: UUID) {
        guard let index = chats.firstIndex(where: { $0.id == chatID }) else { return }
        chats[index].messages = messages
        chats[index].updatedAt = Date()
        save()
    }

    func append(_ message: ChatMessage, to chatID: UUID) {
        guard let index = chats.firstIndex(where: { $0.id == chatID }) else { return }
        chats[index].messages.append(message)
        chats[index].updatedAt = Date()
        if message.role == .user, chats[index].title == "New chat" {
            let trimmed = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
            chats[index].title = trimmed.isEmpty ? "Image" : String(trimmed.prefix(40))
        }
        save()
    }

    func update(messageID: UUID, in chatID: UUID, text: String) {
        guard let chatIndex = chats.firstIndex(where: { $0.id == chatID }),
              let messageIndex = chats[chatIndex].messages.firstIndex(where: { $0.id == messageID }) else { return }
        chats[chatIndex].messages[messageIndex].text = text
        chats[chatIndex].updatedAt = Date()
        save()
    }

    func setStats(_ stats: String, messageID: UUID, in chatID: UUID) {
        guard let chatIndex = chats.firstIndex(where: { $0.id == chatID }),
              let messageIndex = chats[chatIndex].messages.firstIndex(where: { $0.id == messageID }) else { return }
        chats[chatIndex].messages[messageIndex].stats = stats
        save()
    }

    func exportText(_ chat: Chat) -> String {
        var out = "# \(chat.title)\n\n"
        for message in chat.messages {
            out += message.role == .user ? "**You**" : "**Cortex**"
            out += "\n\(message.text)\n\n"
            for attachment in message.attachments {
                out += "_(attachment: \(attachment.name))_\n"
            }
        }
        return out
    }

    func remove(messageID: UUID, in chatID: UUID) {
        guard let chatIndex = chats.firstIndex(where: { $0.id == chatID }) else { return }
        chats[chatIndex].messages.removeAll { $0.id == messageID }
        save()
    }

    func removeLastTurn(in chatID: UUID) {
        guard let index = chats.firstIndex(where: { $0.id == chatID }) else { return }
        while let last = chats[index].messages.last, last.role == .assistant {
            chats[index].messages.removeLast()
        }
        save()
    }

    func messages(for chatID: UUID) -> [ChatMessage] {
        chats.first { $0.id == chatID }?.messages ?? []
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: storeURL) else { return }
        if let decoded = try? JSONDecoder().decode([Chat].self, from: data) { chats = decoded }
    }

    func save() {
        guard let data = try? JSONEncoder().encode(chats) else { return }
        try? data.write(to: storeURL, options: .atomic)
    }
}

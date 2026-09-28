import SwiftUI

struct ChatView: View {
    let chatID: UUID

    @EnvironmentObject private var chats: ChatStore
    @EnvironmentObject private var models: ModelStore
    @EnvironmentObject private var session: Session
    @State private var draft = ""
    @State private var pendingAttachments: [Attachment] = []
    @State private var showFileImporter = false

    private var messages: [ChatMessage] { chats.messages(for: chatID) }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(messages) { message in
                            MessageBubble(message: message, onSpeak: {
                                session.speech.speak(message.text)
                            })
                            .id(message.id)
                        }
                        if session.isGenerating {
                            HStack(spacing: 8) {
                                ProgressView().tint(Theme.accent)
                                Text("generating…").font(.caption).foregroundStyle(Theme.textDim)
                            }
                            .id("generating")
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                }
                .onChange(of: messages.count) { _, _ in
                    if let last = messages.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                }
                .onChange(of: messages.last?.text) { _, _ in
                    if let last = messages.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }

            ComposerView(
                draft: $draft,
                attachments: $pendingAttachments,
                isGenerating: session.isGenerating,
                onSend: {
                    let toSend = pendingAttachments
                    let text = draft
                    draft = ""
                    pendingAttachments = []
                    session.send(text: text, attachments: toSend, chatID: chatID, chats: chats, models: models)
                },
                onStop: { session.stop() }
            )
        }
        .background(Theme.background)
        .navigationTitle(chats.currentChat?.title ?? "Chat")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        session.regenerate(chatID: chatID, chats: chats, models: models)
                    } label: { Label("Regenerate", systemImage: "arrow.clockwise") }

                    Toggle(isOn: Binding(
                        get: { session.speakReplies },
                        set: { session.speakReplies = $0; session.persist() }
                    )) { Label("Speak replies", systemImage: "speaker.wave.2") }

                    Button(role: .destructive) {
                        session.stop()
                        chats.removeLastTurn(in: chatID)
                    } label: { Label("Delete last reply", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .onAppear {
            chats.currentChatID = chatID
        }
    }
}

struct MessageBubble: View {
    let message: ChatMessage
    var onSpeak: () -> Void

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 40) }
            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 6) {
                if !message.attachments.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(message.attachments) { attachment in
                            Label(attachment.name, systemImage: attachment.icon)
                                .font(.caption2)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Theme.surfaceAlt, in: Capsule())
                                .lineLimit(1)
                        }
                    }
                }
                if !message.text.isEmpty || message.role == .user {
                    Text(message.text.isEmpty ? "…" : message.text)
                        .textSelection(.enabled)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(
                            message.role == .user ? Theme.accent.opacity(0.22) : Theme.surface,
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                        )
                }
                if message.role == .assistant, !message.text.isEmpty {
                    Button {
                        UIPasteboard.general.string = message.text
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                            .font(.caption2)
                            .foregroundStyle(Theme.textDim)
                    }
                    .buttonStyle(.plain)
                }
            }
            if message.role == .assistant { Spacer(minLength: 40) }
        }
    }
}

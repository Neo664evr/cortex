import SwiftUI

struct ChatView: View {
    let chatID: UUID

    @EnvironmentObject private var chats: ChatStore
    @EnvironmentObject private var models: ModelStore
    @EnvironmentObject private var session: Session
    @EnvironmentObject private var prompts: PromptStore

    @State private var draft = ""
    @State private var pendingAttachments: [Attachment] = []

    private var messages: [ChatMessage] { chats.messages(for: chatID) }
    private var systemPrompt: String { prompts.selected?.prompt ?? session.settings.systemPrompt }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        if messages.isEmpty { emptyState }
                        ForEach(messages) { message in
                            MessageBubble(
                                message: message,
                                showStats: session.showStats,
                                onSpeak: { session.speech.speak(message.text) },
                                onCopy: { UIPasteboard.general.string = message.text },
                                onDelete: { chats.remove(messageID: message.id, in: chatID) },
                                onRegenerate: {
                                    session.branch(from: message.id, chatID: chatID, chats: chats,
                                                   models: models, systemPrompt: systemPrompt)
                                }
                            )
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
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: messages.count) { _, _ in scroll(proxy) }
                .onChange(of: messages.last?.text) { _, _ in scroll(proxy) }
                .onChange(of: session.isGenerating) { _, _ in scroll(proxy) }
            }

            ComposerView(
                draft: $draft,
                attachments: $pendingAttachments,
                isGenerating: session.isGenerating,
                onSend: {
                    let attachments = pendingAttachments
                    let text = draft
                    draft = ""
                    pendingAttachments = []
                    session.send(text: text, attachments: attachments, chatID: chatID,
                                 chats: chats, models: models, systemPrompt: systemPrompt)
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
                        session.regenerate(chatID: chatID, chats: chats, models: models, systemPrompt: systemPrompt)
                    } label: { Label("Regenerate last reply", systemImage: "arrow.clockwise") }

                    Toggle(isOn: Binding(get: { session.speakReplies },
                                         set: { session.speakReplies = $0; session.persist() })) {
                        Label("Speak replies", systemImage: "speaker.wave.2")
                    }

                    if session.speech.isSpeaking {
                        Button { session.speech.stop() } label: { Label("Stop speaking", systemImage: "speaker.slash") }
                    }

                    ShareLink(item: chats.exportText(chats.currentChat ?? Chat())) {
                        Label("Export chat", systemImage: "square.and.arrow.up")
                    }

                    Button(role: .destructive) {
                        session.stop()
                        chats.removeLastTurn(in: chatID)
                    } label: { Label("Delete last reply", systemImage: "trash") }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .onAppear { chats.currentChatID = chatID }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Ready").font(.title3.weight(.semibold))
            Text("Model: \(models.selectedModel?.name ?? "none selected")")
            Text("Persona: \(prompts.selected?.name ?? "Assistant")")
            if models.selectedProjector == nil {
                Text("Tip: import an mmproj-*.gguf in Models to attach photos.")
            }
            Text("Attach photos, PDFs or text files with the paperclip.")
        }
        .font(.footnote)
        .foregroundStyle(Theme.textDim)
        .padding(.vertical, 8)
    }

    private func scroll(_ proxy: ScrollViewProxy) {
        if let last = messages.last {
            withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(last.id, anchor: .bottom) }
        } else {
            withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo("generating", anchor: .bottom) }
        }
    }
}

struct MessageBubble: View {
    let message: ChatMessage
    let showStats: Bool
    var onSpeak: () -> Void
    var onCopy: () -> Void
    var onDelete: () -> Void
    var onRegenerate: () -> Void

    var body: some View {
        HStack(alignment: .top) {
            if message.role == .user { Spacer(minLength: 36) }
            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 6) {
                if !message.attachments.isEmpty { attachmentStrip }
                if !message.text.isEmpty || message.role == .user {
                    Group {
                        if message.role == .assistant {
                            MarkdownText(text: message.text.isEmpty ? "…" : message.text)
                        } else {
                            Text(message.text)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(message.role == .user ? Theme.accent.opacity(0.22) : Theme.surface,
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                if let stats = message.stats, showStats, message.role == .assistant {
                    Text(stats).font(.caption2).foregroundStyle(Theme.textDim)
                }
                if message.role == .assistant, !message.text.isEmpty {
                    HStack(spacing: 14) {
                        Button(action: onCopy) { Image(systemName: "doc.on.doc") }
                        Button(action: onSpeak) { Image(systemName: "speaker.wave.2") }
                        Button(action: onRegenerate) { Image(systemName: "arrow.clockwise") }
                        Button(action: onDelete) { Image(systemName: "trash") }
                    }
                    .font(.caption)
                    .foregroundStyle(Theme.textDim)
                    .buttonStyle(.plain)
                }
            }
            if message.role == .assistant { Spacer(minLength: 36) }
        }
        .contextMenu {
            Button("Copy") { onCopy() }
            Button("Delete", role: .destructive) { onDelete() }
        }
    }

    private var attachmentStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(message.attachments) { attachment in
                    if attachment.kind == .image, let path = attachment.imagePath,
                       let image = UIImage(contentsOfFile: path) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 66, height: 66)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    } else {
                        Label(attachment.name, systemImage: attachment.icon)
                            .font(.caption2)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(Theme.surfaceAlt, in: Capsule())
                            .lineLimit(1)
                    }
                }
            }
        }
    }
}

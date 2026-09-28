import Foundation
import SwiftUI

@MainActor
final class Session: ObservableObject {
    @Published var isGenerating = false
    @Published var status: String = ""
    @Published var errorMessage: String?
    @Published var settings = GenSettings()
    @Published var speakReplies = false

    let engine = Inference()
    let speech = Speech()

    private let settingsKey = "cortex.settings"

    init() {
        if let data = UserDefaults.standard.data(forKey: settingsKey),
           let decoded = try? JSONDecoder().decode(GenSettings.self, from: data) {
            settings = decoded
        }
        if UserDefaults.standard.object(forKey: "cortex.speak") != nil {
            speakReplies = UserDefaults.standard.bool(forKey: "cortex.speak")
        }
    }

    func persist() {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: settingsKey)
        }
        UserDefaults.standard.set(speakReplies, forKey: "cortex.speak")
    }

    func loadSelection(models: ModelStore) async {
        guard let model = models.selectedModel else {
            status = "No model imported yet"
            return
        }
        let mmproj = models.selectedProjector?.path
        status = "Loading \(model.name)…"
        let snapshot = settings
        do {
            try await Task.detached(priority: .userInitiated) {
                try self.engine.load(modelPath: model.path, mmprojPath: mmproj, settings: snapshot)
            }.value
            status = self.engine.hasVision ? "Ready — vision enabled" : "Ready"
        } catch {
            status = "Load failed"
            errorMessage = error.localizedDescription
        }
    }

    func send(text: String, attachments: [Attachment], chatID: UUID, chats: ChatStore, models: ModelStore) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !attachments.isEmpty else { return }

        let userMessage = ChatMessage(role: .user, text: trimmed, attachments: attachments)
        chats.append(userMessage, to: chatID)
        let history = chats.messages(for: chatID)

        let assistant = ChatMessage(role: .assistant, text: "")
        chats.append(assistant, to: chatID)
        isGenerating = true
        errorMessage = nil

        Task {
            if !engine.isLoaded || engine.loadedModel != models.selectedModel?.path {
                await loadSelection(models: models)
            }
            guard engine.isLoaded else { isGenerating = false; return }

            var buffer = ""
            do {
                let stream = engine.stream(payload: TurnPayload(systemPrompt: settings.systemPrompt, history: history), settings: settings)
                for try await delta in stream {
                    buffer += delta
                    chats.update(messageID: assistant.id, in: chatID, text: buffer)
                }
            } catch {
                errorMessage = error.localizedDescription
                if buffer.isEmpty {
                    buffer = "(generation failed: \(error.localizedDescription))"
                    chats.update(messageID: assistant.id, in: chatID, text: buffer)
                }
            }
            isGenerating = false
            if speakReplies, !buffer.isEmpty { speech.speak(buffer) }
        }
    }

    func stop() {
        engine.stop()
        speech.stop()
        isGenerating = false
    }

    func regenerate(chatID: UUID, chats: ChatStore, models: ModelStore) {
        chats.removeLastTurn(in: chatID)
        isGenerating = false
        Task {
            if !engine.isLoaded { await loadSelection(models: models) }
            let history = chats.messages(for: chatID)
            let assistant = ChatMessage(role: .assistant, text: "")
            chats.append(assistant, to: chatID)
            isGenerating = true
            var buffer = ""
            do {
                let stream = engine.stream(payload: TurnPayload(systemPrompt: settings.systemPrompt, history: history), settings: settings)
                for try await delta in stream {
                    buffer += delta
                    chats.update(messageID: assistant.id, in: chatID, text: buffer)
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            isGenerating = false
        }
    }
}

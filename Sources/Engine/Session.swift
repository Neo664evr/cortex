import Foundation
import SwiftUI

struct GenSettings: Codable, Equatable {
    var contextLength: Int32 = 8192
    var maxTokens: Int32 = 512
    var temperature: Float = 0.7
    var topP: Float = 0.95
    var topK: Int32 = 40
    var repeatPenalty: Float = 1.1
    var gpuLayers: Int32 = 999
    var lowMemory = false
    var systemPrompt = "You are Cortex, a helpful on-device assistant. Answer clearly and never claim to be a cloud service."
}

@MainActor
final class Session: ObservableObject {
    @Published var settings = GenSettings()
    @Published var status = ""
    @Published var errorMessage: String?
    @Published var isGenerating = false
    @Published var currentChatID: UUID?
    @Published var speakReplies = false
    @Published var showStats = true
    @Published var lastStats: Inference.GenStats?
    @Published var crashNote: String?
    @Published var diagnosticsReport = ""

    let engine = Inference()
    let speech = Speech()
    let voice = VoiceInput()

    private var generationTask: Task<Void, Never>?
    private let defaults = UserDefaults.standard

    init() {
        load()
        if let stale = Breadcrumb.stale() {
            crashNote = "Last session stopped while: \(stale)"
            settings.lowMemory = true
            settings.contextLength = 2048
            settings.maxTokens = 256
            persist()
            LogSink.shared.append("crash breadcrumb found: \(stale) — switched to low memory mode")
        }
        Breadcrumb.clear()
    }

    /// Trims the conversation so the prompt cannot blow past the loaded context window.
    private func trimmed(_ messages: [ChatMessage]) -> [ChatMessage] {
        var result = messages
        let budget = Int(settings.contextLength) * 3
        while result.count > 2, result.reduce(0, { $0 + $1.text.count }) > budget {
            result.removeFirst()
        }
        return result
    }

    func persist() {
        if let data = try? JSONEncoder().encode(settings) {
            defaults.set(data, forKey: "cortex.settings")
        }
        defaults.set(speakReplies, forKey: "cortex.speakReplies")
        defaults.set(showStats, forKey: "cortex.showStats")
    }

    func load() {
        if let data = defaults.data(forKey: "cortex.settings"),
           let decoded = try? JSONDecoder().decode(GenSettings.self, from: data) {
            settings = decoded
        }
        if defaults.object(forKey: "cortex.speakReplies") != nil {
            speakReplies = defaults.bool(forKey: "cortex.speakReplies")
        }
        if defaults.object(forKey: "cortex.showStats") != nil {
            showStats = defaults.bool(forKey: "cortex.showStats")
        }
    }

    func modelInfo() -> [Inference.ModelFact] { engine.modelInfo() }

    /// Runs the engine smoke test and stores the report for the Diagnostics screen.
    func runDiagnostics(models: ModelStore, gpuLayers: Int32) async {
        guard let model = models.selectedModel else {
            diagnosticsReport = "No model selected."
            return
        }
        status = "diagnostics…"
        diagnosticsReport = "…running, this can take a minute"
        let report = await engine.smokeTest(modelPath: model.path,
                                            projectorPath: models.selectedProjector?.path,
                                            settings: settings,
                                            gpuLayers: gpuLayers)
        diagnosticsReport = report + "\n— engine log —\n" + LogSink.shared.tail()
        status = engine.isLoaded ? "ready · \(engine.contextSize) ctx" : "idle"
    }

    /// Free memory hint for the UI.
    var memoryNote: String { engine.deviceMemoryNote }

    func loadSelection(models: ModelStore, force: Bool) async {
        guard let model = models.selectedModel else {
            errorMessage = "Import a GGUF model first."
            return
        }
        if !force, engine.loadedModel == model.path, engine.isLoaded { return }
        status = "loading \(model.name)…"
        errorMessage = nil
        Breadcrumb.set("loading \(model.name) · ctx \(settings.contextLength) · gpu \(settings.gpuLayers)")
        do {
            try await engine.loadAsync(modelPath: model.path,
                                       projectorPath: models.selectedProjector?.path,
                                       settings: settings)
            Breadcrumb.set("loaded \(model.name)")
        } catch {
            errorMessage = error.localizedDescription
            status = ""
            Breadcrumb.clear()
            return
        }
        status = engine.isLoaded ? "ready · \(engine.hasVision ? "vision " : "")\(engine.contextSize) ctx" : "not loaded"
    }

    func unload() {
        stop()
        engine.unload()
        status = "unloaded"
    }

    func stop() {
        generationTask?.cancel()
        generationTask = nil
        isGenerating = false
        engine.stop()
    }

    func send(text: String, attachments: [Attachment], chatID: UUID, chats: ChatStore, models: ModelStore, systemPrompt: String) {
        guard !isGenerating else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !attachments.isEmpty else { return }
        chats.append(ChatMessage(role: .user, text: trimmed, attachments: attachments), to: chatID)
        if chats.chats.first(where: { $0.id == chatID })?.title == "New chat", !trimmed.isEmpty {
            chats.retitle(chatID, with: trimmed)
        }
        generate(chatID: chatID, chats: chats, models: models, systemPrompt: systemPrompt)
    }

    /// Regenerates an assistant reply, keeping the conversation up to that point.
    func branch(from messageID: UUID, chatID: UUID, chats: ChatStore, models: ModelStore, systemPrompt: String) {
        guard !isGenerating else { return }
        guard let index = chats.messages(for: chatID).firstIndex(where: { $0.id == messageID }) else { return }
        let kept = Array(chats.messages(for: chatID).prefix(index))
        guard let last = kept.last, last.role == .user else {
            chats.replaceMessages(kept, in: chatID)
            return
        }
        chats.replaceMessages(kept, in: chatID)
        generate(chatID: chatID, chats: chats, models: models, systemPrompt: systemPrompt)
    }

    func regenerate(chatID: UUID, chats: ChatStore, models: ModelStore, systemPrompt: String) {
        guard !isGenerating else { return }
        var messages = chats.messages(for: chatID)
        while let last = messages.last, last.role == .assistant { messages.removeLast() }
        guard !messages.isEmpty else { return }
        chats.replaceMessages(messages, in: chatID)
        generate(chatID: chatID, chats: chats, models: models, systemPrompt: systemPrompt)
    }

    private func generate(chatID: UUID, chats: ChatStore, models: ModelStore, systemPrompt: String) {
        let history = trimmed(chats.messages(for: chatID))
        let prompt = systemPrompt.isEmpty ? settings.systemPrompt : systemPrompt
        let projectorPath = models.selectedProjector?.path
        isGenerating = true
        errorMessage = nil

        generationTask = Task { [weak self] in
            guard let self else { return }
            do {
                if let model = models.selectedModel,
                   !self.engine.isLoaded || self.engine.loadedModel != model.path {
                    self.status = "loading \(model.name)…"
                    Breadcrumb.set("loading \(model.name) · ctx \(self.settings.contextLength) · gpu \(self.settings.gpuLayers)")
                    try await self.engine.loadAsync(modelPath: model.path, projectorPath: projectorPath, settings: self.settings)
                    Breadcrumb.set("loaded \(model.name)")
                }
                guard let model = models.selectedModel else {
                    self.isGenerating = false
                    self.errorMessage = "No model selected."
                    return
                }

                let placeholder = ChatMessage(role: .assistant, text: "")
                chats.append(placeholder, to: chatID)
                var buffer = ""
                var lastUpdate = Date.distantPast

                Breadcrumb.set("generating · ctx \(self.settings.contextLength) · gpu \(self.settings.gpuLayers)")
                let payload = TurnPayload(systemPrompt: prompt, history: history)
                for try await piece in self.engine.stream(payload: payload, settings: self.settings) {
                    if Task.isCancelled { break }
                    buffer += piece
                    let now = Date()
                    if now.timeIntervalSince(lastUpdate) > 0.08 {
                        lastUpdate = now
                        chats.update(messageID: placeholder.id, in: chatID, text: buffer)
                    }
                }
                chats.update(messageID: placeholder.id, in: chatID, text: buffer)

                if let stats = self.engine.lastStats {
                    self.lastStats = stats
                    chats.setStats(stats.label, messageID: placeholder.id, in: chatID)
                }
                Breadcrumb.clear()
                if self.speakReplies, !buffer.isEmpty { self.speech.speak(buffer) }
                self.status = self.engine.isLoaded ? "ready · \(self.engine.contextSize) ctx" : "idle"
            } catch {
                self.errorMessage = error.localizedDescription
                chats.append(ChatMessage(role: .assistant, text: "⚠️ \(error.localizedDescription)"), to: chatID)
            }
            self.isGenerating = false
        }
    }
}

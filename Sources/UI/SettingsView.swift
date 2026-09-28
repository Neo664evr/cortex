import SwiftUI
import UIKit

struct SettingsView: View {
    @EnvironmentObject private var session: Session
    @EnvironmentObject private var prompts: PromptStore
    @EnvironmentObject private var chats: ChatStore
    @EnvironmentObject private var models: ModelStore

    @State private var editing: Persona?
    @State private var draftName = ""
    @State private var draftPrompt = ""
    @State private var confirmWipe = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Persona", selection: Binding(
                        get: { prompts.selected?.id ?? UUID() },
                        set: { prompts.selectedID = $0; prompts.save() }
                    )) {
                        ForEach(prompts.personas) { persona in
                            Text(persona.name).tag(persona.id)
                        }
                    }
                    if let selected = prompts.selected {
                        Text(selected.prompt)
                            .font(.caption)
                            .foregroundStyle(Theme.textDim)
                    }
                    Button {
                        editing = Persona(name: "New persona", prompt: "")
                        draftName = ""
                        draftPrompt = ""
                    } label: { Label("Add persona", systemImage: "plus") }
                    ForEach(prompts.personas) { persona in
                        Button {
                            editing = persona
                            draftName = persona.name
                            draftPrompt = persona.prompt
                        } label: {
                            HStack {
                                Text(persona.name).foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "pencil").foregroundStyle(Theme.textDim)
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { prompts.delete(persona) } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                } header: { SectionHeader(title: "Personas") }

                Section {
                    VStack(alignment: .leading) {
                        Text("Context length: \(Int(session.settings.contextLength))")
                        Slider(value: Binding(get: { Double(session.settings.contextLength) },
                                              set: { session.settings.contextLength = Int32($0); session.persist() }),
                               in: 1024...32768, step: 1024)
                    }
                    VStack(alignment: .leading) {
                        Text("Max reply tokens: \(Int(session.settings.maxTokens))")
                        Slider(value: Binding(get: { Double(session.settings.maxTokens) },
                                              set: { session.settings.maxTokens = Int32($0); session.persist() }),
                               in: 64...4096, step: 64)
                    }
                    VStack(alignment: .leading) {
                        Text(String(format: "Temperature: %.2f", session.settings.temperature))
                        Slider(value: Binding(get: { Double(session.settings.temperature) },
                                              set: { session.settings.temperature = Float($0); session.persist() }),
                               in: 0...1.5, step: 0.05)
                    }
                    VStack(alignment: .leading) {
                        Text(String(format: "Top-p: %.2f", session.settings.topP))
                        Slider(value: Binding(get: { Double(session.settings.topP) },
                                              set: { session.settings.topP = Float($0); session.persist() }),
                               in: 0.1...1.0, step: 0.01)
                    }
                    VStack(alignment: .leading) {
                        Text(String(format: "Repeat penalty: %.2f", session.settings.repeatPenalty))
                        Slider(value: Binding(get: { Double(session.settings.repeatPenalty) },
                                              set: { session.settings.repeatPenalty = Float($0); session.persist() }),
                               in: 1.0...1.5, step: 0.01)
                    }
                    Stepper("Top-k: \(Int(session.settings.topK))",
                            value: Binding(get: { Int(session.settings.topK) },
                                           set: { session.settings.topK = Int32($0); session.persist() }),
                            in: 1...200)
                    Stepper("GPU layers: \(Int(session.settings.gpuLayers))",
                            value: Binding(get: { Int(session.settings.gpuLayers) },
                                           set: { session.settings.gpuLayers = Int32($0); session.persist() }),
                            in: 0...999, step: 8)
                    Text(session.settings.gpuLayers == 0
                         ? "CPU only — slowest but will not hit the GPU memory ceiling."
                         : "Offloading \(Int(session.settings.gpuLayers)) layers to Metal. If the app dies during load, this is why: drop it or run Test run (CPU only) in Diagnostics.")
                        .font(.caption2)
                        .foregroundStyle(Theme.textDim)
                    Toggle("Show speed stats", isOn: Binding(get: { session.showStats },
                                                             set: { session.showStats = $0; session.persist() }))
                    Toggle("Low memory mode", isOn: Binding(get: { session.settings.lowMemory },
                                                            set: { value in
                                                                session.settings.lowMemory = value
                                                                if value {
                                                                    session.settings.contextLength = 2048
                                                                    session.settings.maxTokens = 256
                                                                    session.settings.gpuLayers = 0
                                                                }
                                                                session.persist()
                                                            }))
                } header: { SectionHeader(title: "Sampling & memory") }
                  footer: {
                    Text("Low memory mode drops the context to 2048 and replies to 256 tokens. KV cache already runs 8-bit, which is about half the memory of 16-bit.")
                }

                Section {
                    Toggle("Speak replies", isOn: Binding(get: { session.speakReplies },
                                                          set: { session.speakReplies = $0; session.persist() }))
                    Picker("Voice", selection: Binding(get: { session.speech.voiceID ?? "" },
                                                       set: { session.speech.voiceID = $0.isEmpty ? nil : $0 })) {
                        Text("System default").tag("")
                        ForEach(session.speech.availableVoices, id: \.identifier) { voice in
                            Text("\(voice.name) (\(voice.language))").tag(voice.identifier)
                        }
                    }
                    HStack {
                        Text(String(format: "Rate: %.2f", session.speech.rate))
                        Slider(value: Binding(get: { Double(session.speech.rate) },
                                              set: { session.speech.rate = Float($0) }),
                               in: 0.3...0.8, step: 0.02)
                    }
                    Button("Stop speaking") { session.speech.stop() }
                    Text(session.voice.errorMessage ?? "Voice input uses on-device speech recognition.")
                        .font(.caption2)
                        .foregroundStyle(Theme.textDim)
                } header: { SectionHeader(title: "Voice") }

                Section {
                    LabeledContent("Device", value: session.memoryNote)
                    LabeledContent("Log file", value: "Files → On My iPhone → Cortex → cortex.log")
                    Button {
                        Task { await session.runDiagnostics(models: models, gpuLayers: session.settings.gpuLayers) }
                    } label: { Label("Test run (Metal)", systemImage: "bolt") }
                    Button {
                        Task { await session.runDiagnostics(models: models, gpuLayers: 0) }
                    } label: { Label("Test run (CPU only)", systemImage: "cpu") }
                    if !session.diagnosticsReport.isEmpty {
                        ScrollView(.vertical) {
                            Text(session.diagnosticsReport)
                                .font(.system(.caption2, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 260)
                        ShareLink(item: session.diagnosticsReport) { Label("Share report", systemImage: "square.and.arrow.up") }
                    }
                    Button {
                        session.resetAutoDiagnostics()
                        Task { await session.autoDiagnoseIfNeeded(models: models) }
                    } label: { Label("Run self tests again", systemImage: "arrow.triangle.2.circlepath") }
                    Button {
                        UIPasteboard.general.string = session.diagnosticsReport
                    } label: { Label("Copy report to clipboard", systemImage: "doc.on.doc") }
                    Button {
                        UIPasteboard.general.string = LogSink.shared.tail()
                    } label: { Label("Copy engine log", systemImage: "list.bullet.rectangle") }
                    Button("Clear engine log") {
                        LogSink.shared.clear()
                        session.diagnosticsReport = ""
                    }
                } header: { SectionHeader(title: "Diagnostics") }

                Section {
                    Button { session.unload() } label: { Label("Unload model", systemImage: "eject") }
                    LabeledContent("Engine", value: "llama.cpp v0.5.0 · Metal")
                    LabeledContent("Build", value: "Cortex 2.2")
                    LabeledContent("Models", value: "\(models.models.count) · \(models.projectors.count) projectors")
                    Button("Reset sampler settings") {
                        session.settings = GenSettings()
                        session.persist()
                    }
                    Button("Delete all chats", role: .destructive) { confirmWipe = true }
                } header: { SectionHeader(title: "About") }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Settings")
            .sheet(item: $editing) { persona in
                NavigationStack {
                    Form {
                        TextField("Name", text: $draftName)
                        TextEditor(text: $draftPrompt).frame(minHeight: 180)
                    }
                    .navigationTitle(persona.name)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Cancel") { editing = nil }
                        }
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Save") {
                                var updated = persona
                                updated.name = draftName.isEmpty ? "Persona" : draftName
                                updated.prompt = draftPrompt
                                if prompts.personas.contains(where: { $0.id == persona.id }) {
                                    prompts.update(updated)
                                } else {
                                    prompts.add(updated)
                                }
                                prompts.selectedID = updated.id
                                editing = nil
                            }
                        }
                    }
                }
            }
            .alert("Delete all chats?", isPresented: $confirmWipe) {
                Button("Delete", role: .destructive) {
                    for chat in chats.chats { chats.delete(chat) }
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }
}

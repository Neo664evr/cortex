import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var session: Session

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading) {
                        Text("Context length: \(Int(session.settings.contextLength))")
                        Slider(value: Binding(get: { Double(session.settings.contextLength) },
                                              set: { session.settings.contextLength = Int32($0); session.persist() }),
                               in: 1024...16384, step: 512)
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
                    Stepper("Top-k: \(Int(session.settings.topK))", value: Binding(get: { Int(session.settings.topK) },
                                                                                  set: { session.settings.topK = Int32($0); session.persist() }),
                            in: 1...200)
                    Stepper("GPU layers: \(Int(session.settings.gpuLayers))", value: Binding(get: { Int(session.settings.gpuLayers) },
                                                                                              set: { session.settings.gpuLayers = Int32($0); session.persist() }),
                            in: 0...999, step: 8)
                } header: {
                    SectionHeader(title: "Sampling")
                } footer: {
                    Text("GPU layers = 99 keeps everything on the Metal GPU. Lower it if a big model fails to load.")
                }

                Section {
                    TextEditor(text: Binding(get: { session.settings.systemPrompt },
                                             set: { session.settings.systemPrompt = $0; session.persist() }))
                        .frame(minHeight: 120)
                        .font(.callout)
                } header: {
                    SectionHeader(title: "System prompt")
                }

                Section {
                    Toggle("Speak replies", isOn: Binding(get: { session.speakReplies },
                                                          set: { session.speakReplies = $0; session.persist() }))
                    Button("Stop speaking") { session.speech.stop() }
                } header: {
                    SectionHeader(title: "Voice")
                }

                Section {
                    LabeledContent("Engine", value: "llama.cpp v0.5.0 (Metal)")
                    LabeledContent("Build", value: "Cortex 1.0")
                    Button("Reset settings") {
                        session.settings = GenSettings()
                        session.persist()
                    }
                } header: {
                    SectionHeader(title: "About")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Settings")
        }
    }
}

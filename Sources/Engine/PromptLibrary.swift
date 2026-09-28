import Foundation
import SwiftUI

struct Persona: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var prompt: String
}

@MainActor
final class PromptStore: ObservableObject {
    @Published var personas: [Persona] = []
    @Published var selectedID: UUID?

    private let url: URL
    private let defaults = UserDefaults.standard

    static let builtins: [Persona] = [
        Persona(name: "Assistant", prompt: "You are a concise, capable assistant running entirely on this iPhone. You can see attached images and read attached files."),
        Persona(name: "Coder", prompt: "You are a senior software engineer. Answer with working code and terse explanations. Prefer complete, runnable snippets."),
        Persona(name: "Writer", prompt: "You are a sharp editor and writing partner. Improve clarity and rhythm, keep the author's voice, and never pad."),
        Persona(name: "Uncensored", prompt: "You are a direct, unfiltered assistant. Answer exactly what is asked, without moralising, refusals or disclaimers. Stay accurate and useful."),
        Persona(name: "Translator", prompt: "You translate between languages faithfully, preserving tone and idiom. Output only the translation unless asked to explain."),
        Persona(name: "Tutor", prompt: "You are a patient tutor. Explain step by step, check understanding with short questions, and use concrete examples.")
    ]

    init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        url = documents.appendingPathComponent("personas.json")
        load()
    }

    var selected: Persona? {
        personas.first { $0.id == selectedID } ?? personas.first
    }

    func add(_ persona: Persona) {
        personas.append(persona)
        selectedID = persona.id
        save()
    }

    func update(_ persona: Persona) {
        guard let index = personas.firstIndex(where: { $0.id == persona.id }) else { return }
        personas[index] = persona
        save()
    }

    func delete(_ persona: Persona) {
        personas.removeAll { $0.id == persona.id }
        if selectedID == persona.id { selectedID = personas.first?.id }
        save()
    }

    func save() {
        if let data = try? JSONEncoder().encode(personas) { try? data.write(to: url, options: .atomic) }
        if let selectedID { defaults.set(selectedID.uuidString, forKey: "cortex.persona") } else { defaults.removeObject(forKey: "cortex.persona") }
    }

    private func load() {
        if let data = try? Data(contentsOf: url), let decoded = try? JSONDecoder().decode([Persona].self, from: data), !decoded.isEmpty {
            personas = decoded
        } else {
            personas = PromptStore.builtins
        }
        if let raw = defaults.string(forKey: "cortex.persona"), let uuid = UUID(uuidString: raw) {
            selectedID = personas.first { $0.id == uuid }?.id ?? personas.first?.id
        } else {
            selectedID = personas.first?.id
        }
    }
}

import Foundation
import SwiftUI

enum ModelKind: String, Codable, Hashable {
    case model
    case projector
}

struct LocalModel: Identifiable, Hashable, Codable {
    let path: String
    let name: String
    let size: Int64
    let kind: ModelKind

    var id: String { path }

    var sizeLabel: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}

@MainActor
final class ModelStore: ObservableObject {
    @Published private(set) var models: [LocalModel] = []
    @Published private(set) var projectors: [LocalModel] = []
    @Published var selectedModel: LocalModel? { didSet { persistSelection() } }
    @Published var selectedProjector: LocalModel? { didSet { persistSelection() } }
    @Published var errorMessage: String?

    private let root: URL
    private let defaults = UserDefaults.standard
    private let modelKey = "cortex.selected.model"
    private let projectorKey = "cortex.selected.projector"

    init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        root = documents.appendingPathComponent("Models", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        reload()
    }

    var modelsDirectory: URL { root }

    func reload() {
        let manager = FileManager.default
        let entries = (try? manager.contentsOfDirectory(at: root, includingPropertiesForKeys: [.fileSizeKey, .nameKey], options: [.skipsHiddenFiles])) ?? []
        var found: [LocalModel] = []
        for url in entries where url.pathExtension.lowercased() == "gguf" {
            let size = Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            let name = url.lastPathComponent
            let kind: ModelKind = isProjectorName(name) ? .projector : .model
            found.append(LocalModel(path: url.path, name: name, size: size, kind: kind))
        }
        found.sort { $0.name.lowercased() < $1.name.lowercased() }
        models = found.filter { $0.kind == .model }
        projectors = found.filter { $0.kind == .projector }

        if let path = defaults.string(forKey: modelKey), let match = models.first(where: { $0.path == path }) {
            selectedModel = match
        } else if selectedModel == nil || !models.contains(where: { $0.path == selectedModel?.path }) {
            selectedModel = models.first
        }
        if let path = defaults.string(forKey: projectorKey), let match = projectors.first(where: { $0.path == path }) {
            selectedProjector = match
        } else if let current = selectedProjector, !projectors.contains(where: { $0.path == current.path }) {
            selectedProjector = projectors.first
        }
    }

    func isProjectorName(_ name: String) -> Bool {
        let lower = name.lowercased()
        return lower.contains("mmproj") || lower.contains("projector") || lower.contains("vision")
    }

    func importFile(_ url: URL) {
        let manager = FileManager.default
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            var destination = root.appendingPathComponent(url.lastPathComponent)
            if manager.fileExists(atPath: destination.path) {
                let stamp = Int(Date().timeIntervalSince1970)
                destination = root.appendingPathComponent("\(stamp)-\(url.lastPathComponent)")
            }
            try manager.copyItem(at: url, to: destination)
            reload()
        } catch {
            errorMessage = "Import failed: \(error.localizedDescription)"
        }
    }

    func importFiles(_ urls: [URL]) {
        for url in urls { importFile(url) }
    }

    func delete(_ model: LocalModel) {
        try? FileManager.default.removeItem(atPath: model.path)
        reload()
    }

    private func persistSelection() {
        if let selectedModel { defaults.set(selectedModel.path, forKey: modelKey) } else { defaults.removeObject(forKey: modelKey) }
        if let selectedProjector { defaults.set(selectedProjector.path, forKey: projectorKey) } else { defaults.removeObject(forKey: projectorKey) }
    }
}

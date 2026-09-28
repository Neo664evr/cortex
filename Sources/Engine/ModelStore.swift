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

    var sizeLabel: String { ByteCountFormatter.string(fromByteCount: size, countStyle: .file) }

    var parameterHint: String? {
        let characters = Array(name.lowercased())
        var digits = ""
        for index in characters.indices {
            let character = characters[index]
            if character.isNumber || (character == "." && !digits.isEmpty) {
                digits.append(character)
                continue
            }
            if character == "b", !digits.isEmpty {
                let next = index + 1 < characters.count ? characters[index + 1] : " "
                if !next.isLetter && !next.isNumber {
                    return digits.uppercased() + "B"
                }
            }
            digits = ""
        }
        return nil
    }

    var quantHint: String? {
        let upper = name.uppercased()
        for quant in ["Q8_0", "Q6_K", "Q5_K_M", "Q5_K_S", "Q4_K_M", "Q4_K_S", "Q4_0", "Q3_K_M", "Q3_K_S", "Q2_K", "IQ4_XS", "IQ4_NL", "IQ3_M", "IQ2_M", "F16", "BF16", "FP16"] {
            if upper.contains(quant) { return quant }
        }
        return nil
    }
}

@MainActor
final class ModelStore: ObservableObject {
    @Published private(set) var models: [LocalModel] = []
    @Published private(set) var projectors: [LocalModel] = []
    @Published var selectedModel: LocalModel? { didSet { persistSelection() } }
    @Published var selectedProjector: LocalModel? { didSet { persistSelection() } }
    @Published var errorMessage: String?

    private let documents: URL
    private let root: URL
    private let defaults = UserDefaults.standard
    private let modelKey = "cortex.selected.model"
    private let projectorKey = "cortex.selected.projector"

    init() {
        documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        root = documents.appendingPathComponent("Models", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        reload()
    }

    var modelsDirectory: URL { root }
    var documentsDirectory: URL { documents }

    /// Scans the whole Documents tree plus Models, so files dropped in through the
    /// Files app ("On My iPhone -> Cortex") appear without going through the picker.
    func reload() {
        let manager = FileManager.default
        var found: [LocalModel] = []
        var seen = Set<String>()

        func consider(_ url: URL) {
            guard url.pathExtension.lowercased() == "gguf" else { return }
            let path = url.standardizedFileURL.path
            guard !seen.contains(path) else { return }
            seen.insert(path)
            let size = Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            let kind: ModelKind = isModelProjector(url.lastPathComponent) ? .projector : .model
            found.append(LocalModel(path: path, name: url.lastPathComponent, size: size, kind: kind))
        }

        for directory in [root, documents] {
            guard let enumerator = manager.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey], options: [.skipsHiddenFiles]) else { continue }
            for case let url as URL in enumerator {
                if url.pathComponents.count - documents.pathComponents.count > 3 { enumerator.skipDescendants(); continue }
                consider(url)
            }
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
        if selectedProjector == nil, projectors.count == 1 { selectedProjector = projectors.first }
    }

    func isModelProjector(_ name: String) -> Bool {
        let lower = name.lowercased()
        return lower.contains("mmproj") || lower.contains("projector") || lower.contains("vision")
    }

    func importFile(_ url: URL) {
        let manager = FileManager.default
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard url.pathExtension.lowercased() == "gguf" else {
            errorMessage = "\(url.lastPathComponent) is not a .gguf file."
            return
        }
        do {
            var destination = root.appendingPathComponent(url.lastPathComponent)
            if manager.fileExists(atPath: destination.path) {
                let stamp = Int(Date().timeIntervalSince1970)
                destination = root.appendingPathComponent("\(stamp)-\(url.lastPathComponent)")
            }
            try manager.copyItem(at: url, to: destination)
            reload()
        } catch {
            errorMessage = "Could not import \(url.lastPathComponent): \(error.localizedDescription). If it lives in iCloud Drive, download it from a URL instead, or copy it in with the Files app."
        }
    }

    func importFiles(_ urls: [URL]) { urls.forEach(importFile) }

    func delete(_ model: LocalModel) {
        try? FileManager.default.removeItem(atPath: model.path)
        reload()
    }

    func rename(_ model: LocalModel, to newName: String) {
        let clean = newName.lowercased().hasSuffix(".gguf") ? newName : newName + ".gguf"
        let destination = root.appendingPathComponent(clean)
        do {
            try FileManager.default.moveItem(atPath: model.path, toPath: destination.path)
            reload()
        } catch {
            errorMessage = "Rename failed: \(error.localizedDescription)"
        }
    }

    private func persistSelection() {
        if let selectedModel { defaults.set(selectedModel.path, forKey: modelKey) } else { defaults.removeObject(forKey: modelKey) }
        if let selectedProjector { defaults.set(selectedProjector.path, forKey: projectorKey) } else { defaults.removeObject(forKey: projectorKey) }
    }
}

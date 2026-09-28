import SwiftUI
import UniformTypeIdentifiers

struct ModelsView: View {
    @EnvironmentObject private var models: ModelStore
    @EnvironmentObject private var session: Session
    @State private var showModelImporter = false
    @State private var showProjectorImporter = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if models.models.isEmpty {
                        Text("No models yet. Import a .gguf file (e.g. a 4B–9B Q4_K_M) from Files.")
                            .font(.footnote)
                            .foregroundStyle(Theme.textDim)
                    }
                    ForEach(models.models) { model in
                        ModelRow(model: model, selected: session.engine.loadedModel == model.path || models.selectedModel?.path == model.path) {
                            models.selectedModel = model
                        }
                    }
                    .onDelete { indexSet in
                        for index in indexSet { models.delete(models.models[index]) }
                    }
                } header: {
                    SectionHeader(title: "Models")
                }

                Section {
                    if models.projectors.isEmpty {
                        Text("Optional: import an mmproj-*.gguf to give a vision model the ability to see images.")
                            .font(.footnote)
                            .foregroundStyle(Theme.textDim)
                    }
                    ForEach(models.projectors) { projector in
                        ModelRow(model: projector, selected: models.selectedProjector?.path == projector.path) {
                            models.selectedProjector = projector
                        }
                    }
                    .onDelete { indexSet in
                        for index in indexSet { models.delete(models.projectors[index]) }
                    }
                } header: {
                    SectionHeader(title: "Vision projectors (mmproj)")
                }

                Section {
                    Button {
                        Task { await session.loadSelection(models: models) }
                    } label: {
                        Label(models.selectedModel == nil ? "Import a model first" : "Load selected model", systemImage: "bolt.fill")
                    }
                    .disabled(models.selectedModel == nil)

                    LabeledContent("Status", value: session.status.isEmpty ? "idle" : session.status)
                    LabeledContent("Vision", value: session.engine.hasVision ? "on" : "off")
                    LabeledContent("Folder", value: "Documents/Models")
                } header: {
                    SectionHeader(title: "Engine")
                }

                if let error = session.errorMessage {
                    Section {
                        Text(error).font(.footnote).foregroundStyle(Theme.warn)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Models")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { showModelImporter = true } label: { Label("Import model", systemImage: "cube.box") }
                        Button { showProjectorImporter = true } label: { Label("Import projector", systemImage: "eye") }
                    } label: { Image(systemName: "plus") }
                }
            }
            .fileImporter(isPresented: $showModelImporter, allowedContentTypes: [UTType(filenameExtension: "gguf") ?? .data], allowsMultipleSelection: true) { result in
                if case .success(let urls) = result { models.importFiles(urls) }
            }
            .fileImporter(isPresented: $showProjectorImporter, allowedContentTypes: [UTType(filenameExtension: "gguf") ?? .data], allowsMultipleSelection: false) { result in
                if case .success(let urls) = result { models.importFiles(urls) }
            }
            .alert("Import error", isPresented: Binding(get: { models.errorMessage != nil }, set: { if !$0 { models.errorMessage = nil } })) {
                Button("OK") { models.errorMessage = nil }
            } message: {
                Text(models.errorMessage ?? "")
            }
        }
    }
}

struct ModelRow: View {
    let model: LocalModel
    let selected: Bool
    var onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.name)
                        .font(.subheadline)
                        .lineLimit(1)
                    Text(model.sizeLabel)
                        .font(.caption)
                        .foregroundStyle(Theme.textDim)
                }
                Spacer()
                if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent) }
            }
        }
    }
}

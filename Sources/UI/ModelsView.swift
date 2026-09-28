import SwiftUI
import UniformTypeIdentifiers

struct ModelsView: View {
    @EnvironmentObject private var models: ModelStore
    @EnvironmentObject private var session: Session
    @EnvironmentObject private var downloader: Downloader

    @State private var showModelImporter = false
    @State private var showProjectorImporter = false
    @State private var showDownloadSheet = false
    @State private var deleteTarget: LocalModel?
    @State private var renameTarget: LocalModel?
    @State private var renameText = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if models.models.isEmpty {
                        Text("No models yet. Use Download from URL for a Hugging Face link, or import a .gguf from Files.")
                            .font(.footnote).foregroundStyle(Theme.textDim)
                    }
                    ForEach(models.models) { model in
                        ModelRow(model: model,
                                 selected: models.selectedModel?.path == model.path,
                                 loaded: session.engine.loadedModel == model.path)
                        .swipeActions(edge: .leading) {
                            Button {
                                renameTarget = model
                                renameText = model.name
                            } label: { Label("Rename", systemImage: "pencil") }
                            .tint(Theme.accent)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { deleteTarget = model } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                } header: { SectionHeader(title: "Chat models (\(models.models.count))") }

                Section {
                    if models.projectors.isEmpty {
                        Text("An mmproj-*.gguf adds image input to a vision model.")
                            .font(.footnote).foregroundStyle(Theme.textDim)
                    }
                    ForEach(models.projectors) { projector in
                        ModelRow(model: projector,
                                 selected: models.selectedProjector?.path == projector.path,
                                 loaded: false)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { deleteTarget = projector } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                } header: { SectionHeader(title: "Vision projectors (\(models.projectors.count))") }

                Section {
                    Button { showDownloadSheet = true } label: {
                        Label("Download from URL", systemImage: "arrow.down.circle")
                    }
                    Button { showModelImporter = true } label: {
                        Label("Import model from Files", systemImage: "cube.box")
                    }
                    Button { showProjectorImporter = true } label: {
                        Label("Import projector from Files", systemImage: "eye")
                    }
                    Button { models.reload() } label: {
                        Label("Rescan storage", systemImage: "arrow.clockwise")
                    }
                } header: {
                    SectionHeader(title: "Add models")
                } footer: {
                    Text("Files app route: open Files -> On My iPhone -> Cortex -> Models, and drop .gguf files there. They appear after Rescan storage.")
                }

                Section {
                    Button {
                        Task { await session.loadSelection(models: models, force: true) }
                    } label: {
                        Label(models.selectedModel == nil ? "Import a model first" : "Load selected model", systemImage: "bolt.fill")
                    }
                    .disabled(models.selectedModel == nil)

                    Button { session.unload() } label: { Label("Unload model", systemImage: "eject") }

                    LabeledContent("Status", value: session.status.isEmpty ? "idle" : session.status)
                    ForEach(session.modelInfo()) { fact in
                        LabeledContent(fact.label, value: fact.value)
                    }
                } header: { SectionHeader(title: "Engine") }

                if !downloader.items.isEmpty {
                    Section {
                        ForEach(downloader.items) { item in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.name).font(.subheadline).lineLimit(1)
                                ProgressView(value: item.progress)
                                Text(item.status).font(.caption2).foregroundStyle(item.failed ? Theme.warn : Theme.textDim)
                            }
                        }
                        Button("Clear finished") { downloader.clearFinished() }
                    } header: { SectionHeader(title: "Downloads") }
                }

                if let error = session.errorMessage ?? models.errorMessage {
                    Section { Text(error).font(.footnote).foregroundStyle(Theme.warn) }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Models")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showDownloadSheet = true } label: { Image(systemName: "arrow.down.circle") }
                }
            }
            .sheet(isPresented: $showDownloadSheet) {
                DownloadSheet()
            }
            .fileImporter(isPresented: $showModelImporter, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
                if case .success(let urls) = result { models.importFiles(urls) }
            }
            .fileImporter(isPresented: $showProjectorImporter, allowedContentTypes: [.item], allowsMultipleSelection: false) { result in
                if case .success(let urls) = result { models.importFiles(urls) }
            }
            .alert("Delete file?", isPresented: Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } })) {
                Button("Delete", role: .destructive) {
                    if let target = deleteTarget { models.delete(target) }
                    deleteTarget = nil
                }
                Button("Cancel", role: .cancel) { deleteTarget = nil }
            } message: {
                Text(deleteTarget?.name ?? "")
            }
            .alert("Rename model", isPresented: Binding(get: { renameTarget != nil }, set: { if !$0 { renameTarget = nil } })) {
                TextField("Name", text: $renameText)
                Button("Save") {
                    if let target = renameTarget { models.rename(target, to: renameText) }
                    renameTarget = nil
                }
                Button("Cancel", role: .cancel) { renameTarget = nil }
            }
        }
    }
}

struct DownloadSheet: View {
    @EnvironmentObject private var downloader: Downloader
    @EnvironmentObject private var models: ModelStore
    @Environment(\.dismiss) private var dismiss
    @State private var url = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://huggingface.co/.../resolve/main/model.gguf", text: $url, axis: .vertical)
                        .lineLimit(2...4)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button {
                        downloader.start(urlString: url, into: models.modelsDirectory)
                        url = ""
                    } label: { Label("Start download", systemImage: "arrow.down.circle.fill") }
                    .disabled(url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } header: {
                    SectionHeader(title: "Direct file URL")
                } footer: {
                    Text("Use the direct file link (Hugging Face: open a file and copy the resolve/main link). Downloads land in Models and show up immediately.")
                }

                if !downloader.items.isEmpty {
                    Section {
                        ForEach(downloader.items) { item in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.name).font(.subheadline).lineLimit(1)
                                ProgressView(value: item.progress)
                                Text(item.status).font(.caption2)
                                    .foregroundStyle(item.failed ? Theme.warn : Theme.textDim)
                            }
                        }
                        Button("Clear finished") { downloader.clearFinished() }
                    } header: { SectionHeader(title: "Queue") }
                }
            }
            .navigationTitle("Download model")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        models.reload()
                        dismiss()
                    }
                }
            }
        }
    }
}

struct ModelRow: View {
    let model: LocalModel
    let selected: Bool
    let loaded: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(model.name).font(.subheadline).lineLimit(1)
                HStack(spacing: 6) {
                    Text(model.sizeLabel)
                    if let params = model.parameterHint { Text(params) }
                    if let quant = model.quantHint { Text(quant) }
                    if loaded { Text("loaded").foregroundStyle(Theme.accent) }
                }
                .font(.caption2)
                .foregroundStyle(Theme.textDim)
            }
            Spacer()
            if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent) }
        }
    }
}

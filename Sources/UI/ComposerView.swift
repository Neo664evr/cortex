import SwiftUI
import PhotosUI

struct ComposerView: View {
    @Binding var draft: String
    @Binding var attachments: [Attachment]
    let isGenerating: Bool
    var onSend: () -> Void
    var onStop: () -> Void

    @EnvironmentObject private var models: ModelStore
    @EnvironmentObject private var session: Session

    @State private var photoItems: [PhotosPickerItem] = []
    @State private var showCamera = false
    @State private var showFileImporter = false
    @State private var notice: String?

    var body: some View {
        VStack(spacing: 8) {
            if let notice {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle")
                    Text(notice).font(.caption2)
                    Spacer()
                    Button { self.notice = nil } label: { Image(systemName: "xmark") }
                }
                .foregroundStyle(Theme.warn)
                .padding(.horizontal, 14)
            }

            if !attachments.isEmpty { attachmentStrip }

            if session.voice.isRecording {
                HStack(spacing: 8) {
                    Circle().fill(Theme.warn).frame(width: 8, height: 8)
                    Text(session.voice.transcript.isEmpty ? "listening…" : session.voice.transcript)
                        .font(.caption)
                        .lineLimit(2)
                    Spacer()
                }
                .padding(.horizontal, 14)
            }

            HStack(alignment: .bottom, spacing: 8) {
                Menu {
                    PhotosPicker(selection: $photoItems, maxSelectionCount: 4, matching: .images) {
                        Label("Photos", systemImage: "photo.on.rectangle")
                    }
                    Button { showCamera = true } label: { Label("Camera", systemImage: "camera") }
                    Button { showFileImporter = true } label: { Label("File (PDF, text, code)", systemImage: "doc") }
                    Divider()
                    Button {
                        draft += draft.isEmpty ? session.settings.systemPrompt : "\n" + session.settings.systemPrompt
                    } label: { Label("Insert system prompt", systemImage: "text.quote") }
                    Button { draft += "\n\nContinue. " } label: { Label("Continue", systemImage: "forward") }
                } label: {
                    Image(systemName: "paperclip")
                        .font(.title3)
                        .padding(9)
                        .background(Theme.surfaceAlt, in: Circle())
                }

                TextField("Message", text: $draft, axis: .vertical)
                    .lineLimit(1...6)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                Button { session.voice.toggle() } label: {
                    Image(systemName: session.voice.isRecording ? "mic.fill" : "mic")
                        .font(.title3)
                        .padding(9)
                        .background(session.voice.isRecording ? Theme.warn : Theme.surfaceAlt, in: Circle())
                        .foregroundStyle(session.voice.isRecording ? .black : .primary)
                }

                if isGenerating {
                    Button(action: onStop) {
                        Image(systemName: "stop.fill")
                            .font(.title3)
                            .padding(10)
                            .background(Theme.warn, in: Circle())
                            .foregroundStyle(.black)
                    }
                } else {
                    Button(action: onSend) {
                        Image(systemName: "arrow.up")
                            .font(.title3.weight(.bold))
                            .padding(10)
                            .background(Theme.accent, in: Circle())
                            .foregroundStyle(.black)
                    }
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && attachments.isEmpty)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        .padding(.top, 8)
        .background(Theme.background)
        .onChange(of: photoItems) { _, items in
            guard !items.isEmpty else { return }
            Task {
                for item in items { await loadPhoto(item) }
                photoItems = []
            }
        }
        .onChange(of: session.voice.transcript) { _, value in
            if session.voice.isRecording { draft = value }
        }
        .sheet(isPresented: $showCamera) {
            CameraPicker { image in addImage(image) }
        }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            handleFiles(result)
        }
    }

    private var attachmentStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(attachments) { attachment in
                    HStack(spacing: 6) {
                        if attachment.kind == .image, let path = attachment.imagePath,
                           let image = UIImage(contentsOfFile: path) {
                            Image(uiImage: image).resizable().scaledToFill()
                                .frame(width: 34, height: 34)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        } else {
                            Image(systemName: attachment.icon)
                        }
                        Text(attachment.name).lineLimit(1).font(.caption2)
                        Button { attachments.removeAll { $0.id == attachment.id } } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Theme.surfaceAlt, in: Capsule())
                }
            }
            .padding(.horizontal, 12)
        }
    }

    private func handleFiles(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            notice = error.localizedDescription
        case .success(let urls):
            for url in urls {
                if FileText.isImage(url) {
                    if let data = try? Data(contentsOf: url), let image = UIImage(data: data) {
                        addImage(image)
                    } else {
                        notice = "Could not read \(url.lastPathComponent) — if it is in iCloud Drive, open it once in Files first."
                    }
                } else if let text = FileText.extract(from: url), !text.isEmpty {
                    attachments.append(Attachment(name: url.lastPathComponent, kind: .text, text: text))
                } else {
                    notice = "Could not extract text from \(url.lastPathComponent)."
                }
            }
        }
    }

    private func loadPhoto(_ item: PhotosPickerItem) async {
        if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
            addImage(image)
        } else {
            notice = "Could not load that photo."
        }
    }

    private func addImage(_ image: UIImage) {
        guard models.selectedProjector != nil else {
            notice = "No vision projector selected — import an mmproj GGUF in Models to send images."
            return
        }
        let folder = models.modelsDirectory.appendingPathComponent("Attachments", isDirectory: true)
        if let path = FileText.copyImage(image, into: folder) {
            attachments.append(Attachment(name: "photo.jpg", kind: .image, imagePath: path))
        } else {
            notice = "Could not save that image."
        }
    }
}

struct CameraPicker: UIViewControllerRepresentable {
    var onCapture: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onCapture(image) }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}

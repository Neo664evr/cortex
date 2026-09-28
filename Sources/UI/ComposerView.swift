import SwiftUI
import PhotosUI

struct ComposerView: View {
    @Binding var draft: String
    @Binding var attachments: [Attachment]
    let isGenerating: Bool
    var onSend: () -> Void
    var onStop: () -> Void

    @State private var photoItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var showFileImporter = false
    @State private var notice: String?
    @EnvironmentObject private var models: ModelStore

    var body: some View {
        VStack(spacing: 8) {
            if !attachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(attachments) { attachment in
                            HStack(spacing: 6) {
                                Image(systemName: attachment.icon)
                                Text(attachment.name).lineLimit(1)
                                Button {
                                    attachments.removeAll { $0.id == attachment.id }
                                } label: { Image(systemName: "xmark.circle.fill") }
                            }
                            .font(.caption2)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(Theme.surfaceAlt, in: Capsule())
                        }
                    }
                    .padding(.horizontal, 12)
                }
            }

            if let notice {
                Text(notice)
                    .font(.caption2)
                    .foregroundStyle(Theme.warn)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
            }

            HStack(alignment: .bottom, spacing: 8) {
                Menu {
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Label("Photo library", systemImage: "photo")
                    }
                    Button {
                        showCamera = true
                    } label: { Label("Camera", systemImage: "camera") }
                    Button {
                        showFileImporter = true
                    } label: { Label("File (text, PDF)", systemImage: "doc") }
                } label: {
                    Image(systemName: "paperclip")
                        .font(.title3)
                        .padding(8)
                        .background(Theme.surfaceAlt, in: Circle())
                }

                TextField("Message", text: $draft, axis: .vertical)
                    .lineLimit(1...6)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

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
        .onChange(of: photoItem) { _, newValue in
            guard let newValue else { return }
            Task { await loadPhoto(newValue) }
        }
        .sheet(isPresented: $showCamera) {
            CameraPicker { image in
                addImage(image)
            }
        }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.item], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                if FileText.isImage(url) {
                    if let data = try? Data(contentsOf: url), let image = UIImage(data: data) {
                        addImage(image)
                    } else {
                        notice = "Could not read that image."
                    }
                } else if let text = FileText.extract(from: url) {
                    attachments.append(Attachment(name: url.lastPathComponent, kind: .text, text: text))
                } else {
                    notice = "Could not read text from \(url.lastPathComponent)."
                }
            case .failure(let error):
                notice = error.localizedDescription
            }
        }
    }

    private func loadPhoto(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else {
            notice = "Could not load that photo."
            return
        }
        addImage(image)
    }

    private func addImage(_ image: UIImage) {
        guard models.selectedProjector != nil else {
            notice = "No vision projector selected — pick an mmproj GGUF in Models first."
            return
        }
        let folder = models.modelsDirectory.appendingPathComponent("Attachments", isDirectory: true)
        if let path = FileText.copyImage(image, into: folder) {
            attachments.append(Attachment(name: "photo.jpg", kind: .image, imagePath: path))
        } else {
            notice = "Could not stash that image."
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

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

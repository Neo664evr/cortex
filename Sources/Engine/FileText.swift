import Foundation
import PDFKit
import UIKit

enum FileText {
    static let maxCharacters = 24000

    static func isImage(_ url: URL) -> Bool {
        ["png", "jpg", "jpeg", "heic", "heif", "webp", "gif", "bmp", "tiff"].contains(url.pathExtension.lowercased())
    }

    static func extract(from url: URL) -> String? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        if url.pathExtension.lowercased() == "pdf" {
            guard let document = PDFDocument(url: url) else { return nil }
            var text = ""
            for index in 0..<document.pageCount {
                if let page = document.page(at: index), let body = page.string {
                    text += body + "\n"
                }
                if text.count > maxCharacters { break }
            }
            return String(text.prefix(maxCharacters))
        }

        guard let data = try? Data(contentsOf: url) else { return nil }
        let text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
            ?? ""
        return String(text.prefix(maxCharacters))
    }

    static func copyImage(_ image: UIImage, into folder: URL) -> String? {
        guard let data = image.jpegData(compressionQuality: 0.9) else { return nil }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("img-\(UUID().uuidString).jpg")
        do {
            try data.write(to: url)
            return url.path
        } catch {
            return nil
        }
    }
}

import Foundation
import SwiftUI

/// Downloads GGUF / mmproj files straight into the app's Models folder.
/// This is the reliable path for iCloud-hosted or very large files, where the
/// Files picker can hand back something that cannot be read.
@MainActor
final class Downloader: ObservableObject {
    struct Item: Identifiable {
        let id = UUID()
        var name: String
        var progress: Double
        var status: String
        var failed = false
    }

    @Published var items: [Item] = []
    @Published var errorMessage: String?

    private let session: URLSession
    private let delegate: Delegate
    private var tasks: [Int: UUID] = [:]
    private var destinations: [Int: URL] = [:]

    init() {
        delegate = Delegate()
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 60
        configuration.waitsForConnectivity = true
        session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)

        delegate.onProgress = { [weak self] task, written, total in
            Task { @MainActor in self?.update(taskIdentifier: task, written: written, total: total) }
        }
        delegate.onFinished = { [weak self] task, location in
            Task { @MainActor in self?.finish(taskIdentifier: task, location: location) }
        }
        delegate.onFailed = { [weak self] task, error in
            Task { @MainActor in self?.markFailed(taskIdentifier: task, error: error) }
        }
    }

    /// Starts a download. `url` may be a direct file URL (Hugging Face `resolve/main` links work).
    func start(urlString: String, into directory: URL) {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), url.scheme?.hasPrefix("http") == true else {
            errorMessage = "That does not look like an http(s) URL."
            return
        }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let task = session.downloadTask(with: url)
        let item = Item(name: url.lastPathComponent.isEmpty ? "download" : url.lastPathComponent, progress: 0, status: "starting…")
        tasks[task.taskIdentifier] = item.id
        items.append(item)
        task.resume()
    }

    func clearFinished() {
        items.removeAll { !$0.status.hasPrefix("downloading") && !$0.status.hasPrefix("starting") }
    }

    private func index(of identifier: Int) -> Int? { items.firstIndex { $0.id == tasks[identifier] } }

    private func update(taskIdentifier: Int, written: Int64, total: Int64) {
        guard let index = index(of: taskIdentifier) else { return }
        let fraction = total > 0 ? Double(written) / Double(total) : 0
        items[index].progress = max(0, min(1, fraction))
        let formatter = ByteCountFormatter()
        let done = formatter.string(fromByteCount: written)
        let all = total > 0 ? formatter.string(fromByteCount: total) : "?"
        items[index].status = "downloading \(done) / \(all)"
    }

    private func finish(taskIdentifier: Int, location: URL) {
        guard let index = index(of: taskIdentifier) else { return }
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Models", isDirectory: true)
        let name = items[index].name.isEmpty ? "model-\(Int(Date().timeIntervalSince1970)).gguf" : items[index].name
        let destination = directory.appendingPathComponent(name)
        do {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: location, to: destination)
            items[index].progress = 1
            items[index].status = "saved to Models"
        } catch {
            items[index].failed = true
            items[index].status = "save failed: \(error.localizedDescription)"
        }
    }

    private func markFailed(taskIdentifier: Int, error: Error) {
        guard let index = index(of: taskIdentifier) else { return }
        items[index].failed = true
        items[index].status = "failed: \(error.localizedDescription)"
    }

    final class Delegate: NSObject, URLSessionDownloadDelegate {
        var onProgress: ((Int, Int64, Int64) -> Void)?
        var onFinished: ((Int, URL) -> Void)?
        var onFailed: ((Int, Error) -> Void)?

        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
            onProgress?(downloadTask.taskIdentifier, totalBytesWritten, totalBytesExpectedToWrite)
        }

        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
            onFinished?(downloadTask.taskIdentifier, location)
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            if let error { onFailed?(task.taskIdentifier, error) }
        }
    }
}

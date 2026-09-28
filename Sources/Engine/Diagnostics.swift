import Foundation

/// Captures llama.cpp / ggml log output, keeps the tail in memory and mirrors it to
/// Documents/cortex.log so it survives a crash and can be pulled out through the Files app.
final class LogSink: @unchecked Sendable {
    static let shared = LogSink()

    private let lock = NSLock()
    private var buffer: [String] = []
    private var handle: FileHandle?
    let url: URL
    let started = Date()

    private init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        url = documents.appendingPathComponent("cortex.log")
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        handle = try? FileHandle(forWritingTo: url)
        handle?.seekToEndOfFile()
    }

    func append(_ text: String) {
        lock.lock()
        defer { lock.unlock() }
        let clean = text.trimmingCharacters(in: .newlines)
        guard !clean.isEmpty else { return }
        buffer.append(clean)
        if buffer.count > 600 { buffer.removeFirst(buffer.count - 600) }
        if let data = (clean + "\n").data(using: .utf8) {
            handle?.write(data)
            try? handle?.synchronize()
        }
    }

    func tail() -> String {
        lock.lock()
        defer { lock.unlock() }
        return buffer.suffix(300).joined(separator: "\n")
    }

    func clear() {
        lock.lock()
        buffer.removeAll()
        lock.unlock()
        try? FileManager.default.removeItem(at: url)
        FileManager.default.createFile(atPath: url.path, contents: nil)
        handle = try? FileHandle(forWritingTo: url)
    }

    func write(_ text: String) {
        guard let data = (text + "\n").data(using: .utf8) else { return }
        lock.lock()
        defer { lock.unlock() }
        handle?.write(data)
        try? handle?.synchronize()
    }
}

/// One-line breadcrumbs so a crash leaves behind the step that killed the app.
enum Breadcrumb {
    static var url: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("last-step.txt")
    }

    static func set(_ text: String) {
        LogSink.shared.write("STEP: " + text)
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }

    static func clear() {
        try? FileManager.default.removeItem(at: url)
    }

    static func stale() -> String? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

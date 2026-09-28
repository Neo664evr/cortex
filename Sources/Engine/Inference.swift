import Foundation
import UIKit
import llama

enum InferenceError: LocalizedError {
    case modelLoad(String)
    case contextCreate
    case projectorLoad
    case template
    case decode

    var errorDescription: String? {
        switch self {
        case .modelLoad(let p): return "Could not load the model at \(p)."
        case .contextCreate: return "Could not create the inference context — try a smaller context length."
        case .projectorLoad: return "Could not load that vision projector (mmproj) file."
        case .template: return "Could not apply the model's chat template."
        case .decode: return "llama_decode failed."
        }
    }
}

/// A single outgoing turn: text plus any media/file payloads.
struct TurnPayload {
    var systemPrompt: String
    var history: [ChatMessage]
}

func llama_batch_clear(_ batch: inout llama_batch) {
    batch.n_tokens = 0
}

func llama_batch_add(_ batch: inout llama_batch, _ id: llama_token, _ pos: llama_pos, _ seq_ids: [llama_seq_id], _ logits: Bool) {
    batch.token[Int(batch.n_tokens)] = id
    batch.pos[Int(batch.n_tokens)] = pos
    batch.n_seq_id[Int(batch.n_tokens)] = Int32(seq_ids.count)
    for i in 0..<seq_ids.count {
        batch.seq_id[Int(batch.n_tokens)]![Int(i)] = seq_ids[i]
    }
    batch.logits[Int(batch.n_tokens)] = logits ? 1 : 0
    batch.n_tokens += 1
}

/// Owns the llama.cpp model, context and (optional) multimodal projector.
/// All work happens on a private serial queue.
final class Inference {
    private var model: OpaquePointer?
    private var ctx: OpaquePointer?
    private var vocab: OpaquePointer?
    private var mtmd: OpaquePointer?
    private var sampler: UnsafeMutablePointer<llama_sampler>?
    private var batch = llama_batch_init(512, 0, 1)
    private var pieceBuffer: [CChar] = []
    private var promptTokens = 0
    private var stopFlag = false
    private var activeModel: String?
    private var activeMmproj: String?
    private var settings = GenSettings()

    private let queue = DispatchQueue(label: "com.neo664evr.cortex.inference", qos: .userInitiated)

    struct GenStats {
        var promptTokens: Int
        var generatedTokens: Int
        var seconds: Double
        var tokensPerSecond: Double
        var label: String {
            String(format: "%d tok in, %d out, %.1f tok/s", promptTokens, generatedTokens, tokensPerSecond)
        }
    }

    private(set) var lastStats: GenStats?

    var isLoaded: Bool { model != nil && ctx != nil }
    var contextSize: Int32 { ctx != nil ? Int32(llama_n_ctx(ctx)) : 0 }

    struct ModelFact: Identifiable {
        let id = UUID()
        let label: String
        let value: String
    }

    /// Human-readable model facts for the Models screen.
    func modelInfo() -> [ModelFact] {
        guard let model else { return [] }
        var buffer = [CChar](repeating: 0, count: 256)
        llama_model_desc(model, &buffer, 256)
        let description = String(cString: buffer)
        let params = Double(llama_model_n_params(model)) / 1_000_000_000
        let trained = llama_model_n_ctx_train(model)
        return [
            ModelFact(label: "Model", value: description),
            ModelFact(label: "Parameters", value: String(format: "%.2f B", params)),
            ModelFact(label: "Trained context", value: "\(trained)"),
            ModelFact(label: "Loaded context", value: "\(contextSize)"),
            ModelFact(label: "Vision", value: hasVision ? "on" : "off")
        ]
    }
    var loadedModel: String? { activeModel }
    var hasVision: Bool { mtmd != nil }

    func stop() {
        queue.async { self.stopFlag = true }
    }

    func unload() {
        llama_batch_free(batch)
        if let sampler { llama_sampler_free(sampler); self.sampler = nil }
        if let mtmd { mtmd_free(mtmd); self.mtmd = nil }
        if let ctx { llama_free(ctx); self.ctx = nil }
        if let model { llama_model_free(model); self.model = nil }
        vocab = nil
        activeModel = nil
        activeMmproj = nil
    }

    /// Loads on the private queue so the UI keeps animating during a big model load.
    func loadAsync(modelPath: String, projectorPath: String?, settings: GenSettings) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                do {
                    try self.load(modelPath: modelPath, mmprojPath: projectorPath, settings: settings)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func load(modelPath: String, mmprojPath: String?, settings: GenSettings) throws {
        self.settings = settings
        if activeModel == modelPath && activeMmproj == (mmprojPath ?? "") && isLoaded { return }
        unload()

        llama_backend_init()

        var mparams = llama_model_default_params()
        mparams.n_gpu_layers = settings.gpuLayers
        guard let loaded = llama_model_load_from_file(modelPath, mparams) else {
            throw InferenceError.modelLoad(modelPath)
        }
        model = loaded
        vocab = llama_model_get_vocab(loaded)

        let threads = Int32(max(1, min(8, ProcessInfo.processInfo.processorCount - 2)))
        var cparams = llama_context_default_params()
        cparams.n_ctx = UInt32(max(512, settings.contextLength))
        cparams.n_batch = 512
        cparams.n_ubatch = 512
        cparams.n_threads = threads
        cparams.n_threads_batch = threads
        guard let context = llama_init_from_model(loaded, cparams) else {
            llama_model_free(loaded)
            model = nil
            throw InferenceError.contextCreate
        }
        ctx = context

        if let mmprojPath, !mmprojPath.isEmpty {
            var tparams = mtmd_context_params_default()
            tparams.use_gpu = true
            tparams.print_timings = false
            tparams.n_threads = threads
            tparams.image_max_tokens = 1024
            guard let mctx = mtmd_init_from_file(mmprojPath, loaded, tparams) else {
                llama_free(context)
                llama_model_free(loaded)
                ctx = nil
                model = nil
                throw InferenceError.projectorLoad
            }
            mtmd = mctx
        }

        activeModel = modelPath
        activeMmproj = mmprojPath ?? ""
    }

    // MARK: - Generation

    func stream(payload: TurnPayload, settings: GenSettings) -> AsyncThrowingStream<String, Error> {
        self.settings = settings
        return AsyncThrowingStream { continuation in
            self.queue.async {
                do {
                    try self.run(payload: payload, continuation: continuation)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func run(payload: TurnPayload, continuation: AsyncThrowingStream<String, Error>.Continuation) throws {
        guard let model, let ctx else { throw InferenceError.modelLoad("(none loaded)") }
        stopFlag = false
        pieceBuffer.removeAll()

        let marker = String(cString: mtmd_default_marker())
        var imageData: [Data] = []
        var chat: [(role: String, content: String)] = []
        chat.append((role: "system", content: payload.systemPrompt))

        let lastUserIndex = payload.history.lastIndex(where: { $0.role == .user })
        for (index, message) in payload.history.enumerated() {
            var content = message.text
            for attachment in message.attachments {
                switch attachment.kind {
                case .text:
                    if let body = attachment.text, !body.isEmpty {
                        content += "\n\n--- file: \(attachment.name) ---\n\(body)"
                    }
                case .image:
                    if index == lastUserIndex, let path = attachment.imagePath,
                       let data = try? Data(contentsOf: URL(fileURLWithPath: path)) {
                        content += "\n\(marker)"
                        imageData.append(data)
                    }
                }
            }
            let role = message.role == .assistant ? "assistant" : "user"
            chat.append((role: role, content: content))
        }

        // Only keep images when a projector is loaded.
        if mtmd == nil { imageData.removeAll() }

        let prompt = try applyTemplate(chat, addAssistant: true)
        llama_memory_clear(llama_get_memory(ctx), true)

        var nPast: llama_pos = 0
        if !imageData.isEmpty, let mtmd {
            nPast = try evaluateMultimodal(prompt: prompt, images: imageData, mtmd: mtmd, ctx: ctx)
            promptTokens = Int(nPast)
        } else {
            nPast = try evaluateText(prompt: prompt, ctx: ctx)
            promptTokens = Int(nPast)
        }

        try buildSampler()

        let started = Date()
        var generated: Int32 = 0
        while generated < settings.maxTokens {
            if stopFlag { break }
            guard let sampler else { break }
            let token = llama_sampler_sample(sampler, ctx, -1)
            llama_sampler_accept(sampler, token)
            if llama_vocab_is_eog(vocab, token) { break }

            let piece = tokenToPiece(token)
            pieceBuffer.append(contentsOf: piece)
            if let text = String(validatingUTF8: pieceBuffer) {
                pieceBuffer.removeAll()
                if !text.isEmpty { continuation.yield(text) }
            } else if pieceBuffer.count > 8 {
                let text = String(decoding: pieceBuffer.map { UInt8(bitPattern: $0) }, as: UTF8.self)
                pieceBuffer.removeAll()
                if !text.isEmpty { continuation.yield(text) }
            }

            llama_batch_clear(&batch)
            llama_batch_add(&batch, token, nPast, [0], true)
            if llama_decode(ctx, batch) != 0 { throw InferenceError.decode }
            nPast += 1
            generated += 1
        }

        if !pieceBuffer.isEmpty {
            let tail = String(decoding: pieceBuffer.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            pieceBuffer.removeAll()
            if !tail.isEmpty { continuation.yield(tail) }
        }
        let elapsed = max(0.001, Date().timeIntervalSince(started))
        lastStats = GenStats(promptTokens: promptTokens, generatedTokens: Int(generated),
                             seconds: elapsed, tokensPerSecond: Double(generated) / elapsed)
        _ = model
    }

    private func buildSampler() throws {
        if let sampler { llama_sampler_free(sampler) }
        let params = llama_sampler_chain_default_params()
        guard let chain = llama_sampler_chain_init(params) else { throw InferenceError.decode }
        llama_sampler_chain_add(chain, llama_sampler_init_penalties(llama_vocab_n_tokens(vocab), 64, settings.repeatPenalty, 0.0, 0.0))
        llama_sampler_chain_add(chain, llama_sampler_init_top_k(settings.topK))
        llama_sampler_chain_add(chain, llama_sampler_init_top_p(settings.topP, 1))
        llama_sampler_chain_add(chain, llama_sampler_init_temp(settings.temperature))
        llama_sampler_chain_add(chain, llama_sampler_init_dist(UInt32.random(in: 0..<UInt32.max)))
        sampler = chain
    }

    private func evaluateText(prompt: String, ctx: OpaquePointer) throws -> llama_pos {
        let tokens = tokenize(prompt, addSpecial: true)
        guard !tokens.isEmpty else { throw InferenceError.decode }
        var nPast: llama_pos = 0
        var index = 0
        let chunk = 512
        while index < tokens.count {
            let count = min(chunk, tokens.count - index)
            llama_batch_clear(&batch)
            for offset in 0..<count {
                let isLast = (index + offset) == tokens.count - 1
                llama_batch_add(&batch, tokens[index + offset], nPast + llama_pos(offset), [0], isLast)
            }
            if llama_decode(ctx, batch) != 0 { throw InferenceError.decode }
            nPast += llama_pos(count)
            index += count
        }
        return nPast
    }

    private func evaluateMultimodal(prompt: String, images: [Data], mtmd: OpaquePointer, ctx: OpaquePointer) throws -> llama_pos {
        var chunks = mtmd_input_chunks_init()
        defer { if let chunks { mtmd_input_chunks_free(chunks) } }
        guard let chunks else { throw InferenceError.decode }

        var bitmaps: [OpaquePointer?] = []
        let helperOpt = mtmd_helper_init_opt_default()
        for data in images {
            let wrapper = data.withUnsafeBytes { raw -> mtmd_helper_bitmap_wrapper in
                mtmd_helper_bitmap_init_from_buf(mtmd, raw.bindMemory(to: UInt8.self).baseAddress, data.count, false, helperOpt)
            }
            if let bitmap = wrapper.bitmap { bitmaps.append(bitmap) }
        }
        defer { for bitmap in bitmaps { if let bitmap { mtmd_bitmap_free(bitmap) } } }
        guard !bitmaps.isEmpty else { throw InferenceError.decode }

        let cString = strdup(prompt)!
        defer { free(cString) }
        var inputText = mtmd_input_text(text: cString, text_len: prompt.utf8.count, add_special: true, parse_special: true)

        var bitmapPointers = bitmaps
        let rc = mtmd_tokenize(mtmd, chunks, &inputText, &bitmapPointers, bitmapPointers.count)
        guard rc == 0 else { throw InferenceError.decode }

        var newNPast: llama_pos = 0
        let evalRC = mtmd_helper_eval_chunks(mtmd, ctx, chunks, 0, 0, 512, true, &newNPast)
        guard evalRC == 0 else { throw InferenceError.decode }
        return newNPast
    }

    private func applyTemplate(_ messages: [(role: String, content: String)], addAssistant: Bool) throws -> String {
        guard let model else { throw InferenceError.template }
        var cStrings: [UnsafeMutablePointer<CChar>] = []
        var chatMessages: [llama_chat_message] = []
        for message in messages {
            guard let role = strdup(message.role), let content = strdup(message.content) else { continue }
            cStrings.append(role)
            cStrings.append(content)
            chatMessages.append(llama_chat_message(role: role, content: content))
        }
        defer { for pointer in cStrings { free(pointer) } }

        let template = llama_model_chat_template(model, nil)
        var buffer = [CChar](repeating: 0, count: 65536)
        var needed = llama_chat_apply_template(template, &chatMessages, chatMessages.count, addAssistant, &buffer, Int32(buffer.count))
        if needed > buffer.count {
            buffer = [CChar](repeating: 0, count: Int(needed) + 1024)
            needed = llama_chat_apply_template(template, &chatMessages, chatMessages.count, addAssistant, &buffer, Int32(buffer.count))
        }
        if needed <= 0 {
            return fallbackTemplate(messages, addAssistant: addAssistant)
        }
        return String(cString: buffer)
    }

    private func fallbackTemplate(_ messages: [(role: String, content: String)], addAssistant: Bool) -> String {
        var out = ""
        for message in messages {
            out += "<|im_start|>\(message.role)\n\(message.content)<|im_end|>\n"
        }
        if addAssistant { out += "<|im_start|>assistant\n" }
        return out
    }

    private func tokenize(_ text: String, addSpecial: Bool) -> [llama_token] {
        let utf8Count = text.utf8.count
        let capacity = utf8Count + 16
        let tokens = UnsafeMutablePointer<llama_token>.allocate(capacity: capacity)
        defer { tokens.deallocate() }
        let count = llama_tokenize(vocab, text, Int32(utf8Count), tokens, Int32(capacity), addSpecial, true)
        guard count > 0 else { return [] }
        var result: [llama_token] = []
        result.reserveCapacity(Int(count))
        for index in 0..<Int(count) { result.append(tokens[index]) }
        return result
    }

    private func tokenToPiece(_ token: llama_token) -> [CChar] {
        var buffer = [CChar](repeating: 0, count: 64)
        let count = llama_token_to_piece(vocab, token, &buffer, Int32(buffer.count), 0, false)
        if count < 0 {
            buffer = [CChar](repeating: 0, count: Int(-count))
            let again = llama_token_to_piece(vocab, token, &buffer, Int32(buffer.count), 0, false)
            return Array(buffer.prefix(max(0, Int(again))))
        }
        return Array(buffer.prefix(Int(count)))
    }
}

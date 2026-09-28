import SwiftUI

/// Small markdown pass: fenced code blocks render monospaced, everything else goes
/// through AttributedString's inline markdown (bold, italic, code, links).
enum MD {
    struct Block: Identifiable {
        enum Kind { case text, code }
        let id = UUID()
        var kind: Kind
        var body: String
    }

    static func blocks(_ raw: String) -> [Block] {
        var result: [Block] = []
        var current = ""
        var insideCode = false
        for line in raw.components(separatedBy: "\n") {
            if line.hasPrefix("```") {
                if insideCode {
                    result.append(Block(kind: .code, body: current))
                    current = ""
                } else if !current.isEmpty {
                    result.append(Block(kind: .text, body: current))
                    current = ""
                }
                insideCode.toggle()
                continue
            }
            current += (current.isEmpty ? "" : "\n") + line
        }
        if !current.isEmpty {
            result.append(Block(kind: insideCode ? .code : .text, body: current))
        }
        return result
    }

    static func inline(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }
}

struct MarkdownText: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(MD.blocks(text)) { block in
                switch block.kind {
                case .code:
                    Text(block.body)
                        .font(.system(.footnote, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.background, in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.accent.opacity(0.25)))
                case .text:
                    Text(MD.inline(block.body))
                        .textSelection(.enabled)
                }
            }
        }
    }
}

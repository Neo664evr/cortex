import SwiftUI

enum Theme {
    static let accent = Color(red: 0.184, green: 0.831, blue: 0.769)      // #2FD4C4
    static let warn = Color(red: 0.98, green: 0.66, blue: 0.24)
    static let background = Color(red: 0.055, green: 0.062, blue: 0.071)
    static let surface = Color(red: 0.098, green: 0.109, blue: 0.125)
    static let surfaceAlt = Color(red: 0.145, green: 0.16, blue: 0.18)
    static let textDim = Color.white.opacity(0.6)
}

struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct SectionHeader: View {
    let title: String
    var body: some View {
        Text(title.uppercased())
            .font(.caption.weight(.semibold))
            .foregroundStyle(Theme.textDim)
            .padding(.horizontal, 4)
    }
}

import SwiftUI

/// Displays article metadata: "AUTHOR . SOURCE . 5 MIN READ"
struct MetaLine: View {
    let author: String?
    let source: String?
    let readTime: Int?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let parts = buildParts()
        if !parts.isEmpty {
            Text(parts.joined(separator: " \u{2022} "))
                .font(.metaLabel(13))
                .tracking(1.5)
                .textCase(.uppercase)
                .foregroundColor(Color.bubbleUpTextMuted(for: colorScheme))
                .lineLimit(1)
        }
    }

    private func buildParts() -> [String] {
        var parts: [String] = []
        if let author, !author.isEmpty { parts.append(author) }
        if let source, !source.isEmpty { parts.append(source) }
        if let readTime, readTime > 0 { parts.append("\(readTime) MIN READ") }
        return parts
    }
}

#Preview {
    MetaLine(author: "John Doe", source: "The Atlantic", readTime: 5)
}

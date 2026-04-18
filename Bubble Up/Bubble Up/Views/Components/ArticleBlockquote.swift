import SwiftUI

/// Blockquote with red left border, serif italic text.
struct ArticleBlockquote: View {
    let text: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text(text)
            .font(.displayItalic(24))
            .foregroundColor(Color.bubbleUpText(for: colorScheme))
            .lineSpacing(6)
            .padding(.leading, 20)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(BubbleUpTheme.primary)
                    .frame(width: 3)
            }
            .padding(.vertical, 24)
    }
}

#Preview {
    ArticleBlockquote(text: "We can no longer afford the luxury of designing structures that fight their environment.")
        .padding()
}

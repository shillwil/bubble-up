import SwiftUI

/// Underline-style search bar matching the editorial design.
struct UnderlineSearchBar: View {
    @Binding var text: String
    let placeholder: String
    @FocusState private var isFocused: Bool
    @Environment(\.colorScheme) private var colorScheme

    init(text: Binding<String>, placeholder: String = "Search...") {
        self._text = text
        self.placeholder = placeholder
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16))
                .foregroundColor(Color.bubbleUpTextMuted(for: colorScheme))

            TextField(placeholder, text: $text)
                .font(.bodyText(15))
                .focused($isFocused)
                .autocorrectionDisabled()
        }
        .padding(.bottom, 8)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(isFocused ? BubbleUpTheme.primary : Color.bubbleUpText(for: colorScheme))
                .frame(height: 1)
        }
    }
}

#Preview {
    UnderlineSearchBar(text: .constant(""), placeholder: "Search your archive...")
        .padding()
}

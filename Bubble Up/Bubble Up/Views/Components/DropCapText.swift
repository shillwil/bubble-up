import SwiftUI

/// Renders the first letter of text as a large serif drop cap.
struct DropCapText: View {
    let text: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if text.isEmpty {
            EmptyView()
        } else {
            let firstChar = String(text.prefix(1))
            let rest = String(text.dropFirst())

            HStack(alignment: .top, spacing: 4) {
                Text(firstChar)
                    .font(.display(48, weight: .bold))
                    .foregroundColor(Color.bubbleUpText(for: colorScheme))
                    .padding(.trailing, 2)
                    .padding(.top, -4)

                Text(rest)
                    .font(.bodyText(17))
                    .foregroundColor(Color.bubbleUpText(for: colorScheme))
                    .lineSpacing(10)
            }
        }
    }
}

#Preview {
    DropCapText(text: "As sea levels rise and extreme weather events become the norm, the architectural paradigms of the 20th century are rapidly proving inadequate.")
        .padding()
}

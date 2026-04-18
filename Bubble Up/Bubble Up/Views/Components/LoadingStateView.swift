import SwiftUI

/// Generic loading state with editorial styling.
struct LoadingStateView: View {
    let message: String
    @Environment(\.colorScheme) private var colorScheme

    init(_ message: String = "Loading...") {
        self.message = message
    }

    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .tint(BubbleUpTheme.textMuted)

            Text(message.uppercased())
                .font(.metaLabel(12))
                .tracking(2)
                .foregroundColor(Color.bubbleUpTextMuted(for: colorScheme))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.bubbleUpBackground(for: colorScheme))
    }
}

#Preview {
    LoadingStateView("Parsing Article")
}

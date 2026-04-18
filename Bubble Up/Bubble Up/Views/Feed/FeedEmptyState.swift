import SwiftUI

/// Empty state shown when the feed has no items.
struct FeedEmptyState: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 48, weight: .ultraLight))
                .foregroundColor(Color.bubbleUpTextMuted(for: colorScheme))
                .padding(.bottom, 8)

            Text("Your desk is clear.")
                .font(.display(32, weight: .bold))
                .foregroundColor(Color.bubbleUpText(for: colorScheme))

            Text("Save articles from Safari to read them here.")
                .font(.bodyText(17))
                .foregroundColor(Color.bubbleUpTextMuted(for: colorScheme))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.bubbleUpBackground(for: colorScheme))
    }
}

#Preview {
    FeedEmptyState()
}

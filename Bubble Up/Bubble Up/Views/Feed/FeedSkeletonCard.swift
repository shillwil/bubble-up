import SwiftUI

/// Shimmer skeleton placeholder for loading summary bullets.
struct FeedSkeletonCard: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(0..<3, id: \.self) { index in
                HStack(alignment: .top, spacing: 16) {
                    Circle()
                        .fill(Color.bubbleUpBorder(for: colorScheme))
                        .frame(width: 6, height: 6)
                        .padding(.top, 8)

                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.bubbleUpBorder(for: colorScheme).opacity(0.7))
                        .frame(height: 16)
                        .frame(maxWidth: index == 2 ? .infinity : .infinity)
                        .padding(.trailing, index == 2 ? 60 : 0)
                }
            }
        }
        .shimmer()
    }
}

#Preview {
    FeedSkeletonCard()
        .padding()
}

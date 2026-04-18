import SwiftUI

/// Bullet point list with red dot markers, matching the editorial feed design.
struct RedBulletList: View {
    let bullets: [String]
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(bullets.enumerated()), id: \.offset) { _, bullet in
                HStack(alignment: .top, spacing: 16) {
                    Circle()
                        .fill(BubbleUpTheme.primary)
                        .frame(width: 6, height: 6)
                        .padding(.top, 8)

                    Text(bullet)
                        .font(.bodyText(17))
                        .foregroundColor(Color.bubbleUpText(for: colorScheme).opacity(0.9))
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

#Preview {
    RedBulletList(bullets: [
        "Digital spaces are increasingly mirroring physical minimalism to reduce cognitive load.",
        "The shift from 'feature-rich' to 'focused utility' is driving modern UI trends.",
        "Typography and negative space replace borders and backgrounds."
    ])
    .padding()
}

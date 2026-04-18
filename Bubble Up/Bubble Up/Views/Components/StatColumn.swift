import SwiftUI

/// Stat display column for the profile screen (e.g., "142 / ARTICLES READ").
struct StatColumn: View {
    let value: String
    let label: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.display(30, weight: .regular))
                .foregroundColor(Color.bubbleUpText(for: colorScheme))

            Text(label)
                .font(.system(size: 10, weight: .medium))
                .tracking(2)
                .textCase(.uppercase)
                .foregroundColor(Color.bubbleUpTextMuted(for: colorScheme))
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    HStack {
        StatColumn(value: "142", label: "Articles Read")
        StatColumn(value: "28", label: "Saved")
        StatColumn(value: "12", label: "Day Streak")
    }
    .padding()
}

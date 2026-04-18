import SwiftUI

/// 2px red progress bar shown at the top of the article detail view.
struct ReadingProgressBar: View {
    let progress: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(BubbleUpTheme.borderSubtle)
                    .frame(height: 2)

                Rectangle()
                    .fill(BubbleUpTheme.primary)
                    .frame(width: geo.size.width * min(max(progress, 0), 1), height: 2)
                    .animation(.linear(duration: 0.1), value: progress)
            }
        }
        .frame(height: 2)
    }
}

#Preview {
    ReadingProgressBar(progress: 0.45)
}

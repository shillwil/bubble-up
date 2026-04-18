import SwiftUI

/// Gradient overlay that fades an image into the background color.
/// Used on feed card cover images.
struct GradientOverlay: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                LinearGradient(
                    colors: [
                        .clear,
                        Color.bubbleUpBackground(for: colorScheme)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 200)
            }
    }
}

extension View {
    func gradientOverlay() -> some View {
        modifier(GradientOverlay())
    }
}

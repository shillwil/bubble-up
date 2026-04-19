import SwiftUI

/// Shimmer animation modifier for loading skeleton states.
struct ShimmerModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content
            .overlay {
                GeometryReader { geometry in
                    let shimmerColor = colorScheme == .dark
                        ? Color.white.opacity(0.15)
                        : Color.white.opacity(0.4)

                    LinearGradient(
                        colors: [
                            .clear,
                            shimmerColor,
                            .clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geometry.size.width * 2)
                    .offset(x: phase * geometry.size.width)
                }
                .clipped()
            }
            .onAppear {
                withAnimation(
                    .linear(duration: 1.5)
                    .repeatForever(autoreverses: false)
                ) {
                    phase = 1
                }
            }
    }
}

extension View {
    func shimmer() -> some View {
        modifier(ShimmerModifier())
    }
}

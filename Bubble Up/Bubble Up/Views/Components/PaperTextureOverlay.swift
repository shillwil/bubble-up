import SwiftUI

/// Subtle noise grain overlay for the editorial paper texture effect.
struct PaperTextureOverlay: ViewModifier {
    func body(content: Content) -> some View {
        content
            .overlay {
                Canvas { context, size in
                    // Draw a subtle noise pattern
                    for _ in 0..<500 {
                        let x = CGFloat.random(in: 0..<size.width)
                        let y = CGFloat.random(in: 0..<size.height)
                        let dotSize = CGFloat.random(in: 0.5...1.5)
                        let opacity = Double.random(in: 0.02...0.06)

                        context.opacity = opacity
                        context.fill(
                            Path(ellipseIn: CGRect(x: x, y: y, width: dotSize, height: dotSize)),
                            with: .color(.black)
                        )
                    }
                }
                .allowsHitTesting(false)
                .blendMode(.multiply)
            }
    }
}

extension View {
    func paperTexture() -> some View {
        modifier(PaperTextureOverlay())
    }
}

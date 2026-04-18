import SwiftUI

extension Font {
    /// Headlines and display text — New York (Apple's system serif)
    static func display(_ size: CGFloat, weight: Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    /// Italic display text — New York serif italic
    static func displayItalic(_ size: CGFloat) -> Font {
        .system(size: size, design: .serif).italic()
    }

    /// Body text — SF Pro Text (system default)
    static func bodyText(_ size: CGFloat = 17) -> Font {
        .system(size: size)
    }

    /// Meta labels — SF Pro, used with .textCase(.uppercase) + .tracking()
    static func metaLabel(_ size: CGFloat = 13) -> Font {
        .system(size: size, weight: .medium)
    }

    /// Button text — SF Pro bold
    static func buttonText(_ size: CGFloat = 15) -> Font {
        .system(size: size, weight: .bold)
    }
}

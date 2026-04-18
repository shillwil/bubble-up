import SwiftUI

enum BubbleUpTheme {
    // MARK: - Colors

    static let primary = Color(hex: 0xDA2D16)
    static let background = Color(hex: 0xF5F4F0)
    static let surface = Color.white
    static let textDark = Color(hex: 0x111111)
    static let textMuted = Color(hex: 0x82817D)
    static let borderSubtle = Color(hex: 0xE5E4E0)

    // Dark mode variants
    static let backgroundDark = Color(hex: 0x211311)
    static let surfaceDark = Color(hex: 0x2A1A17)
    static let textDarkInverted = Color(hex: 0xF5F4F0)
    static let textMutedDark = Color(hex: 0xA09E99)
    static let borderSubtleDark = Color(hex: 0x3A2A25)

    // MARK: - Spacing

    static let paddingHorizontal: CGFloat = 24
    static let paddingVertical: CGFloat = 16
    static let cardPaddingBottom: CGFloat = 96
    static let gridSpacing: CGFloat = 16

    // MARK: - Corner Radii

    static let cornerRadiusSm: CGFloat = 2
    static let cornerRadiusMd: CGFloat = 4
    static let cornerRadiusLg: CGFloat = 8
    static let cornerRadiusXL: CGFloat = 16
}

// MARK: - Color Hex Initializer

extension Color {
    init(hex: UInt, alpha: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

// MARK: - Environment-Aware Colors

extension Color {
    static func bubbleUpBackground(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? BubbleUpTheme.backgroundDark : BubbleUpTheme.background
    }

    static func bubbleUpSurface(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? BubbleUpTheme.surfaceDark : BubbleUpTheme.surface
    }

    static func bubbleUpText(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? BubbleUpTheme.textDarkInverted : BubbleUpTheme.textDark
    }

    static func bubbleUpTextMuted(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? BubbleUpTheme.textMutedDark : BubbleUpTheme.textMuted
    }

    static func bubbleUpBorder(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? BubbleUpTheme.borderSubtleDark : BubbleUpTheme.borderSubtle
    }
}

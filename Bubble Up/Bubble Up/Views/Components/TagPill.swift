import SwiftUI

/// Reusable capsule tag component with display-only and tappable modes.
struct TagPill: View {
    let label: String
    var isSelected: Bool = false
    var onTap: (() -> Void)? = nil
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if let onTap {
            Button(action: onTap) {
                pillContent
            }
            .buttonStyle(.plain)
        } else {
            pillContent
        }
    }

    private var pillContent: some View {
        Text(label.uppercased())
            .font(.system(size: 11, weight: .medium))
            .tracking(1.0)
            .foregroundColor(foregroundColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(backgroundColor)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(borderColor, lineWidth: isSelected ? 0 : 1)
            )
    }

    private var foregroundColor: Color {
        if onTap != nil && isSelected {
            return .white
        }
        return Color.bubbleUpTextMuted(for: colorScheme)
    }

    private var backgroundColor: Color {
        if onTap != nil && isSelected {
            return BubbleUpTheme.primary
        }
        return .clear
    }

    private var borderColor: Color {
        if onTap != nil && isSelected {
            return .clear
        }
        return Color.bubbleUpBorder(for: colorScheme)
    }
}

import SwiftUI

/// Custom two-column masonry/waterfall layout using the Layout protocol.
struct MasonryLayout: Layout {
    let columns: Int
    let spacing: CGFloat

    init(columns: Int = 2, spacing: CGFloat = 16) {
        self.columns = columns
        self.spacing = spacing
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let containerWidth = proposal.width ?? 0
        let columnWidth = (containerWidth - spacing * CGFloat(columns - 1)) / CGFloat(columns)
        var columnHeights = Array(repeating: CGFloat(0), count: columns)

        for subview in subviews {
            let shortestColumn = columnHeights.enumerated().min(by: { $0.element < $1.element })?.offset ?? 0
            let size = subview.sizeThatFits(ProposedViewSize(width: columnWidth, height: nil))
            columnHeights[shortestColumn] += size.height + spacing
        }

        let maxHeight = columnHeights.max() ?? 0
        return CGSize(width: containerWidth, height: maxHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let columnWidth = (bounds.width - spacing * CGFloat(columns - 1)) / CGFloat(columns)
        var columnHeights = Array(repeating: CGFloat(0), count: columns)

        for subview in subviews {
            let shortestColumn = columnHeights.enumerated().min(by: { $0.element < $1.element })?.offset ?? 0
            let x = bounds.minX + CGFloat(shortestColumn) * (columnWidth + spacing)
            let y = bounds.minY + columnHeights[shortestColumn]

            let size = subview.sizeThatFits(ProposedViewSize(width: columnWidth, height: nil))

            subview.place(
                at: CGPoint(x: x, y: y),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: columnWidth, height: size.height)
            )

            columnHeights[shortestColumn] += size.height + spacing
        }
    }
}

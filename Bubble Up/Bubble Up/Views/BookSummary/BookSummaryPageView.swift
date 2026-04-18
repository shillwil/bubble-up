import SwiftUI

/// Single page in a full book summary (horizontal paging).
struct BookSummaryPageView: View {
    @ObservedObject var page: PagedItem
    let totalPages: Int
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Page indicator
                Text("\(page.pageNumber) / \(totalPages)")
                    .font(.metaLabel(12))
                    .tracking(2)
                    .foregroundColor(Color.bubbleUpTextMuted(for: colorScheme))

                // Page title
                Text(page.pageTitle ?? "Key Idea")
                    .font(.display(24, weight: .bold))
                    .foregroundColor(Color.bubbleUpText(for: colorScheme))

                // Page content
                Text(page.content ?? "")
                    .font(.bodyText(17))
                    .foregroundColor(Color.bubbleUpText(for: colorScheme))
                    .lineSpacing(8)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 16)
        }
    }
}

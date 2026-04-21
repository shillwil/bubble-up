import SwiftUI

/// Renders extracted long-form article text (`rawContent`) as a styled reader,
/// splitting on paragraph boundaries and applying a drop cap to the opening
/// paragraph to match the editorial look of the summary block above it.
struct ArticleReaderSection: View {
    let rawContent: String
    @Environment(\.colorScheme) private var colorScheme

    private var paragraphs: [String] {
        rawContent
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        if paragraphs.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 20) {
                sectionHeader

                DropCapText(text: paragraphs[0])

                ForEach(Array(paragraphs.dropFirst().enumerated()), id: \.offset) { _, paragraph in
                    Text(paragraph)
                        .font(.bodyText(17))
                        .foregroundColor(Color.bubbleUpText(for: colorScheme))
                        .lineSpacing(8)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var sectionHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("FULL TEXT")
                .font(.metaLabel(12))
                .tracking(2)
                .foregroundColor(Color.bubbleUpTextMuted(for: colorScheme))
            Divider()
        }
    }
}

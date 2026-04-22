import SwiftUI

/// Single card in the library masonry grid.
struct LibraryCard: View {
    @ObservedObject var item: LibraryItem
    @Environment(LibraryItemsRepository.self) private var repository
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .headline) private var titleSize: CGFloat = 15
    @State private var showDeleteConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Thumbnail (if available)
            if let thumbnailData = item.thumbnailData,
               let uiImage = UIImage(data: thumbnailData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity)
                    .frame(height: imageHeight)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: BubbleUpTheme.cornerRadiusSm))
                    .padding(.bottom, 12)
            } else if let thumbnailURL = item.thumbnailURL,
                      let url = URL(string: thumbnailURL) {
                AsyncImage(url: url) { phase in
                    if case .success(let image) = phase {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(maxWidth: .infinity)
                            .frame(height: imageHeight)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: BubbleUpTheme.cornerRadiusSm))
                            .padding(.bottom, 12)
                    }
                }
            } else if item.thumbnailData == nil && item.thumbnailURL == nil && item.summary != nil {
                // Text-only card: show excerpt
                Text(item.summary ?? "")
                    .font(.bodyText(14))
                    .foregroundColor(Color.bubbleUpText(for: colorScheme))
                    .lineLimit(3)
                    .lineSpacing(4)
                    .padding(.bottom, 8)
                    .padding(.top, 8)
            }

            // Title
            Text(item.title ?? "Untitled")
                .font(.system(size: titleSize, weight: .semibold, design: .serif))
                .foregroundColor(Color.bubbleUpText(for: colorScheme))
                .lineLimit(3)
                .padding(.bottom, 4)

            // Source
            if let source = item.sourceDisplayName {
                Text(source)
                    .font(.system(size: 12))
                    .tracking(0.5)
                    .textCase(.uppercase)
                    .foregroundColor(Color.bubbleUpTextMuted(for: colorScheme))
            }

            // Tags
            if !item.tagsArray.isEmpty {
                HStack(spacing: 4) {
                    ForEach(item.tagsArray.prefix(3), id: \.self) { tag in
                        TagPill(label: tag)
                    }
                }
                .padding(.top, 6)
            }
        }
        .padding(8)
        .background(Color.bubbleUpSurface(for: colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: BubbleUpTheme.cornerRadiusMd))
        .overlay {
            RoundedRectangle(cornerRadius: BubbleUpTheme.cornerRadiusMd)
                .stroke(Color.bubbleUpBorder(for: colorScheme), lineWidth: 1)
        }
        .contextMenu {
            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .confirmationDialog("Delete this item?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                repository.deleteItem(item)
            }
        }
    }

    /// Vary image height for visual interest in masonry grid.
    private var imageHeight: CGFloat {
        guard let id = item.id else { return 150 }
        let hash = abs(id.hashValue)
        let heights: [CGFloat] = [120, 150, 180, 200]
        return heights[hash % heights.count]
    }
}

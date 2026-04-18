import SwiftUI
import CoreData

/// Single full-screen feed card matching the editorial mock.
struct FeedCardView: View {
    @ObservedObject var item: LibraryItem
    @Environment(LibraryItemsRepository.self) private var repository
    @Environment(\.colorScheme) private var colorScheme
    @State private var showArticleDetail = false
    @State private var showDeleteConfirmation = false

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                VStack(spacing: 0) {
                    // Cover image (top ~50%)
                    coverImage(height: geo.size.height * 0.5, width: geo.size.width)

                    Spacer(minLength: 0)
                }

                // Content overlapping the image from the bottom
                VStack(alignment: .leading, spacing: 0) {
                    Spacer(minLength: geo.size.height * 0.35)

                    // Title
                    Text(item.title ?? "Untitled")
                        .font(.display(36, weight: .bold))
                        .foregroundColor(Color.bubbleUpText(for: colorScheme))
                        .tracking(-0.5)
                        .lineLimit(3)
                        .padding(.bottom, 12)

                    // Meta line
                    MetaLine(
                        author: item.authorName,
                        source: item.sourceDisplayName,
                        readTime: item.estimatedReadTime > 0 ? Int(item.estimatedReadTime) : nil
                    )
                    .padding(.bottom, 24)

                    // Summary bullets or skeleton
                    summaryContent

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, BubbleUpTheme.paddingHorizontal)
                .padding(.bottom, 80)

                // Sticky bottom button
                readFullButton
            }
        }
        .background(Color.bubbleUpBackground(for: colorScheme))
        .navigationDestination(isPresented: $showArticleDetail) {
            ArticleDetailView(item: item)
        }
        .confirmationDialog("Delete this item?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                repository.deleteItem(item)
            }
        }
        .contextMenu {
            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: - Cover Image

    @ViewBuilder
    private func coverImage(height: CGFloat, width: CGFloat) -> some View {
        ZStack(alignment: .bottom) {
            if let thumbnailData = item.thumbnailData,
               let uiImage = UIImage(data: thumbnailData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: width, height: height)
                    .clipped()
            } else if let thumbnailURL = item.thumbnailURL,
                      let url = URL(string: thumbnailURL) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: width, height: height)
                            .clipped()
                    default:
                        Rectangle()
                            .fill(Color.bubbleUpBorder(for: colorScheme))
                            .frame(width: width, height: height)
                    }
                }
            } else {
                Rectangle()
                    .fill(Color.bubbleUpBorder(for: colorScheme))
                    .frame(width: width, height: height)
            }

            // Gradient overlay
            LinearGradient(
                colors: [.clear, Color.bubbleUpBackground(for: colorScheme)],
                startPoint: .init(x: 0.5, y: 0.3),
                endPoint: .bottom
            )
            .frame(height: height * 0.7)
        }
        .frame(height: height)
    }

    // MARK: - Summary Content

    @ViewBuilder
    private var summaryContent: some View {
        switch item.summaryStatusEnum {
        case .completed:
            RedBulletList(bullets: item.summaryBulletsArray)
        case .pending, .generating:
            FeedSkeletonCard()
        case .failed:
            Button {
                retrySummary()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.clockwise")
                    Text("Tap to retry summary")
                }
                .font(.bodyText(15))
                .foregroundColor(BubbleUpTheme.primary)
            }
        }
    }

    // MARK: - Read Full Button

    private var readFullButton: some View {
        VStack(spacing: 0) {
            Button {
                showArticleDetail = true
            } label: {
                Text("READ FULL")
                    .font(.buttonText(15))
                    .tracking(1.5)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(BubbleUpTheme.primary)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: BubbleUpTheme.cornerRadiusSm))
            }
            .padding(.horizontal, BubbleUpTheme.paddingHorizontal)
            .padding(.vertical, BubbleUpTheme.paddingVertical)
        }
        .background(Color.bubbleUpBackground(for: colorScheme))
    }

    // MARK: - Retry

    private func retrySummary() {
        guard let itemID = item.id else { return }

        // Reset status to pending
        item.summaryStatusEnum = .pending
        try? item.managedObjectContext?.save()

        // Create a new pending request
        if let context = item.managedObjectContext {
            let _ = PendingRequest(
                context: context,
                libraryItemID: itemID,
                requestType: item.itemTypeEnum == .bookSummary ? "book_summary" : "link_summary",
                priority: .userInitiated
            )
            try? context.save()
        }

        // Notify scheduler
        if let scheduler = repository.requestScheduler {
            Task { await scheduler.notifyNewRequest() }
        }
    }
}

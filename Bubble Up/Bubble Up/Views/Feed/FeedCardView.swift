import SwiftUI
import CoreData

/// Single full-screen feed card matching the editorial mock.
struct FeedCardView: View {
    @ObservedObject var item: LibraryItem
    var bottomInset: CGFloat = 0
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
                        .font(.system(.largeTitle, design: .serif, weight: .bold))
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

                    // Tags
                    if !item.tagsArray.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(item.tagsArray, id: \.self) { tag in
                                    TagPill(label: tag)
                                }
                            }
                        }
                        .padding(.bottom, 8)
                    }

                    // Summary bullets or skeleton
                    summaryContent

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, BubbleUpTheme.paddingHorizontal)
                .padding(.bottom, 80 + max(bottomInset, 90))

                // Sticky bottom button
                readFullButton
            }
        }
        .background(Color.bubbleUpBackground(for: colorScheme))
        .navigationDestination(isPresented: $showArticleDetail) {
            if item.itemTypeEnum == .bookSummary {
                BookSummaryView(itemID: item.id!, showSaveButton: false)
            } else if item.itemTypeEnum == .image {
                ImageDetailView(item: item)
            } else if item.itemTypeEnum == .video {
                VideoDetailView(item: item)
            } else if item.itemTypeEnum == .pdf {
                PDFDetailView(item: item)
            } else {
                ArticleDetailView(item: item)
            }
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
        .onTapGesture {
            showArticleDetail = true
        }
    }

    // MARK: - Summary Content

    @ViewBuilder
    private var summaryContent: some View {
        switch item.summaryStatusEnum {
        case .completed:
            RedBulletList(bullets: item.summaryBulletsArray)
        case .skipped:
            // Short / media-only content (memes, one-liners). Show a plain-text
            // preview of the extracted body so the card still says something.
            if let preview = skippedContentPreview {
                Text(preview)
                    .font(.bodyText(15))
                    .foregroundColor(Color.bubbleUpText(for: colorScheme).opacity(0.9))
                    .lineSpacing(4)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .pending, .generating:
            FeedSkeletonCard()
        case .failed:
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                    Text("Summary generation failed")
                }
                .font(.bodyText(15))
                .foregroundColor(Color.bubbleUpTextMuted(for: colorScheme))

                Text("Try opening the original link to verify it\u{2019}s accessible, then tap below to retry.")
                    .font(.bodyText(13))
                    .foregroundColor(Color.bubbleUpTextMuted(for: colorScheme))

                Button {
                    retrySummary()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.clockwise")
                        Text("Retry Summary")
                    }
                    .font(.bodyText(15))
                    .foregroundColor(BubbleUpTheme.primary)
                }
                .padding(.top, 4)
            }
        }
    }

    // MARK: - Read Full Button

    private var readFullButtonLabel: String {
        switch item.itemTypeEnum {
        case .youtube: return "WATCH VIDEO"
        case .pdf: return "VIEW PDF"
        case .bookSummary: return "READ SUMMARY"
        case .image: return "VIEW IMAGE"
        case .video: return "WATCH VIDEO"
        default: return "READ FULL"
        }
    }

    private var readFullButton: some View {
        VStack(spacing: 0) {
            Button {
                showArticleDetail = true
            } label: {
                Text(readFullButtonLabel)
                    .font(.buttonText(15))
                    .tracking(1.5)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(BubbleUpTheme.primary)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: BubbleUpTheme.cornerRadiusSm))
            }
            .padding(.horizontal, BubbleUpTheme.paddingHorizontal)
            .padding(.top, 24)
            .padding(.bottom, max(bottomInset, 90) + 24)
        }
        .background(Color.bubbleUpBackground(for: colorScheme))
    }

    // MARK: - Retry

    private func retrySummary() {
        repository.retryRequest(for: item)
    }

    // MARK: - Skipped preview

    /// For `.skipped` items, pull a clean body preview out of rawContent so the
    /// card reads as content rather than an empty frame.
    private var skippedContentPreview: String? {
        guard let raw = item.rawContent, !raw.isEmpty else { return nil }

        let body: String
        switch item.contentMimeType {
        case "application/twitter":
            body = SocialPostCodec.decode(raw, platform: .twitter)?.body ?? raw
        case "application/reddit":
            body = SocialPostCodec.decode(raw, platform: .reddit)?.body ?? raw
        default:
            body = raw
        }

        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

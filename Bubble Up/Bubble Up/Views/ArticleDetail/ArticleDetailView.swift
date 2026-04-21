import SwiftUI
import Observation

/// Reference-typed holder for the scroll progress so that writes don't
/// invalidate the parent view's body. `ArticleDetailView` holds the model
/// but never reads `progress.value` in its own body — only the
/// `ReadingProgressBarSubscriber` subview reads it. SwiftUI's Observation
/// framework therefore only rebuilds the subscriber subview on scroll,
/// leaving the (expensive) Reddit hierarchy untouched.
@Observable
@MainActor
final class ScrollProgressModel {
    var value: Double = 0
}

/// Reads the progress value, so it — and only it — re-evaluates on scroll.
private struct ReadingProgressBarSubscriber: View {
    let model: ScrollProgressModel
    var body: some View {
        ReadingProgressBar(progress: model.value)
    }
}

/// Full article reader view with reading progress bar, editorial typography.
struct ArticleDetailView: View {
    @ObservedObject var item: LibraryItem
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    @State private var scrollProgress = ScrollProgressModel()
    @State private var showWebView = false

    var body: some View {
        ZStack(alignment: .top) {
            // Reading progress bar at very top. The bar reads `scrollProgress.value`
            // inside its own body, so only this subview invalidates on scroll.
            ReadingProgressBarSubscriber(model: scrollProgress)
                .zIndex(1)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    articleHeader
                    heroImage
                    articleBody
                }
                .padding(.top, 16)
            }
            .onScrollGeometryChange(for: Double.self) { geo in
                let contentHeight = geo.contentSize.height - geo.containerSize.height
                let raw = contentHeight > 0 ? geo.contentOffset.y / contentHeight : 0
                // Round to 1% so the action fires at most ~100 times per full
                // scroll instead of per sub-pixel.
                return (raw * 100).rounded() / 100
            } action: { _, newValue in
                scrollProgress.value = min(max(newValue, 0), 1)
            }
        }
        .background(Color.bubbleUpBackground(for: colorScheme))
        .navigationBarBackButtonHidden(false)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    shareArticle()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .foregroundColor(Color.bubbleUpText(for: colorScheme))
                }
            }
        }
        .sheet(isPresented: $showWebView) {
            if let urlString = item.url, let url = URL(string: urlString) {
                NavigationStack {
                    WebView(url: url)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Done") { showWebView = false }
                            }
                        }
                }
            }
        }
    }

    // MARK: - Article Header

    private var articleHeader: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(item.title ?? "Untitled")
                .font(.display(32, weight: .bold))
                .foregroundColor(Color.bubbleUpText(for: colorScheme))
                .tracking(-0.3)

            MetaLine(
                author: item.authorName,
                source: item.sourceDisplayName,
                readTime: item.estimatedReadTime > 0 ? Int(item.estimatedReadTime) : nil
            )

            if !item.tagsArray.isEmpty {
                HStack(spacing: 6) {
                    ForEach(item.tagsArray, id: \.self) { tag in
                        TagPill(label: tag)
                    }
                }
            }
        }
        .padding(.horizontal, BubbleUpTheme.paddingHorizontal)
        .padding(.bottom, 24)
    }

    // MARK: - Hero Image

    @ViewBuilder
    private var heroImage: some View {
        if let thumbnailData = item.thumbnailData,
           let uiImage = UIImage(data: thumbnailData) {
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(height: 220)
                .frame(maxWidth: .infinity)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: BubbleUpTheme.cornerRadiusSm))
                .padding(.horizontal, BubbleUpTheme.paddingHorizontal)
                .padding(.bottom, 24)
                .onTapGesture { showWebView = true }
        } else if let thumbnailURL = item.thumbnailURL,
                  let url = URL(string: thumbnailURL) {
            AsyncImage(url: url) { phase in
                if case .success(let image) = phase {
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 220)
                        .frame(maxWidth: .infinity)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: BubbleUpTheme.cornerRadiusSm))
                        .padding(.horizontal, BubbleUpTheme.paddingHorizontal)
                        .padding(.bottom, 24)
                        .onTapGesture { showWebView = true }
                }
            }
        }
    }

    // MARK: - Article Body

    private var articleBody: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Summary + key takeaways are only shown when the AI actually ran.
            // For `.skipped` items (memes, one-liners, image-only posts) we jump
            // straight to the reader section below.
            if item.summaryStatusEnum != .skipped,
               let summary = item.summary, !summary.isEmpty {
                DropCapText(text: summary)

                if !item.summaryBulletsArray.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Key Takeaways")
                            .font(.display(24, weight: .bold))
                            .foregroundColor(Color.bubbleUpText(for: colorScheme))

                        RedBulletList(bullets: item.summaryBulletsArray)
                    }
                    .padding(.top, 16)
                }
            } else if item.summaryStatusEnum == .pending || item.summaryStatusEnum == .generating {
                LoadingStateView("Generating summary")
                    .frame(height: 200)
            }

            readerSection

            // View full article button
            if item.url != nil {
                Button {
                    showWebView = true
                } label: {
                    Text(originalButtonLabel)
                        .font(.buttonText(14))
                        .tracking(1.5)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .overlay {
                            RoundedRectangle(cornerRadius: BubbleUpTheme.cornerRadiusSm)
                                .stroke(BubbleUpTheme.primary, lineWidth: 1)
                        }
                        .foregroundColor(BubbleUpTheme.primary)
                }
                .padding(.top, 16)
            }

            // Comments section
            commentsSection
        }
        .padding(.horizontal, BubbleUpTheme.paddingHorizontal)
        .padding(.bottom, 60)
    }

    // MARK: - Reader Section

    /// Renders the extracted raw content in-app, branching by content type so
    /// tweets and reddit posts get structured cards instead of a wall of text.
    @ViewBuilder
    private var readerSection: some View {
        if let raw = item.rawContent, !raw.isEmpty {
            switch item.contentMimeType {
            case "application/twitter":
                TweetReaderCard(rawContent: raw)
                    .padding(.top, item.summaryStatusEnum == .skipped ? 0 : 16)
            case "application/reddit":
                RedditReaderCard(rawContent: raw)
                    .padding(.top, item.summaryStatusEnum == .skipped ? 0 : 16)
            default:
                // Only show the article reader for items where the AI summary
                // ran — showing the full article text alongside a still-loading
                // summary would be visually noisy. Skipped items don't route here
                // (they use the tweet/reddit cards above).
                if item.summaryStatusEnum == .completed {
                    ArticleReaderSection(rawContent: raw)
                        .padding(.top, 16)
                }
            }
        }
    }

    // MARK: - Comments

    private var commentsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !item.orderedComments.isEmpty {
                Divider()
                    .padding(.vertical, 8)

                Text("Notes")
                    .font(.display(20, weight: .bold))
                    .foregroundColor(Color.bubbleUpText(for: colorScheme))

                ForEach(item.orderedComments) { comment in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(comment.text ?? "")
                            .font(.bodyText(15))
                            .foregroundColor(Color.bubbleUpText(for: colorScheme))

                        if let date = comment.createdAt {
                            Text(date, style: .relative)
                                .font(.metaLabel(12))
                                .foregroundColor(Color.bubbleUpTextMuted(for: colorScheme))
                        }
                    }
                }
            }
        }
    }

    // MARK: - Dynamic Labels

    private var originalButtonLabel: String {
        switch item.itemTypeEnum {
        case .youtube: return "WATCH ON YOUTUBE"
        case .pdf: return "VIEW ORIGINAL PDF"
        default: return "VIEW ORIGINAL ARTICLE"
        }
    }

    // MARK: - Actions

    private func shareArticle() {
        guard let urlString = item.url, let url = URL(string: urlString) else { return }
        let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)

        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = scene.windows.first?.rootViewController {
            rootVC.present(activityVC, animated: true)
        }
    }
}

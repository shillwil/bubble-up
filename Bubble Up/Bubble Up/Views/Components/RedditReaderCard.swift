import SwiftUI

/// Structured renderer for a Reddit post decoded from `LibraryItem.rawContent`
/// via `SocialPostCodec`. Shows a subreddit badge, author, post body, and a
/// stack of top comments if any were captured during extraction.
struct RedditReaderCard: View {
    let rawContent: String
    @Environment(\.colorScheme) private var colorScheme

    // Cache the decoded post so `SocialPostCodec.decode` runs once per card
    // lifetime instead of on every parent body invalidation. On Reddit the
    // rawContent is big enough (TL;DR + comments) that re-decoding per scroll
    // tick measurably drops frame rate.
    @State private var post: SocialPostContent?

    var body: some View {
        Group {
            if let post {
                loadedContent(post)
            } else {
                ArticleReaderSection(rawContent: rawContent)
            }
        }
        .task(id: rawContent) {
            post = SocialPostCodec.decode(rawContent, platform: .reddit)
        }
    }

    @ViewBuilder
    private func loadedContent(_ post: SocialPostContent) -> some View {
            VStack(alignment: .leading, spacing: 20) {
                sectionHeader

                if let summary = post.discussionSummary {
                    discussionSummaryCard(summary)
                }

                VStack(alignment: .leading, spacing: 12) {
                    metadataRow(for: post)

                    if !post.body.isEmpty {
                        if post.body.count > 120 {
                            DropCapText(text: post.body)
                        } else {
                            Text(post.body)
                                .font(.bodyText(17))
                                .foregroundColor(Color.bubbleUpText(for: colorScheme))
                                .lineSpacing(6)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: BubbleUpTheme.cornerRadiusLg)
                        .fill(Color.bubbleUpSurface(for: colorScheme))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: BubbleUpTheme.cornerRadiusLg)
                        .stroke(Color.bubbleUpBorder(for: colorScheme), lineWidth: 1)
                )

                if !post.topComments.isEmpty {
                    commentsStack(for: post)
                }
            }
    }

    private func discussionSummaryCard(_ summary: SocialPostContent.DiscussionSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // No Spacer — a Spacer inside an HStack advertises an infinite
            // ideal width, which propagates up through every leading-aligned
            // VStack and lets the outer ScrollView pan horizontally. Inline
            // the author attribution with a "·" separator instead.
            HStack(spacing: 6) {
                Image(systemName: "text.bubble.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(BubbleUpTheme.primary)
                Text("THREAD TL;DR · u/\(summary.author)")
                    .font(.metaLabel(11))
                    .tracking(2)
                    .foregroundColor(BubbleUpTheme.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Text(summary.body)
                .font(.bodyText(15))
                .foregroundColor(Color.bubbleUpText(for: colorScheme))
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: BubbleUpTheme.cornerRadiusMd)
                .fill(BubbleUpTheme.primary.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: BubbleUpTheme.cornerRadiusMd)
                .stroke(BubbleUpTheme.primary.opacity(0.35), lineWidth: 1)
        )
    }

    private var sectionHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("REDDIT POST")
                .font(.metaLabel(12))
                .tracking(2)
                .foregroundColor(Color.bubbleUpTextMuted(for: colorScheme))
            Divider()
        }
    }

    private func metadataRow(for post: SocialPostContent) -> some View {
        HStack(spacing: 8) {
            if let subreddit = post.subreddit {
                Text(subreddit)
                    .font(.metaLabel(12).weight(.semibold))
                    .tracking(1)
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(BubbleUpTheme.primary))
                    .lineLimit(1)
            }
            if let handle = post.authorHandle {
                Text(handle)
                    .font(.metaLabel(12))
                    .tracking(0.5)
                    .foregroundColor(Color.bubbleUpTextMuted(for: colorScheme))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
    }

    private func commentsStack(for post: SocialPostContent) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("TOP COMMENTS")
                .font(.metaLabel(11))
                .tracking(2)
                .foregroundColor(Color.bubbleUpTextMuted(for: colorScheme))

            ForEach(Array(post.topComments.enumerated()), id: \.offset) { _, comment in
                VStack(alignment: .leading, spacing: 4) {
                    Text("u/\(comment.author)")
                        .font(.metaLabel(12).weight(.semibold))
                        .foregroundColor(BubbleUpTheme.primary)
                    Text(comment.body)
                        .font(.bodyText(15))
                        .foregroundColor(Color.bubbleUpText(for: colorScheme).opacity(0.9))
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: BubbleUpTheme.cornerRadiusMd)
                        .fill(Color.bubbleUpBorder(for: colorScheme).opacity(0.3))
                )
            }
        }
    }
}

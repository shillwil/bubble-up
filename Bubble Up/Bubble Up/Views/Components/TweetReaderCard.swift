import SwiftUI

/// Structured renderer for a tweet decoded from `LibraryItem.rawContent` via
/// `SocialPostCodec`. Mimics the spacing and weight of a native tweet without
/// pulling in any external embed.
struct TweetReaderCard: View {
    let rawContent: String
    @Environment(\.colorScheme) private var colorScheme

    private var post: SocialPostContent? {
        SocialPostCodec.decode(rawContent, platform: .twitter)
    }

    var body: some View {
        if let post {
            VStack(alignment: .leading, spacing: 16) {
                sectionHeader

                VStack(alignment: .leading, spacing: 12) {
                    authorRow(for: post)

                    if !post.body.isEmpty {
                        Text(post.body)
                            .font(.bodyText(18))
                            .foregroundColor(Color.bubbleUpText(for: colorScheme))
                            .lineSpacing(6)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if post.mediaCount > 0 || post.hasVideo {
                        mediaChips(for: post)
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
            }
        } else {
            // Decoding failed — fall back to raw content as a safety net.
            ArticleReaderSection(rawContent: rawContent)
        }
    }

    private var sectionHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("TWEET")
                .font(.metaLabel(12))
                .tracking(2)
                .foregroundColor(Color.bubbleUpTextMuted(for: colorScheme))
            Divider()
        }
    }

    private func authorRow(for post: SocialPostContent) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Circle()
                .fill(BubbleUpTheme.primary.opacity(0.15))
                .frame(width: 36, height: 36)
                .overlay(
                    Text(String((post.authorDisplayName ?? post.authorHandle ?? "?").prefix(1)).uppercased())
                        .font(.display(16, weight: .bold))
                        .foregroundColor(BubbleUpTheme.primary)
                )

            VStack(alignment: .leading, spacing: 2) {
                if let name = post.authorDisplayName {
                    Text(name)
                        .font(.bodyText(15).weight(.semibold))
                        .foregroundColor(Color.bubbleUpText(for: colorScheme))
                }
                if let handle = post.authorHandle {
                    Text(handle)
                        .font(.metaLabel(13))
                        .foregroundColor(Color.bubbleUpTextMuted(for: colorScheme))
                }
            }
        }
    }

    @ViewBuilder
    private func mediaChips(for post: SocialPostContent) -> some View {
        HStack(spacing: 8) {
            if post.mediaCount > 0 {
                Label(
                    "\(post.mediaCount) \(post.mediaCount == 1 ? "image" : "images")",
                    systemImage: "photo"
                )
                .font(.metaLabel(12))
                .foregroundColor(Color.bubbleUpTextMuted(for: colorScheme))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.bubbleUpBorder(for: colorScheme).opacity(0.4)))
            }
            if post.hasVideo {
                Label("Video", systemImage: "play.rectangle")
                    .font(.metaLabel(12))
                    .foregroundColor(Color.bubbleUpTextMuted(for: colorScheme))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.bubbleUpBorder(for: colorScheme).opacity(0.4)))
            }
        }
    }
}

import SwiftUI
import AVKit

/// Video playback view using AVPlayerViewController.
struct VideoDetailView: View {
    @ObservedObject var item: LibraryItem
    @Environment(\.colorScheme) private var colorScheme
    @State private var player: AVPlayer?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Video player
                if let player {
                    VideoPlayer(player: player)
                        .frame(height: 250)
                        .clipShape(RoundedRectangle(cornerRadius: BubbleUpTheme.cornerRadiusSm))
                } else if let thumbnailData = item.thumbnailData,
                          let uiImage = UIImage(data: thumbnailData) {
                    // Thumbnail fallback
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 250)
                        .frame(maxWidth: .infinity)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: BubbleUpTheme.cornerRadiusSm))
                }

                // Title
                Text(item.title ?? "Video")
                    .font(.display(24, weight: .bold))
                    .foregroundColor(Color.bubbleUpText(for: colorScheme))

                // Duration
                if item.estimatedReadTime > 0 {
                    Text("\(item.estimatedReadTime) min")
                        .font(.metaLabel(13))
                        .foregroundColor(Color.bubbleUpTextMuted(for: colorScheme))
                }

                // Tags
                if !item.tagsArray.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(item.tagsArray, id: \.self) { tag in
                            TagPill(label: tag)
                        }
                    }
                }
            }
            .padding(.horizontal, BubbleUpTheme.paddingHorizontal)
            .padding(.top, 16)
            .padding(.bottom, 60)
        }
        .background(Color.bubbleUpBackground(for: colorScheme))
        .navigationBarBackButtonHidden(false)
        .onAppear {
            loadPlayer()
        }
        .onDisappear {
            player?.pause()
        }
    }

    private func loadPlayer() {
        guard let localFilePath = item.localFilePath else { return }
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.shillwil.bubble-up") else { return }
        let fileURL = containerURL.appendingPathComponent("SharedFiles").appendingPathComponent(localFilePath)

        if FileManager.default.fileExists(atPath: fileURL.path) {
            player = AVPlayer(url: fileURL)
        }
    }
}

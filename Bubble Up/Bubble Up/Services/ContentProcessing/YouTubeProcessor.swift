import Foundation

/// Stub processor for YouTube videos.
/// Future: Extract video metadata, thumbnail, and transcript.
struct YouTubeProcessor: ContentProcessor {

    func canProcess(url: URL, contentType: ContentType) -> Bool {
        contentType == .youtube
    }

    func extractContent(from url: URL) async throws -> ExtractedContent {
        // Extract video ID from URL
        let videoID = extractVideoID(from: url)

        // For now, return basic metadata from the URL
        // Future: Use YouTube Data API or oEmbed for full metadata
        return ExtractedContent(
            title: nil, // Will be populated by LinkPreviewService
            authorName: nil,
            textContent: nil,
            thumbnailURL: videoID.map { URL(string: "https://img.youtube.com/vi/\($0)/maxresdefault.jpg") } ?? nil,
            estimatedReadTime: nil,
            contentMimeType: "video/youtube"
        )
    }

    private func extractVideoID(from url: URL) -> String? {
        let host = url.host?.lowercased() ?? ""

        if host.contains("youtu.be") {
            return url.pathComponents.last
        }

        if host.contains("youtube.com") {
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            return components?.queryItems?.first(where: { $0.name == "v" })?.value
        }

        return nil
    }
}

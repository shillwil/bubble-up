import Foundation

/// Fallback processor for unknown content types.
/// Extracts basic URL metadata only.
struct DefaultProcessor: ContentProcessor {

    func canProcess(url: URL, contentType: ContentType) -> Bool {
        true // Catches everything not handled by specific processors
    }

    func extractContent(from url: URL) async throws -> ExtractedContent {
        ExtractedContent(
            title: url.lastPathComponent,
            authorName: nil,
            textContent: nil,
            thumbnailURL: nil,
            estimatedReadTime: nil,
            contentMimeType: ContentType.from(url: url).mimeType
        )
    }
}

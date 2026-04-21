import Foundation

/// Returns the appropriate ContentProcessor for a given URL.
/// Register new processors here when adding support for new content types.
enum ContentProcessorFactory {
    private static let processors: [ContentProcessor] = [
        // Domain-specific processors must be listed before WebArticleProcessor,
        // because WebArticleProcessor matches the broad `.webArticle` content type
        // which is also the fallback for unknown hosts.
        YouTubeProcessor(),
        RedditProcessor(),
        TwitterProcessor(),
        PDFProcessor(),
        ImageProcessor(),
        VideoProcessor(),
        WebArticleProcessor(),
        DefaultProcessor()
    ]

    static func processor(for url: URL) -> ContentProcessor {
        let contentType = ContentType.from(url: url)
        return processors.first { $0.canProcess(url: url, contentType: contentType) }
            ?? DefaultProcessor()
    }
}

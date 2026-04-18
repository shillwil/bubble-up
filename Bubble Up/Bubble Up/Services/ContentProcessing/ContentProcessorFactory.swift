import Foundation

/// Returns the appropriate ContentProcessor for a given URL.
/// Register new processors here when adding support for new content types.
enum ContentProcessorFactory {
    private static let processors: [ContentProcessor] = [
        WebArticleProcessor(),
        YouTubeProcessor(),
        PDFProcessor(),
        DefaultProcessor()
    ]

    static func processor(for url: URL) -> ContentProcessor {
        let contentType = ContentType.from(url: url)
        return processors.first { $0.canProcess(url: url, contentType: contentType) }
            ?? DefaultProcessor()
    }
}

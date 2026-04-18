import Foundation

/// Strategy protocol for extracting content from different source types.
/// Adding a new content type (YouTube, PDF, etc.) requires only implementing this protocol
/// and registering in ContentProcessorFactory.
protocol ContentProcessor: Sendable {
    func canProcess(url: URL, contentType: ContentType) -> Bool
    func extractContent(from url: URL) async throws -> ExtractedContent
}

/// Extracted content from a URL, ready for AI summarization.
struct ExtractedContent: Sendable {
    let title: String?
    let authorName: String?
    let textContent: String?
    let thumbnailURL: URL?
    let estimatedReadTime: Int?
    let contentMimeType: String
}

enum ContentProcessorError: Error, LocalizedError {
    case unsupportedContentType
    case extractionFailed(String)
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .unsupportedContentType: return "Content type not supported"
        case .extractionFailed(let reason): return "Content extraction failed: \(reason)"
        case .networkError(let error): return "Network error: \(error.localizedDescription)"
        }
    }
}

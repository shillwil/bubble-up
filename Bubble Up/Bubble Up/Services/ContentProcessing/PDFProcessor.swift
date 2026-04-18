import Foundation

/// Stub processor for PDF documents.
/// Future: Extract text content using PDFKit.
struct PDFProcessor: ContentProcessor {

    func canProcess(url: URL, contentType: ContentType) -> Bool {
        contentType == .pdf
    }

    func extractContent(from url: URL) async throws -> ExtractedContent {
        // Future: Download PDF and extract text using PDFKit
        // let (data, _) = try await URLSession.shared.data(from: url)
        // let pdfDocument = PDFDocument(data: data)
        // Extract text from all pages

        return ExtractedContent(
            title: url.lastPathComponent,
            authorName: nil,
            textContent: nil,
            thumbnailURL: nil,
            estimatedReadTime: nil,
            contentMimeType: "application/pdf"
        )
    }
}

import Foundation
import PDFKit

/// Extracts text content from PDF documents using PDFKit.
struct PDFProcessor: ContentProcessor {

    func canProcess(url: URL, contentType: ContentType) -> Bool {
        contentType == .pdf
    }

    func extractContent(from url: URL) async throws -> ExtractedContent {
        // Load the PDF data from local file or remote URL
        let data: Data
        if url.isFileURL {
            data = try Data(contentsOf: url)
        } else {
            let (downloaded, _) = try await URLSession.shared.data(from: url)
            data = downloaded
        }

        guard let pdfDocument = PDFDocument(data: data) else {
            throw ContentProcessorError.extractionFailed("Invalid PDF document")
        }

        // Extract text from pages (cap at 50 pages to avoid excessive processing)
        var fullText = ""
        let pageCount = min(pdfDocument.pageCount, 50)
        for i in 0..<pageCount {
            if let page = pdfDocument.page(at: i), let pageText = page.string {
                fullText += pageText + "\n"
            }
        }

        // Extract metadata
        let attributes = pdfDocument.documentAttributes
        let title = attributes?[PDFDocumentAttribute.titleAttribute] as? String
        let author = attributes?[PDFDocumentAttribute.authorAttribute] as? String

        let wordCount = fullText.split(separator: " ").count

        return ExtractedContent(
            title: title ?? cleanFilename(from: url),
            authorName: author,
            textContent: fullText.isEmpty ? nil : fullText,
            thumbnailURL: nil,
            estimatedReadTime: wordCount > 0 ? max(1, wordCount / 200) : nil,
            contentMimeType: "application/pdf"
        )
    }

    /// Generate a thumbnail image from the first page of a PDF.
    func generateThumbnail(from data: Data) -> Data? {
        guard let pdfDocument = PDFDocument(data: data),
              let firstPage = pdfDocument.page(at: 0) else { return nil }

        let thumbnail = firstPage.thumbnail(of: CGSize(width: 600, height: 800), for: .mediaBox)
        return thumbnail.pngData()
    }

    /// Cleans a filename from a URL for use as a fallback title.
    private func cleanFilename(from url: URL) -> String {
        let filename = url.lastPathComponent
        return filename
            .replacingOccurrences(of: ".pdf", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
    }
}

import Foundation
import UIKit
import Vision

/// Processes image files — extracts OCR text using Vision framework.
struct ImageProcessor: ContentProcessor {

    func canProcess(url: URL, contentType: ContentType) -> Bool {
        contentType == .image
    }

    func extractContent(from url: URL) async throws -> ExtractedContent {
        let data: Data
        if url.isFileURL {
            data = try Data(contentsOf: url)
        } else {
            let (downloaded, _) = try await URLSession.shared.data(from: url)
            data = downloaded
        }

        // Run OCR to extract any text from the image
        let ocrText = await performOCR(on: data)

        return ExtractedContent(
            title: url.lastPathComponent,
            authorName: nil,
            textContent: ocrText,
            thumbnailURL: nil,
            estimatedReadTime: nil,
            contentMimeType: "image/jpeg"
        )
    }

    /// Performs OCR on image data using the Vision framework.
    private func performOCR(on imageData: Data) async -> String? {
        guard let cgImage = UIImage(data: imageData)?.cgImage else { return nil }

        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: nil)
                    return
                }
                let text = observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
                continuation.resume(returning: text.isEmpty ? nil : text)
            }
            request.recognitionLevel = .accurate

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: nil)
            }
        }
    }
}

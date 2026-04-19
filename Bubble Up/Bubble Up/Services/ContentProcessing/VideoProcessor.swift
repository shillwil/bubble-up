import Foundation
import AVFoundation
import UIKit

/// Processes video files — extracts thumbnail and duration metadata.
struct VideoProcessor: ContentProcessor {

    func canProcess(url: URL, contentType: ContentType) -> Bool {
        contentType == .video
    }

    func extractContent(from url: URL) async throws -> ExtractedContent {
        let asset = AVURLAsset(url: url)

        // Get duration
        let duration = try await asset.load(.duration)
        let durationSeconds = Int(CMTimeGetSeconds(duration))
        let durationMinutes = max(1, durationSeconds / 60)

        return ExtractedContent(
            title: url.lastPathComponent,
            authorName: nil,
            textContent: nil,
            thumbnailURL: nil,
            estimatedReadTime: durationMinutes,
            contentMimeType: "video/mp4"
        )
    }

    /// Generates a thumbnail from the first frame of a video.
    func generateThumbnail(from url: URL) async -> Data? {
        let asset = AVURLAsset(url: url)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.maximumSize = CGSize(width: 600, height: 600)

        do {
            let (cgImage, _) = try await imageGenerator.image(at: .zero)
            return UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.8)
        } catch {
            print("Video thumbnail generation failed: \(error)")
            return nil
        }
    }
}

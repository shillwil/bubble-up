import Foundation
import LinkPresentation

/// Fetches link metadata (title, thumbnail, icon) using Apple's LinkPresentation framework.
@MainActor
final class LinkPreviewService {

    /// Fetches metadata for a URL and updates the library item.
    func fetchMetadata(for url: URL, updating item: LibraryItem) async {
        let provider = LPMetadataProvider()
        provider.timeout = 10

        do {
            let metadata = try await provider.startFetchingMetadata(for: url)

            if let title = metadata.title, item.title == LibraryItem.titlePlaceholder || item.title?.isEmpty == true {
                item.title = title
            }

            // Fetch thumbnail image data
            if let imageProvider = metadata.imageProvider {
                let data = try await loadImageData(from: imageProvider)
                item.thumbnailData = data
            }
        } catch {
            // Link preview is best-effort; don't fail the save
            print("Link preview fetch failed: \(error)")
        }
    }

    private func loadImageData(from provider: NSItemProvider) async throws -> Data? {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: "public.image") { data, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: data)
                }
            }
        }
    }
}

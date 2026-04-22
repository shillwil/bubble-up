import UIKit
import SwiftUI
import UniformTypeIdentifiers
import PDFKit
import LinkPresentation
import ImageIO
import AVFoundation

class ShareViewController: UIViewController {

    private var sharedURL = ""
    private var sharedTitle = ""

    override func viewDidLoad() {
        super.viewDidLoad()

        // Use a wrapper to hold mutable state that SwiftUI can bind to
        let stateHolder = ShareStateHolder()

        let hostingView = UIHostingController(rootView: ShareExtensionContentView(
            stateHolder: stateHolder,
            onSave: { [weak self] url, title, tags, localFileName, contentMimeType in
                self?.saveItem(url: url, title: title, tags: tags, localFileName: localFileName, contentMimeType: contentMimeType)
                self?.close()
            },
            onCancel: { [weak self] in
                self?.close()
            }
        ))

        addChild(hostingView)
        view.addSubview(hostingView.view)
        hostingView.view.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            hostingView.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingView.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingView.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingView.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        hostingView.didMove(toParent: self)

        // Extract the shared content — updates stateHolder, which SwiftUI observes
        extractContent(into: stateHolder)
    }

    // MARK: - Content Extraction

    private func extractContent(into stateHolder: ShareStateHolder) {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else { return }

        for item in items {
            guard let attachments = item.attachments else { continue }
            for provider in attachments {
                // 1. Check for PDFs first (PDFs also conform to UTType.url, so must check before URL)
                if provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) {
                    self.handleFileAttachment(provider: provider, utType: UTType.pdf, contentType: "pdf", mimeType: "application/pdf", ext: "pdf", stateHolder: stateHolder)
                    return
                }

                // 2. Check for images
                if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                    self.handleFileAttachment(provider: provider, utType: UTType.image, contentType: "image", mimeType: "image/jpeg", ext: "jpg", stateHolder: stateHolder)
                    return
                }

                // 3. Check for videos
                if provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
                    self.handleFileAttachment(provider: provider, utType: UTType.movie, contentType: "video", mimeType: "video/mp4", ext: "mp4", stateHolder: stateHolder)
                    return
                }

                // 4. Check for URLs
                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    provider.loadItem(forTypeIdentifier: UTType.url.identifier) { [weak self] item, _ in
                        if let url = item as? URL {
                            DispatchQueue.main.async {
                                stateHolder.url = url.absoluteString
                                stateHolder.contentType = "link"
                                stateHolder.previewState = .loading
                                self?.fetchLinkPreview(for: url, stateHolder: stateHolder)
                            }
                        }
                    }
                    return
                }

                // 5. Check for plain text (fallback)
                if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) { [weak self] item, _ in
                        if let text = item as? String, let url = URL(string: text), url.scheme != nil {
                            DispatchQueue.main.async {
                                stateHolder.url = text
                                stateHolder.contentType = "link"
                                stateHolder.previewState = .loading
                                self?.fetchLinkPreview(for: url, stateHolder: stateHolder)
                            }
                        }
                    }
                    return
                }
            }
        }
    }

    private func handleFileAttachment(provider: NSItemProvider, utType: UTType, contentType: String, mimeType: String, ext: String, stateHolder: ShareStateHolder) {
        DispatchQueue.main.async {
            stateHolder.previewState = .loading
        }

        provider.loadFileRepresentation(forTypeIdentifier: utType.identifier) { [weak self] url, error in
            guard let sourceURL = url else {
                DispatchQueue.main.async { stateHolder.previewState = .failed }
                return
            }

            // Copy file to App Group shared container
            let fileName = UUID().uuidString + "." + ext
            guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.shillwil.bubble-up") else {
                DispatchQueue.main.async { stateHolder.previewState = .failed }
                return
            }

            let sharedDir = containerURL.appendingPathComponent("SharedFiles")
            try? FileManager.default.createDirectory(at: sharedDir, withIntermediateDirectories: true)

            let destURL = sharedDir.appendingPathComponent(fileName)
            try? FileManager.default.copyItem(at: sourceURL, to: destURL)

            // Generate preview thumbnail from the copied file
            let previewImage = self?.generatePreview(for: contentType, fileURL: destURL)

            DispatchQueue.main.async {
                stateHolder.contentType = contentType
                stateHolder.localFileName = fileName
                stateHolder.title = sourceURL.lastPathComponent
                if let image = previewImage {
                    stateHolder.previewState = .loaded(image)
                } else {
                    stateHolder.previewState = .failed
                }
            }
        }
    }

    // MARK: - Preview Generation

    private func generatePreview(for contentType: String, fileURL: URL) -> UIImage? {
        switch contentType {
        case "pdf":
            return generatePDFPreview(from: fileURL)
        case "image":
            return downsampledImage(from: fileURL, maxPixelSize: 800)
        case "video":
            return generateVideoPreview(from: fileURL)
        default:
            return nil
        }
    }

    private func generatePDFPreview(from url: URL) -> UIImage? {
        guard let document = PDFDocument(url: url),
              let firstPage = document.page(at: 0) else { return nil }
        return firstPage.thumbnail(of: CGSize(width: 400, height: 600), for: .mediaBox)
    }

    private func downsampledImage(from url: URL, maxPixelSize: CGFloat) -> UIImage? {
        let sourceOptions: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions as CFDictionary) else { return nil }

        let downsampleOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, downsampleOptions as CFDictionary) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    private func generateVideoPreview(from url: URL) -> UIImage? {
        let asset = AVURLAsset(url: url)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.maximumSize = CGSize(width: 600, height: 600)

        do {
            let cgImage = try imageGenerator.copyCGImage(at: .zero, actualTime: nil)
            return UIImage(cgImage: cgImage)
        } catch {
            return nil
        }
    }

    private func fetchLinkPreview(for url: URL, stateHolder: ShareStateHolder) {
        Task { @MainActor in
            let provider = LPMetadataProvider()
            provider.timeout = 8

            do {
                let metadata = try await provider.startFetchingMetadata(for: url)

                // LPMetadataProvider returns useless SEO titles for X/Twitter
                // ("author (@handle) 10K likes · 1K replies") and similar for
                // Reddit. Skip title auto-fill for those so the user sees a
                // clean placeholder and AI can generate a real title after save.
                let host = url.host?.lowercased() ?? ""
                let isSocialHost =
                    host == "x.com" || host.hasSuffix(".x.com") ||
                    host == "twitter.com" || host.hasSuffix(".twitter.com") ||
                    host == "reddit.com" || host.hasSuffix(".reddit.com") ||
                    host == "redd.it" || host.hasSuffix(".redd.it")

                if let title = metadata.title, stateHolder.title.isEmpty, !isSocialHost {
                    stateHolder.title = title
                }

                if let imageProvider = metadata.imageProvider {
                    let data = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data?, Error>) in
                        imageProvider.loadDataRepresentation(forTypeIdentifier: "public.image") { data, error in
                            if let error {
                                continuation.resume(throwing: error)
                            } else {
                                continuation.resume(returning: data)
                            }
                        }
                    }
                    if let data, let image = UIImage(data: data) {
                        stateHolder.previewState = .loaded(image)
                        return
                    }
                }
                stateHolder.previewState = .failed
            } catch {
                stateHolder.previewState = .failed
            }
        }
    }

    // MARK: - Save & Close

    private func saveItem(url: String?, title: String?, tags: [String], localFileName: String? = nil, contentMimeType: String? = nil) {
        let item = SharedPendingItem(url: url, title: title, tags: tags, localFileName: localFileName, contentMimeType: contentMimeType)
        SharedPendingItemStore.save(item)
    }

    private func close() {
        extensionContext?.completeRequest(returningItems: nil)
    }
}

// MARK: - Preview state

enum PreviewState {
    case idle
    case loading
    case loaded(UIImage)
    case failed
}

// MARK: - Observable state holder that bridges UIKit -> SwiftUI

@Observable
class ShareStateHolder {
    var url: String = ""
    var title: String = ""
    var contentType: String = "link"  // "link", "pdf", "image", "video"
    var localFileName: String? = nil
    var previewState: PreviewState = .idle
}

// MARK: - Wrapper view that converts @Observable to @Binding

struct ShareExtensionContentView: View {
    @Bindable var stateHolder: ShareStateHolder
    var onSave: (String?, String?, [String], String?, String?) -> Void
    var onCancel: () -> Void

    var body: some View {
        ShareExtensionView(
            sharedURL: $stateHolder.url,
            sharedTitle: $stateHolder.title,
            contentType: $stateHolder.contentType,
            localFileName: $stateHolder.localFileName,
            previewState: stateHolder.previewState,
            onSave: onSave,
            onCancel: onCancel
        )
    }
}

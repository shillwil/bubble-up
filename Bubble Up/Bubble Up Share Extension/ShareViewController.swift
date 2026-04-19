import UIKit
import SwiftUI
import UniformTypeIdentifiers

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
                    provider.loadItem(forTypeIdentifier: UTType.url.identifier) { item, _ in
                        if let url = item as? URL {
                            DispatchQueue.main.async {
                                stateHolder.url = url.absoluteString
                                stateHolder.contentType = "link"
                            }
                        }
                    }
                    return
                }

                // 5. Check for plain text (fallback)
                if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) { item, _ in
                        if let text = item as? String, let url = URL(string: text), url.scheme != nil {
                            DispatchQueue.main.async {
                                stateHolder.url = text
                                stateHolder.contentType = "link"
                            }
                        }
                    }
                    return
                }
            }
        }
    }

    private func handleFileAttachment(provider: NSItemProvider, utType: UTType, contentType: String, mimeType: String, ext: String, stateHolder: ShareStateHolder) {
        provider.loadFileRepresentation(forTypeIdentifier: utType.identifier) { [weak self] url, error in
            guard let sourceURL = url else { return }

            // Copy file to App Group shared container
            let fileName = UUID().uuidString + "." + ext
            guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.shillwil.bubble-up") else { return }

            let sharedDir = containerURL.appendingPathComponent("SharedFiles")
            try? FileManager.default.createDirectory(at: sharedDir, withIntermediateDirectories: true)

            let destURL = sharedDir.appendingPathComponent(fileName)
            try? FileManager.default.copyItem(at: sourceURL, to: destURL)

            DispatchQueue.main.async {
                stateHolder.contentType = contentType
                stateHolder.localFileName = fileName
                stateHolder.title = sourceURL.lastPathComponent
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

// MARK: - Observable state holder that bridges UIKit -> SwiftUI

@Observable
class ShareStateHolder {
    var url: String = ""
    var title: String = ""
    var contentType: String = "link"  // "link", "pdf", "image", "video"
    var localFileName: String? = nil
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
            onSave: onSave,
            onCancel: onCancel
        )
    }
}

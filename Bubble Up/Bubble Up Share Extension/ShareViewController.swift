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
            onSave: { [weak self] url, title, tags in
                self?.saveItem(url: url, title: title, tags: tags)
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

        // Extract the shared URL — updates stateHolder, which SwiftUI observes
        extractURL(into: stateHolder)
    }

    // MARK: - URL Extraction

    private func extractURL(into stateHolder: ShareStateHolder) {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else { return }

        for item in items {
            guard let attachments = item.attachments else { continue }
            for provider in attachments {
                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    provider.loadItem(forTypeIdentifier: UTType.url.identifier) { item, _ in
                        if let url = item as? URL {
                            DispatchQueue.main.async {
                                stateHolder.url = url.absoluteString
                            }
                        }
                    }
                    return
                }
                if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) { item, _ in
                        if let text = item as? String, let url = URL(string: text), url.scheme != nil {
                            DispatchQueue.main.async {
                                stateHolder.url = text
                            }
                        }
                    }
                    return
                }
            }
        }
    }

    // MARK: - Save & Close

    private func saveItem(url: String, title: String?, tags: [String]) {
        let item = SharedPendingItem(url: url, title: title, tags: tags)
        SharedPendingItemStore.save(item)
    }

    private func close() {
        extensionContext?.completeRequest(returningItems: nil)
    }
}

// MARK: - Observable state holder that bridges UIKit → SwiftUI

@Observable
class ShareStateHolder {
    var url: String = ""
    var title: String = ""
}

// MARK: - Wrapper view that converts @Observable to @Binding

struct ShareExtensionContentView: View {
    @Bindable var stateHolder: ShareStateHolder
    var onSave: (String, String?, [String]) -> Void
    var onCancel: () -> Void

    var body: some View {
        ShareExtensionView(
            sharedURL: $stateHolder.url,
            sharedTitle: $stateHolder.title,
            onSave: onSave,
            onCancel: onCancel
        )
    }
}

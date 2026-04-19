import SwiftUI
import PDFKit

/// UIViewRepresentable wrapping PDFKit's PDFView for interactive PDF viewing.
struct PDFKitView: UIViewRepresentable {
    let url: URL
    @Binding var currentPage: Int
    @Binding var totalPages: Int

    func makeCoordinator() -> Coordinator {
        Coordinator(currentPage: $currentPage, totalPages: $totalPages)
    }

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.pageShadowsEnabled = true
        pdfView.maxScaleFactor = 4.0

        context.coordinator.pdfView = pdfView

        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.pageChanged),
            name: .PDFViewPageChanged,
            object: pdfView
        )

        loadDocument(into: pdfView, coordinator: context.coordinator)

        return pdfView
    }

    func updateUIView(_ pdfView: PDFView, context: Context) {}

    private func loadDocument(into pdfView: PDFView, coordinator: Coordinator) {
        if url.isFileURL {
            if let document = PDFDocument(url: url) {
                pdfView.document = document
                coordinator.updatePageInfo()
                // Defer scale setup until after layout so scaleFactorForSizeToFit is accurate
                DispatchQueue.main.async {
                    pdfView.scaleFactor = pdfView.scaleFactorForSizeToFit
                    pdfView.minScaleFactor = pdfView.scaleFactorForSizeToFit
                }
            }
        } else {
            Task {
                do {
                    let (data, _) = try await URLSession.shared.data(from: url)
                    await MainActor.run {
                        if let document = PDFDocument(data: data) {
                            pdfView.document = document
                            coordinator.updatePageInfo()
                            DispatchQueue.main.async {
                                pdfView.scaleFactor = pdfView.scaleFactorForSizeToFit
                                pdfView.minScaleFactor = pdfView.scaleFactorForSizeToFit
                            }
                        }
                    }
                } catch {}
            }
        }
    }

    class Coordinator: NSObject {
        var currentPage: Binding<Int>
        var totalPages: Binding<Int>
        weak var pdfView: PDFView?

        init(currentPage: Binding<Int>, totalPages: Binding<Int>) {
            self.currentPage = currentPage
            self.totalPages = totalPages
        }

        func updatePageInfo() {
            guard let pdfView, let document = pdfView.document else { return }
            totalPages.wrappedValue = document.pageCount
            if let current = pdfView.currentPage {
                currentPage.wrappedValue = document.index(for: current)
            }
        }

        @objc func pageChanged() {
            updatePageInfo()
        }
    }
}

/// UIViewRepresentable wrapping PDFThumbnailView for page navigation.
struct PDFThumbnailStrip: UIViewRepresentable {
    let pdfView: PDFView

    func makeUIView(context: Context) -> PDFThumbnailView {
        let thumbnailView = PDFThumbnailView()
        thumbnailView.pdfView = pdfView
        thumbnailView.thumbnailSize = CGSize(width: 40, height: 56)
        thumbnailView.backgroundColor = .clear
        return thumbnailView
    }

    func updateUIView(_ uiView: PDFThumbnailView, context: Context) {}
}

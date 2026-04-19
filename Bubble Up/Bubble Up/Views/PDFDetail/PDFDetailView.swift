import SwiftUI
import PDFKit

/// Full PDF reader view with reading progress, rich text extraction, and interactive PDF viewer.
struct PDFDetailView: View {
    @ObservedObject var item: LibraryItem
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    @State private var readingProgress: Double = 0
    @State private var showPDFViewer = false
    @State private var attributedPages: [AttributedString] = []
    @State private var pdfFileURL: URL?
    @State private var isLoadingText = false
    @State private var pdfCurrentPage: Int = 0
    @State private var pdfTotalPages: Int = 0

    var body: some View {
        ZStack(alignment: .top) {
            ReadingProgressBar(progress: readingProgress)
                .zIndex(1)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    pdfHeader
                    heroImage
                    pdfBody
                }
                .padding(.top, 16)
            }
            .onScrollGeometryChange(for: Double.self) { geo in
                let contentHeight = geo.contentSize.height - geo.containerSize.height
                return contentHeight > 0 ? geo.contentOffset.y / contentHeight : 0
            } action: { _, newValue in
                readingProgress = min(max(newValue, 0), 1)
            }
        }
        .background(Color.bubbleUpBackground(for: colorScheme))
        .navigationBarBackButtonHidden(false)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    shareItem()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .foregroundColor(Color.bubbleUpText(for: colorScheme))
                }
            }
        }
        .task {
            pdfFileURL = resolvePDFURL()
            await loadAttributedText()
        }
        .sheet(isPresented: $showPDFViewer) {
            pdfViewerSheet
        }
    }

    // MARK: - Header

    private var pdfHeader: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(item.title ?? "Untitled")
                .font(.display(32, weight: .bold))
                .foregroundColor(Color.bubbleUpText(for: colorScheme))
                .tracking(-0.3)

            MetaLine(
                author: item.authorName,
                source: item.sourceDisplayName,
                readTime: item.estimatedReadTime > 0 ? Int(item.estimatedReadTime) : nil
            )

            if !item.tagsArray.isEmpty {
                HStack(spacing: 6) {
                    ForEach(item.tagsArray, id: \.self) { tag in
                        TagPill(label: tag)
                    }
                }
            }
        }
        .padding(.horizontal, BubbleUpTheme.paddingHorizontal)
        .padding(.bottom, 24)
    }

    // MARK: - Hero Image

    @ViewBuilder
    private var heroImage: some View {
        if let thumbnailData = item.thumbnailData,
           let uiImage = UIImage(data: thumbnailData) {
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxHeight: 300)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: BubbleUpTheme.cornerRadiusSm))
                .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
                .padding(.horizontal, BubbleUpTheme.paddingHorizontal)
                .padding(.bottom, 24)
                .onTapGesture { showPDFViewer = true }
        }
    }

    // MARK: - Body

    private var pdfBody: some View {
        VStack(alignment: .leading, spacing: 24) {
            // AI Summary
            if let summary = item.summary, !summary.isEmpty {
                DropCapText(text: summary)

                if !item.summaryBulletsArray.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Key Takeaways")
                            .font(.display(24, weight: .bold))
                            .foregroundColor(Color.bubbleUpText(for: colorScheme))

                        RedBulletList(bullets: item.summaryBulletsArray)
                    }
                    .padding(.top, 16)
                }
            } else if item.summaryStatusEnum == .pending || item.summaryStatusEnum == .generating {
                LoadingStateView("Generating summary")
                    .frame(height: 200)
            }

            // Extracted rich text
            extractedTextSection

            // View original PDF button
            if pdfFileURL != nil || item.url != nil {
                Button {
                    showPDFViewer = true
                } label: {
                    Text("VIEW ORIGINAL PDF")
                        .font(.buttonText(14))
                        .tracking(1.5)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .overlay {
                            RoundedRectangle(cornerRadius: BubbleUpTheme.cornerRadiusSm)
                                .stroke(BubbleUpTheme.primary, lineWidth: 1)
                        }
                        .foregroundColor(BubbleUpTheme.primary)
                }
                .padding(.top, 16)
            }

            // Comments section
            commentsSection
        }
        .padding(.horizontal, BubbleUpTheme.paddingHorizontal)
        .padding(.bottom, 60)
    }

    // MARK: - Extracted Text

    @ViewBuilder
    private var extractedTextSection: some View {
        if isLoadingText {
            VStack(spacing: 12) {
                ProgressView()
                    .tint(BubbleUpTheme.textMuted)
                Text("EXTRACTING TEXT")
                    .font(.metaLabel(12))
                    .tracking(2)
                    .foregroundColor(Color.bubbleUpTextMuted(for: colorScheme))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
        } else if !attributedPages.isEmpty {
            Divider().padding(.vertical, 8)

            Text("Full Text")
                .font(.display(24, weight: .bold))
                .foregroundColor(Color.bubbleUpText(for: colorScheme))

            ForEach(Array(attributedPages.enumerated()), id: \.offset) { index, attrText in
                VStack(alignment: .leading, spacing: 8) {
                    if attributedPages.count > 1 {
                        Text("PAGE \(index + 1)")
                            .font(.metaLabel(11))
                            .tracking(2)
                            .foregroundColor(Color.bubbleUpTextMuted(for: colorScheme))
                    }

                    Text(attrText)
                        .lineSpacing(6)
                }
                .padding(.vertical, 4)
            }
        } else if item.rawContent != nil && !item.rawContent!.isEmpty {
            // Fallback to plain text
            Divider().padding(.vertical, 8)

            Text("Full Text")
                .font(.display(24, weight: .bold))
                .foregroundColor(Color.bubbleUpText(for: colorScheme))

            Text(item.rawContent!)
                .font(.bodyText(17))
                .foregroundColor(Color.bubbleUpText(for: colorScheme))
                .lineSpacing(6)
        }
    }

    // MARK: - Comments

    private var commentsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !item.orderedComments.isEmpty {
                Divider()
                    .padding(.vertical, 8)

                Text("Notes")
                    .font(.display(20, weight: .bold))
                    .foregroundColor(Color.bubbleUpText(for: colorScheme))

                ForEach(item.orderedComments) { comment in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(comment.text ?? "")
                            .font(.bodyText(15))
                            .foregroundColor(Color.bubbleUpText(for: colorScheme))

                        if let date = comment.createdAt {
                            Text(date, style: .relative)
                                .font(.metaLabel(12))
                                .foregroundColor(Color.bubbleUpTextMuted(for: colorScheme))
                        }
                    }
                }
            }
        }
    }

    // MARK: - PDF Viewer Sheet

    private var pdfViewerSheet: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ReadingProgressBar(
                    progress: pdfTotalPages > 0
                        ? Double(pdfCurrentPage) / Double(max(pdfTotalPages - 1, 1))
                        : 0
                )

                if let url = pdfFileURL {
                    PDFKitView(
                        url: url,
                        currentPage: $pdfCurrentPage,
                        totalPages: $pdfTotalPages
                    )
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "doc.questionmark")
                            .font(.system(size: 48, weight: .ultraLight))
                            .foregroundColor(Color.bubbleUpBorder(for: colorScheme))
                        Text("Unable to load PDF")
                            .font(.bodyText(15))
                            .foregroundColor(Color.bubbleUpTextMuted(for: colorScheme))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(Color.bubbleUpBackground(for: colorScheme))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    if pdfTotalPages > 0 {
                        Text("Page \(pdfCurrentPage + 1) of \(pdfTotalPages)")
                            .font(.metaLabel(13))
                            .foregroundColor(Color.bubbleUpTextMuted(for: colorScheme))
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showPDFViewer = false }
                        .foregroundColor(BubbleUpTheme.primary)
                }
            }
        }
    }

    // MARK: - PDF URL Resolution

    private func resolvePDFURL() -> URL? {
        if let localFilePath = item.localFilePath,
           let containerURL = FileManager.default.containerURL(
               forSecurityApplicationGroupIdentifier: Config.appGroupIdentifier
           ) {
            let fileURL = containerURL
                .appendingPathComponent("SharedFiles")
                .appendingPathComponent(localFilePath)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                return fileURL
            }
        }
        if let urlString = item.url, let url = URL(string: urlString) {
            return url
        }
        return nil
    }

    // MARK: - Rich Text Extraction

    private func loadAttributedText() async {
        guard let url = pdfFileURL else { return }

        await MainActor.run { isLoadingText = true }

        let data: Data
        do {
            if url.isFileURL {
                data = try Data(contentsOf: url)
            } else {
                let (downloaded, _) = try await URLSession.shared.data(from: url)
                data = downloaded
            }
        } catch {
            await MainActor.run { isLoadingText = false }
            return
        }

        guard let document = PDFDocument(data: data) else {
            await MainActor.run { isLoadingText = false }
            return
        }

        var pages: [AttributedString] = []
        let pageCount = min(document.pageCount, 50)

        for i in 0..<pageCount {
            guard let page = document.page(at: i) else { continue }

            if let plainText = page.string, !plainText.isEmpty {
                let styled = stylePageText(plainText)
                pages.append(styled)
            }
        }

        // Filter out empty pages
        let nonEmpty = pages.filter { !$0.characters.isEmpty }

        await MainActor.run {
            attributedPages = nonEmpty
            isLoadingText = false
        }
    }

    // MARK: - Text Styling

    /// Styles plain text from PDFPage.string with app typography and paragraph spacing.
    private func stylePageText(_ text: String) -> AttributedString {
        let bodyFont = UIFont.systemFont(ofSize: 17)
        let paraStyle: NSParagraphStyle = {
            let s = NSMutableParagraphStyle()
            s.paragraphSpacing = 14
            s.lineSpacing = 6
            return s
        }()

        let mutable = NSMutableAttributedString(
            string: text,
            attributes: [.font: bodyFont, .paragraphStyle: paraStyle]
        )

        // Join line-wrapped newlines into flowing paragraphs
        joinLineWraps(in: mutable)

        do {
            var result = try AttributedString(mutable, including: \.uiKit)
            result.foregroundColor = nil
            return result
        } catch {
            var fallback = AttributedString(text)
            fallback.font = .bodyText(17)
            return fallback
        }
    }

    /// Joins single-\n line wraps into spaces; preserves \n\n paragraph breaks.
    private func joinLineWraps(in mutable: NSMutableAttributedString) {
        let characters = Array(mutable.string)
        guard !characters.isEmpty else { return }

        let sentenceEnders: Set<Character> = [".", "!", "?", ":", "\"", "\u{201D}"]
        var replacements: [(location: Int, length: Int, replacement: String)] = []

        var i = 0
        while i < characters.count {
            guard characters[i] == "\n" else { i += 1; continue }

            // Double newline — real paragraph break, skip
            if i + 1 < characters.count && characters[i + 1] == "\n" {
                i += 2
                continue
            }

            // Single newline — paragraph break or line wrap?
            let charBefore: Character? = i > 0 ? characters[i - 1] : nil
            let endsSentence = charBefore.map { sentenceEnders.contains($0) } ?? false

            var j = i + 1
            while j < characters.count && characters[j] == " " { j += 1 }
            let nextIsUpper = j < characters.count && characters[j].isUppercase

            if endsSentence && nextIsUpper {
                replacements.append((location: i, length: 1, replacement: "\n\n"))
            } else {
                replacements.append((location: i, length: 1, replacement: " "))
            }

            i += 1
        }

        for rep in replacements.reversed() {
            mutable.replaceCharacters(in: NSRange(location: rep.location, length: rep.length), with: rep.replacement)
        }
    }

    // MARK: - Actions

    private func shareItem() {
        var shareItems: [Any] = []
        if let urlString = item.url, let url = URL(string: urlString) {
            shareItems.append(url)
        } else if let pdfFileURL {
            shareItems.append(pdfFileURL)
        }
        guard !shareItems.isEmpty else { return }

        let activityVC = UIActivityViewController(activityItems: shareItems, applicationActivities: nil)
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = scene.windows.first?.rootViewController {
            rootVC.present(activityVC, animated: true)
        }
    }
}

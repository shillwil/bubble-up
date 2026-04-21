import Foundation
import CoreData

/// Manages the queue of pending AI summary requests with retry and backoff.
actor RequestScheduler {
    private let persistenceController: PersistenceController
    private let keychainService: KeychainService
    private var isProcessing = false
    var syncEngine: SyncEngine?

    init(persistenceController: PersistenceController, keychainService: KeychainService) {
        self.persistenceController = persistenceController
        self.keychainService = keychainService
    }

    // MARK: - Public API

    func setSyncEngine(_ engine: SyncEngine) {
        self.syncEngine = engine
    }

    /// Resume any pending/interrupted requests on app launch.
    func resumePendingRequests() async {
        let context = persistenceController.newBackgroundContext()

        await context.perform {
            let fetchRequest = PendingRequest.fetchRequest()
            fetchRequest.predicate = NSPredicate(
                format: "status == %@ OR status == %@",
                RequestStatus.inProgress.rawValue,
                RequestStatus.pending.rawValue
            )

            guard let requests = try? context.fetch(fetchRequest) else { return }

            for request in requests where request.statusEnum == .inProgress {
                request.statusEnum = .pending
            }
            try? context.save()
        }

        await processQueue()
    }

    /// Notify the scheduler that a new request was added.
    func notifyNewRequest() async {
        await processQueue()
    }

    /// Process the next batch of pending requests.
    func processQueue() async {
        guard !isProcessing else { return }
        isProcessing = true
        defer { isProcessing = false }

        let context = persistenceController.newBackgroundContext()

        while true {
            let requests: [PendingRequestSnapshot] = await context.perform {
                let fetchRequest = PendingRequest.fetchRequest()
                fetchRequest.predicate = NSPredicate(format: "status == %@", RequestStatus.pending.rawValue)
                fetchRequest.sortDescriptors = [
                    NSSortDescriptor(key: "priority", ascending: true),
                    NSSortDescriptor(key: "createdAt", ascending: true)
                ]
                fetchRequest.fetchLimit = Config.maxConcurrentRequests

                guard let results = try? context.fetch(fetchRequest) else { return [] }

                let now = Date()
                let ready = results.filter { request in
                    if let nextRetry = request.nextRetryAt {
                        return now >= nextRetry
                    }
                    return true
                }

                for request in ready {
                    request.statusEnum = .inProgress
                    request.lastAttemptAt = now
                }
                try? context.save()

                return ready.compactMap { PendingRequestSnapshot(from: $0) }
            }

            guard !requests.isEmpty else { break }

            await withTaskGroup(of: Void.self) { group in
                for snapshot in requests {
                    group.addTask {
                        await self.processRequest(snapshot)
                    }
                }
            }
        }
    }

    // MARK: - Request Processing

    private func processRequest(_ snapshot: PendingRequestSnapshot) async {
        let context = persistenceController.newBackgroundContext()

        do {
            if snapshot.requestType == "link_summary" {
                try await processLinkSummary(snapshot, context: context)
            } else if snapshot.requestType == "book_summary" {
                try await processBookSummary(snapshot, context: context)
            } else if snapshot.requestType == "youtube_summary" {
                try await processYouTubeSummary(snapshot, context: context)
            } else if snapshot.requestType == "pdf_summary" {
                try await processPDFSummary(snapshot, context: context)
            }
        } catch {
            print("❌ RequestScheduler error for \(snapshot.requestType) [item: \(snapshot.libraryItemID)]: \(error)")
            if let urlError = error as? URLError {
                print("  URLError code: \(urlError.code.rawValue)")
            }
            await context.perform {
                self.handleRequestFailure(context: context, requestID: snapshot.id, error: error)
            }
        }
    }

    private func processLinkSummary(_ snapshot: PendingRequestSnapshot, context: NSManagedObjectContext) async throws {
        // 1. Get the URL from the library item
        let itemInfo: (url: String?, title: String?, rawContent: String?) = await context.perform {
            let fetchRequest = LibraryItem.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id == %@", snapshot.libraryItemID as CVarArg)
            fetchRequest.fetchLimit = 1
            guard let item = try? context.fetch(fetchRequest).first else { return (nil, nil, nil) }
            return (item.url, item.title, item.rawContent)
        }

        guard let urlString = itemInfo.url, let url = URL(string: urlString) else {
            throw SummaryProviderError.contentTooShort
        }

        // 2. Extract content from the web page if not already cached
        var content = itemInfo.rawContent ?? ""
        var extractedTitle = itemInfo.title
        var didSkipAI = false

        if content.isEmpty {
            let processor = ContentProcessorFactory.processor(for: url)
            let extracted = try await processor.extractContent(from: url)
            content = extracted.textContent ?? ""
            if extractedTitle == LibraryItem.titlePlaceholder || extractedTitle?.isEmpty == true {
                extractedTitle = extracted.title
            }

            // If extraction didn't find a title, leave it as the placeholder so
            // the AI-generated title (or URL fallback) can claim it in
            // writeSummaryResult. Avoid URL-deriving here — a real AI title is
            // better than a hostname.

            // Short-content bypass: memes, one-liners, and image-only tweets/reddit
            // posts shouldn't be summarized — rendering the extracted content verbatim
            // gives a better UX than a one-bullet "summary" or a failure card.
            let wordCount = content.split { $0.isWhitespace }.count
            let shouldSkipAI = wordCount < Self.shortContentWordThreshold

            // Cache the extracted content and metadata back to the item
            await context.perform {
                let fetchRequest = LibraryItem.fetchRequest()
                fetchRequest.predicate = NSPredicate(format: "id == %@", snapshot.libraryItemID as CVarArg)
                fetchRequest.fetchLimit = 1
                if let item = try? context.fetch(fetchRequest).first {
                    item.rawContent = content
                    if let title = extractedTitle, item.title == LibraryItem.titlePlaceholder || item.title?.isEmpty == true {
                        item.title = title
                    }
                    if let author = extracted.authorName, item.authorName?.isEmpty != false {
                        item.authorName = author
                    }
                    if let readTime = extracted.estimatedReadTime {
                        item.estimatedReadTime = Int16(readTime)
                    }
                    if let thumbnailURL = extracted.thumbnailURL {
                        item.thumbnailURL = thumbnailURL.absoluteString
                    }
                    item.contentMimeType = extracted.contentMimeType
                    item.summaryStatusEnum = shouldSkipAI ? .skipped : .generating
                    try? context.save()
                }
            }

            didSkipAI = shouldSkipAI
        }

        // 3. If we skipped the AI, mark the request done and kick off thumbnail
        //    download — the reader will render rawContent directly.
        if didSkipAI {
            await context.perform {
                self.markRequestCompleted(context: context, requestID: snapshot.id)
            }
            await syncEngine?.enqueuePush()
            await downloadSavedThumbnail(for: snapshot.libraryItemID, context: context)
            return
        }

        // 4. Generate summary
        let provider = getSummaryProvider(for: snapshot.requestType)
        let result = try await provider.generateLinkSummary(
            content: content,
            title: extractedTitle,
            url: urlString
        )

        // 5. Write result back
        await context.perform {
            self.writeSummaryResult(
                context: context,
                itemID: snapshot.libraryItemID,
                summary: result.summary,
                bullets: result.bullets,
                estimatedReadTime: result.estimatedReadTime,
                aiTitle: result.title
            )
            self.markRequestCompleted(context: context, requestID: snapshot.id)
        }

        await syncEngine?.enqueuePush()

        // 6. Download thumbnail image for offline use
        await downloadSavedThumbnail(for: snapshot.libraryItemID, context: context)
    }

    /// Content shorter than this (in whitespace-delimited tokens) skips the AI
    /// call and is rendered verbatim. 40 ≈ what a reader can parse at a glance.
    private static let shortContentWordThreshold = 40

    private func downloadSavedThumbnail(for itemID: UUID, context: NSManagedObjectContext) async {
        let savedThumbnailURL: String? = await context.perform {
            let fetchRequest = LibraryItem.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id == %@", itemID as CVarArg)
            fetchRequest.fetchLimit = 1
            return try? context.fetch(fetchRequest).first?.thumbnailURL
        }
        if let thumbnailURLString = savedThumbnailURL, let thumbnailURL = URL(string: thumbnailURLString) {
            Task {
                await self.downloadThumbnail(itemID: itemID, from: thumbnailURL)
            }
        }
    }

    private func processBookSummary(_ snapshot: PendingRequestSnapshot, context: NSManagedObjectContext) async throws {
        let itemInfo: (title: String?, author: String?) = await context.perform {
            let fetchRequest = LibraryItem.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id == %@", snapshot.libraryItemID as CVarArg)
            fetchRequest.fetchLimit = 1
            guard let item = try? context.fetch(fetchRequest).first else { return (nil, nil) }
            item.summaryStatusEnum = .generating
            try? context.save()
            return (item.title, item.authorName)
        }

        guard let title = itemInfo.title else {
            throw SummaryProviderError.contentTooShort
        }

        let provider = getSummaryProvider(for: snapshot.requestType)
        let result = try await provider.generateBookSummary(
            title: title,
            author: itemInfo.author,
            length: .full
        )

        await context.perform {
            self.writeBookSummaryResult(
                context: context,
                itemID: snapshot.libraryItemID,
                summary: result.summary,
                elevatorPitch: result.elevatorPitch,
                pages: result.pages.map { ($0.title, $0.content) }
            )
            self.markRequestCompleted(context: context, requestID: snapshot.id)
        }

        await syncEngine?.enqueuePush()

        // Fetch book cover image
        Task {
            await self.fetchAndSaveBookCover(
                itemID: snapshot.libraryItemID,
                title: itemInfo.title ?? "",
                author: itemInfo.author
            )
        }
    }

    private func processYouTubeSummary(_ snapshot: PendingRequestSnapshot, context: NSManagedObjectContext) async throws {
        // 1. Get the URL from the library item
        let itemInfo: (url: String?, title: String?) = await context.perform {
            let fetchRequest = LibraryItem.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id == %@", snapshot.libraryItemID as CVarArg)
            fetchRequest.fetchLimit = 1
            guard let item = try? context.fetch(fetchRequest).first else { return (nil, nil) }
            return (item.url, item.title)
        }

        guard let urlString = itemInfo.url, let url = URL(string: urlString) else {
            throw SummaryProviderError.contentTooShort
        }

        // 2. Extract transcript and metadata
        let processor = YouTubeProcessor()
        let extracted = try await processor.extractContent(from: url)

        let transcript = extracted.textContent ?? ""
        let extractedTitle = extracted.title ?? itemInfo.title

        // Cache metadata back to the item
        await context.perform {
            let fetchRequest = LibraryItem.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id == %@", snapshot.libraryItemID as CVarArg)
            fetchRequest.fetchLimit = 1
            if let item = try? context.fetch(fetchRequest).first {
                if let title = extractedTitle, item.title == LibraryItem.titlePlaceholder || item.title?.isEmpty == true {
                    item.title = title
                }
                if let author = extracted.authorName {
                    item.authorName = author
                }
                if let thumbnailURL = extracted.thumbnailURL {
                    item.thumbnailURL = thumbnailURL.absoluteString
                }
                if let readTime = extracted.estimatedReadTime {
                    item.estimatedReadTime = Int16(readTime)
                }
                if !transcript.isEmpty {
                    item.rawContent = transcript
                }
                item.summaryStatusEnum = .generating
                try? context.save()
            }
        }

        // 3. Generate summary — prefer sending the YouTube URL directly to Gemini
        // (Google/Gemini can watch and analyze YouTube videos natively).
        // Fall back to transcript only if the URL-based approach fails.
        let provider = getSummaryProvider(for: snapshot.requestType)

        let urlContent = "YouTube video URL: \(urlString)\n\nPlease watch/analyze this YouTube video and provide a summary."

        var result: SummaryResult
        do {
            result = try await provider.generateLinkSummary(
                content: urlContent,
                title: extractedTitle,
                url: urlString
            )
        } catch {
            // URL-based analysis failed — fall back to transcript if available
            guard !transcript.isEmpty else { throw error }
            result = try await provider.generateLinkSummary(
                content: transcript,
                title: extractedTitle,
                url: urlString
            )
        }

        // 4. Write result back
        await context.perform {
            self.writeSummaryResult(
                context: context,
                itemID: snapshot.libraryItemID,
                summary: result.summary,
                bullets: result.bullets,
                estimatedReadTime: result.estimatedReadTime,
                aiTitle: result.title
            )
            self.markRequestCompleted(context: context, requestID: snapshot.id)
        }

        await syncEngine?.enqueuePush()

        // 5. Download thumbnail
        if let thumbnailURL = extracted.thumbnailURL {
            Task {
                await self.downloadThumbnail(itemID: snapshot.libraryItemID, from: thumbnailURL)
            }
        }
    }

    private func processPDFSummary(_ snapshot: PendingRequestSnapshot, context: NSManagedObjectContext) async throws {
        // 1. Get the URL or local file path from the library item
        let itemInfo: (url: String?, localFilePath: String?, title: String?, rawContent: String?) = await context.perform {
            let fetchRequest = LibraryItem.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id == %@", snapshot.libraryItemID as CVarArg)
            fetchRequest.fetchLimit = 1
            guard let item = try? context.fetch(fetchRequest).first else { return (nil, nil, nil, nil) }
            return (item.url, item.localFilePath, item.title, item.rawContent)
        }

        // 2. Determine the source URL (remote URL or local file)
        let sourceURL: URL
        if let urlString = itemInfo.url, let url = URL(string: urlString) {
            sourceURL = url
        } else if let localFilePath = itemInfo.localFilePath,
                  let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Config.appGroupIdentifier) {
            sourceURL = containerURL.appendingPathComponent("SharedFiles").appendingPathComponent(localFilePath)
        } else {
            throw SummaryProviderError.contentTooShort
        }

        // 3. Extract content if not already cached
        var content = itemInfo.rawContent ?? ""
        var extractedTitle = itemInfo.title

        if content.isEmpty {
            let processor = PDFProcessor()
            let extracted = try await processor.extractContent(from: sourceURL)
            content = extracted.textContent ?? ""

            if extractedTitle == LibraryItem.titlePlaceholder || extractedTitle?.isEmpty == true {
                extractedTitle = extracted.title
            }

            // Generate thumbnail from PDF first page
            let pdfData: Data
            if sourceURL.isFileURL {
                pdfData = try Data(contentsOf: sourceURL)
            } else {
                let (downloaded, _) = try await URLSession.shared.data(from: sourceURL)
                pdfData = downloaded
            }
            let thumbnailData = processor.generateThumbnail(from: pdfData)

            // Cache extracted content and metadata
            await context.perform {
                let fetchRequest = LibraryItem.fetchRequest()
                fetchRequest.predicate = NSPredicate(format: "id == %@", snapshot.libraryItemID as CVarArg)
                fetchRequest.fetchLimit = 1
                if let item = try? context.fetch(fetchRequest).first {
                    item.rawContent = content
                    if let title = extractedTitle, item.title == LibraryItem.titlePlaceholder || item.title?.isEmpty == true {
                        item.title = title
                    }
                    if let author = extracted.authorName {
                        item.authorName = author
                    }
                    if let readTime = extracted.estimatedReadTime {
                        item.estimatedReadTime = Int16(readTime)
                    }
                    if let thumbData = thumbnailData {
                        item.thumbnailData = thumbData
                    }
                    item.summaryStatusEnum = .generating
                    try? context.save()
                }
            }
        }

        // For scanned/image-only PDFs, provide minimal context instead of failing
        guard !content.isEmpty || extractedTitle != nil else {
            throw SummaryProviderError.contentTooShort
        }
        if content.isEmpty {
            content = "PDF document titled: \(extractedTitle ?? sourceURL.lastPathComponent). The PDF contains scanned images without extractable text. Please provide a brief description based on the title."
        }

        // 4. Generate summary
        let urlString = itemInfo.url ?? sourceURL.absoluteString
        let provider = getSummaryProvider(for: snapshot.requestType)
        let result = try await provider.generateLinkSummary(
            content: content,
            title: extractedTitle,
            url: urlString
        )

        // 5. Write result back
        await context.perform {
            self.writeSummaryResult(
                context: context,
                itemID: snapshot.libraryItemID,
                summary: result.summary,
                bullets: result.bullets,
                estimatedReadTime: result.estimatedReadTime,
                aiTitle: result.title
            )
            self.markRequestCompleted(context: context, requestID: snapshot.id)
        }

        await syncEngine?.enqueuePush()
    }

    // MARK: - Provider Selection

    private func getSummaryProvider(for requestType: String) -> SummaryProvider {
        if let geminiKey = keychainService.get(.geminiAPIKey) {
            return GeminiSummaryProvider(apiKey: geminiKey)
        }
        if let claudeKey = keychainService.get(.claudeAPIKey) {
            return ClaudeSummaryProvider(apiKey: claudeKey)
        }
        if let openAIKey = keychainService.get(.openAIAPIKey) {
            return OpenAISummaryProvider(apiKey: openAIKey)
        }

        // Default: Supabase Edge Functions (F&F)
        return SupabaseSummaryProvider()
    }

    // MARK: - Core Data Helpers (called within context.perform)

    private nonisolated func writeSummaryResult(
        context: NSManagedObjectContext,
        itemID: UUID,
        summary: String,
        bullets: [String],
        estimatedReadTime: Int?,
        aiTitle: String? = nil
    ) {
        let fetchRequest = LibraryItem.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", itemID as CVarArg)
        fetchRequest.fetchLimit = 1
        guard let item = try? context.fetch(fetchRequest).first else { return }

        // If the title is still the placeholder (user didn't provide one and
        // extraction didn't find one), prefer the AI-generated title; fall
        // back to a URL-derived title so items never render as "Loading...".
        if item.title == LibraryItem.titlePlaceholder || item.title?.isEmpty == true {
            let trimmedAI = aiTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let ai = trimmedAI, !ai.isEmpty {
                item.title = ai
            } else if let urlString = item.url {
                item.title = Self.titleFromURL(urlString)
            }
        }

        item.summary = summary
        item.summaryBulletsArray = bullets
        item.summaryStatusEnum = .completed
        if let readTime = estimatedReadTime {
            item.estimatedReadTime = Int16(readTime)
        }
        item.updatedAt = Date()
        if item.syncStatus == SyncStatus.synced.rawValue {
            item.syncStatus = SyncStatus.pendingUpdate.rawValue
        }
        try? context.save()
    }

    private nonisolated func writeBookSummaryResult(
        context: NSManagedObjectContext,
        itemID: UUID,
        summary: String,
        elevatorPitch: String,
        pages: [(title: String, content: String)]
    ) {
        let fetchRequest = LibraryItem.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", itemID as CVarArg)
        fetchRequest.fetchLimit = 1
        guard let item = try? context.fetch(fetchRequest).first else { return }

        item.summary = summary
        item.summaryBulletsArray = [elevatorPitch]
        item.summaryStatusEnum = .completed
        item.updatedAt = Date()
        if item.syncStatus == SyncStatus.synced.rawValue {
            item.syncStatus = SyncStatus.pendingUpdate.rawValue
        }

        for (index, page) in pages.enumerated() {
            let _ = PagedItem(
                context: context,
                pageNumber: Int16(index + 1),
                pageTitle: page.title,
                content: page.content,
                libraryItem: item
            )
        }
        try? context.save()
    }

    private nonisolated func markRequestCompleted(context: NSManagedObjectContext, requestID: UUID) {
        let fetchRequest = PendingRequest.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", requestID as CVarArg)
        fetchRequest.fetchLimit = 1
        guard let request = try? context.fetch(fetchRequest).first else { return }
        context.delete(request)
        try? context.save()
    }

    private nonisolated func handleRequestFailure(context: NSManagedObjectContext, requestID: UUID, error: Error) {
        let fetchRequest = PendingRequest.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", requestID as CVarArg)
        fetchRequest.fetchLimit = 1
        guard let request = try? context.fetch(fetchRequest).first else { return }

        request.retryCount += 1
        request.errorMessage = error.localizedDescription

        if request.isExhausted {
            request.statusEnum = .failed

            let itemFetch = LibraryItem.fetchRequest()
            itemFetch.predicate = NSPredicate(format: "id == %@", (request.libraryItemID ?? UUID()) as CVarArg)
            itemFetch.fetchLimit = 1
            if let item = try? context.fetch(itemFetch).first {
                item.summaryStatusEnum = .failed
            }
        } else {
            request.statusEnum = .pending
            request.nextRetryAt = Date().addingTimeInterval(request.backoffDelay)
        }

        try? context.save()
    }
    // MARK: - Book Cover Fetch

    private func fetchAndSaveBookCover(itemID: UUID, title: String, author: String?) async {
        guard let coverURL = await BookCoverService().fetchCoverURL(title: title, author: author) else { return }

        let context = persistenceController.newBackgroundContext()

        // Save the cover URL first for immediate AsyncImage display
        await context.perform {
            let fetchRequest = LibraryItem.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id == %@", itemID as CVarArg)
            fetchRequest.fetchLimit = 1
            if let item = try? context.fetch(fetchRequest).first {
                item.thumbnailURL = coverURL.absoluteString
                try? context.save()
            }
        }

        // Download binary data for offline use
        await self.downloadThumbnail(itemID: itemID, from: coverURL)
    }

    // MARK: - Thumbnail Download

    private func downloadThumbnail(itemID: UUID, from url: URL) async {
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let context = persistenceController.newBackgroundContext()
            await context.perform {
                let fetchRequest = LibraryItem.fetchRequest()
                fetchRequest.predicate = NSPredicate(format: "id == %@", itemID as CVarArg)
                fetchRequest.fetchLimit = 1
                if let item = try? context.fetch(fetchRequest).first {
                    item.thumbnailData = data
                    try? context.save()
                }
            }
        } catch {
            print("Thumbnail download failed: \(error)")
        }
    }

    // MARK: - Title Fallback

    /// Derives a human-readable title from a URL when content extraction fails.
    static func titleFromURL(_ urlString: String) -> String {
        guard let url = URL(string: urlString) else { return urlString }
        let host = url.host?.replacingOccurrences(of: "www.", with: "") ?? ""
        let lastComponent = url.lastPathComponent

        if !lastComponent.isEmpty && lastComponent != "/" {
            // Clean up path component: "great-article-2024" -> "Great Article 2024"
            let cleaned = lastComponent
                .replacingOccurrences(of: "-", with: " ")
                .replacingOccurrences(of: "_", with: " ")
                .split(separator: " ")
                .map { $0.prefix(1).uppercased() + $0.dropFirst() }
                .joined(separator: " ")
            return "\(host) \u{2014} \(cleaned)"
        }
        return host.isEmpty ? urlString : host
    }
}

// MARK: - Snapshot for safe cross-actor transfer

private struct PendingRequestSnapshot: Sendable {
    let id: UUID
    let libraryItemID: UUID
    let requestType: String
    let priority: String

    init?(from request: PendingRequest) {
        guard let id = request.id, let itemID = request.libraryItemID else { return nil }
        self.id = id
        self.libraryItemID = itemID
        self.requestType = request.requestType ?? "link_summary"
        self.priority = request.priority ?? "background"
    }
}

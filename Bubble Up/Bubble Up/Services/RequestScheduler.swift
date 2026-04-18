import Foundation
import CoreData

/// Manages the queue of pending AI summary requests with retry and backoff.
actor RequestScheduler {
    private let persistenceController: PersistenceController
    private let keychainService: KeychainService
    private var isProcessing = false

    init(persistenceController: PersistenceController, keychainService: KeychainService) {
        self.persistenceController = persistenceController
        self.keychainService = keychainService
    }

    // MARK: - Public API

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

        if content.isEmpty {
            let processor = ContentProcessorFactory.processor(for: url)
            let extracted = try await processor.extractContent(from: url)
            content = extracted.textContent ?? ""
            if extractedTitle == "Loading..." || extractedTitle?.isEmpty == true {
                extractedTitle = extracted.title
            }

            // Cache the extracted content and metadata back to the item
            await context.perform {
                let fetchRequest = LibraryItem.fetchRequest()
                fetchRequest.predicate = NSPredicate(format: "id == %@", snapshot.libraryItemID as CVarArg)
                fetchRequest.fetchLimit = 1
                if let item = try? context.fetch(fetchRequest).first {
                    item.rawContent = content
                    if let title = extractedTitle, item.title == "Loading..." || item.title?.isEmpty == true {
                        item.title = title
                    }
                    if let readTime = extracted.estimatedReadTime {
                        item.estimatedReadTime = Int16(readTime)
                    }
                    item.summaryStatusEnum = .generating
                    try? context.save()
                }
            }
        }

        // 3. Generate summary
        let provider = getSummaryProvider(for: snapshot.requestType)
        let result = try await provider.generateLinkSummary(
            content: content,
            title: extractedTitle,
            url: urlString
        )

        // 4. Write result back
        await context.perform {
            self.writeSummaryResult(
                context: context,
                itemID: snapshot.libraryItemID,
                summary: result.summary,
                bullets: result.bullets,
                estimatedReadTime: result.estimatedReadTime
            )
            self.markRequestCompleted(context: context, requestID: snapshot.id)
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
        estimatedReadTime: Int?
    ) {
        let fetchRequest = LibraryItem.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", itemID as CVarArg)
        fetchRequest.fetchLimit = 1
        guard let item = try? context.fetch(fetchRequest).first else { return }

        item.summary = summary
        item.summaryBulletsArray = bullets
        item.summaryStatusEnum = .completed
        if let readTime = estimatedReadTime {
            item.estimatedReadTime = Int16(readTime)
        }
        item.updatedAt = Date()
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

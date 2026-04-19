import CoreData
import Foundation

/// Single entry point for all LibraryItem data mutations.
/// Views use @FetchRequest for reactive reads; this class handles writes.
@Observable
@MainActor
final class LibraryItemsRepository {
    private let viewContext: NSManagedObjectContext
    private let backgroundContext: NSManagedObjectContext
    var requestScheduler: RequestScheduler?
    var syncEngine: SyncEngine?

    init(viewContext: NSManagedObjectContext, backgroundContext: NSManagedObjectContext) {
        self.viewContext = viewContext
        self.backgroundContext = backgroundContext
    }

    // MARK: - Create

    /// Saves a new link and queues summary prefetch.
    /// Returns `.existing` if a link with the same URL is already in the library.
    @discardableResult
    func saveLink(url: String, title: String? = nil, tags: [String] = [], preGeneratedSummary: String? = nil, preGeneratedBullets: [String]? = nil, preGeneratedReadTime: Int? = nil) -> SaveResult {
        // Check for existing link with the same URL
        if let existing = findExistingLink(url: url) {
            let existingID = existing.id!
            // If the existing item failed, auto-retry it
            if existing.summaryStatusEnum == .failed && !hasActivePendingRequest(for: existingID) {
                existing.summaryStatusEnum = .pending
                let retryType: String
                switch existing.itemTypeEnum {
                case .youtube: retryType = "youtube_summary"
                case .pdf: retryType = "pdf_summary"
                default: retryType = "link_summary"
                }
                let _ = PendingRequest(
                    context: viewContext,
                    libraryItemID: existingID,
                    requestType: retryType,
                    priority: .userInitiated
                )
                saveViewContext()
                if let scheduler = requestScheduler {
                    Task { await scheduler.notifyNewRequest() }
                }
            }
            return .existing(existingID)
        }

        let item = LibraryItem(
            context: viewContext,
            title: title ?? "Loading...",
            itemType: .link,
            url: url,
            tags: tags
        )
        // Detect content type from URL and set correct item type
        if let parsedURL = URL(string: url) {
            let contentType = ContentType.from(url: parsedURL)
            if contentType == .youtube {
                item.itemTypeEnum = .youtube
            } else if contentType == .pdf {
                item.itemTypeEnum = .pdf
            }
        }

        let itemID = item.id!

        // If the share extension pre-generated a summary, use it directly
        if let summary = preGeneratedSummary, let bullets = preGeneratedBullets {
            item.summary = summary
            item.summaryBulletsArray = bullets
            if let readTime = preGeneratedReadTime {
                item.estimatedReadTime = Int16(readTime)
            }
            item.summaryStatusEnum = .completed
            saveViewContext()
            return .created(itemID)
        }

        // Otherwise, create pending request for AI summary
        let requestType: String
        switch item.itemTypeEnum {
        case .youtube: requestType = "youtube_summary"
        case .pdf: requestType = "pdf_summary"
        default: requestType = "link_summary"
        }
        let _ = PendingRequest(
            context: viewContext,
            libraryItemID: itemID,
            requestType: requestType,
            priority: .background
        )

        saveViewContext()
        notifySync()

        // Notify scheduler to process the new request
        if let scheduler = requestScheduler {
            Task { await scheduler.notifyNewRequest() }
        }

        return .created(itemID)
    }

    /// Creates a book summary request.
    /// Returns `.existing` if a book summary with the same title already exists.
    @discardableResult
    func saveBookSummaryRequest(title: String, author: String?, length: SummaryLength, tags: [String] = []) -> SaveResult {
        // Check for existing book summary with the same title
        if let existing = findExistingBookSummary(title: title, author: author) {
            let existingID = existing.id!
            // If the existing item failed, auto-retry it
            if existing.summaryStatusEnum == .failed && !hasActivePendingRequest(for: existingID) {
                existing.summaryStatusEnum = .pending
                let _ = PendingRequest(
                    context: viewContext,
                    libraryItemID: existingID,
                    requestType: "book_summary",
                    priority: .userInitiated
                )
                saveViewContext()
                if let scheduler = requestScheduler {
                    Task { await scheduler.notifyNewRequest() }
                }
            }
            return .existing(existingID)
        }

        let item = LibraryItem(
            context: viewContext,
            title: title,
            itemType: .bookSummary
        )
        item.authorName = author
        item.tagsArray = tags
        item.summaryStatusEnum = .pending

        let itemID = item.id!

        let _ = PendingRequest(
            context: viewContext,
            libraryItemID: itemID,
            requestType: "book_summary",
            priority: .userInitiated
        )

        saveViewContext()
        notifySync()

        if let scheduler = requestScheduler {
            Task { await scheduler.notifyNewRequest() }
        }

        return .created(itemID)
    }

    // MARK: - Update

    func updateTitle(_ item: LibraryItem, title: String) {
        item.title = title
        item.updatedAt = Date()
        markForSync(item)
        saveViewContext()
        notifySync()
    }

    func updateTags(_ item: LibraryItem, tags: [String]) {
        item.tagsArray = tags
        item.updatedAt = Date()
        markForSync(item)
        saveViewContext()
        notifySync()
    }

    func markAsRead(_ item: LibraryItem) {
        item.isRead = true
        item.updatedAt = Date()
        markForSync(item)
        saveViewContext()
        notifySync()
    }

    func addComment(to item: LibraryItem, text: String) {
        let _ = Comment(context: viewContext, text: text, libraryItem: item)
        item.updatedAt = Date()
        markForSync(item)
        saveViewContext()
        notifySync()
    }

    /// Called by RequestScheduler when an AI summary completes.
    func writeSummaryResult(
        itemID: UUID,
        summary: String,
        bullets: [String],
        estimatedReadTime: Int? = nil,
        context: NSManagedObjectContext? = nil
    ) {
        let ctx = context ?? viewContext
        let fetchRequest = LibraryItem.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", itemID as CVarArg)
        fetchRequest.fetchLimit = 1

        guard let item = try? ctx.fetch(fetchRequest).first else { return }

        item.summary = summary
        item.summaryBulletsArray = bullets
        item.summaryStatusEnum = .completed
        if let readTime = estimatedReadTime {
            item.estimatedReadTime = Int16(readTime)
        }
        item.updatedAt = Date()
        markForSync(item)

        try? ctx.save()
        notifySync()
    }

    /// Called by RequestScheduler when a book summary completes.
    func writeBookSummaryResult(
        itemID: UUID,
        summary: String,
        elevatorPitch: String,
        pages: [(title: String, content: String)],
        context: NSManagedObjectContext? = nil
    ) {
        let ctx = context ?? viewContext
        let fetchRequest = LibraryItem.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", itemID as CVarArg)
        fetchRequest.fetchLimit = 1

        guard let item = try? ctx.fetch(fetchRequest).first else { return }

        item.summary = summary
        item.summaryBulletsArray = [elevatorPitch]
        item.summaryStatusEnum = .completed
        item.updatedAt = Date()

        // Create paged items
        for (index, page) in pages.enumerated() {
            let _ = PagedItem(
                context: ctx,
                pageNumber: Int16(index + 1),
                pageTitle: page.title,
                content: page.content,
                libraryItem: item
            )
        }
        markForSync(item)

        try? ctx.save()
        notifySync()
    }

    func markSummaryFailed(itemID: UUID, context: NSManagedObjectContext? = nil) {
        let ctx = context ?? viewContext
        let fetchRequest = LibraryItem.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", itemID as CVarArg)
        fetchRequest.fetchLimit = 1

        guard let item = try? ctx.fetch(fetchRequest).first else { return }
        item.summaryStatusEnum = .failed
        item.updatedAt = Date()
        try? ctx.save()
    }

    // MARK: - Delete

    func deleteItem(_ item: LibraryItem) {
        // Soft-delete: mark for sync, then the sync engine will push deleted_at
        // and hard-delete from Core Data after server confirmation.
        // If sync engine is not available (offline), the item is hidden from views
        // via FetchRequest predicate and cleaned up on next sync.
        item.syncStatusEnum = .pendingDelete
        item.updatedAt = Date()
        saveViewContext()
        notifySync()
    }

    // MARK: - Fetch Helpers

    func fetchItem(by id: UUID) -> LibraryItem? {
        let fetchRequest = LibraryItem.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        fetchRequest.fetchLimit = 1
        return try? viewContext.fetch(fetchRequest).first
    }

    // MARK: - Retry

    /// Centralized retry for failed items. Guards against duplicate in-flight requests.
    func retryRequest(for item: LibraryItem) {
        guard let itemID = item.id else { return }
        guard !hasActivePendingRequest(for: itemID) else { return }

        item.summaryStatusEnum = .pending
        let _ = PendingRequest(
            context: viewContext,
            libraryItemID: itemID,
            requestType: {
                switch item.itemTypeEnum {
                case .bookSummary: return "book_summary"
                case .youtube: return "youtube_summary"
                case .pdf: return "pdf_summary"
                case .image: return "image_process"
                case .video: return "video_process"
                default: return "link_summary"
                }
            }(),
            priority: .userInitiated
        )
        saveViewContext()

        if let scheduler = requestScheduler {
            Task { await scheduler.notifyNewRequest() }
        }
    }

    // MARK: - Duplicate Detection

    /// Finds an existing link with the same normalized URL.
    private func findExistingLink(url: String) -> LibraryItem? {
        let normalized = Self.normalizeURL(url)
        let fetchRequest = LibraryItem.fetchRequest()
        fetchRequest.predicate = NSPredicate(
            format: "itemType == %@ OR itemType == %@ OR itemType == %@",
            ItemType.link.rawValue,
            ItemType.youtube.rawValue,
            ItemType.pdf.rawValue
        )

        guard let items = try? viewContext.fetch(fetchRequest) else { return nil }
        return items.first { Self.normalizeURL($0.url ?? "") == normalized }
    }

    /// Finds an existing book summary with the same title (case-insensitive).
    private func findExistingBookSummary(title: String, author: String?) -> LibraryItem? {
        let fetchRequest = LibraryItem.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "itemType == %@", ItemType.bookSummary.rawValue)

        guard let items = try? viewContext.fetch(fetchRequest) else { return nil }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return items.first { item in
            let existingTitle = (item.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard existingTitle == trimmedTitle else { return false }
            // If author provided, check it matches (but allow match if existing has no author)
            if let author = author, !author.isEmpty, let existingAuthor = item.authorName, !existingAuthor.isEmpty {
                return existingAuthor.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    == author.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            }
            return true
        }
    }

    /// Checks if a non-failed PendingRequest already exists for this item.
    private func hasActivePendingRequest(for libraryItemID: UUID) -> Bool {
        let fetchRequest = PendingRequest.fetchRequest()
        fetchRequest.predicate = NSPredicate(
            format: "libraryItemID == %@ AND status != %@",
            libraryItemID as CVarArg,
            RequestStatus.failed.rawValue
        )
        fetchRequest.fetchLimit = 1
        return ((try? viewContext.fetch(fetchRequest))?.isEmpty == false)
    }

    /// Normalizes a URL for comparison: lowercase host, strip www., remove trailing slash, prefer https.
    static func normalizeURL(_ urlString: String) -> String {
        guard var components = URLComponents(string: urlString) else {
            return urlString.lowercased()
        }
        // Normalize scheme to https
        if components.scheme?.lowercased() == "http" {
            components.scheme = "https"
        }
        // Lowercase host and strip www.
        components.host = components.host?.lowercased().replacingOccurrences(of: "www.", with: "")
        // Remove trailing slash from path
        if components.path.hasSuffix("/") && components.path.count > 1 {
            components.path = String(components.path.dropLast())
        }
        // Remove common tracking query parameters
        if let queryItems = components.queryItems {
            let trackingParams: Set<String> = ["utm_source", "utm_medium", "utm_campaign", "utm_term", "utm_content", "ref", "fbclid", "gclid"]
            let filtered = queryItems.filter { !trackingParams.contains($0.name.lowercased()) }
            components.queryItems = filtered.isEmpty ? nil : filtered
        }
        return components.string ?? urlString.lowercased()
    }

    // MARK: - Share Extension Pickup

    /// Checks for items saved by the Share Extension and imports them into Core Data.
    /// Call this on app launch and when returning to foreground.
    func importPendingSharedItems() {
        let pendingItems = SharedPendingItemStore.load()
        guard !pendingItems.isEmpty else { return }

        for pending in pendingItems {
            if let url = pending.url, !url.isEmpty {
                // URL-based item — use pre-generated summary if available
                saveLink(
                    url: url,
                    title: pending.title,
                    tags: pending.tags,
                    preGeneratedSummary: pending.summary,
                    preGeneratedBullets: pending.summaryBullets,
                    preGeneratedReadTime: pending.estimatedReadTime
                )
            } else if let localFileName = pending.localFileName {
                // File-based item
                importFileItem(localFileName: localFileName, title: pending.title, tags: pending.tags, mimeType: pending.contentMimeType)
            }
        }

        SharedPendingItemStore.clear()
    }

    // MARK: - File Import

    private func importFileItem(localFileName: String, title: String?, tags: [String], mimeType: String?) {
        let contentType = ContentType.from(mimeType: mimeType)
        let itemType: ItemType

        switch contentType {
        case .pdf: itemType = .pdf
        case .image: itemType = .image
        case .video: itemType = .video
        default: itemType = .link
        }

        let item = LibraryItem(
            context: viewContext,
            title: title ?? localFileName,
            itemType: itemType
        )
        item.tagsArray = tags
        item.localFilePath = localFileName
        item.contentMimeType = mimeType

        let itemID = item.id!

        // Images don't need AI summarization — load the image data as thumbnail
        if itemType == .image {
            if let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Config.appGroupIdentifier) {
                let fileURL = containerURL.appendingPathComponent("SharedFiles").appendingPathComponent(localFileName)
                if let imageData = try? Data(contentsOf: fileURL) {
                    item.thumbnailData = imageData
                }
            }
            item.summaryStatusEnum = .completed
            item.summary = "Image"
        } else if itemType == .video {
            // Videos: generate thumbnail, no AI summary in v1
            if let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Config.appGroupIdentifier) {
                let fileURL = containerURL.appendingPathComponent("SharedFiles").appendingPathComponent(localFileName)
                Task {
                    let processor = VideoProcessor()
                    if let thumbnailData = await processor.generateThumbnail(from: fileURL) {
                        await MainActor.run {
                            item.thumbnailData = thumbnailData
                            self.saveViewContext()
                        }
                    }
                }
            }
            item.summaryStatusEnum = .completed
            item.summary = "Video"
        } else if itemType == .pdf {
            // PDFs: queue for AI summarization
            let _ = PendingRequest(
                context: viewContext,
                libraryItemID: itemID,
                requestType: "pdf_summary",
                priority: .background
            )
            if let scheduler = requestScheduler {
                Task { await scheduler.notifyNewRequest() }
            }
        }

        saveViewContext()
    }

    // MARK: - Private

    private func saveViewContext() {
        guard viewContext.hasChanges else { return }
        do {
            try viewContext.save()
        } catch {
            print("Failed to save view context: \(error)")
        }
    }

    // MARK: - Sync Helpers

    /// Marks an item for sync upload/update based on its current sync status.
    private func markForSync(_ item: LibraryItem) {
        if item.syncStatusEnum == .synced {
            item.syncStatusEnum = .pendingUpdate
        }
        // Items that are already pendingUpload stay that way
    }

    /// Notifies the sync engine to push changes (debounced).
    private func notifySync() {
        if let engine = syncEngine {
            Task { await engine.enqueuePush() }
        }
    }
}

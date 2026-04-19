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

    init(viewContext: NSManagedObjectContext, backgroundContext: NSManagedObjectContext) {
        self.viewContext = viewContext
        self.backgroundContext = backgroundContext
    }

    // MARK: - Create

    /// Saves a new link and queues summary prefetch.
    /// Returns `.existing` if a link with the same URL is already in the library.
    @discardableResult
    func saveLink(url: String, title: String? = nil, tags: [String] = []) -> SaveResult {
        // Check for existing link with the same URL
        if let existing = findExistingLink(url: url) {
            let existingID = existing.id!
            // If the existing item failed, auto-retry it
            if existing.summaryStatusEnum == .failed && !hasActivePendingRequest(for: existingID) {
                existing.summaryStatusEnum = .pending
                let _ = PendingRequest(
                    context: viewContext,
                    libraryItemID: existingID,
                    requestType: "link_summary",
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

        let itemID = item.id!

        // Create pending request for AI summary prefetch
        let _ = PendingRequest(
            context: viewContext,
            libraryItemID: itemID,
            requestType: "link_summary",
            priority: .background
        )

        saveViewContext()

        // Notify scheduler to process the new request
        if let scheduler = requestScheduler {
            Task { await scheduler.notifyNewRequest() }
        }

        return .created(itemID)
    }

    /// Creates a book summary request.
    /// Returns `.existing` if a book summary with the same title already exists.
    @discardableResult
    func saveBookSummaryRequest(title: String, author: String?, length: SummaryLength) -> SaveResult {
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
        item.summaryStatusEnum = .pending

        let itemID = item.id!

        let _ = PendingRequest(
            context: viewContext,
            libraryItemID: itemID,
            requestType: "book_summary",
            priority: .userInitiated
        )

        saveViewContext()

        if let scheduler = requestScheduler {
            Task { await scheduler.notifyNewRequest() }
        }

        return .created(itemID)
    }

    // MARK: - Update

    func updateTitle(_ item: LibraryItem, title: String) {
        item.title = title
        item.updatedAt = Date()
        saveViewContext()
    }

    func updateTags(_ item: LibraryItem, tags: [String]) {
        item.tagsArray = tags
        item.updatedAt = Date()
        saveViewContext()
    }

    func markAsRead(_ item: LibraryItem) {
        item.isRead = true
        item.updatedAt = Date()
        saveViewContext()
    }

    func addComment(to item: LibraryItem, text: String) {
        let _ = Comment(context: viewContext, text: text, libraryItem: item)
        item.updatedAt = Date()
        saveViewContext()
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

        try? ctx.save()
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

        try? ctx.save()
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
        viewContext.delete(item)
        saveViewContext()
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
            requestType: item.itemTypeEnum == .bookSummary ? "book_summary" : "link_summary",
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
        fetchRequest.predicate = NSPredicate(format: "itemType == %@", ItemType.link.rawValue)

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
            saveLink(url: pending.url, title: pending.title, tags: pending.tags)
        }

        SharedPendingItemStore.clear()
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
}

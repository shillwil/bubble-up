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
    /// Returns the created item's ID for tracking.
    @discardableResult
    func saveLink(url: String, title: String? = nil, tags: [String] = []) -> UUID {
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

        return itemID
    }

    /// Creates a book summary request.
    @discardableResult
    func saveBookSummaryRequest(title: String, author: String?, length: SummaryLength) -> UUID {
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

        return itemID
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

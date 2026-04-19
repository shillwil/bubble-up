import Foundation
import CoreData

@objc(LibraryItem)
public class LibraryItem: NSManagedObject {

    /// Convenience initializer for creating a new library item.
    convenience init(
        context: NSManagedObjectContext,
        title: String,
        itemType: ItemType,
        url: String? = nil,
        tags: [String] = []
    ) {
        self.init(context: context)
        self.id = UUID()
        self.title = title
        self.itemType = itemType.rawValue
        self.url = url
        self.tags = tags as NSObject
        self.summaryStatus = SummaryStatus.pending.rawValue
        self.isRead = false
        self.createdAt = Date()
        self.updatedAt = Date()

        // Infer source display name and content MIME type from URL
        if let urlString = url, let parsedURL = URL(string: urlString) {
            self.sourceDisplayName = parsedURL.host?.replacingOccurrences(of: "www.", with: "")
            let contentType = ContentType.from(url: parsedURL)
            self.contentMimeType = contentType.mimeType
        }
    }

    // MARK: - Typed Accessors

    var itemTypeEnum: ItemType {
        get { ItemType(rawValue: itemType ?? "link") ?? .link }
        set { itemType = newValue.rawValue }
    }

    var summaryStatusEnum: SummaryStatus {
        get { SummaryStatus(rawValue: summaryStatus ?? "pending") ?? .pending }
        set { summaryStatus = newValue.rawValue }
    }

    var syncStatusEnum: SyncStatus {
        get { SyncStatus(rawValue: syncStatus ?? "pendingUpload") ?? .pendingUpload }
        set { syncStatus = newValue.rawValue }
    }

    var tagsArray: [String] {
        get { tags as? [String] ?? [] }
        set { tags = newValue as NSObject }
    }

    var summaryBulletsArray: [String] {
        get { summaryBullets as? [String] ?? [] }
        set { summaryBullets = newValue as NSObject }
    }

    var orderedPages: [PagedItem] {
        let set = pages as? Set<PagedItem> ?? []
        return set.sorted { $0.pageNumber < $1.pageNumber }
    }

    var orderedComments: [Comment] {
        let set = comments as? Set<Comment> ?? []
        return set.sorted { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
    }
}

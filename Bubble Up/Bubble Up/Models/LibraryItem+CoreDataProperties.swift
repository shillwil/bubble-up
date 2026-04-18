import Foundation
import CoreData

extension LibraryItem {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<LibraryItem> {
        return NSFetchRequest<LibraryItem>(entityName: "LibraryItem")
    }

    @NSManaged public var id: UUID?
    @NSManaged public var itemType: String?
    @NSManaged public var title: String?
    @NSManaged public var url: String?
    @NSManaged public var sourceDisplayName: String?
    @NSManaged public var authorName: String?
    @NSManaged public var summary: String?
    @NSManaged public var summaryBullets: NSObject?
    @NSManaged public var tags: NSObject?
    @NSManaged public var thumbnailData: Data?
    @NSManaged public var thumbnailURL: String?
    @NSManaged public var estimatedReadTime: Int16
    @NSManaged public var isRead: Bool
    @NSManaged public var createdAt: Date?
    @NSManaged public var updatedAt: Date?
    @NSManaged public var rawContent: String?
    @NSManaged public var contentMimeType: String?
    @NSManaged public var summaryStatus: String?
    @NSManaged public var pages: NSSet?
    @NSManaged public var comments: NSSet?
}

// MARK: - Generated accessors for pages

extension LibraryItem {

    @objc(addPagesObject:)
    @NSManaged public func addToPages(_ value: PagedItem)

    @objc(removePagesObject:)
    @NSManaged public func removeFromPages(_ value: PagedItem)

    @objc(addPages:)
    @NSManaged public func addToPages(_ values: NSSet)

    @objc(removePages:)
    @NSManaged public func removeFromPages(_ values: NSSet)
}

// MARK: - Generated accessors for comments

extension LibraryItem {

    @objc(addCommentsObject:)
    @NSManaged public func addToComments(_ value: Comment)

    @objc(removeCommentsObject:)
    @NSManaged public func removeFromComments(_ value: Comment)

    @objc(addComments:)
    @NSManaged public func addToComments(_ values: NSSet)

    @objc(removeComments:)
    @NSManaged public func removeFromComments(_ values: NSSet)
}

extension LibraryItem: @retroactive Identifiable {}

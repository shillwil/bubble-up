import Foundation
import CoreData

extension PagedItem {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<PagedItem> {
        return NSFetchRequest<PagedItem>(entityName: "PagedItem")
    }

    @NSManaged public var id: UUID?
    @NSManaged public var pageNumber: Int16
    @NSManaged public var pageTitle: String?
    @NSManaged public var content: String?
    @NSManaged public var libraryItem: LibraryItem?
}

extension PagedItem: @retroactive Identifiable {}

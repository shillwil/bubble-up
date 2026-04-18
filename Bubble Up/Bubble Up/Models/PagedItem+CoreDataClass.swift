import Foundation
import CoreData

@objc(PagedItem)
public class PagedItem: NSManagedObject {

    convenience init(
        context: NSManagedObjectContext,
        pageNumber: Int16,
        pageTitle: String,
        content: String,
        libraryItem: LibraryItem
    ) {
        self.init(context: context)
        self.id = UUID()
        self.pageNumber = pageNumber
        self.pageTitle = pageTitle
        self.content = content
        self.libraryItem = libraryItem
    }
}

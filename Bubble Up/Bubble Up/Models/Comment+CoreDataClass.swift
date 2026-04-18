import Foundation
import CoreData

@objc(Comment)
public class Comment: NSManagedObject {

    convenience init(
        context: NSManagedObjectContext,
        text: String,
        libraryItem: LibraryItem
    ) {
        self.init(context: context)
        self.id = UUID()
        self.text = text
        self.createdAt = Date()
        self.libraryItem = libraryItem
    }
}

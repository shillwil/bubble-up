import Foundation
import CoreData

extension Comment {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<Comment> {
        return NSFetchRequest<Comment>(entityName: "Comment")
    }

    @NSManaged public var id: UUID?
    @NSManaged public var text: String?
    @NSManaged public var createdAt: Date?
    @NSManaged public var libraryItem: LibraryItem?
}

extension Comment: @retroactive Identifiable {}

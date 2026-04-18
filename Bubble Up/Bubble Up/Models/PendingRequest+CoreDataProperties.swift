import Foundation
import CoreData

extension PendingRequest {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<PendingRequest> {
        return NSFetchRequest<PendingRequest>(entityName: "PendingRequest")
    }

    @NSManaged public var id: UUID?
    @NSManaged public var libraryItemID: UUID?
    @NSManaged public var requestType: String?
    @NSManaged public var status: String?
    @NSManaged public var priority: String?
    @NSManaged public var retryCount: Int16
    @NSManaged public var maxRetries: Int16
    @NSManaged public var lastAttemptAt: Date?
    @NSManaged public var nextRetryAt: Date?
    @NSManaged public var errorMessage: String?
    @NSManaged public var createdAt: Date?
}

extension PendingRequest: @retroactive Identifiable {}

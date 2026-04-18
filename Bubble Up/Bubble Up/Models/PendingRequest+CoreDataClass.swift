import Foundation
import CoreData

@objc(PendingRequest)
public class PendingRequest: NSManagedObject {

    convenience init(
        context: NSManagedObjectContext,
        libraryItemID: UUID,
        requestType: String,
        priority: RequestPriority = .background
    ) {
        self.init(context: context)
        self.id = UUID()
        self.libraryItemID = libraryItemID
        self.requestType = requestType
        self.status = RequestStatus.pending.rawValue
        self.priority = priority.rawValue
        self.retryCount = 0
        self.maxRetries = 5
        self.createdAt = Date()
    }

    // MARK: - Typed Accessors

    var statusEnum: RequestStatus {
        get { RequestStatus(rawValue: status ?? "pending") ?? .pending }
        set { status = newValue.rawValue }
    }

    var priorityEnum: RequestPriority {
        get { RequestPriority(rawValue: priority ?? "background") ?? .background }
        set { priority = newValue.rawValue }
    }

    /// Calculate next retry delay using exponential backoff (capped at 5 minutes).
    var backoffDelay: TimeInterval {
        min(pow(2.0, Double(retryCount)), 300)
    }

    /// Whether this request has exhausted all retries.
    var isExhausted: Bool {
        retryCount >= maxRetries
    }
}

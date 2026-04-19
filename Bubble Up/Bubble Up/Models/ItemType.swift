import Foundation

/// Content item types. Extensible for future content formats.
enum ItemType: String, CaseIterable, Sendable {
    case link
    case bookSummary
    case youtube
    case pdf
    case image
    case video
    // Future: document, epub
}

/// Summary generation length options for book summaries.
enum SummaryLength: String, CaseIterable, Sendable {
    case short
    case full
}

/// Status of an AI summary generation request.
enum SummaryStatus: String, Sendable {
    case pending
    case generating
    case completed
    case failed
}

/// Priority level for pending requests.
enum RequestPriority: String, Sendable {
    case userInitiated
    case background
}

/// Status of a pending request in the queue.
enum RequestStatus: String, Sendable {
    case pending
    case inProgress
    case failed
}

/// Sync status for cross-device synchronization.
enum SyncStatus: String, Sendable {
    case synced
    case pendingUpload
    case pendingUpdate
    case pendingDelete
}

/// Result of attempting to save a link or book summary.
enum SaveResult {
    case created(UUID)
    case existing(UUID)

    var id: UUID {
        switch self {
        case .created(let id), .existing(let id):
            return id
        }
    }

    var isExisting: Bool {
        if case .existing = self { return true }
        return false
    }
}

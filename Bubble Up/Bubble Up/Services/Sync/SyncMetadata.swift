import Foundation

/// Persists sync state per user in UserDefaults.
enum SyncMetadata {
    private static let defaults = UserDefaults.standard

    private static func key(_ base: String, for userID: String) -> String {
        "sync_\(userID)_\(base)"
    }

    static func lastSyncDate(for userID: String) -> Date? {
        let key = key("lastSyncDate", for: userID)
        let interval = defaults.double(forKey: key)
        return interval > 0 ? Date(timeIntervalSince1970: interval) : nil
    }

    static func setLastSyncDate(_ date: Date, for userID: String) {
        defaults.set(date.timeIntervalSince1970, forKey: key("lastSyncDate", for: userID))
    }

    static func needsInitialSync(for userID: String) -> Bool {
        !defaults.bool(forKey: key("initialSyncDone", for: userID))
    }

    static func markInitialSyncComplete(for userID: String) {
        defaults.set(true, forKey: key("initialSyncDone", for: userID))
    }
}

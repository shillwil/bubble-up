import Foundation

/// Lightweight model for sharing pending items between the Share Extension and the main app.
/// This is a standalone copy for the extension target — the main app has its own copy
/// that references Config.appGroupIdentifier.
struct SharedPendingItem: Codable {
    let url: String?
    let title: String?
    let tags: [String]
    let savedAt: Date
    let localFileName: String?
    let contentMimeType: String?
    let userNotes: String?

    // Pre-generated summary (filled by share extension if BYOK key is available)
    var summary: String?
    var summaryBullets: [String]?
    var estimatedReadTime: Int?

    init(url: String? = nil, title: String? = nil, tags: [String] = [], localFileName: String? = nil, contentMimeType: String? = nil, userNotes: String? = nil) {
        self.url = url
        self.title = title
        self.tags = tags
        self.savedAt = Date()
        self.localFileName = localFileName
        self.contentMimeType = contentMimeType
        self.userNotes = userNotes
    }
}

enum SharedPendingItemStore {
    private static let suiteName = "group.com.shillwil.bubble-up"
    private static let key = "pendingSharedItems"

    static func save(_ item: SharedPendingItem) {
        var items = load()
        items.append(item)
        write(items)
    }

    static func load() -> [SharedPendingItem] {
        guard let defaults = UserDefaults(suiteName: suiteName),
              let data = defaults.data(forKey: key) else {
            return []
        }
        return (try? JSONDecoder().decode([SharedPendingItem].self, from: data)) ?? []
    }

    /// Updates the most recently saved item with a pre-generated summary.
    static func updateLatestWithSummary(summary: String, bullets: [String], estimatedReadTime: Int?) {
        var items = load()
        guard !items.isEmpty else { return }
        items[items.count - 1].summary = summary
        items[items.count - 1].summaryBullets = bullets
        items[items.count - 1].estimatedReadTime = estimatedReadTime
        write(items)
    }

    static func clear() {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return }
        defaults.removeObject(forKey: key)
    }

    private static func write(_ items: [SharedPendingItem]) {
        guard let defaults = UserDefaults(suiteName: suiteName),
              let data = try? JSONEncoder().encode(items) else { return }
        defaults.set(data, forKey: key)
    }
}

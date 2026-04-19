import Foundation

/// Lightweight model for sharing pending items between the Share Extension and the main app
/// via App Group UserDefaults. No Core Data dependency.
struct SharedPendingItem: Codable {
    let url: String?              // Optional now (nil for file-based items)
    let title: String?
    let tags: [String]
    let savedAt: Date
    let localFileName: String?    // Filename in App Group shared container
    let contentMimeType: String?  // MIME type for file-based items
    let userNotes: String?        // Optional context from user about why they saved this

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

/// Reads and writes pending items to the shared App Group UserDefaults.
enum SharedPendingItemStore {
    private static let suiteName = Config.appGroupIdentifier
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

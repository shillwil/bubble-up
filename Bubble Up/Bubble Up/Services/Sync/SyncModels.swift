import Foundation

// MARK: - Library Item DTO

struct LibraryItemDTO: Codable {
    let id: UUID
    let userId: UUID
    let itemType: String
    let title: String
    let url: String?
    let sourceDisplayName: String?
    let authorName: String?
    let summary: String?
    let summaryBullets: [String]?
    let tags: [String]?
    let summaryStatus: String
    let isRead: Bool
    let estimatedReadTime: Int16
    let rawContent: String?
    let contentMimeType: String?
    let localFilePath: String?
    let thumbnailUrl: String?
    let thumbnailStoragePath: String?
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, title, url, summary, tags
        case userId = "user_id"
        case itemType = "item_type"
        case sourceDisplayName = "source_display_name"
        case authorName = "author_name"
        case summaryBullets = "summary_bullets"
        case summaryStatus = "summary_status"
        case isRead = "is_read"
        case estimatedReadTime = "estimated_read_time"
        case rawContent = "raw_content"
        case contentMimeType = "content_mime_type"
        case localFilePath = "local_file_path"
        case thumbnailUrl = "thumbnail_url"
        case thumbnailStoragePath = "thumbnail_storage_path"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }
}

// MARK: - Paged Item DTO

struct PagedItemDTO: Codable {
    let id: UUID
    let libraryItemId: UUID
    let pageNumber: Int16
    let pageTitle: String
    let content: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, content
        case libraryItemId = "library_item_id"
        case pageNumber = "page_number"
        case pageTitle = "page_title"
        case createdAt = "created_at"
    }
}

// MARK: - Comment DTO

struct CommentDTO: Codable {
    let id: UUID
    let libraryItemId: UUID
    let text: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, text
        case libraryItemId = "library_item_id"
        case createdAt = "created_at"
    }
}

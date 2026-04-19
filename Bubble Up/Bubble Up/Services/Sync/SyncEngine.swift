import Foundation
import CoreData
import Supabase

/// Manages bidirectional sync between local Core Data and Supabase.
actor SyncEngine {
    private let supabase: SupabaseClient
    private let persistenceController: PersistenceController
    private let authService: AuthService
    private var isSyncing = false
    private var pushTask: Task<Void, Never>?

    init(persistenceController: PersistenceController, authService: AuthService) {
        self.supabase = SupabaseClientProvider.shared
        self.persistenceController = persistenceController
        self.authService = authService
    }

    // MARK: - Public API

    /// Run a full push-then-pull sync cycle.
    func performFullSync() async {
        guard !isSyncing else { return }
        guard let userID = await authService.currentUserID else { return }
        isSyncing = true
        defer { isSyncing = false }

        // Handle first-time sync for existing local data
        if SyncMetadata.needsInitialSync(for: userID) {
            await markAllItemsForUpload()
            SyncMetadata.markInitialSyncComplete(for: userID)
        }

        // Re-queue synced items that have local files but missing thumbnailStoragePath
        // (file/thumbnail upload may have failed on a previous sync)
        await requeueItemsMissingFiles()

        do {
            try await pushLocalChanges(userID: userID)
        } catch {
            print("[SyncEngine] Push failed: \(error)")
        }

        do {
            try await pullRemoteChanges(userID: userID)
        } catch {
            print("[SyncEngine] Pull failed: \(error)")
        }
    }

    /// Debounced push after a local mutation.
    func enqueuePush() {
        pushTask?.cancel()
        pushTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            guard let userID = await authService.currentUserID else { return }
            try? await pushLocalChanges(userID: userID)
        }
    }

    // MARK: - Push

    private func pushLocalChanges(userID: String) async throws {
        let context = persistenceController.newBackgroundContext()

        // Fetch items needing sync
        let snapshots: [LocalItemSnapshot] = await context.perform {
            let fetch = LibraryItem.fetchRequest()
            fetch.predicate = NSPredicate(
                format: "syncStatus != %@ AND syncStatus != nil",
                SyncStatus.synced.rawValue
            )
            guard let items = try? context.fetch(fetch) else { return [] }
            return items.map { LocalItemSnapshot(item: $0) }
        }

        guard !snapshots.isEmpty else { return }

        for snapshot in snapshots {
            do {
                switch snapshot.syncStatus {
                case .pendingUpload, .pendingUpdate:
                    try await upsertItem(snapshot, userID: userID, context: context)
                case .pendingDelete:
                    try await softDeleteItem(snapshot, context: context)
                case .synced:
                    break
                }
            } catch {
                print("[SyncEngine] Failed to push item \(snapshot.id): \(error)")
            }
        }
    }

    private func upsertItem(_ snapshot: LocalItemSnapshot, userID: String, context: NSManagedObjectContext) async throws {
        guard let userUUID = UUID(uuidString: userID) else { return }

        var dto = LibraryItemDTO(
            id: snapshot.id,
            userId: userUUID,
            itemType: snapshot.itemType,
            title: snapshot.title,
            url: snapshot.url,
            sourceDisplayName: snapshot.sourceDisplayName,
            authorName: snapshot.authorName,
            summary: snapshot.summary,
            summaryBullets: snapshot.summaryBullets,
            tags: snapshot.tags,
            summaryStatus: snapshot.summaryStatus,
            isRead: snapshot.isRead,
            estimatedReadTime: snapshot.estimatedReadTime,
            rawContent: snapshot.rawContent,
            contentMimeType: snapshot.contentMimeType,
            localFilePath: snapshot.localFilePath,
            thumbnailUrl: snapshot.thumbnailURL,
            thumbnailStoragePath: snapshot.thumbnailStoragePath,
            createdAt: snapshot.createdAt,
            updatedAt: snapshot.updatedAt,
            deletedAt: nil
        )

        // Upload file to Storage if needed (check if it exists remotely by trying to upload)
        if let localFileName = snapshot.localFilePath {
            do {
                try await uploadFile(
                    itemID: snapshot.id,
                    userID: userID,
                    localFileName: localFileName,
                    mimeType: snapshot.contentMimeType ?? "application/octet-stream"
                )
            } catch {
                print("[SyncEngine] File upload failed for \(snapshot.id): \(error)")
            }
        }

        // Upload thumbnail if we have local data but no storage path yet
        if snapshot.hasThumbnailData, snapshot.thumbnailStoragePath == nil {
            if let thumbPath = try? await uploadThumbnail(
                itemID: snapshot.id,
                userID: userID,
                context: context
            ) {
                dto = LibraryItemDTO(
                    id: dto.id, userId: dto.userId, itemType: dto.itemType, title: dto.title,
                    url: dto.url, sourceDisplayName: dto.sourceDisplayName, authorName: dto.authorName,
                    summary: dto.summary, summaryBullets: dto.summaryBullets, tags: dto.tags,
                    summaryStatus: dto.summaryStatus, isRead: dto.isRead,
                    estimatedReadTime: dto.estimatedReadTime, rawContent: dto.rawContent,
                    contentMimeType: dto.contentMimeType, localFilePath: dto.localFilePath,
                    thumbnailUrl: dto.thumbnailUrl, thumbnailStoragePath: thumbPath,
                    createdAt: dto.createdAt, updatedAt: dto.updatedAt, deletedAt: nil
                )
            }
        }

        // Upsert to Supabase
        try await supabase
            .from("library_items")
            .upsert(dto)
            .execute()

        // Push associated pages and comments
        try await pushPages(for: snapshot.id, context: context)
        try await pushComments(for: snapshot.id, context: context)

        // Mark as synced
        await context.perform {
            let fetch = LibraryItem.fetchRequest()
            fetch.predicate = NSPredicate(format: "id == %@", snapshot.id as CVarArg)
            if let item = try? context.fetch(fetch).first {
                item.syncStatus = SyncStatus.synced.rawValue
                if let storagePath = dto.thumbnailStoragePath {
                    item.thumbnailStoragePath = storagePath
                }
                try? context.save()
            }
        }
    }

    private func pushPages(for itemID: UUID, context: NSManagedObjectContext) async throws {
        let dtos: [PagedItemDTO] = await context.perform {
            let fetch = LibraryItem.fetchRequest()
            fetch.predicate = NSPredicate(format: "id == %@", itemID as CVarArg)
            guard let item = try? context.fetch(fetch).first else { return [] }
            return item.orderedPages.map {
                PagedItemDTO(
                    id: $0.id ?? UUID(),
                    libraryItemId: itemID,
                    pageNumber: $0.pageNumber,
                    pageTitle: $0.pageTitle ?? "",
                    content: $0.content ?? "",
                    createdAt: Date()
                )
            }
        }

        guard !dtos.isEmpty else { return }

        // Delete existing remote pages and re-insert
        try await supabase
            .from("paged_items")
            .delete()
            .eq("library_item_id", value: itemID)
            .execute()

        try await supabase
            .from("paged_items")
            .insert(dtos)
            .execute()
    }

    private func pushComments(for itemID: UUID, context: NSManagedObjectContext) async throws {
        let dtos: [CommentDTO] = await context.perform {
            let fetch = LibraryItem.fetchRequest()
            fetch.predicate = NSPredicate(format: "id == %@", itemID as CVarArg)
            guard let item = try? context.fetch(fetch).first else { return [] }
            return item.orderedComments.map {
                CommentDTO(
                    id: $0.id ?? UUID(),
                    libraryItemId: itemID,
                    text: $0.text ?? "",
                    createdAt: $0.createdAt ?? Date()
                )
            }
        }

        guard !dtos.isEmpty else { return }

        try await supabase
            .from("comments")
            .delete()
            .eq("library_item_id", value: itemID)
            .execute()

        try await supabase
            .from("comments")
            .insert(dtos)
            .execute()
    }

    private func softDeleteItem(_ snapshot: LocalItemSnapshot, context: NSManagedObjectContext) async throws {
        // Set deleted_at on Supabase
        try await supabase
            .from("library_items")
            .update(["deleted_at": Date().ISO8601Format()])
            .eq("id", value: snapshot.id)
            .execute()

        // Delete associated files from Storage
        if let localFileName = snapshot.localFilePath,
           let userID = await authService.currentUserID {
            let storagePath = "\(userID.lowercased())/\(snapshot.id.uuidString.lowercased())/\(localFileName)"
            try? await supabase.storage
                .from("user-files")
                .remove(paths: [storagePath])
        }

        if let thumbPath = snapshot.thumbnailStoragePath {
            try? await supabase.storage
                .from("user-files")
                .remove(paths: [thumbPath])
        }

        // Hard-delete from Core Data
        await context.perform {
            let fetch = LibraryItem.fetchRequest()
            fetch.predicate = NSPredicate(format: "id == %@", snapshot.id as CVarArg)
            if let item = try? context.fetch(fetch).first {
                // Delete local file
                if let localPath = item.localFilePath {
                    if let containerURL = FileManager.default.containerURL(
                        forSecurityApplicationGroupIdentifier: Config.appGroupIdentifier
                    ) {
                        let fileURL = containerURL.appendingPathComponent("SharedFiles").appendingPathComponent(localPath)
                        try? FileManager.default.removeItem(at: fileURL)
                    }
                }
                context.delete(item)
                try? context.save()
            }
        }
    }

    // MARK: - Pull

    private func pullRemoteChanges(userID: String) async throws {
        let lastSync = SyncMetadata.lastSyncDate(for: userID) ?? Date.distantPast

        let remoteDTOs: [LibraryItemDTO] = try await supabase
            .from("library_items")
            .select()
            .gt("updated_at", value: lastSync.ISO8601Format())
            .execute()
            .value

        guard !remoteDTOs.isEmpty else {
            SyncMetadata.setLastSyncDate(Date(), for: userID)
            return
        }

        let context = persistenceController.newBackgroundContext()

        for dto in remoteDTOs {
            await context.perform {
                let fetch = LibraryItem.fetchRequest()
                fetch.predicate = NSPredicate(format: "id == %@", dto.id as CVarArg)
                let localItem = try? context.fetch(fetch).first

                if dto.deletedAt != nil {
                    // Remote was deleted — remove locally
                    if let item = localItem {
                        if let localPath = item.localFilePath {
                            if let containerURL = FileManager.default.containerURL(
                                forSecurityApplicationGroupIdentifier: Config.appGroupIdentifier
                            ) {
                                let fileURL = containerURL.appendingPathComponent("SharedFiles").appendingPathComponent(localPath)
                                try? FileManager.default.removeItem(at: fileURL)
                            }
                        }
                        context.delete(item)
                    }
                } else if let item = localItem {
                    // Update existing item if remote is newer
                    let localUpdated = item.updatedAt ?? .distantPast
                    if dto.updatedAt > localUpdated {
                        self.applyDTO(dto, to: item)
                    }
                } else {
                    // New item from another device
                    let item = LibraryItem(entity: LibraryItem.entity(), insertInto: context)
                    self.applyDTO(dto, to: item)
                }

                try? context.save()
            }

            // Download files for new/updated items that have storage paths
            if dto.deletedAt == nil {
                await downloadFilesIfNeeded(for: dto, context: context)
                await pullPages(for: dto.id, context: context)
                await pullComments(for: dto.id, context: context)
            }
        }

        SyncMetadata.setLastSyncDate(Date(), for: userID)
    }

    private func applyDTO(_ dto: LibraryItemDTO, to item: LibraryItem) {
        item.id = dto.id
        item.itemType = dto.itemType
        item.title = dto.title
        item.url = dto.url
        item.sourceDisplayName = dto.sourceDisplayName
        item.authorName = dto.authorName
        item.summary = dto.summary
        item.summaryBullets = (dto.summaryBullets ?? []) as NSObject
        item.tags = (dto.tags ?? []) as NSObject
        item.summaryStatus = dto.summaryStatus
        item.isRead = dto.isRead
        item.estimatedReadTime = dto.estimatedReadTime
        item.rawContent = dto.rawContent
        item.contentMimeType = dto.contentMimeType
        item.localFilePath = dto.localFilePath
        item.thumbnailURL = dto.thumbnailUrl
        item.thumbnailStoragePath = dto.thumbnailStoragePath
        item.createdAt = dto.createdAt
        item.updatedAt = dto.updatedAt
        item.syncStatus = SyncStatus.synced.rawValue
    }

    private func pullPages(for itemID: UUID, context: NSManagedObjectContext) async {
        do {
            let remoteDTOs: [PagedItemDTO] = try await supabase
                .from("paged_items")
                .select()
                .eq("library_item_id", value: itemID)
                .order("page_number")
                .execute()
                .value

            guard !remoteDTOs.isEmpty else { return }

            await context.perform {
                let fetch = LibraryItem.fetchRequest()
                fetch.predicate = NSPredicate(format: "id == %@", itemID as CVarArg)
                guard let item = try? context.fetch(fetch).first else { return }

                // Remove existing pages and replace
                if let existingPages = item.pages {
                    item.removeFromPages(existingPages)
                    for page in existingPages {
                        if let page = page as? NSManagedObject {
                            context.delete(page)
                        }
                    }
                }

                for dto in remoteDTOs {
                    let page = PagedItem(entity: PagedItem.entity(), insertInto: context)
                    page.id = dto.id
                    page.pageNumber = dto.pageNumber
                    page.pageTitle = dto.pageTitle
                    page.content = dto.content
                    page.libraryItem = item
                }

                try? context.save()
            }
        } catch {
            print("[SyncEngine] Failed to pull pages for \(itemID): \(error)")
        }
    }

    private func pullComments(for itemID: UUID, context: NSManagedObjectContext) async {
        do {
            let remoteDTOs: [CommentDTO] = try await supabase
                .from("comments")
                .select()
                .eq("library_item_id", value: itemID)
                .order("created_at")
                .execute()
                .value

            guard !remoteDTOs.isEmpty else { return }

            await context.perform {
                let fetch = LibraryItem.fetchRequest()
                fetch.predicate = NSPredicate(format: "id == %@", itemID as CVarArg)
                guard let item = try? context.fetch(fetch).first else { return }

                // Remove existing comments and replace
                if let existingComments = item.comments {
                    item.removeFromComments(existingComments)
                    for comment in existingComments {
                        if let comment = comment as? NSManagedObject {
                            context.delete(comment)
                        }
                    }
                }

                for dto in remoteDTOs {
                    let comment = Comment(entity: Comment.entity(), insertInto: context)
                    comment.id = dto.id
                    comment.text = dto.text
                    comment.createdAt = dto.createdAt
                    comment.libraryItem = item
                }

                try? context.save()
            }
        } catch {
            print("[SyncEngine] Failed to pull comments for \(itemID): \(error)")
        }
    }

    // MARK: - File Upload/Download

    private func uploadFile(itemID: UUID, userID: String, localFileName: String, mimeType: String) async throws -> String {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: Config.appGroupIdentifier
        ) else { throw SyncError.noContainer }

        let fileURL = containerURL.appendingPathComponent("SharedFiles").appendingPathComponent(localFileName)
        let fileData = try Data(contentsOf: fileURL)

        let storagePath = "\(userID.lowercased())/\(itemID.uuidString.lowercased())/\(localFileName)"

        try await supabase.storage
            .from("user-files")
            .upload(
                storagePath,
                data: fileData,
                options: FileOptions(contentType: mimeType, upsert: true)
            )

        return storagePath
    }

    private func uploadThumbnail(itemID: UUID, userID: String, context: NSManagedObjectContext) async throws -> String {
        let thumbnailData: Data? = await context.perform {
            let fetch = LibraryItem.fetchRequest()
            fetch.predicate = NSPredicate(format: "id == %@", itemID as CVarArg)
            return try? context.fetch(fetch).first?.thumbnailData
        }

        guard let data = thumbnailData else { throw SyncError.noThumbnail }

        let storagePath = "\(userID.lowercased())/\(itemID.uuidString.lowercased())/thumbnail.jpg"

        try await supabase.storage
            .from("user-files")
            .upload(
                storagePath,
                data: data,
                options: FileOptions(contentType: "image/jpeg", upsert: true)
            )

        return storagePath
    }

    private func downloadFilesIfNeeded(for dto: LibraryItemDTO, context: NSManagedObjectContext) async {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: Config.appGroupIdentifier
        ) else { return }

        let sharedDir = containerURL.appendingPathComponent("SharedFiles")
        try? FileManager.default.createDirectory(at: sharedDir, withIntermediateDirectories: true)

        // Download the main file if it has a local file path and we don't have it locally
        var downloadedFileData: Data?
        if let localFileName = dto.localFilePath {
            let localFileURL = sharedDir.appendingPathComponent(localFileName)
            if !FileManager.default.fileExists(atPath: localFileURL.path),
               let userID = await authService.currentUserID {
                let storagePath = "\(userID.lowercased())/\(dto.id.uuidString.lowercased())/\(localFileName)"
                do {
                    let data = try await supabase.storage
                        .from("user-files")
                        .download(path: storagePath)
                    try data.write(to: localFileURL)
                    downloadedFileData = data
                } catch {
                    print("[SyncEngine] Failed to download file \(storagePath): \(error)")
                }
            }
        }

        // Download thumbnail if we have a storage path but no local thumbnail data
        let hasThumbnail: Bool = await context.perform {
            let fetch = LibraryItem.fetchRequest()
            fetch.predicate = NSPredicate(format: "id == %@", dto.id as CVarArg)
            return (try? context.fetch(fetch).first?.thumbnailData) != nil
        }

        if !hasThumbnail {
            if let thumbPath = dto.thumbnailStoragePath {
                do {
                    let data = try await supabase.storage
                        .from("user-files")
                        .download(path: thumbPath)
                    await context.perform {
                        let fetch = LibraryItem.fetchRequest()
                        fetch.predicate = NSPredicate(format: "id == %@", dto.id as CVarArg)
                        if let item = try? context.fetch(fetch).first {
                            item.thumbnailData = data
                            try? context.save()
                        }
                    }
                } catch {
                    print("[SyncEngine] Failed to download thumbnail \(thumbPath): \(error)")
                }
            } else if let fileData = downloadedFileData, isImageMimeType(dto.contentMimeType) {
                // Fallback for images: use the downloaded file data as thumbnail
                await context.perform {
                    let fetch = LibraryItem.fetchRequest()
                    fetch.predicate = NSPredicate(format: "id == %@", dto.id as CVarArg)
                    if let item = try? context.fetch(fetch).first {
                        item.thumbnailData = fileData
                        try? context.save()
                    }
                }
            } else if let localFileName = dto.localFilePath, isVideoMimeType(dto.contentMimeType) {
                // Fallback for videos: generate thumbnail from the downloaded video file
                let fileURL = sharedDir.appendingPathComponent(localFileName)
                if FileManager.default.fileExists(atPath: fileURL.path) {
                    let processor = VideoProcessor()
                    if let thumbData = await processor.generateThumbnail(from: fileURL) {
                        await context.perform {
                            let fetch = LibraryItem.fetchRequest()
                            fetch.predicate = NSPredicate(format: "id == %@", dto.id as CVarArg)
                            if let item = try? context.fetch(fetch).first {
                                item.thumbnailData = thumbData
                                try? context.save()
                            }
                        }
                    }
                }
            }
        }
    }

    private func isImageMimeType(_ mimeType: String?) -> Bool {
        mimeType?.hasPrefix("image/") ?? false
    }

    private func isVideoMimeType(_ mimeType: String?) -> Bool {
        mimeType?.hasPrefix("video/") ?? false
    }

    // MARK: - Initial Sync Helper

    private func markAllItemsForUpload() async {
        let context = persistenceController.newBackgroundContext()
        await context.perform {
            let fetch = LibraryItem.fetchRequest()
            guard let items = try? context.fetch(fetch) else { return }
            for item in items {
                if item.syncStatus == nil || item.syncStatusEnum != .synced {
                    item.syncStatus = SyncStatus.pendingUpload.rawValue
                }
            }
            try? context.save()
        }
    }

    /// Re-queues items that were marked synced but are missing file/thumbnail uploads.
    private func requeueItemsMissingFiles() async {
        let context = persistenceController.newBackgroundContext()
        await context.perform {
            let fetch = LibraryItem.fetchRequest()
            // Items that are synced, have a local file, but no thumbnail storage path
            fetch.predicate = NSPredicate(
                format: "syncStatus == %@ AND localFilePath != nil AND thumbnailStoragePath == nil",
                SyncStatus.synced.rawValue
            )
            guard let items = try? context.fetch(fetch), !items.isEmpty else { return }
            for item in items {
                item.syncStatus = SyncStatus.pendingUpdate.rawValue
            }
            try? context.save()
            print("[SyncEngine] Re-queued \(items.count) items missing file uploads")
        }
    }
}

// MARK: - Local Snapshot

/// Thread-safe snapshot of a LibraryItem for use outside Core Data context.
private struct LocalItemSnapshot {
    let id: UUID
    let syncStatus: SyncStatus
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
    let thumbnailURL: String?
    let thumbnailStoragePath: String?
    let hasThumbnailData: Bool
    let createdAt: Date
    let updatedAt: Date

    init(item: LibraryItem) {
        self.id = item.id ?? UUID()
        self.syncStatus = item.syncStatusEnum
        self.itemType = item.itemType ?? "link"
        self.title = item.title ?? ""
        self.url = item.url
        self.sourceDisplayName = item.sourceDisplayName
        self.authorName = item.authorName
        self.summary = item.summary
        self.summaryBullets = item.summaryBulletsArray
        self.tags = item.tagsArray
        self.summaryStatus = item.summaryStatus ?? "pending"
        self.isRead = item.isRead
        self.estimatedReadTime = item.estimatedReadTime
        self.rawContent = item.rawContent
        self.contentMimeType = item.contentMimeType
        self.localFilePath = item.localFilePath
        self.thumbnailURL = item.thumbnailURL
        self.thumbnailStoragePath = item.thumbnailStoragePath
        self.hasThumbnailData = item.thumbnailData != nil
        self.createdAt = item.createdAt ?? Date()
        self.updatedAt = item.updatedAt ?? Date()
    }
}

// MARK: - Errors

enum SyncError: Error {
    case noContainer
    case noThumbnail
}

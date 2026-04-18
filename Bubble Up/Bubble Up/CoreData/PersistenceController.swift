import CoreData

final class PersistenceController: @unchecked Sendable {
    static let shared = PersistenceController()

    /// For SwiftUI previews and tests
    static let preview: PersistenceController = {
        let controller = PersistenceController(inMemory: true)
        let context = controller.container.viewContext

        // Create sample data for previews
        let item1 = LibraryItem(
            context: context,
            title: "The Future of Minimalist Design",
            itemType: .link,
            url: "https://theatlantic.com/minimalist-design"
        )
        item1.authorName = "John Doe"
        item1.summaryBullets = [
            "Digital spaces are increasingly mirroring physical minimalism to reduce cognitive load.",
            "The shift from 'feature-rich' to 'focused utility' is driving modern UI trends.",
            "Typography and negative space replace borders and backgrounds as primary structural elements."
        ] as NSObject
        item1.summaryStatusEnum = .completed
        item1.estimatedReadTime = 5

        let item2 = LibraryItem(
            context: context,
            title: "The Art of Doing Nothing",
            itemType: .link,
            url: "https://theatlantic.com/doing-nothing"
        )
        item2.summaryStatusEnum = .completed
        item2.estimatedReadTime = 8

        let item3 = LibraryItem(
            context: context,
            title: "Brutalism in Modern Interfaces",
            itemType: .link,
            url: "https://uxdesign.cc/brutalism"
        )
        item3.summaryStatusEnum = .pending

        try? context.save()
        return controller
    }()

    let container: NSPersistentContainer

    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "BubbleUp")

        if inMemory {
            let description = NSPersistentStoreDescription()
            description.url = URL(fileURLWithPath: "/dev/null")
            container.persistentStoreDescriptions = [description]
        } else {
            // Use App Group for Share Extension access
            if let appGroupURL = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: "group.com.shillwil.bubble-up"
            ) {
                let storeURL = appGroupURL.appendingPathComponent("BubbleUp.sqlite")
                let description = NSPersistentStoreDescription(url: storeURL)
                description.shouldMigrateStoreAutomatically = true
                description.shouldInferMappingModelAutomatically = true
                container.persistentStoreDescriptions = [description]
            }
        }

        container.loadPersistentStores { _, error in
            if let error {
                fatalError("Core Data failed to load: \(error)")
            }
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }

    /// Creates a new background context for off-main-thread work (e.g., RequestScheduler).
    func newBackgroundContext() -> NSManagedObjectContext {
        let context = container.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        return context
    }
}

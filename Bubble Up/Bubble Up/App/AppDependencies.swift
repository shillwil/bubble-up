import SwiftUI
import CoreData

/// Central dependency container for the app. Injected into the SwiftUI environment.
@Observable
@MainActor
final class AppDependencies {
    let persistenceController: PersistenceController
    let keychainService: KeychainService
    let authService: AuthService
    let repository: LibraryItemsRepository
    let requestScheduler: RequestScheduler

    init(persistenceController: PersistenceController = .shared) {
        self.persistenceController = persistenceController
        self.keychainService = KeychainService()
        self.authService = AuthService(keychainService: keychainService)
        self.repository = LibraryItemsRepository(
            viewContext: persistenceController.container.viewContext,
            backgroundContext: persistenceController.newBackgroundContext()
        )
        self.requestScheduler = RequestScheduler(
            persistenceController: persistenceController,
            keychainService: keychainService
        )

        self.repository.requestScheduler = requestScheduler
    }

    /// Starts background services. Restores auth session FIRST, then starts scheduler.
    func startServices() {
        // Sync BYOK API keys to App Group so share extension can access them
        keychainService.syncKeysToAppGroup()

        Task {
            // 1. Restore auth session so the Supabase client has a valid JWT
            await authService.restoreSession()

            // 2. Import any items from Share Extension
            repository.importPendingSharedItems()

            // 3. NOW start processing the queue (session is ready)
            await requestScheduler.resumePendingRequests()
        }
    }
}

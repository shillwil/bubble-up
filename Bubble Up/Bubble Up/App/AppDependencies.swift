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
    let syncEngine: SyncEngine

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
        self.syncEngine = SyncEngine(
            persistenceController: persistenceController,
            authService: authService
        )

        self.repository.requestScheduler = requestScheduler
        self.repository.syncEngine = syncEngine
    }

    /// Starts background services. Restores auth session FIRST, then starts scheduler and sync.
    func startServices() {
        Task {
            // Wire up sync engine to scheduler so completed summaries get pushed
            await requestScheduler.setSyncEngine(syncEngine)

            // 1. Restore auth session so the Supabase client has a valid JWT
            await authService.restoreSession()

            // 2. Import any items from Share Extension
            repository.importPendingSharedItems()

            // 3. Start processing the queue (session is ready)
            await requestScheduler.resumePendingRequests()

            // 4. Sync with Supabase if authenticated
            if authService.isAuthenticated {
                await syncEngine.performFullSync()
            }
        }
    }
}

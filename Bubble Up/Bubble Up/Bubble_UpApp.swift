import SwiftUI
import CoreData

@main
struct Bubble_UpApp: App {
    @State private var dependencies = AppDependencies()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("appearanceMode") private var appearanceMode = "system"

    private var resolvedColorScheme: ColorScheme? {
        switch appearanceMode {
        case "light": return .light
        case "dark": return .dark
        default: return nil // system
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(dependencies)
                .environment(dependencies.authService)
                .environment(dependencies.repository)
                .environment(dependencies.keychainService)
                .environment(\.managedObjectContext, dependencies.persistenceController.container.viewContext)
                .preferredColorScheme(resolvedColorScheme)
                .task {
                    dependencies.startServices()
                }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                dependencies.repository.importPendingSharedItems()
                // Re-process any pending requests when returning to foreground
                Task { await dependencies.requestScheduler.notifyNewRequest() }
            }
        }
    }
}

import SwiftUI
import CoreData

struct MainTabView: View {
    @State private var selectedTab: Tab = .feed

    enum Tab: String {
        case feed, library, settings
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                FeedView()
            }
            .tabItem {
                Label {
                    Text("FEED")
                        .font(.system(size: 11, weight: .semibold))
                } icon: {
                    Image(systemName: selectedTab == .feed ? "rectangle.stack.fill" : "rectangle.stack")
                }
            }
            .tag(Tab.feed)

            NavigationStack {
                LibraryView()
            }
            .tabItem {
                Label {
                    Text("LIBRARY")
                        .font(.system(size: 11, weight: .semibold))
                } icon: {
                    Image(systemName: selectedTab == .library ? "book.fill" : "book")
                }
            }
            .tag(Tab.library)

            NavigationStack {
                ProfileView()
            }
            .tabItem {
                Label {
                    Text("SETTINGS")
                        .font(.system(size: 11, weight: .semibold))
                } icon: {
                    Image(systemName: selectedTab == .settings ? "gearshape.fill" : "gearshape")
                }
            }
            .tag(Tab.settings)
        }
        .tint(BubbleUpTheme.primary)
    }
}

#Preview {
    MainTabView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}

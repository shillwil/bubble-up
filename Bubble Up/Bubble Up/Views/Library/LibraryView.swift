import SwiftUI
import CoreData

/// Archive/collection view with masonry grid and search.
struct LibraryView: View {
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \LibraryItem.createdAt, ascending: false)],
        animation: .default
    )
    private var allItems: FetchedResults<LibraryItem>

    @Environment(\.colorScheme) private var colorScheme
    @State private var searchText = ""
    @State private var selectedItem: LibraryItem?

    private var filteredItems: [LibraryItem] {
        if searchText.isEmpty {
            return Array(allItems)
        }
        let query = searchText.lowercased()
        return allItems.filter { item in
            (item.title?.lowercased().contains(query) == true) ||
            (item.summary?.lowercased().contains(query) == true) ||
            (item.tagsArray.contains { $0.lowercased().contains(query) })
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                Text("Archive")
                    .font(.display(40, weight: .bold))
                    .foregroundColor(Color.bubbleUpText(for: colorScheme))

                // Search Bar
                UnderlineSearchBar(text: $searchText, placeholder: "Search your archive...")

                // Masonry Grid
                if filteredItems.isEmpty {
                    emptyState
                } else {
                    MasonryLayout(columns: 2, spacing: BubbleUpTheme.gridSpacing) {
                        ForEach(filteredItems) { item in
                            LibraryCard(item: item)
                                .onTapGesture {
                                    selectedItem = item
                                }
                        }
                    }
                }
            }
            .padding(.horizontal, BubbleUpTheme.paddingHorizontal)
            .padding(.top, 12)
            .padding(.bottom, 100)
        }
        .background(Color.bubbleUpBackground(for: colorScheme))
        .paperTexture()
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $selectedItem) { item in
            ArticleDetailView(item: item)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "books.vertical")
                .font(.system(size: 48, weight: .ultraLight))
                .foregroundColor(Color.bubbleUpBorder(for: colorScheme))
                .padding(.bottom, 8)

            Text("No articles archived.")
                .font(.displayItalic(20))
                .foregroundColor(Color.bubbleUpTextMuted(for: colorScheme))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }
}

#Preview {
    NavigationStack {
        LibraryView()
    }
    .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}

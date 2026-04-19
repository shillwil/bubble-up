import SwiftUI
import CoreData

/// Archive/collection view with masonry grid and search.
struct LibraryView: View {
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \LibraryItem.createdAt, ascending: false)],
        predicate: NSPredicate(format: "syncStatus != %@", SyncStatus.pendingDelete.rawValue),
        animation: .default
    )
    private var allItems: FetchedResults<LibraryItem>

    @Environment(\.colorScheme) private var colorScheme
    @State private var searchText = ""
    @State private var selectedTag: String?
    @State private var selectedItem: LibraryItem?

    private var allTags: [String] {
        Array(Set(allItems.flatMap { $0.tagsArray.map { $0.lowercased() } })).sorted()
    }

    private var filteredItems: [LibraryItem] {
        var items = Array(allItems)
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            items = items.filter { item in
                (item.title?.lowercased().contains(query) == true) ||
                (item.summary?.lowercased().contains(query) == true) ||
                (item.tagsArray.contains { $0.lowercased().contains(query) })
            }
        }
        if let tag = selectedTag {
            items = items.filter { $0.tagsArray.contains { $0.lowercased() == tag.lowercased() } }
        }
        return items
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

                // Tag Filter
                if !allTags.isEmpty {
                    TagFilterBar(tags: allTags, selectedTag: $selectedTag)
                }

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
            if item.itemTypeEnum == .bookSummary {
                BookSummaryView(itemID: item.id!, showSaveButton: false)
            } else if item.itemTypeEnum == .image {
                ImageDetailView(item: item)
            } else if item.itemTypeEnum == .video {
                VideoDetailView(item: item)
            } else {
                ArticleDetailView(item: item)
            }
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

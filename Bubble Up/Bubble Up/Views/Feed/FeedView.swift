import SwiftUI
import CoreData

/// TikTok-style vertical snap-scroll feed of saved content.
struct FeedView: View {
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \LibraryItem.createdAt, ascending: false)],
        animation: .default
    )
    private var items: FetchedResults<LibraryItem>

    @Environment(\.colorScheme) private var colorScheme
    @State private var showAddLink = false
    @State private var showBookSummary = false
    @State private var showAddMenu = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if items.isEmpty {
                FeedEmptyState()
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(items) { item in
                            FeedCardView(item: item)
                                .containerRelativeFrame(.vertical)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging)
            }

            // Floating add button
            addButton
        }
        .background(Color.bubbleUpBackground(for: colorScheme))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showAddLink) {
            AddLinkView()
        }
        .fullScreenCover(isPresented: $showBookSummary) {
            NavigationStack {
                BookSummaryInputView(onDone: { showBookSummary = false })
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Cancel") { showBookSummary = false }
                                .foregroundColor(BubbleUpTheme.primary)
                        }
                    }
            }
        }
        .confirmationDialog("Add Content", isPresented: $showAddMenu) {
            Button("Add Link") { showAddLink = true }
            Button("Book Summary") { showBookSummary = true }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var addButton: some View {
        Button {
            showAddMenu = true
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 56, height: 56)
                .background(BubbleUpTheme.primary)
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
        }
        .padding(.trailing, BubbleUpTheme.paddingHorizontal)
        .padding(.bottom, 24)
    }
}

#Preview {
    NavigationStack {
        FeedView()
    }
    .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}

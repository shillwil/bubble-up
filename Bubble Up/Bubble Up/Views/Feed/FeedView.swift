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

    /// Number of times to repeat the feed after "All Caught Up"
    private let loopRepetitions = 3

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if items.isEmpty {
                FeedEmptyState()
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        // Original items
                        ForEach(items) { item in
                            FeedCardView(item: item)
                                .containerRelativeFrame(.vertical)
                        }

                        // "All Caught Up" divider card
                        AllCaughtUpCard()
                            .containerRelativeFrame(.vertical)

                        // Loop: repeat the archive
                        ForEach(0..<loopRepetitions, id: \.self) { repetition in
                            ForEach(items) { item in
                                FeedCardView(item: item)
                                    .containerRelativeFrame(.vertical)
                                    .id("loop-\(repetition)-\(item.id?.uuidString ?? "")")
                            }
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging)
                .ignoresSafeArea(edges: .vertical)
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
    }

    // MARK: - Add Button + Menu

    private var addButton: some View {
        Menu {
            Button {
                showAddLink = true
            } label: {
                Label("Add Link", systemImage: "link")
            }

            Button {
                showBookSummary = true
            } label: {
                Label("Book Summary", systemImage: "book.closed")
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 56, height: 56)
                .background(Color.bubbleUpText(for: colorScheme))
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
        }
        .padding(.trailing, BubbleUpTheme.paddingHorizontal)
        .padding(.bottom, 100)
    }
}

// MARK: - All Caught Up Card

private struct AllCaughtUpCard: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 56, weight: .light))
                .foregroundColor(BubbleUpTheme.primary)

            Text("All Caught Up")
                .font(.display(32, weight: .bold))
                .foregroundColor(Color.bubbleUpText(for: colorScheme))

            Text("You\u{2019}ve seen everything. Keep swiping to revisit your archive.")
                .font(.bodyText(15))
                .foregroundColor(Color.bubbleUpTextMuted(for: colorScheme))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.bubbleUpBackground(for: colorScheme))
    }
}

#Preview {
    NavigationStack {
        FeedView()
    }
    .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}

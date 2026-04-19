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
    @Environment(\.scenePhase) private var scenePhase

    /// Number of times to repeat the feed after "All Caught Up"
    private let loopRepetitions = 3

    var body: some View {
        GeometryReader { outerGeo in
            let bottomInset = outerGeo.safeAreaInsets.bottom
            ZStack {
                if items.isEmpty {
                    FeedEmptyState()
                } else {
                    ScrollViewReader { proxy in
                        ScrollView(.vertical, showsIndicators: false) {
                            LazyVStack(spacing: 0) {
                                // Original items
                                ForEach(items) { item in
                                    FeedCardView(item: item, bottomInset: bottomInset)
                                        .containerRelativeFrame(.vertical)
                                        .clipped()
                                        .id(item.id)
                                }

                                // "All Caught Up" divider card
                                AllCaughtUpCard()
                                    .containerRelativeFrame(.vertical)
                                    .clipped()

                                // Loop: repeat the archive
                                ForEach(0..<loopRepetitions, id: \.self) { repetition in
                                    ForEach(items) { item in
                                        FeedCardView(item: item, bottomInset: bottomInset)
                                            .containerRelativeFrame(.vertical)
                                            .clipped()
                                            .id("loop-\(repetition)-\(item.id?.uuidString ?? "")")
                                    }
                                }
                            }
                            .scrollTargetLayout()
                        }
                        .scrollTargetBehavior(.paging)
                        .ignoresSafeArea(edges: [.top, .bottom])
                        .onChange(of: scenePhase) { _, newPhase in
                            if newPhase == .active, let firstID = items.first?.id {
                                withAnimation(.none) {
                                    proxy.scrollTo(firstID, anchor: .top)
                                }
                            }
                        }
                    }
                }
            }
            .background(Color.bubbleUpBackground(for: colorScheme))
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .ignoresSafeArea(edges: [.top, .bottom])
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

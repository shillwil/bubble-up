import SwiftUI
import CoreData

/// Displays a generated book summary (short or full mode).
/// Observes Core Data changes so the UI updates when the scheduler writes the summary.
struct BookSummaryView: View {
    let itemID: UUID
    var onDone: (() -> Void)?

    @FetchRequest private var items: FetchedResults<LibraryItem>
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @State private var showSavedConfirmation = false

    init(itemID: UUID, onDone: (() -> Void)? = nil) {
        self.itemID = itemID
        self.onDone = onDone
        self._items = FetchRequest(
            sortDescriptors: [],
            predicate: NSPredicate(format: "id == %@", itemID as CVarArg)
        )
    }

    private var item: LibraryItem? { items.first }

    var body: some View {
        Group {
            if let item {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        header(for: item)
                        summaryContent(for: item)

                        // Save / Done button (shown when summary is complete)
                        if item.summaryStatusEnum == .completed {
                            Button {
                                showSavedConfirmation = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                    if let onDone {
                                        onDone()
                                    } else {
                                        dismiss()
                                    }
                                }
                            } label: {
                                Text(showSavedConfirmation ? "SAVED TO LIBRARY" : "SAVE & CLOSE")
                                    .font(.buttonText())
                                    .tracking(1.5)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 16)
                                    .background(showSavedConfirmation ? Color.green : BubbleUpTheme.primary)
                                    .foregroundColor(.white)
                                    .clipShape(RoundedRectangle(cornerRadius: BubbleUpTheme.cornerRadiusSm))
                                    .animation(.easeInOut, value: showSavedConfirmation)
                            }
                            .disabled(showSavedConfirmation)
                        }
                    }
                    .padding(.horizontal, BubbleUpTheme.paddingHorizontal)
                    .padding(.top, 24)
                    .padding(.bottom, 60)
                }
            } else {
                LoadingStateView("Loading summary")
            }
        }
        .background(Color.bubbleUpBackground(for: colorScheme))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") {
                    if let onDone {
                        onDone()
                    } else {
                        dismiss()
                    }
                }
                .foregroundColor(BubbleUpTheme.primary)
            }
        }
    }

    // MARK: - Header

    private func header(for item: LibraryItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(item.title ?? "Book Summary")
                .font(.display(32, weight: .bold))
                .foregroundColor(Color.bubbleUpText(for: colorScheme))

            if let author = item.authorName {
                Text(author.uppercased())
                    .font(.metaLabel(13))
                    .tracking(1.5)
                    .foregroundColor(Color.bubbleUpTextMuted(for: colorScheme))
            }

            Text("BOOK SUMMARY")
                .font(.metaLabel(12))
                .tracking(2)
                .foregroundColor(Color.bubbleUpTextMuted(for: colorScheme))
        }
    }

    // MARK: - Content

    @ViewBuilder
    private func summaryContent(for item: LibraryItem) -> some View {
        switch item.summaryStatusEnum {
        case .completed:
            // Elevator pitch as blockquote
            if let firstBullet = item.summaryBulletsArray.first, !firstBullet.isEmpty {
                ArticleBlockquote(text: firstBullet)
            }

            // Full summary
            if let summary = item.summary, !summary.isEmpty {
                Text(summary)
                    .font(.bodyText(17))
                    .foregroundColor(Color.bubbleUpText(for: colorScheme))
                    .lineSpacing(8)
            }

            // Pages
            let pages = item.orderedPages
            if !pages.isEmpty {
                Divider().padding(.vertical, 8)

                Text("Key Ideas")
                    .font(.display(24, weight: .bold))
                    .foregroundColor(Color.bubbleUpText(for: colorScheme))

                ForEach(pages) { page in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(page.pageTitle ?? "")
                            .font(.display(20, weight: .bold))
                            .foregroundColor(Color.bubbleUpText(for: colorScheme))

                        Text(page.content ?? "")
                            .font(.bodyText(17))
                            .foregroundColor(Color.bubbleUpText(for: colorScheme))
                            .lineSpacing(6)
                    }
                    .padding(.vertical, 8)
                }
            }

        case .pending, .generating:
            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(BubbleUpTheme.textMuted)

                Text("GENERATING SUMMARY")
                    .font(.metaLabel(12))
                    .tracking(2)
                    .foregroundColor(Color.bubbleUpTextMuted(for: colorScheme))

                Text("This may take up to 30 seconds")
                    .font(.bodyText(14))
                    .foregroundColor(Color.bubbleUpTextMuted(for: colorScheme))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 80)

        case .failed:
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 32, weight: .light))
                    .foregroundColor(BubbleUpTheme.primary)

                Text("Summary generation failed")
                    .font(.bodyText(15))
                    .foregroundColor(Color.bubbleUpTextMuted(for: colorScheme))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 60)
        }
    }
}

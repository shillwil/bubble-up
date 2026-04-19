import SwiftUI

/// Input screen for requesting a book summary.
struct BookSummaryInputView: View {
    var onDone: (() -> Void)?

    @Environment(LibraryItemsRepository.self) private var repository
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    @State private var bookTitle = ""
    @State private var author = ""
    @State private var summaryLength: SummaryLength = .full
    @State private var isGenerating = false
    @State private var generatedItemID: UUID?
    @State private var showDuplicateMessage = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                // Header
                Text("Book Summary")
                    .font(.display(32, weight: .bold))
                    .foregroundColor(Color.bubbleUpText(for: colorScheme))

                Text("Generate a Blinkist-style breakdown of any book's key ideas.")
                    .font(.bodyText(15))
                    .foregroundColor(Color.bubbleUpTextMuted(for: colorScheme))

                // Form
                VStack(spacing: 20) {
                    underlineField("BOOK TITLE", text: $bookTitle)
                    underlineField("AUTHOR (OPTIONAL)", text: $author)
                }

                // Length Picker
                VStack(alignment: .leading, spacing: 8) {
                    Text("SUMMARY LENGTH")
                        .font(.system(size: 12, weight: .semibold))
                        .tracking(1.5)

                    Picker("", selection: $summaryLength) {
                        Text("Short").tag(SummaryLength.short)
                        Text("Full").tag(SummaryLength.full)
                    }
                    .pickerStyle(.segmented)
                }

                // Generate Button
                Button {
                    generateSummary()
                } label: {
                    Group {
                        if isGenerating {
                            ProgressView().tint(.white)
                        } else {
                            Text("GENERATE SUMMARY")
                                .font(.buttonText())
                                .tracking(1.5)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(BubbleUpTheme.primary)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: BubbleUpTheme.cornerRadiusSm))
                }
                .disabled(bookTitle.isEmpty || isGenerating)
            }
            .padding(.horizontal, BubbleUpTheme.paddingHorizontal)
            .padding(.top, 24)
        }
        .background(Color.bubbleUpBackground(for: colorScheme))
        .navigationDestination(item: $generatedItemID) { itemID in
            BookSummaryView(
                itemID: itemID,
                showSaveButton: !showDuplicateMessage,
                onDone: onDone
            )
        }
    }

    private func underlineField(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .tracking(1.5)
                .foregroundColor(Color.bubbleUpTextMuted(for: colorScheme))

            TextField("", text: text)
                .font(.bodyText())
                .padding(.bottom, 8)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(Color.bubbleUpBorder(for: colorScheme))
                        .frame(height: 1)
                }
        }
    }

    private func generateSummary() {
        isGenerating = true
        let result = repository.saveBookSummaryRequest(
            title: bookTitle,
            author: author.isEmpty ? nil : author,
            length: summaryLength
        )

        if result.isExisting {
            showDuplicateMessage = true
        }

        generatedItemID = result.id
        isGenerating = false
    }
}

#Preview {
    NavigationStack {
        BookSummaryInputView()
    }
}

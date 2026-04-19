import SwiftUI

/// Sheet for adding a link directly in-app.
struct AddLinkView: View {
    @Environment(LibraryItemsRepository.self) private var repository
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    @State private var urlText = ""
    @State private var tagsText = ""
    @State private var isSaving = false
    @State private var showDuplicateMessage = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("Add Link")
                        .font(.display(32, weight: .bold))
                        .foregroundColor(Color.bubbleUpText(for: colorScheme))

                    Text("Paste a URL to save it to your feed. An AI summary will be generated automatically.")
                        .font(.bodyText(15))
                        .foregroundColor(Color.bubbleUpTextMuted(for: colorScheme))

                    // URL field
                    VStack(alignment: .leading, spacing: 6) {
                        Text("URL")
                            .font(.system(size: 12, weight: .semibold))
                            .tracking(1.5)
                            .foregroundColor(Color.bubbleUpTextMuted(for: colorScheme))

                        TextField("https://...", text: $urlText)
                            .font(.bodyText())
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(.bottom, 8)
                            .overlay(alignment: .bottom) {
                                Rectangle()
                                    .fill(Color.bubbleUpBorder(for: colorScheme))
                                    .frame(height: 1)
                            }
                    }

                    // Tags field
                    VStack(alignment: .leading, spacing: 6) {
                        Text("TAGS (OPTIONAL)")
                            .font(.system(size: 12, weight: .semibold))
                            .tracking(1.5)
                            .foregroundColor(Color.bubbleUpTextMuted(for: colorScheme))

                        TextField("tech, design, reading...", text: $tagsText)
                            .font(.bodyText())
                            .autocorrectionDisabled()
                            .padding(.bottom, 8)
                            .overlay(alignment: .bottom) {
                                Rectangle()
                                    .fill(Color.bubbleUpBorder(for: colorScheme))
                                    .frame(height: 1)
                            }
                    }

                    // Save button
                    Button {
                        saveLink()
                    } label: {
                        Group {
                            if isSaving {
                                ProgressView().tint(.white)
                            } else {
                                Text("SAVE TO FEED")
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
                    .disabled(urlText.isEmpty || isSaving)

                    // Paste from clipboard
                    Button {
                        if let clipboard = UIPasteboard.general.string {
                            urlText = clipboard
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "doc.on.clipboard")
                            Text("PASTE FROM CLIPBOARD")
                                .font(.system(size: 13, weight: .semibold))
                                .tracking(1)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .overlay {
                            RoundedRectangle(cornerRadius: BubbleUpTheme.cornerRadiusSm)
                                .stroke(Color.bubbleUpBorder(for: colorScheme), lineWidth: 1)
                        }
                        .foregroundColor(Color.bubbleUpText(for: colorScheme))
                    }
                }
                .padding(.horizontal, BubbleUpTheme.paddingHorizontal)
                .padding(.top, 24)
            }
            .background(Color.bubbleUpBackground(for: colorScheme))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(BubbleUpTheme.primary)
                }
            }
            .overlay {
                if showDuplicateMessage {
                    VStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(BubbleUpTheme.primary)
                        Text("Already in your library")
                            .font(.bodyText(15))
                            .foregroundColor(Color.bubbleUpText(for: colorScheme))
                    }
                    .padding(24)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .transition(.opacity)
                }
            }
            .animation(.easeInOut, value: showDuplicateMessage)
        }
    }

    private func saveLink() {
        let tags = tagsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        // Ensure URL has a scheme
        var finalURL = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !finalURL.hasPrefix("http://") && !finalURL.hasPrefix("https://") {
            finalURL = "https://" + finalURL
        }

        isSaving = true
        let result = repository.saveLink(url: finalURL, tags: tags)

        if result.isExisting {
            showDuplicateMessage = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                dismiss()
            }
        } else {
            dismiss()
        }
    }
}

#Preview {
    AddLinkView()
}

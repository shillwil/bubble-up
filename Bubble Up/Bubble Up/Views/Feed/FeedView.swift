import SwiftUI
import CoreData
import PhotosUI

/// TikTok-style vertical snap-scroll feed of saved content.
struct FeedView: View {
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \LibraryItem.createdAt, ascending: false)],
        animation: .default
    )
    private var items: FetchedResults<LibraryItem>

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @Environment(LibraryItemsRepository.self) private var repository
    @State private var showAddLink = false
    @State private var showBookSummary = false
    @State private var showAddMenu = false
    @State private var showDocumentPicker = false
    @State private var showPhotoPicker = false
    @State private var selectedPhotoItem: PhotosPickerItem?

    /// Number of times to repeat the feed after "All Caught Up"
    private let loopRepetitions = 3

    var body: some View {
        GeometryReader { outerGeo in
            let bottomInset = outerGeo.safeAreaInsets.bottom
            ZStack(alignment: .bottomTrailing) {
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

            // Floating add button
            addButton
        }
        .background(Color.bubbleUpBackground(for: colorScheme))
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .ignoresSafeArea(edges: [.top, .bottom])
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
        .fileImporter(isPresented: $showDocumentPicker, allowedContentTypes: [.pdf]) { result in
            switch result {
            case .success(let url):
                importFile(from: url, contentType: "pdf", mimeType: "application/pdf")
            case .failure(let error):
                print("Document picker error: \(error)")
            }
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $selectedPhotoItem, matching: .any(of: [.images, .videos]))
        .onChange(of: selectedPhotoItem) { _, newItem in
            guard let newItem else { return }
            Task {
                await importPhotoItem(newItem)
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

            Button {
                showDocumentPicker = true
            } label: {
                Label("Import PDF", systemImage: "doc.fill")
            }

            Button {
                showPhotoPicker = true
            } label: {
                Label("Photo / Video", systemImage: "photo.on.rectangle")
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(Color.bubbleUpBackground(for: colorScheme))
                .frame(width: 56, height: 56)
                .background(Color.bubbleUpText(for: colorScheme))
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
        }
        .padding(.trailing, BubbleUpTheme.paddingHorizontal)
        .padding(.bottom, 100)
    }

    // MARK: - File Import Helpers

    private func importFile(from url: URL, contentType: String, mimeType: String) {
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }

        let ext = url.pathExtension.isEmpty ? "pdf" : url.pathExtension
        let fileName = UUID().uuidString + "." + ext
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Config.appGroupIdentifier) else { return }

        let sharedDir = containerURL.appendingPathComponent("SharedFiles")
        try? FileManager.default.createDirectory(at: sharedDir, withIntermediateDirectories: true)
        let destURL = sharedDir.appendingPathComponent(fileName)

        do {
            try FileManager.default.copyItem(at: url, to: destURL)
            let pending = SharedPendingItem(title: url.lastPathComponent, localFileName: fileName, contentMimeType: mimeType)
            SharedPendingItemStore.save(pending)
            repository.importPendingSharedItems()
        } catch {
            print("File import failed: \(error)")
        }
    }

    private func importPhotoItem(_ item: PhotosPickerItem) async {
        if let data = try? await item.loadTransferable(type: Data.self) {
            let isVideo = item.supportedContentTypes.contains(where: { $0.conforms(to: .movie) })
            let ext = isVideo ? "mp4" : "jpg"
            let mimeType = isVideo ? "video/mp4" : "image/jpeg"
            let fileName = UUID().uuidString + "." + ext

            guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Config.appGroupIdentifier) else { return }
            let sharedDir = containerURL.appendingPathComponent("SharedFiles")
            try? FileManager.default.createDirectory(at: sharedDir, withIntermediateDirectories: true)
            let destURL = sharedDir.appendingPathComponent(fileName)

            do {
                try data.write(to: destURL)
                let pending = SharedPendingItem(title: nil, localFileName: fileName, contentMimeType: mimeType)
                SharedPendingItemStore.save(pending)
                await MainActor.run {
                    repository.importPendingSharedItems()
                }
            } catch {
                print("Photo import failed: \(error)")
            }
        }
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

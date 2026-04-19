import SwiftUI
import CoreData
import PhotosUI

struct MainTabView: View {
    @State private var selectedTab: AppTab = .feed
    @State private var showAddMenu = false
    @State private var showAddLink = false
    @State private var showBookSummary = false
    @State private var showDocumentPicker = false
    @State private var showPhotoPicker = false
    @State private var selectedPhotoItem: PhotosPickerItem?

    @Environment(LibraryItemsRepository.self) private var repository

    enum AppTab: String {
        case feed, library, settings, add
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("FEED", systemImage: "rectangle.stack", value: AppTab.feed) {
                NavigationStack {
                    FeedView()
                }
            }

            Tab("LIBRARY", systemImage: "book", value: AppTab.library) {
                NavigationStack {
                    LibraryView()
                }
            }

            Tab("SETTINGS", systemImage: "gearshape", value: AppTab.settings) {
                NavigationStack {
                    ProfileView()
                }
            }

            Tab("Add", systemImage: "plus", value: AppTab.add, role: .search) {
                Color.clear
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .onChange(of: selectedTab) { oldValue, newValue in
            if newValue == .add {
                selectedTab = oldValue
                showAddMenu = true
            }
        }
        .tint(BubbleUpTheme.primary)
        .confirmationDialog("Add Content", isPresented: $showAddMenu) {
            Button("Add Link") { showAddLink = true }
            Button("Book Summary") { showBookSummary = true }
            Button("Import PDF") { showDocumentPicker = true }
            Button("Photo / Video") { showPhotoPicker = true }
        }
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

#Preview {
    MainTabView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}

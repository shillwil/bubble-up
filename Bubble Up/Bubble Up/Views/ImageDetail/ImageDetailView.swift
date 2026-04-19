import SwiftUI

/// Full-screen image display with pinch-to-zoom.
struct ImageDetailView: View {
    @ObservedObject var item: LibraryItem
    @Environment(\.colorScheme) private var colorScheme
    @State private var scale: CGFloat = 1.0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Image
                if let thumbnailData = item.thumbnailData,
                   let uiImage = UIImage(data: thumbnailData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: BubbleUpTheme.cornerRadiusSm))
                        .scaleEffect(scale)
                        .gesture(
                            MagnifyGesture()
                                .onChanged { value in
                                    scale = value.magnification
                                }
                                .onEnded { _ in
                                    withAnimation { scale = 1.0 }
                                }
                        )
                }

                // Title
                Text(item.title ?? "Image")
                    .font(.display(24, weight: .bold))
                    .foregroundColor(Color.bubbleUpText(for: colorScheme))

                // Tags
                if !item.tagsArray.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(item.tagsArray, id: \.self) { tag in
                            TagPill(label: tag)
                        }
                    }
                }

                // OCR text if available
                if let rawContent = item.rawContent, !rawContent.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Extracted Text")
                            .font(.display(20, weight: .bold))
                            .foregroundColor(Color.bubbleUpText(for: colorScheme))

                        Text(rawContent)
                            .font(.bodyText(15))
                            .foregroundColor(Color.bubbleUpText(for: colorScheme))
                            .lineSpacing(6)
                    }
                }
            }
            .padding(.horizontal, BubbleUpTheme.paddingHorizontal)
            .padding(.top, 16)
            .padding(.bottom, 60)
        }
        .background(Color.bubbleUpBackground(for: colorScheme))
        .navigationBarBackButtonHidden(false)
    }
}

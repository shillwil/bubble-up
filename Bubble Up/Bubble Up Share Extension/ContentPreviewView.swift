import SwiftUI

struct ContentPreviewView: View {
    let previewState: PreviewState
    let contentType: String
    let title: String
    var onTap: () -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch previewState {
                case .idle, .loading:
                    Rectangle()
                        .fill(Color(hex: 0xE5E4E0))
                        .shimmer()
                case .loaded(let image):
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                case .failed:
                    fallbackPreview
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()

            // Bottom gradient fading into the sheet background
            LinearGradient(
                colors: [.clear, Color(hex: 0xF5F4F0)],
                startPoint: .init(x: 0.5, y: 0.0),
                endPoint: .bottom
            )
            .frame(height: 60)
        }
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
    }

    private var fallbackPreview: some View {
        VStack(spacing: 12) {
            Image(systemName: fallbackIcon)
                .font(.system(size: 48))
                .foregroundColor(Color(hex: 0x82817D))
            if !title.isEmpty {
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(Color(hex: 0x82817D))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(hex: 0xE5E4E0))
    }

    private var fallbackIcon: String {
        switch contentType {
        case "pdf": return "doc.fill"
        case "image": return "photo.fill"
        case "video": return "video.fill"
        default: return "link"
        }
    }
}

// Standalone Color hex init for the extension
private extension Color {
    init(hex: UInt, alpha: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

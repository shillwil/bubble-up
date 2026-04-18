import SwiftUI

struct ShareExtensionView: View {
    @Binding var sharedURL: String
    @Binding var sharedTitle: String
    var onSave: (String, String?, [String]) -> Void
    var onCancel: () -> Void

    @State private var tagsText: String = ""
    @State private var isSaved = false

    var body: some View {
        ZStack {
            // Dimmed background
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture { onCancel() }

            // Bottom sheet
            VStack {
                Spacer()
                sheetContent
            }
        }
    }

    private var sheetContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Drag handle
            HStack {
                Spacer()
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(hex: 0xE5E4E0))
                    .frame(width: 40, height: 4)
                Spacer()
            }
            .padding(.top, 8)
            .padding(.bottom, 20)

            // Title
            Text(isSaved ? "Saved!" : "Saving to Library...")
                .font(.system(size: 24, weight: .bold, design: .serif))
                .foregroundColor(Color(hex: 0x111111))
                .padding(.bottom, 20)

            // Link preview
            if !sharedURL.isEmpty {
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color(hex: 0xE5E4E0))
                        .frame(width: 48, height: 48)
                        .overlay {
                            Image(systemName: "link")
                                .font(.system(size: 18))
                                .foregroundColor(Color(hex: 0x82817D))
                        }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(sharedTitle.isEmpty ? sharedURL : sharedTitle)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(Color(hex: 0x1A1A1A))
                            .lineLimit(1)

                        Text(domainFrom(sharedURL).uppercased())
                            .font(.system(size: 13))
                            .tracking(1)
                            .foregroundColor(Color(hex: 0x82817D))
                            .lineLimit(1)
                    }

                    Spacer()
                }
                .padding(.bottom, 16)
            }

            // Tag input
            TextField("Add tags, comma separated...", text: $tagsText)
                .font(.system(size: 15))
                .foregroundColor(Color(hex: 0x1A1A1A))
                .padding(.bottom, 8)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(Color(hex: 0xE5E4E0))
                        .frame(height: 1)
                }
                .padding(.bottom, 16)

            // Save button
            Button {
                let tags = tagsText
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                onSave(sharedURL, sharedTitle.isEmpty ? nil : sharedTitle, tags)
                isSaved = true
            } label: {
                Text("SAVE")
                    .font(.system(size: 15, weight: .bold))
                    .tracking(1.5)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color(hex: 0xDA2D16))
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 2))
            }
            .disabled(sharedURL.isEmpty)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 32)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(hex: 0xF5F4F0))
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private func domainFrom(_ urlString: String) -> String {
        guard let url = URL(string: urlString) else { return urlString }
        return url.host?.replacingOccurrences(of: "www.", with: "") ?? urlString
    }
}

// Standalone Color hex init for the extension (can't import main app's theme)
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

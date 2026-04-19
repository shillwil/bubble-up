import SwiftUI

struct ShareExtensionView: View {
    @Binding var sharedURL: String
    @Binding var sharedTitle: String
    @Binding var contentType: String
    @Binding var localFileName: String?
    var previewState: PreviewState
    var onSave: (String?, String?, [String], String?, String?, String?) -> Void
    var onCancel: () -> Void

    @State private var tagsText: String = ""
    @State private var notesText: String = ""
    @State private var isSaved = false

    var body: some View {
        VStack(spacing: 0) {
            // Content preview area
            ContentPreviewView(
                previewState: previewState,
                contentType: contentType,
                title: sharedTitle,
                onTap: { onCancel() }
            )

            // Bottom sheet
            sheetContent
        }
        .ignoresSafeArea(edges: .top)
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
            Text(isSaved ? "Saved! Generating summary..." : contentType == "link" ? "Saving to Library..." : "Saving \(contentType.capitalized)...")
                .font(.system(size: 24, weight: .bold, design: .serif))
                .foregroundColor(Color(hex: 0x111111))
                .padding(.bottom, 20)

            // Content preview
            if contentType == "link" && !sharedURL.isEmpty {
                // Existing URL preview
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
            } else if contentType == "pdf" {
                filePreviewRow(icon: "doc.fill", label: sharedTitle.isEmpty ? "PDF Document" : sharedTitle, typeLabel: "PDF")
            } else if contentType == "image" {
                filePreviewRow(icon: "photo.fill", label: sharedTitle.isEmpty ? "Image" : sharedTitle, typeLabel: "IMAGE")
            } else if contentType == "video" {
                filePreviewRow(icon: "video.fill", label: sharedTitle.isEmpty ? "Video" : sharedTitle, typeLabel: "VIDEO")
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

            // Notes input
            TextField("Add a note (optional)", text: $notesText, axis: .vertical)
                .font(.system(size: 15))
                .foregroundColor(Color(hex: 0x1A1A1A))
                .lineLimit(1...3)
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
                let mimeType: String? = {
                    switch contentType {
                    case "pdf": return "application/pdf"
                    case "image": return "image/jpeg"
                    case "video": return "video/mp4"
                    default: return nil
                    }
                }()
                let urlToSave = contentType == "link" ? sharedURL : nil
                onSave(urlToSave, sharedTitle.isEmpty ? nil : sharedTitle, tags, localFileName, mimeType, notesText.isEmpty ? nil : notesText)
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
            .disabled(contentType == "link" ? sharedURL.isEmpty : localFileName == nil)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 32)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(hex: 0xF5F4F0))
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private func filePreviewRow(icon: String, label: String, typeLabel: String) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(hex: 0xE5E4E0))
                .frame(width: 48, height: 48)
                .overlay {
                    Image(systemName: icon)
                        .font(.system(size: 18))
                        .foregroundColor(Color(hex: 0x82817D))
                }
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(Color(hex: 0x1A1A1A))
                    .lineLimit(1)
                Text(typeLabel)
                    .font(.system(size: 13))
                    .tracking(1)
                    .foregroundColor(Color(hex: 0x82817D))
            }
            Spacer()
        }
        .padding(.bottom, 16)
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

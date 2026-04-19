import SwiftUI

/// Admin-only screen for generating F&F invite codes.
struct GenerateInviteCodeView: View {
    @Environment(AuthService.self) private var authService
    @Environment(\.colorScheme) private var colorScheme

    @State private var name = ""
    @State private var isGenerating = false
    @State private var generatedCode: String?
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                Text("Generate Invite Code")
                    .font(.display(32, weight: .bold))
                    .foregroundColor(Color.bubbleUpText(for: colorScheme))

                Text("Create a Friends & Family invite code for someone. The code will follow the format BUBBLEUP-NAME-001.")
                    .font(.bodyText(15))
                    .foregroundColor(Color.bubbleUpTextMuted(for: colorScheme))

                // Name Field
                VStack(alignment: .leading, spacing: 8) {
                    Text("NAME")
                        .font(.system(size: 12, weight: .semibold))
                        .tracking(1.5)

                    TextField("e.g. SCOTT", text: $name)
                        .font(.bodyText())
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .padding(.bottom, 8)
                        .overlay(alignment: .bottom) {
                            Rectangle()
                                .fill(Color.bubbleUpBorder(for: colorScheme))
                                .frame(height: 1)
                        }
                }

                // Error Message
                if let errorMessage {
                    HStack(spacing: 8) {
                        Image(systemName: "xmark.circle.fill")
                        Text(errorMessage)
                    }
                    .font(.bodyText(14))
                    .foregroundColor(BubbleUpTheme.primary)
                }

                // Generated Code Display
                if let generatedCode {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("GENERATED CODE")
                            .font(.system(size: 12, weight: .semibold))
                            .tracking(1.5)

                        HStack {
                            Text(generatedCode)
                                .font(.bodyText(18))
                                .foregroundColor(Color.bubbleUpText(for: colorScheme))

                            Spacer()

                            Button {
                                UIPasteboard.general.string = generatedCode
                            } label: {
                                Image(systemName: "doc.on.doc")
                                    .font(.system(size: 16))
                                    .foregroundColor(BubbleUpTheme.primary)
                            }
                        }
                        .padding(16)
                        .background(Color.bubbleUpSurface(for: colorScheme))
                        .clipShape(RoundedRectangle(cornerRadius: BubbleUpTheme.cornerRadiusMd))
                        .overlay(
                            RoundedRectangle(cornerRadius: BubbleUpTheme.cornerRadiusMd)
                                .stroke(Color.bubbleUpBorder(for: colorScheme), lineWidth: 1)
                        )
                    }
                }

                // Generate Button
                Button {
                    generateCode()
                } label: {
                    Group {
                        if isGenerating {
                            ProgressView().tint(.white)
                        } else {
                            Text("GENERATE CODE")
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
                .disabled(name.isEmpty || isGenerating)
            }
            .padding(.horizontal, BubbleUpTheme.paddingHorizontal)
            .padding(.top, 24)
        }
        .background(Color.bubbleUpBackground(for: colorScheme))
    }

    private func generateCode() {
        isGenerating = true
        errorMessage = nil
        generatedCode = nil

        Task {
            do {
                let code = try await authService.generateInviteCode(name: name)
                generatedCode = code
            } catch {
                errorMessage = error.localizedDescription
            }
            isGenerating = false
        }
    }
}

#Preview {
    NavigationStack {
        GenerateInviteCodeView()
    }
    .environment(AuthService(keychainService: KeychainService()))
}

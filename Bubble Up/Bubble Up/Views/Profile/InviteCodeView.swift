import SwiftUI

/// F&F invite code redemption screen.
struct InviteCodeView: View {
    @Environment(AuthService.self) private var authService
    @Environment(\.colorScheme) private var colorScheme

    @State private var inviteCode = ""
    @State private var isValidating = false
    @State private var statusMessage: String?
    @State private var isSuccess = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                Text("Invite Code")
                    .font(.display(32, weight: .bold))
                    .foregroundColor(Color.bubbleUpText(for: colorScheme))

                Text("Enter a Friends & Family invite code to unlock AI summaries without needing your own API keys.")
                    .font(.bodyText(15))
                    .foregroundColor(Color.bubbleUpTextMuted(for: colorScheme))

                // Invite Code Field
                VStack(alignment: .leading, spacing: 8) {
                    Text("CODE")
                        .font(.system(size: 12, weight: .semibold))
                        .tracking(1.5)

                    TextField("BUBBLEUP-XXXX-000", text: $inviteCode)
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

                // Status Message
                if let statusMessage {
                    HStack(spacing: 8) {
                        Image(systemName: isSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                        Text(statusMessage)
                    }
                    .font(.bodyText(14))
                    .foregroundColor(isSuccess ? .green : BubbleUpTheme.primary)
                }

                // Redeem Button
                Button {
                    redeemCode()
                } label: {
                    Group {
                        if isValidating {
                            ProgressView().tint(.white)
                        } else {
                            Text("REDEEM CODE")
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
                .disabled(inviteCode.isEmpty || isValidating)

                // F&F status
                if authService.isFriendsAndFamily {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundColor(.green)
                        Text("Friends & Family access active")
                            .font(.bodyText(14))
                    }
                    .padding(.top, 8)
                }
            }
            .padding(.horizontal, BubbleUpTheme.paddingHorizontal)
            .padding(.top, 24)
        }
        .background(Color.bubbleUpBackground(for: colorScheme))
    }

    private func redeemCode() {
        isValidating = true
        statusMessage = nil

        Task {
            do {
                let isValid = try await authService.validateInviteCode(inviteCode)
                if isValid {
                    statusMessage = "Code redeemed successfully!"
                    isSuccess = true
                } else {
                    statusMessage = "Invalid or already claimed code"
                    isSuccess = false
                }
            } catch {
                statusMessage = error.localizedDescription
                isSuccess = false
            }
            isValidating = false
        }
    }
}

#Preview {
    NavigationStack {
        InviteCodeView()
    }
    .environment(AuthService(keychainService: KeychainService()))
}

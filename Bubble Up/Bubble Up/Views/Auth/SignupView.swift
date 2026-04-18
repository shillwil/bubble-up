import SwiftUI

struct SignupView: View {
    @Environment(AuthService.self) private var authService
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var inviteCode = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                Spacer(minLength: 40)

                // Header
                VStack(spacing: 8) {
                    Text("Create Account")
                        .font(.display(32, weight: .bold))
                        .foregroundColor(Color.bubbleUpText(for: colorScheme))

                    Text("JOIN THE READING REVOLUTION")
                        .font(.metaLabel(12))
                        .tracking(2)
                        .foregroundColor(Color.bubbleUpTextMuted(for: colorScheme))
                }

                // Form Fields
                VStack(spacing: 20) {
                    underlineField(label: "EMAIL", text: $email)
                        .textContentType(.emailAddress)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)

                    underlineField(label: "PASSWORD", text: $password, isSecure: true)
                        .textContentType(.newPassword)

                    underlineField(label: "CONFIRM PASSWORD", text: $confirmPassword, isSecure: true)
                        .textContentType(.newPassword)

                    underlineField(label: "INVITE CODE (OPTIONAL)", text: $inviteCode)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                }

                // Error
                if let errorMessage {
                    Text(errorMessage)
                        .font(.bodyText(14))
                        .foregroundColor(BubbleUpTheme.primary)
                }

                // Sign Up Button
                Button {
                    signUp()
                } label: {
                    Group {
                        if isLoading {
                            ProgressView().tint(.white)
                        } else {
                            Text("CREATE ACCOUNT")
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
                .disabled(isLoading || !isFormValid)

                Spacer()
            }
            .padding(.horizontal, BubbleUpTheme.paddingHorizontal)
        }
        .background(Color.bubbleUpBackground(for: colorScheme))
        .navigationBarBackButtonHidden(false)
    }

    // MARK: - Helpers

    private var isFormValid: Bool {
        !email.isEmpty && !password.isEmpty && password == confirmPassword && password.count >= 8
    }

    @ViewBuilder
    private func underlineField(label: String, text: Binding<String>, isSecure: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.metaLabel(11))
                .tracking(1.5)
                .foregroundColor(Color.bubbleUpTextMuted(for: colorScheme))

            Group {
                if isSecure {
                    SecureField("", text: text)
                } else {
                    TextField("", text: text)
                }
            }
            .font(.bodyText())
            .padding(.bottom, 8)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Color.bubbleUpBorder(for: colorScheme))
                    .frame(height: 1)
            }
        }
    }

    private func signUp() {
        guard password == confirmPassword else {
            errorMessage = "Passwords don't match"
            return
        }

        isLoading = true
        errorMessage = nil
        Task {
            do {
                try await authService.signUpWithEmail(
                    email,
                    password: password,
                    inviteCode: inviteCode.isEmpty ? nil : inviteCode
                )
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }
}

#Preview {
    NavigationStack {
        SignupView()
    }
    .environment(AuthService(keychainService: KeychainService()))
}

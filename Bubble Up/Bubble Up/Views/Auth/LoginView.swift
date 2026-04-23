import SwiftUI

struct LoginView: View {
    @Environment(AuthService.self) private var authService
    @Environment(\.colorScheme) private var colorScheme

    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showSignup = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 32) {
                    Spacer(minLength: 60)

                    // App Title
                    VStack(spacing: 8) {
                        Text("Bubble Up")
                            .font(.display(40, weight: .bold))
                            .foregroundColor(Color.bubbleUpText(for: colorScheme))

                        Text("YOUR READING, REDISCOVERED")
                            .font(.metaLabel(12))
                            .tracking(2)
                            .foregroundColor(Color.bubbleUpTextMuted(for: colorScheme))
                    }

                    Spacer(minLength: 40)

                    // Login Form
                    VStack(spacing: 20) {
                        // Email Field
                        VStack(alignment: .leading, spacing: 6) {
                            Text("EMAIL")
                                .font(.metaLabel(11))
                                .tracking(1.5)
                                .foregroundColor(Color.bubbleUpTextMuted(for: colorScheme))

                            TextField("", text: $email)
                                .textContentType(.emailAddress)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                .keyboardType(.emailAddress)
                                .font(.bodyText())
                                .padding(.bottom, 8)
                                .overlay(alignment: .bottom) {
                                    Rectangle()
                                        .fill(Color.bubbleUpBorder(for: colorScheme))
                                        .frame(height: 1)
                                }
                        }

                        // Password Field
                        VStack(alignment: .leading, spacing: 6) {
                            Text("PASSWORD")
                                .font(.metaLabel(11))
                                .tracking(1.5)
                                .foregroundColor(Color.bubbleUpTextMuted(for: colorScheme))

                            SecureField("", text: $password)
                                .textContentType(.password)
                                .font(.bodyText())
                                .padding(.bottom, 8)
                                .overlay(alignment: .bottom) {
                                    Rectangle()
                                        .fill(Color.bubbleUpBorder(for: colorScheme))
                                        .frame(height: 1)
                                }
                        }
                    }

                    // Error Message
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.bodyText(14))
                            .foregroundColor(BubbleUpTheme.primary)
                    }

                    // Sign In Button
                    Button {
                        signIn()
                    } label: {
                        Group {
                            if isLoading {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Text("SIGN IN")
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
                    .disabled(isLoading || email.isEmpty || password.isEmpty)

                    // Sign Up Link
                    Button {
                        showSignup = true
                    } label: {
                        Text("Don't have an account? ")
                            .foregroundColor(Color.bubbleUpTextMuted(for: colorScheme))
                        + Text("Sign Up")
                            .foregroundColor(BubbleUpTheme.primary)
                            .bold()
                    }
                    .font(.bodyText(15))

                    Spacer()
                }
                .padding(.horizontal, BubbleUpTheme.paddingHorizontal)
            }
            .background(Color.bubbleUpBackground(for: colorScheme))
            .navigationDestination(isPresented: $showSignup) {
                SignupView()
            }
        }
    }

    // MARK: - Actions

    private func signIn() {
        isLoading = true
        errorMessage = nil
        Task {
            do {
                try await authService.signInWithEmail(email, password: password)
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    private func signInWithApple() {
        Task {
            do {
                try await authService.signInWithApple()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

#Preview {
    LoginView()
        .environment(AuthService(keychainService: KeychainService()))
}

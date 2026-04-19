import SwiftUI

/// Profile and settings screen matching the editorial mock.
struct ProfileView: View {
    @Environment(AuthService.self) private var authService
    @Environment(\.colorScheme) private var colorScheme

    @AppStorage("typographySize") private var typographySize: Double = 16
    @AppStorage("appearanceMode") private var appearanceMode = "system"
    @AppStorage("dailyDigest") private var dailyDigest = true

    @State private var showAPIKeyManagement = false
    @State private var showInviteCode = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Profile Header
                profileHeader
                    .padding(.bottom, 32)

                // Stats Row
                statsRow
                    .padding(.bottom, 40)

                // Preferences
                preferencesSection
                    .padding(.bottom, 32)

                // Account
                accountSection
            }
            .padding(.horizontal, BubbleUpTheme.paddingHorizontal)
            .padding(.top, 24)
            .padding(.bottom, 100)
        }
        .background(Color.bubbleUpBackground(for: colorScheme))
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $showAPIKeyManagement) {
            APIKeyManagementView()
        }
        .navigationDestination(isPresented: $showInviteCode) {
            InviteCodeView()
        }
    }

    // MARK: - Profile Header

    private var profileHeader: some View {
        VStack(spacing: 12) {
            // Avatar placeholder
            Circle()
                .fill(Color.bubbleUpBorder(for: colorScheme))
                .frame(width: 120, height: 120)
                .overlay {
                    Image(systemName: "person.fill")
                        .font(.system(size: 48, weight: .light))
                        .foregroundColor(Color.bubbleUpTextMuted(for: colorScheme))
                }

            Text(authService.currentUserEmail ?? "User")
                .font(.display(36, weight: .light))
                .foregroundColor(Color.bubbleUpText(for: colorScheme))

            if let email = authService.currentUserEmail {
                Text(email.uppercased())
                    .font(.system(size: 12, weight: .medium))
                    .tracking(2)
                    .foregroundColor(Color.bubbleUpTextMuted(for: colorScheme))
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Stats Row

    private var statsRow: some View {
        HStack(spacing: 0) {
            StatColumn(value: "0", label: "Articles Read")
            Divider().frame(height: 40)
            StatColumn(value: "0", label: "Saved")
            Divider().frame(height: 40)
            StatColumn(value: "0", label: "Day Streak")
        }
        .padding(.vertical, 24)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.bubbleUpBorder(for: colorScheme)).frame(height: 1)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.bubbleUpBorder(for: colorScheme)).frame(height: 1)
        }
    }

    // MARK: - Preferences Section

    private var preferencesSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            sectionHeader("Preferences")

            // Typography Settings
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("TYPOGRAPHY SETTINGS")
                        .font(.system(size: 12, weight: .semibold))
                        .tracking(1.5)
                    Spacer()
                    Text("\(Int(typographySize))pt")
                        .font(.displayItalic(16))
                        .foregroundColor(Color.bubbleUpTextMuted(for: colorScheme))
                }

                Slider(value: $typographySize, in: 12...24, step: 1)
                    .tint(Color.bubbleUpText(for: colorScheme))

                HStack {
                    Text("Small").font(.displayItalic(10))
                    Spacer()
                    Text("Large").font(.displayItalic(10))
                }
                .foregroundColor(Color.bubbleUpTextMuted(for: colorScheme))
            }

            // Appearance
            VStack(alignment: .leading, spacing: 8) {
                Text("APPEARANCE")
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(1.5)

                Picker("", selection: $appearanceMode) {
                    Text("Light").tag("light")
                    Text("System").tag("system")
                    Text("Dark").tag("dark")
                }
                .pickerStyle(.segmented)
            }
            .padding(.vertical, 4)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color.bubbleUpBorder(for: colorScheme).opacity(0.5)).frame(height: 0.5)
            }

            // Daily Digest
            VStack(alignment: .leading, spacing: 4) {
                settingToggle("DAILY DIGEST", isOn: $dailyDigest)

                Text("Receive an AI-powered summary of your daily saves every morning.")
                    .font(.system(size: 11))
                    .italic()
                    .foregroundColor(Color.bubbleUpTextMuted(for: colorScheme))
            }

            Divider()

            // API Key Management
            Button { showAPIKeyManagement = true } label: {
                settingRow("API KEY MANAGEMENT", icon: "key.fill")
            }

            // Invite Code
            Button { showInviteCode = true } label: {
                settingRow("REDEEM INVITE CODE", icon: "ticket.fill")
            }
        }
    }

    // MARK: - Account Section

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            sectionHeader("Account")

            Button {
                // TODO: Export data
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "icloud.and.arrow.down")
                        .font(.system(size: 14))
                    Text("EXPORT DATA")
                        .font(.system(size: 12, weight: .semibold))
                        .tracking(1.5)
                }
                .foregroundColor(Color.bubbleUpText(for: colorScheme))
            }

            Button {
                Task { try? await authService.signOut() }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .font(.system(size: 14))
                    Text("SIGN OUT")
                        .font(.system(size: 12, weight: .semibold))
                        .tracking(1.5)
                }
                .foregroundColor(BubbleUpTheme.primary)
            }
        }
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.displayItalic(20))
            .foregroundColor(Color.bubbleUpTextMuted(for: colorScheme))
            .padding(.bottom, 8)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color.bubbleUpBorder(for: colorScheme)).frame(height: 1)
            }
    }

    private func settingToggle(_ label: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .tracking(1.5)
        }
        .tint(Color.bubbleUpText(for: colorScheme))
        .padding(.vertical, 4)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.bubbleUpBorder(for: colorScheme).opacity(0.5)).frame(height: 0.5)
        }
    }

    private func settingRow(_ label: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .tracking(1.5)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12))
                .foregroundColor(Color.bubbleUpTextMuted(for: colorScheme))
        }
        .foregroundColor(Color.bubbleUpText(for: colorScheme))
    }
}

#Preview {
    NavigationStack {
        ProfileView()
    }
    .environment(AuthService(keychainService: KeychainService()))
}

import SwiftUI

/// BYOK API key management screen.
struct APIKeyManagementView: View {
    @Environment(KeychainService.self) private var keychainService
    @Environment(\.colorScheme) private var colorScheme

    @State private var claudeKey = ""
    @State private var geminiKey = ""
    @State private var openAIKey = ""
    @State private var statusMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                Text("API Keys")
                    .font(.display(32, weight: .bold))
                    .foregroundColor(Color.bubbleUpText(for: colorScheme))

                Text("Enter your own API keys to use AI features directly. Keys are stored securely in your device's Keychain.")
                    .font(.bodyText(15))
                    .foregroundColor(Color.bubbleUpTextMuted(for: colorScheme))

                apiKeyField(
                    provider: "Anthropic (Claude)",
                    key: $claudeKey,
                    keychainKey: .claudeAPIKey,
                    placeholder: "sk-ant-..."
                )

                apiKeyField(
                    provider: "Google (Gemini)",
                    key: $geminiKey,
                    keychainKey: .geminiAPIKey,
                    placeholder: "AIza..."
                )

                apiKeyField(
                    provider: "OpenAI",
                    key: $openAIKey,
                    keychainKey: .openAIAPIKey,
                    placeholder: "sk-..."
                )

                if let statusMessage {
                    Text(statusMessage)
                        .font(.bodyText(14))
                        .foregroundColor(BubbleUpTheme.primary)
                }
            }
            .padding(.horizontal, BubbleUpTheme.paddingHorizontal)
            .padding(.top, 24)
        }
        .background(Color.bubbleUpBackground(for: colorScheme))
        .onAppear { loadExistingKeys() }
    }

    @ViewBuilder
    private func apiKeyField(
        provider: String,
        key: Binding<String>,
        keychainKey: KeychainService.Key,
        placeholder: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(provider.uppercased())
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(1.5)

                Spacer()

                if keychainService.has(keychainKey) {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12))
                        Text("Saved")
                            .font(.system(size: 12))
                    }
                    .foregroundColor(.green)
                }
            }

            HStack(spacing: 8) {
                SecureField(placeholder, text: key)
                    .font(.bodyText(14))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)

                if !key.wrappedValue.isEmpty {
                    Button("Save") {
                        saveKey(key.wrappedValue, for: keychainKey, provider: provider)
                    }
                    .font(.buttonText(13))
                    .foregroundColor(BubbleUpTheme.primary)
                }

                if keychainService.has(keychainKey) {
                    Button {
                        deleteKey(keychainKey, provider: provider)
                        key.wrappedValue = ""
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 14))
                            .foregroundColor(BubbleUpTheme.primary)
                    }
                }
            }
            .padding(.bottom, 8)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Color.bubbleUpBorder(for: colorScheme))
                    .frame(height: 1)
            }
        }
    }

    private func loadExistingKeys() {
        // Show masked existing keys
        if keychainService.has(.claudeAPIKey) { claudeKey = "••••••••" }
        if keychainService.has(.geminiAPIKey) { geminiKey = "••••••••" }
        if keychainService.has(.openAIAPIKey) { openAIKey = "••••••••" }
    }

    private func saveKey(_ value: String, for key: KeychainService.Key, provider: String) {
        do {
            try keychainService.set(value, for: key)
            keychainService.syncKeysToAppGroup()
            statusMessage = "\(provider) key saved successfully"
        } catch {
            statusMessage = "Failed to save key: \(error.localizedDescription)"
        }
    }

    private func deleteKey(_ key: KeychainService.Key, provider: String) {
        do {
            try keychainService.delete(key)
            keychainService.syncKeysToAppGroup()
            statusMessage = "\(provider) key removed"
        } catch {
            statusMessage = "Failed to remove key: \(error.localizedDescription)"
        }
    }
}

#Preview {
    NavigationStack {
        APIKeyManagementView()
    }
    .environment(KeychainService())
}

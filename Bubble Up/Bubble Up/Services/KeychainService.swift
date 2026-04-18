import Foundation
import Security

/// Manages secure storage of API keys and sensitive data in the iOS Keychain.
@Observable
final class KeychainService: @unchecked Sendable {

    enum Key: String, CaseIterable, Sendable {
        case claudeAPIKey = "com.shillwil.bubble-up.claude-api-key"
        case geminiAPIKey = "com.shillwil.bubble-up.gemini-api-key"
        case openAIAPIKey = "com.shillwil.bubble-up.openai-api-key"
    }

    enum KeychainError: Error {
        case encodingFailed
        case saveFailed(OSStatus)
        case deleteFailed(OSStatus)
        case unexpectedData
    }

    // MARK: - Public API

    func set(_ value: String, for key: Key) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }

        // Delete existing item first (update pattern)
        try? delete(key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key.rawValue,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    func get(_ key: Key) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }

        return string
    }

    func delete(_ key: Key) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key.rawValue
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }

    /// Check if a key exists without retrieving its value.
    func has(_ key: Key) -> Bool {
        get(key) != nil
    }

    /// Validates an API key by checking if it's non-empty.
    /// Actual API validation happens at the provider level.
    func hasAnyBYOKKey() -> Bool {
        Key.allCases.contains { has($0) }
    }
}

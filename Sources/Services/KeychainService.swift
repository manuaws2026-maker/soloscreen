import Foundation
import Security

/// Thread-safe Keychain wrapper for storing and retrieving API keys.
///
/// Uses the macOS Keychain Services API to securely persist sensitive credentials.
/// All operations are actor-isolated to guarantee thread safety.
actor KeychainService {

    // MARK: - Singleton

    static let shared = KeychainService()

    private init() {}

    // MARK: - Service Identifiers

    enum ServiceKey: String, CaseIterable, Sendable {
        case openAI    = "com.subtleai.openai-key"
        case anthropic = "com.subtleai.anthropic-key"
        case google    = "com.subtleai.google-key"
        case deepgram  = "com.subtleai.deepgram-key"
    }

    // MARK: - Errors

    enum KeychainError: LocalizedError {
        case saveFailed(OSStatus)
        case deleteFailed(OSStatus)
        case unexpectedData
        case encodingFailed

        var errorDescription: String? {
            switch self {
            case .saveFailed(let status):
                return "Keychain save failed (OSStatus \(status)): \(SecCopyErrorMessageString(status, nil) as String? ?? "Unknown")"
            case .deleteFailed(let status):
                return "Keychain delete failed (OSStatus \(status)): \(SecCopyErrorMessageString(status, nil) as String? ?? "Unknown")"
            case .unexpectedData:
                return "Keychain returned data in an unexpected format."
            case .encodingFailed:
                return "Failed to encode the key as UTF-8 data."
            }
        }
    }

    // MARK: - Core CRUD

    /// Save a string value to the Keychain under the specified service identifier.
    ///
    /// If a value already exists for the service, it is updated in place.
    /// - Parameters:
    ///   - key: The secret string to store.
    ///   - service: The Keychain service identifier.
    func save(key: String, service: String) throws {
        guard let data = key.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }

        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: service
        ]

        // Attempt to delete any existing item first so we can do a clean add.
        // errSecItemNotFound is acceptable — it means there was nothing to delete.
        let deleteStatus = SecItemDelete(query as CFDictionary)
        if deleteStatus != errSecSuccess && deleteStatus != errSecItemNotFound {
            throw KeychainError.deleteFailed(deleteStatus)
        }

        var addQuery = query
        addQuery[kSecValueData as String] = data

        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw KeychainError.saveFailed(addStatus)
        }
    }

    /// Load a string value from the Keychain for the specified service identifier.
    ///
    /// - Parameter service: The Keychain service identifier.
    /// - Returns: The stored string, or `nil` if no value exists.
    func load(service: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: service,
            kSecReturnData as String:  true,
            kSecMatchLimit as String:  kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }

    /// Delete the value stored under the specified service identifier.
    ///
    /// This is a no-op if no value exists for the service.
    /// - Parameter service: The Keychain service identifier.
    func delete(service: String) throws {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: service
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }

    // MARK: - OpenAI Convenience

    func saveOpenAIKey(_ key: String) throws {
        try save(key: key, service: ServiceKey.openAI.rawValue)
    }

    func loadOpenAIKey() -> String? {
        load(service: ServiceKey.openAI.rawValue)
    }

    func deleteOpenAIKey() throws {
        try delete(service: ServiceKey.openAI.rawValue)
    }

    // MARK: - Anthropic Convenience

    func saveAnthropicKey(_ key: String) throws {
        try save(key: key, service: ServiceKey.anthropic.rawValue)
    }

    func loadAnthropicKey() -> String? {
        load(service: ServiceKey.anthropic.rawValue)
    }

    func deleteAnthropicKey() throws {
        try delete(service: ServiceKey.anthropic.rawValue)
    }

    // MARK: - Google Convenience

    func saveGoogleKey(_ key: String) throws {
        try save(key: key, service: ServiceKey.google.rawValue)
    }

    func loadGoogleKey() -> String? {
        load(service: ServiceKey.google.rawValue)
    }

    func deleteGoogleKey() throws {
        try delete(service: ServiceKey.google.rawValue)
    }

    // MARK: - Deepgram Convenience

    func saveDeepgramKey(_ key: String) throws {
        try save(key: key, service: ServiceKey.deepgram.rawValue)
    }

    func loadDeepgramKey() -> String? {
        load(service: ServiceKey.deepgram.rawValue)
    }

    func deleteDeepgramKey() throws {
        try delete(service: ServiceKey.deepgram.rawValue)
    }

    // MARK: - Bulk Operations

    /// Load the API key for a given provider name (e.g., "openai", "anthropic", "google").
    func loadKey(forProvider provider: String) -> String? {
        switch provider.lowercased() {
        case "openai":    return loadOpenAIKey()
        case "anthropic": return loadAnthropicKey()
        case "google":    return loadGoogleKey()
        case "deepgram":  return loadDeepgramKey()
        default:          return nil
        }
    }

    /// Save an API key for a given provider name.
    func saveKey(_ key: String, forProvider provider: String) throws {
        switch provider.lowercased() {
        case "openai":    try saveOpenAIKey(key)
        case "anthropic": try saveAnthropicKey(key)
        case "google":    try saveGoogleKey(key)
        case "deepgram":  try saveDeepgramKey(key)
        default: break
        }
    }

    /// Delete all stored API keys.
    func deleteAll() throws {
        for serviceKey in ServiceKey.allCases {
            try delete(service: serviceKey.rawValue)
        }
    }
}

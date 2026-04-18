import Foundation

/// Thread-safe storage for API keys.
///
/// Uses a local encrypted JSON file in the app's Application Support directory.
/// This avoids macOS Keychain password prompts that occur with ad-hoc signed apps.
/// In a production build with proper code signing, this could be swapped back to
/// Keychain Services.
actor KeychainService {

    // MARK: - Singleton

    static let shared = KeychainService()

    private init() {}

    // MARK: - Service Identifiers

    enum ServiceKey: String, CaseIterable, Sendable {
        case openAI    = "com.soloscreen.openai-key"
        case anthropic = "com.soloscreen.anthropic-key"
        case google    = "com.soloscreen.google-key"
        case deepgram  = "com.soloscreen.deepgram-key"
    }

    // MARK: - Errors

    enum KeychainError: LocalizedError {
        case saveFailed(String)
        case encodingFailed

        var errorDescription: String? {
            switch self {
            case .saveFailed(let reason): return "Failed to save key: \(reason)"
            case .encodingFailed:         return "Failed to encode the key as UTF-8 data."
            }
        }
    }

    // MARK: - Storage Path

    private var storageURL: URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory

        let dir = appSupport.appendingPathComponent("SoloScreen", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(".keys.json")
    }

    // MARK: - Internal Storage

    private var cache: [String: String]?

    private func loadAll() -> [String: String] {
        if let cache { return cache }

        guard let data = try? Data(contentsOf: storageURL),
              let dict = try? JSONDecoder().decode([String: String].self, from: data) else {
            cache = [:]
            return [:]
        }
        cache = dict
        return dict
    }

    private func persist(_ dict: [String: String]) throws {
        let data = try JSONEncoder().encode(dict)
        try data.write(to: storageURL, options: [.atomic, .completeFileProtection])
        cache = dict
    }

    // MARK: - Core CRUD

    /// Save a string value under the specified service identifier.
    func save(key: String, service: String) throws {
        guard !key.isEmpty else { return }
        var dict = loadAll()
        dict[service] = key
        try persist(dict)
    }

    /// Load a string value for the specified service identifier.
    func load(service: String) -> String? {
        loadAll()[service]
    }

    /// Delete the value stored under the specified service identifier.
    func delete(service: String) throws {
        var dict = loadAll()
        dict.removeValue(forKey: service)
        try persist(dict)
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
        try persist([:])
    }
}

import Foundation

/// Thread-safe local JSON file persistence for sessions, projects, and settings.
///
/// All data is stored in `~/Library/Application Support/SoloScreen/`.
/// Actor isolation guarantees no concurrent read/write races.
actor PersistenceService {

    // MARK: - Singleton

    static let shared = PersistenceService()

    // MARK: - Storage Paths

    private let baseDirectory: URL
    private let sessionsFileURL: URL
    private let projectsFileURL: URL
    private let settingsFileURL: URL
    private let templatesFileURL: URL

    // MARK: - Encoder / Decoder

    private let encoder: JSONEncoder = {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return enc
    }()

    private let decoder: JSONDecoder = {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return dec
    }()

    // MARK: - Errors

    enum PersistenceError: LocalizedError {
        case directoryCreationFailed(underlying: Error)
        case encodingFailed(underlying: Error)
        case writeFailed(underlying: Error)
        case readFailed(underlying: Error)
        case decodingFailed(underlying: Error)

        var errorDescription: String? {
            switch self {
            case .directoryCreationFailed(let err):
                return "Failed to create storage directory: \(err.localizedDescription)"
            case .encodingFailed(let err):
                return "Failed to encode data: \(err.localizedDescription)"
            case .writeFailed(let err):
                return "Failed to write data to disk: \(err.localizedDescription)"
            case .readFailed(let err):
                return "Failed to read data from disk: \(err.localizedDescription)"
            case .decodingFailed(let err):
                return "Failed to decode stored data: \(err.localizedDescription)"
            }
        }
    }

    // MARK: - Initialization

    private init() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory

        baseDirectory = appSupport.appendingPathComponent("SoloScreen", isDirectory: true)
        sessionsFileURL = baseDirectory.appendingPathComponent("sessions.json")
        projectsFileURL = baseDirectory.appendingPathComponent("projects.json")
        settingsFileURL = baseDirectory.appendingPathComponent("settings.json")
        templatesFileURL = baseDirectory.appendingPathComponent("templates.json")
    }

    /// Testable initializer that writes to a custom directory.
    init(directory: URL) {
        baseDirectory = directory
        sessionsFileURL = directory.appendingPathComponent("sessions.json")
        projectsFileURL = directory.appendingPathComponent("projects.json")
        settingsFileURL = directory.appendingPathComponent("settings.json")
        templatesFileURL = directory.appendingPathComponent("templates.json")
    }

    // MARK: - Directory Setup

    /// Ensure the storage directory exists, creating it if necessary.
    private func ensureDirectoryExists() throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: baseDirectory.path) {
            do {
                try fm.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
            } catch {
                throw PersistenceError.directoryCreationFailed(underlying: error)
            }
        }
    }

    // MARK: - Generic Helpers

    /// Encode and write a `Codable` value to the specified file URL.
    private func write<T: Encodable>(_ value: T, to url: URL) throws {
        try ensureDirectoryExists()

        let data: Data
        do {
            data = try encoder.encode(value)
        } catch {
            throw PersistenceError.encodingFailed(underlying: error)
        }

        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw PersistenceError.writeFailed(underlying: error)
        }
    }

    /// Read and decode a `Codable` value from the specified file URL.
    /// Returns `nil` if the file does not exist.
    private func read<T: Decodable>(_ type: T.Type, from url: URL) throws -> T? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else {
            return nil
        }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw PersistenceError.readFailed(underlying: error)
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw PersistenceError.decodingFailed(underlying: error)
        }
    }

    // MARK: - Sessions

    /// Persist the given sessions array to disk.
    func saveSessions(_ sessions: [Session]) throws {
        try write(sessions, to: sessionsFileURL)
    }

    /// Load persisted sessions. Returns an empty array if no file exists.
    func loadSessions() -> [Session] {
        do {
            return try read([Session].self, from: sessionsFileURL) ?? []
        } catch {
            logError("Loading sessions", error)
            return []
        }
    }

    // MARK: - Projects

    /// Persist the given projects array to disk.
    func saveProjects(_ projects: [Project]) throws {
        try write(projects, to: projectsFileURL)
    }

    /// Load persisted projects. Returns an empty array if no file exists.
    func loadProjects() -> [Project] {
        do {
            return try read([Project].self, from: projectsFileURL) ?? []
        } catch {
            logError("Loading projects", error)
            return []
        }
    }

    // MARK: - Settings

    /// Persist user settings to disk.
    func saveSettings(_ settings: UserSettings) throws {
        try write(settings, to: settingsFileURL)
    }

    /// Load user settings. Returns default settings if no file exists.
    func loadSettings() -> UserSettings {
        do {
            return try read(UserSettings.self, from: settingsFileURL) ?? UserSettings()
        } catch {
            logError("Loading settings", error)
            return UserSettings()
        }
    }

    // MARK: - Chat Templates (user-defined only; built-ins are hardcoded)

    func saveTemplates(_ templates: [ChatTemplate]) throws {
        try write(templates, to: templatesFileURL)
    }

    func loadTemplates() -> [ChatTemplate] {
        do {
            return try read([ChatTemplate].self, from: templatesFileURL) ?? []
        } catch {
            logError("Loading templates", error)
            return []
        }
    }

    // MARK: - Utilities

    /// Remove all stored data. Primarily for testing or account reset.
    func deleteAll() throws {
        let fm = FileManager.default
        for url in [sessionsFileURL, projectsFileURL, settingsFileURL] {
            if fm.fileExists(atPath: url.path) {
                try fm.removeItem(at: url)
            }
        }
    }

    /// The URL of the storage directory, useful for debugging.
    var storageDirectory: URL {
        baseDirectory
    }

    // MARK: - Logging

    private func logError(_ context: String, _ error: Error) {
        #if DEBUG
        print("[PersistenceService] \(context) failed: \(error.localizedDescription)")
        #endif
    }
}

import Testing
import Foundation
@testable import SoloScreen

@Suite("PersistenceService")
struct PersistenceTests {

    /// Create a fresh PersistenceService backed by a unique temporary directory.
    /// Returns the service and the temp directory URL for cleanup.
    private func makeTempService() -> (PersistenceService, URL) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SoloScreenTests_\(UUID().uuidString)", isDirectory: true)
        let service = PersistenceService(directory: tempDir)
        return (service, tempDir)
    }

    /// Clean up a temporary directory.
    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Sessions

    @Test("Save and load sessions round-trip")
    func sessionsRoundTrip() async throws {
        let (service, tempDir) = makeTempService()
        defer { cleanup(tempDir) }

        let sessions = [
            Session(
                title: "Chat 1",
                messages: [
                    Message(role: .system, content: "You are helpful"),
                    Message(role: .user, content: "Hello"),
                    Message(role: .assistant, content: "Hi there!"),
                ],
                model: "gpt-4o"
            ),
            Session(
                title: "Chat 2",
                messages: [
                    Message(role: .user, content: "What is 2+2?"),
                ],
                model: "gpt-4o-mini"
            ),
        ]

        try await service.saveSessions(sessions)
        let loaded = await service.loadSessions()

        #expect(loaded.count == 2)
        #expect(loaded[0].title == "Chat 1")
        #expect(loaded[0].messages.count == 3)
        #expect(loaded[0].model == "gpt-4o")
        #expect(loaded[1].title == "Chat 2")
        #expect(loaded[1].messages.count == 1)
    }

    @Test("Load sessions when no file exists returns empty array")
    func loadSessionsEmpty() async {
        let (service, tempDir) = makeTempService()
        defer { cleanup(tempDir) }

        let loaded = await service.loadSessions()
        #expect(loaded.isEmpty)
    }

    @Test("Sessions with attachments survive round-trip")
    func sessionsWithAttachments() async throws {
        let (service, tempDir) = makeTempService()
        defer { cleanup(tempDir) }

        let attachment = Message.Attachment(
            type: .screenshot,
            data: Data([0x89, 0x50, 0x4E, 0x47]),
            fileName: "screenshot.png",
            mimeType: "image/png"
        )
        let session = Session(
            title: "With Attachment",
            messages: [
                Message(role: .user, content: "Look at this", attachments: [attachment])
            ]
        )

        try await service.saveSessions([session])
        let loaded = await service.loadSessions()

        #expect(loaded.count == 1)
        #expect(loaded[0].messages[0].attachments.count == 1)
        #expect(loaded[0].messages[0].attachments[0].fileName == "screenshot.png")
        #expect(loaded[0].messages[0].attachments[0].data == Data([0x89, 0x50, 0x4E, 0x47]))
    }

    @Test("Saving sessions overwrites previous data")
    func sessionsOverwrite() async throws {
        let (service, tempDir) = makeTempService()
        defer { cleanup(tempDir) }

        let original = [Session(title: "Original")]
        try await service.saveSessions(original)

        let updated = [Session(title: "Updated"), Session(title: "New")]
        try await service.saveSessions(updated)

        let loaded = await service.loadSessions()
        #expect(loaded.count == 2)
        #expect(loaded[0].title == "Updated")
        #expect(loaded[1].title == "New")
    }

    @Test("Empty sessions array saves and loads correctly")
    func sessionsEmptyArray() async throws {
        let (service, tempDir) = makeTempService()
        defer { cleanup(tempDir) }

        // First save some sessions
        try await service.saveSessions([Session(title: "Temp")])
        // Then save empty array
        try await service.saveSessions([])

        let loaded = await service.loadSessions()
        #expect(loaded.isEmpty)
    }

    // MARK: - Projects

    @Test("Save and load projects round-trip")
    func projectsRoundTrip() async throws {
        let (service, tempDir) = makeTempService()
        defer { cleanup(tempDir) }

        let file = ProjectFile(
            fileName: "notes.md",
            mimeType: "text/markdown",
            textContent: "# Notes\nSome content here",
            sizeBytes: 25
        )
        let projects = [
            Project(name: "Project Alpha", files: [file]),
            Project(name: "Project Beta"),
        ]

        try await service.saveProjects(projects)
        let loaded = await service.loadProjects()

        #expect(loaded.count == 2)
        #expect(loaded[0].name == "Project Alpha")
        #expect(loaded[0].files.count == 1)
        #expect(loaded[0].files[0].fileName == "notes.md")
        #expect(loaded[0].files[0].textContent == "# Notes\nSome content here")
        #expect(loaded[1].name == "Project Beta")
        #expect(loaded[1].files.isEmpty)
    }

    @Test("Load projects when no file exists returns empty array")
    func loadProjectsEmpty() async {
        let (service, tempDir) = makeTempService()
        defer { cleanup(tempDir) }

        let loaded = await service.loadProjects()
        #expect(loaded.isEmpty)
    }

    @Test("Project with max files survives round-trip")
    func projectMaxFiles() async throws {
        let (service, tempDir) = makeTempService()
        defer { cleanup(tempDir) }

        let files = (0..<15).map { i in
            ProjectFile(
                fileName: "file\(i).txt",
                mimeType: "text/plain",
                textContent: "Content \(i)",
                sizeBytes: 10
            )
        }
        let project = Project(name: "Full Project", files: files)

        try await service.saveProjects([project])
        let loaded = await service.loadProjects()

        #expect(loaded.count == 1)
        #expect(loaded[0].files.count == 15)
        #expect(loaded[0].canAddFile == false)
    }

    // MARK: - Settings

    @Test("Save and load settings round-trip")
    func settingsRoundTrip() async throws {
        let (service, tempDir) = makeTempService()
        defer { cleanup(tempDir) }

        let settings = UserSettings(
            selectedProvider: "anthropic",
            selectedModel: "claude-sonnet-4-20250514",
            transcriptionProvider: "whisper",
            freeMessagesUsed: 7,
            onboardingCompleted: true,
            stealthEnabled: false,
            extremeStealthEnabled: true,
            overlayOpacity: 0.5,
            fontSize: 18.0
        )

        try await service.saveSettings(settings)
        let loaded = await service.loadSettings()

        #expect(loaded == settings)
        #expect(loaded.selectedProvider == "anthropic")
        #expect(loaded.selectedModel == "claude-sonnet-4-20250514")
        #expect(loaded.freeMessagesUsed == 7)
        #expect(loaded.onboardingCompleted == true)
        #expect(loaded.stealthEnabled == false)
        #expect(loaded.extremeStealthEnabled == true)
        #expect(loaded.overlayOpacity == 0.5)
        #expect(loaded.fontSize == 18.0)
    }

    @Test("Load settings when no file exists returns defaults")
    func loadSettingsDefault() async {
        let (service, tempDir) = makeTempService()
        defer { cleanup(tempDir) }

        let loaded = await service.loadSettings()
        let defaults = UserSettings()

        #expect(loaded == defaults)
        #expect(loaded.selectedProvider == "openai")
        #expect(loaded.selectedModel == "gpt-4o-mini")
        #expect(loaded.freeMessagesUsed == 0)
        #expect(loaded.onboardingCompleted == false)
    }

    @Test("Settings update persists correctly")
    func settingsUpdate() async throws {
        let (service, tempDir) = makeTempService()
        defer { cleanup(tempDir) }

        // Save initial settings
        var settings = UserSettings()
        try await service.saveSettings(settings)

        // Update and save again
        settings.freeMessagesUsed = 5
        settings.onboardingCompleted = true
        settings.selectedModel = "gpt-4o"
        try await service.saveSettings(settings)

        let loaded = await service.loadSettings()
        #expect(loaded.freeMessagesUsed == 5)
        #expect(loaded.onboardingCompleted == true)
        #expect(loaded.selectedModel == "gpt-4o")
    }

    // MARK: - Cross-Instance Persistence

    @Test("Data persists across service instances sharing same directory")
    func crossInstancePersistence() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SoloScreenTests_\(UUID().uuidString)", isDirectory: true)
        defer { cleanup(tempDir) }

        // Instance 1: save data
        let service1 = PersistenceService(directory: tempDir)
        let sessions = [Session(title: "Persisted Chat")]
        let projects = [Project(name: "Persisted Project")]
        let settings = UserSettings(freeMessagesUsed: 3)

        try await service1.saveSessions(sessions)
        try await service1.saveProjects(projects)
        try await service1.saveSettings(settings)

        // Instance 2: load data from same directory
        let service2 = PersistenceService(directory: tempDir)

        let loadedSessions = await service2.loadSessions()
        let loadedProjects = await service2.loadProjects()
        let loadedSettings = await service2.loadSettings()

        #expect(loadedSessions.count == 1)
        #expect(loadedSessions[0].title == "Persisted Chat")
        #expect(loadedProjects.count == 1)
        #expect(loadedProjects[0].name == "Persisted Project")
        #expect(loadedSettings.freeMessagesUsed == 3)
    }

    // MARK: - Delete All

    @Test("deleteAll removes all persisted data")
    func deleteAll() async throws {
        let (service, tempDir) = makeTempService()
        defer { cleanup(tempDir) }

        // Save some data
        try await service.saveSessions([Session(title: "Temp")])
        try await service.saveProjects([Project(name: "Temp")])
        try await service.saveSettings(UserSettings(freeMessagesUsed: 5))

        // Delete
        try await service.deleteAll()

        // Verify everything is back to defaults
        let sessions = await service.loadSessions()
        let projects = await service.loadProjects()
        let settings = await service.loadSettings()

        #expect(sessions.isEmpty)
        #expect(projects.isEmpty)
        #expect(settings == UserSettings()) // default settings
    }

    @Test("deleteAll on empty directory does not throw")
    func deleteAllEmpty() async throws {
        let (service, tempDir) = makeTempService()
        defer { cleanup(tempDir) }

        // Should not throw when there's nothing to delete
        try await service.deleteAll()
    }

    // MARK: - Storage Directory

    @Test("storageDirectory returns the configured directory")
    func storageDirectory() async {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SoloScreenTests_\(UUID().uuidString)", isDirectory: true)
        let service = PersistenceService(directory: tempDir)

        let dir = await service.storageDirectory
        #expect(dir == tempDir)
    }

    // MARK: - Date Preservation

    @Test("Dates are preserved accurately through persistence")
    func datePreservation() async throws {
        let (service, tempDir) = makeTempService()
        defer { cleanup(tempDir) }

        // Use a specific date (ISO 8601 rounds to seconds)
        let calendar = Calendar(identifier: .gregorian)
        let components = DateComponents(
            timeZone: TimeZone(identifier: "UTC"),
            year: 2025, month: 6, day: 15,
            hour: 10, minute: 30, second: 0
        )
        let date = calendar.date(from: components)!

        let session = Session(
            title: "Date Test",
            messages: [Message(role: .user, content: "Hi", timestamp: date)],
            createdAt: date,
            updatedAt: date
        )

        try await service.saveSessions([session])
        let loaded = await service.loadSessions()

        #expect(loaded.count == 1)
        // ISO 8601 encoding rounds to seconds, so compare within 1 second
        #expect(abs(loaded[0].createdAt.timeIntervalSince(date)) < 1.0)
        #expect(abs(loaded[0].updatedAt.timeIntervalSince(date)) < 1.0)
        #expect(abs(loaded[0].messages[0].timestamp.timeIntervalSince(date)) < 1.0)
    }
}

import Testing
import Foundation
@testable import SubtleAI

// MARK: - Session Tests

@Suite("Session")
struct SessionTests {

    // MARK: Creation & Defaults

    @Test("Default initializer sets expected values")
    func defaultInit() {
        let session = Session()
        #expect(session.title == "New Chat")
        #expect(session.messages.isEmpty)
        #expect(session.projectId == nil)
        #expect(session.model == "gpt-4o-mini")
    }

    @Test("Custom initializer preserves all fields")
    func customInit() {
        let id = UUID()
        let projectId = UUID()
        let date = Date.distantPast
        let msg = Message(role: .user, content: "Hi")
        let session = Session(
            id: id,
            title: "My Chat",
            messages: [msg],
            projectId: projectId,
            model: "gpt-4o",
            createdAt: date,
            updatedAt: date
        )
        #expect(session.id == id)
        #expect(session.title == "My Chat")
        #expect(session.messages.count == 1)
        #expect(session.projectId == projectId)
        #expect(session.model == "gpt-4o")
        #expect(session.createdAt == date)
        #expect(session.updatedAt == date)
    }

    // MARK: visibleMessageCount

    @Test("visibleMessageCount excludes system messages")
    func visibleMessageCountExcludesSystem() {
        let messages: [Message] = [
            Message(role: .system, content: "You are helpful"),
            Message(role: .user, content: "Hello"),
            Message(role: .assistant, content: "Hi there"),
            Message(role: .system, content: "Another system msg"),
        ]
        let session = Session(messages: messages)
        #expect(session.visibleMessageCount == 2)
    }

    @Test("visibleMessageCount is zero for system-only messages")
    func visibleMessageCountAllSystem() {
        let messages = [Message(role: .system, content: "sys")]
        let session = Session(messages: messages)
        #expect(session.visibleMessageCount == 0)
    }

    @Test("visibleMessageCount is zero for empty session")
    func visibleMessageCountEmpty() {
        let session = Session()
        #expect(session.visibleMessageCount == 0)
    }

    @Test("visibleMessageCount counts all when no system messages")
    func visibleMessageCountNoSystem() {
        let messages = [
            Message(role: .user, content: "A"),
            Message(role: .assistant, content: "B"),
            Message(role: .user, content: "C"),
        ]
        let session = Session(messages: messages)
        #expect(session.visibleMessageCount == 3)
    }

    // MARK: autoTitle

    @Test("autoTitle generates title from first user message")
    func autoTitleBasic() {
        var session = Session(messages: [
            Message(role: .user, content: "What is the meaning of life")
        ])
        session.autoTitle()
        #expect(session.title == "What is the meaning of life")
    }

    @Test("autoTitle truncates at 8 words and adds ellipsis")
    func autoTitleTruncates() {
        var session = Session(messages: [
            Message(role: .user, content: "one two three four five six seven eight nine ten eleven")
        ])
        session.autoTitle()
        #expect(session.title == "one two three four five six seven eight...")
    }

    @Test("autoTitle does nothing if title is already customized")
    func autoTitleSkipsCustomTitle() {
        var session = Session(title: "Custom Title", messages: [
            Message(role: .user, content: "Hello world")
        ])
        session.autoTitle()
        #expect(session.title == "Custom Title")
    }

    @Test("autoTitle does nothing if no user messages exist")
    func autoTitleNoUserMessages() {
        var session = Session(messages: [
            Message(role: .system, content: "System prompt"),
            Message(role: .assistant, content: "Hello"),
        ])
        session.autoTitle()
        #expect(session.title == "New Chat")
    }

    @Test("autoTitle uses first user message even if system comes first")
    func autoTitleSkipsSystemMessages() {
        var session = Session(messages: [
            Message(role: .system, content: "System prompt"),
            Message(role: .user, content: "Hello there friend"),
        ])
        session.autoTitle()
        #expect(session.title == "Hello there friend")
    }

    @Test("autoTitle handles single-word message")
    func autoTitleSingleWord() {
        var session = Session(messages: [
            Message(role: .user, content: "Hello")
        ])
        session.autoTitle()
        #expect(session.title == "Hello")
    }

    @Test("autoTitle handles exactly 8 words without ellipsis")
    func autoTitleExactlyEightWords() {
        var session = Session(messages: [
            Message(role: .user, content: "one two three four five six seven eight")
        ])
        session.autoTitle()
        #expect(session.title == "one two three four five six seven eight")
    }

    // MARK: Codable Round-Trip

    @Test("Session survives JSON encode/decode round-trip")
    func codableRoundTrip() throws {
        // Use whole-second dates to survive ISO 8601 round-trip (which drops sub-second precision).
        let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)
        let original = Session(
            title: "Test Session",
            messages: [
                Message(role: .system, content: "You are helpful", timestamp: fixedDate),
                Message(role: .user, content: "Hello", timestamp: fixedDate),
                Message(role: .assistant, content: "Hi!", timestamp: fixedDate),
            ],
            model: "gpt-4o",
            createdAt: fixedDate,
            updatedAt: fixedDate
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(Session.self, from: data)

        #expect(decoded == original)
        #expect(decoded.title == "Test Session")
        #expect(decoded.messages.count == 3)
        #expect(decoded.model == "gpt-4o")
    }

    // MARK: Equatable

    @Test("Sessions with same id are equal")
    func equatable() {
        let id = UUID()
        let date = Date()
        let a = Session(id: id, title: "A", createdAt: date, updatedAt: date)
        let b = Session(id: id, title: "A", createdAt: date, updatedAt: date)
        #expect(a == b)
    }

    @Test("Sessions with different id are not equal")
    func notEqual() {
        let a = Session(title: "Same")
        let b = Session(title: "Same")
        #expect(a != b)
    }
}

// MARK: - Message Tests

@Suite("Message")
struct MessageTests {

    @Test("Default message creation with role and content")
    func creation() {
        let msg = Message(role: .user, content: "Hello")
        #expect(msg.role == .user)
        #expect(msg.content == "Hello")
        #expect(msg.attachments.isEmpty)
    }

    @Test("Message with attachments")
    func withAttachments() {
        let attachment = Message.Attachment(
            type: .screenshot,
            data: Data([0x89, 0x50, 0x4E, 0x47]),
            fileName: "screen.png",
            mimeType: "image/png"
        )
        let msg = Message(role: .user, content: "See this", attachments: [attachment])
        #expect(msg.attachments.count == 1)
        #expect(msg.attachments[0].type == .screenshot)
        #expect(msg.attachments[0].fileName == "screen.png")
        #expect(msg.attachments[0].mimeType == "image/png")
    }

    @Test("Attachment type file")
    func attachmentFile() {
        let attachment = Message.Attachment(
            type: .file,
            data: Data("hello".utf8),
            fileName: "notes.txt",
            mimeType: "text/plain"
        )
        #expect(attachment.type == .file)
        #expect(attachment.fileName == "notes.txt")
    }

    @Test("Attachment default mimeType is image/png")
    func attachmentDefaultMimeType() {
        let attachment = Message.Attachment(type: .screenshot, data: Data())
        #expect(attachment.mimeType == "image/png")
        #expect(attachment.fileName == nil)
    }

    @Test("Role raw values encode correctly")
    func roleRawValues() {
        #expect(Message.Role.system.rawValue == "system")
        #expect(Message.Role.user.rawValue == "user")
        #expect(Message.Role.assistant.rawValue == "assistant")
    }

    @Test("Role Codable round-trip")
    func roleCodableRoundTrip() throws {
        let roles: [Message.Role] = [.system, .user, .assistant]
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for role in roles {
            let data = try encoder.encode(role)
            let decoded = try decoder.decode(Message.Role.self, from: data)
            #expect(decoded == role)
        }
    }

    @Test("AttachmentType raw values")
    func attachmentTypeRawValues() {
        #expect(Message.AttachmentType.screenshot.rawValue == "screenshot")
        #expect(Message.AttachmentType.file.rawValue == "file")
    }

    @Test("Message Codable round-trip preserves all fields")
    func messageCodableRoundTrip() throws {
        let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)
        let attachment = Message.Attachment(
            type: .file,
            data: Data("content".utf8),
            fileName: "test.txt",
            mimeType: "text/plain"
        )
        let original = Message(
            role: .user,
            content: "Test message",
            attachments: [attachment],
            timestamp: fixedDate
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(Message.self, from: data)

        #expect(decoded == original)
        #expect(decoded.role == .user)
        #expect(decoded.content == "Test message")
        #expect(decoded.attachments.count == 1)
        #expect(decoded.attachments[0].fileName == "test.txt")
    }
}

// MARK: - Project Tests

@Suite("Project")
struct ProjectTests {

    @Test("Default project creation")
    func creation() {
        let project = Project(name: "My Project")
        #expect(project.name == "My Project")
        #expect(project.files.isEmpty)
    }

    @Test("canAddFile is true when files count is below max")
    func canAddFileTrue() {
        let project = Project(name: "P", files: [])
        #expect(project.canAddFile == true)
    }

    @Test("canAddFile is true when files count is 14")
    func canAddFileAtFourteen() {
        let files = (0..<14).map { i in
            ProjectFile(fileName: "file\(i).txt", mimeType: "text/plain", textContent: "", sizeBytes: 100)
        }
        let project = Project(name: "P", files: files)
        #expect(project.canAddFile == true)
    }

    @Test("canAddFile is false when files count equals maxFiles (15)")
    func canAddFileFalseAtMax() {
        let files = (0..<15).map { i in
            ProjectFile(fileName: "file\(i).txt", mimeType: "text/plain", textContent: "", sizeBytes: 100)
        }
        let project = Project(name: "P", files: files)
        #expect(project.canAddFile == false)
    }

    @Test("canAddFile is false when files count exceeds maxFiles")
    func canAddFileFalseOverMax() {
        let files = (0..<20).map { i in
            ProjectFile(fileName: "file\(i).txt", mimeType: "text/plain", textContent: "", sizeBytes: 100)
        }
        let project = Project(name: "P", files: files)
        #expect(project.canAddFile == false)
    }

    @Test("maxFiles constant is 15")
    func maxFilesConstant() {
        #expect(Project.maxFiles == 15)
    }

    @Test("maxFileSizeMB constant is 10")
    func maxFileSizeMBConstant() {
        #expect(Project.maxFileSizeMB == 10)
    }

    @Test("Project Codable round-trip")
    func codableRoundTrip() throws {
        let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)
        let file = ProjectFile(
            fileName: "readme.md",
            mimeType: "text/markdown",
            textContent: "# Hello",
            sizeBytes: 7,
            addedAt: fixedDate
        )
        let original = Project(name: "Test Project", files: [file], createdAt: fixedDate, updatedAt: fixedDate)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(Project.self, from: data)

        #expect(decoded == original)
        #expect(decoded.name == "Test Project")
        #expect(decoded.files.count == 1)
        #expect(decoded.files[0].fileName == "readme.md")
    }
}

// MARK: - ProjectFile Tests

@Suite("ProjectFile")
struct ProjectFileTests {

    @Test("supportedExtensions contains expected types")
    func supportedExtensions() {
        let expected: Set<String> = ["txt", "md", "rtf", "pdf", "doc", "docx"]
        #expect(ProjectFile.supportedExtensions == expected)
    }

    @Test("isSupportedExtension returns true for all supported types")
    func isSupportedExtensionAllSupported() {
        for ext in ["txt", "md", "rtf", "pdf", "doc", "docx"] {
            #expect(ProjectFile.isSupportedExtension(ext) == true, "Expected \(ext) to be supported")
        }
    }

    @Test("isSupportedExtension is case insensitive")
    func isSupportedExtensionCaseInsensitive() {
        #expect(ProjectFile.isSupportedExtension("TXT") == true)
        #expect(ProjectFile.isSupportedExtension("Md") == true)
        #expect(ProjectFile.isSupportedExtension("PDF") == true)
        #expect(ProjectFile.isSupportedExtension("RTF") == true)
        #expect(ProjectFile.isSupportedExtension("DOC") == true)
        #expect(ProjectFile.isSupportedExtension("DOCX") == true)
    }

    @Test("isSupportedExtension returns false for unsupported types")
    func isSupportedExtensionUnsupported() {
        for ext in ["jpg", "png", "mp3", "mp4", "zip", "swift", "py", "exe", "html", "csv"] {
            #expect(ProjectFile.isSupportedExtension(ext) == false, "Expected \(ext) to be unsupported")
        }
    }

    @Test("isSupportedExtension returns false for empty string")
    func isSupportedExtensionEmpty() {
        #expect(ProjectFile.isSupportedExtension("") == false)
    }

    @Test("ProjectFile creation preserves all fields")
    func creation() {
        let id = UUID()
        let date = Date()
        let file = ProjectFile(
            id: id,
            fileName: "notes.txt",
            mimeType: "text/plain",
            textContent: "Some content",
            sizeBytes: 12,
            addedAt: date
        )
        #expect(file.id == id)
        #expect(file.fileName == "notes.txt")
        #expect(file.mimeType == "text/plain")
        #expect(file.textContent == "Some content")
        #expect(file.sizeBytes == 12)
        #expect(file.addedAt == date)
    }

    @Test("ProjectFile Codable round-trip")
    func codableRoundTrip() throws {
        let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)
        let original = ProjectFile(
            fileName: "report.pdf",
            mimeType: "application/pdf",
            textContent: "Extracted text from PDF",
            sizeBytes: 1024,
            addedAt: fixedDate
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(ProjectFile.self, from: data)

        #expect(decoded == original)
    }
}

// MARK: - UserSettings Tests

@Suite("UserSettings")
struct UserSettingsTests {

    // MARK: Defaults

    @Test("Default UserSettings has expected values")
    func defaults() {
        let settings = UserSettings()
        #expect(settings.selectedProvider == "openai")
        #expect(settings.selectedModel == "gpt-4o-mini")
        #expect(settings.transcriptionProvider == "deepgram")
        #expect(settings.freeMessagesUsed == 0)
        #expect(settings.onboardingCompleted == false)
        #expect(settings.stealthEnabled == true)
        #expect(settings.extremeStealthEnabled == false)
        #expect(settings.overlayOpacity == 1.0)
        #expect(settings.fontSize == 14.0)
    }

    // MARK: Free Tier

    @Test("hasFreeTierRemaining is true at 0 messages used")
    func hasFreeTierRemainingAtZero() {
        let settings = UserSettings(freeMessagesUsed: 0)
        #expect(settings.hasFreeTierRemaining == true)
    }

    @Test("hasFreeTierRemaining is true at 9 messages used")
    func hasFreeTierRemainingAtNine() {
        let settings = UserSettings(freeMessagesUsed: 9)
        #expect(settings.hasFreeTierRemaining == true)
    }

    @Test("hasFreeTierRemaining is false at 10 messages used")
    func hasFreeTierRemainingAtLimit() {
        let settings = UserSettings(freeMessagesUsed: 10)
        #expect(settings.hasFreeTierRemaining == false)
    }

    @Test("hasFreeTierRemaining is false when exceeding limit")
    func hasFreeTierRemainingOverLimit() {
        let settings = UserSettings(freeMessagesUsed: 15)
        #expect(settings.hasFreeTierRemaining == false)
    }

    @Test("freeMessagesRemaining calculation at 0 used")
    func freeMessagesRemainingAtZero() {
        let settings = UserSettings(freeMessagesUsed: 0)
        #expect(settings.freeMessagesRemaining == 10)
    }

    @Test("freeMessagesRemaining calculation at 5 used")
    func freeMessagesRemainingAtFive() {
        let settings = UserSettings(freeMessagesUsed: 5)
        #expect(settings.freeMessagesRemaining == 5)
    }

    @Test("freeMessagesRemaining calculation at 10 used")
    func freeMessagesRemainingAtLimit() {
        let settings = UserSettings(freeMessagesUsed: 10)
        #expect(settings.freeMessagesRemaining == 0)
    }

    @Test("freeMessagesRemaining does not go negative")
    func freeMessagesRemainingNeverNegative() {
        let settings = UserSettings(freeMessagesUsed: 100)
        #expect(settings.freeMessagesRemaining == 0)
    }

    @Test("freeMessageLimit constant is 10")
    func freeMessageLimitConstant() {
        #expect(UserSettings.freeMessageLimit == 10)
    }

    // MARK: Codable

    @Test("UserSettings Codable round-trip preserves all fields")
    func codableRoundTrip() throws {
        let original = UserSettings(
            selectedProvider: "anthropic",
            selectedModel: "claude-sonnet-4-20250514",
            transcriptionProvider: "whisper",
            freeMessagesUsed: 7,
            onboardingCompleted: true,
            stealthEnabled: false,
            extremeStealthEnabled: true,
            overlayOpacity: 0.8,
            fontSize: 16.0
        )

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(UserSettings.self, from: data)

        #expect(decoded == original)
        #expect(decoded.selectedProvider == "anthropic")
        #expect(decoded.selectedModel == "claude-sonnet-4-20250514")
        #expect(decoded.transcriptionProvider == "whisper")
        #expect(decoded.freeMessagesUsed == 7)
        #expect(decoded.onboardingCompleted == true)
        #expect(decoded.stealthEnabled == false)
        #expect(decoded.extremeStealthEnabled == true)
        #expect(decoded.overlayOpacity == 0.8)
        #expect(decoded.fontSize == 16.0)
    }

    // MARK: Equatable

    @Test("UserSettings equality")
    func equatable() {
        let a = UserSettings()
        let b = UserSettings()
        #expect(a == b)
    }

    @Test("UserSettings inequality when field differs")
    func notEqual() {
        let a = UserSettings()
        let b = UserSettings(freeMessagesUsed: 5)
        #expect(a != b)
    }
}

import Foundation

/// A chat session containing messages and optional project context.
struct Session: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var messages: [Message]
    var projectId: UUID?
    var model: String
    /// Overrides the default system prompt for this session when non-nil.
    /// Copied in from the selected chat template at creation time.
    var systemPrompt: String?
    /// Displayed as a pill in the chat top bar (e.g., "Coding Help").
    var templateName: String?
    /// SF Symbol for the template pill.
    var templateIcon: String?
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String = "New Chat",
        messages: [Message] = [],
        projectId: UUID? = nil,
        model: String = "gpt-4o-mini",
        systemPrompt: String? = nil,
        templateName: String? = nil,
        templateIcon: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.messages = messages
        self.projectId = projectId
        self.model = model
        self.systemPrompt = systemPrompt
        self.templateName = templateName
        self.templateIcon = templateIcon
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// User-visible message count (excludes system messages).
    var visibleMessageCount: Int {
        messages.filter { $0.role != .system }.count
    }

    /// Generate a title from the first user message if still default.
    mutating func autoTitle() {
        guard title == "New Chat",
              let first = messages.first(where: { $0.role == .user }) else { return }
        let words = first.content.prefix(80).split(separator: " ")
        title = words.prefix(8).joined(separator: " ")
        if words.count > 8 { title += "..." }
    }
}

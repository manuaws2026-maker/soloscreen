import Foundation

/// A chat session containing messages and optional project context.
struct Session: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var messages: [Message]
    var projectId: UUID?
    var model: String
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String = "New Chat",
        messages: [Message] = [],
        projectId: UUID? = nil,
        model: String = "gpt-4o-mini",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.messages = messages
        self.projectId = projectId
        self.model = model
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

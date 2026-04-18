import Foundation

/// A single message in a chat session.
struct Message: Identifiable, Codable, Equatable {
    let id: UUID
    var role: Role
    var content: String
    var attachments: [Attachment]
    let timestamp: Date

    init(id: UUID = UUID(), role: Role, content: String, attachments: [Attachment] = [], timestamp: Date = Date()) {
        self.id = id
        self.role = role
        self.content = content
        self.attachments = attachments
        self.timestamp = timestamp
    }

    enum Role: String, Codable, Sendable {
        case system
        case user
        case assistant
    }

    struct Attachment: Identifiable, Codable, Equatable {
        let id: UUID
        var type: AttachmentType
        var data: Data
        var fileName: String?
        var mimeType: String
        var textContent: String?

        init(id: UUID = UUID(), type: AttachmentType, data: Data, fileName: String? = nil, mimeType: String = "image/png", textContent: String? = nil) {
            self.id = id
            self.type = type
            self.data = data
            self.fileName = fileName
            self.mimeType = mimeType
            self.textContent = textContent
        }
    }

    enum AttachmentType: String, Codable, Sendable {
        case screenshot
        case file
    }
}

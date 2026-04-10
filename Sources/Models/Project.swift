import Foundation

/// A project containing reference files for RAG context.
struct Project: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var files: [ProjectFile]
    let createdAt: Date
    var updatedAt: Date

    static let maxFiles = 15
    static let maxFileSizeMB = 10

    init(id: UUID = UUID(), name: String, files: [ProjectFile] = [], createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.files = files
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var canAddFile: Bool { files.count < Self.maxFiles }
}

/// A single file within a project.
struct ProjectFile: Identifiable, Codable, Equatable {
    let id: UUID
    var fileName: String
    var mimeType: String
    var textContent: String
    var sizeBytes: Int
    let addedAt: Date

    init(id: UUID = UUID(), fileName: String, mimeType: String, textContent: String, sizeBytes: Int, addedAt: Date = Date()) {
        self.id = id
        self.fileName = fileName
        self.mimeType = mimeType
        self.textContent = textContent
        self.sizeBytes = sizeBytes
        self.addedAt = addedAt
    }

    /// Supported file types for upload.
    static let supportedExtensions: Set<String> = ["txt", "md", "rtf", "pdf", "doc", "docx"]

    static func isSupportedExtension(_ ext: String) -> Bool {
        supportedExtensions.contains(ext.lowercased())
    }
}

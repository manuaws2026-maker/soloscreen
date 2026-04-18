import Foundation
import NaturalLanguage

/// Local vector store for RAG (Retrieval-Augmented Generation).
///
/// Uses Apple's NaturalLanguage framework for sentence embeddings — fully on-device,
/// no API calls needed. Stores vectors in memory with periodic JSON persistence
/// to `~/Library/Application Support/SoloScreen/vector_store.json`.
actor VectorStoreService {

    // MARK: - Types

    /// A search result with the matched text, similarity score, and source file.
    struct SearchResult: Sendable {
        let text: String
        let score: Float
        let fileId: UUID
    }

    /// A single stored vector entry.
    private struct VectorEntry: Codable {
        let id: UUID
        let text: String
        let embedding: [Double]
        let fileId: UUID
        let projectId: UUID
    }

    // MARK: - Errors

    enum VectorStoreError: LocalizedError {
        case embeddingNotAvailable
        case embeddingFailed(String)
        case persistenceFailed(underlying: Error)

        var errorDescription: String? {
            switch self {
            case .embeddingNotAvailable:
                return "Sentence embeddings are not available for the English language on this system."
            case .embeddingFailed(let text):
                let preview = text.prefix(50)
                return "Failed to compute embedding for text: \"\(preview)...\"."
            case .persistenceFailed(let err):
                return "Failed to persist vector store: \(err.localizedDescription)"
            }
        }
    }

    // MARK: - Singleton

    static let shared = VectorStoreService()

    // MARK: - State

    private var entries: [VectorEntry] = []
    private let storeFileURL: URL
    private var isDirty: Bool = false

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = .prettyPrinted
        return e
    }()

    private let decoder = JSONDecoder()

    // MARK: - Initialization

    init() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory

        let baseDir = appSupport.appendingPathComponent("SoloScreen", isDirectory: true)
        storeFileURL = baseDir.appendingPathComponent("vector_store.json")

        // Load persisted entries synchronously on init.
        if FileManager.default.fileExists(atPath: storeFileURL.path),
           let data = try? Data(contentsOf: storeFileURL),
           let stored = try? decoder.decode([VectorEntry].self, from: data) {
            entries = stored
        }
    }

    // MARK: - Indexing

    /// Index a set of text chunks for a file within a project.
    ///
    /// Computes a sentence embedding for each chunk using Apple's NaturalLanguage framework
    /// and stores the vectors for later retrieval.
    ///
    /// - Parameters:
    ///   - chunks: Text chunks to embed and index.
    ///   - fileId: The UUID of the source file.
    ///   - projectId: The UUID of the project the file belongs to.
    func index(chunks: [String], fileId: UUID, projectId: UUID) async throws {
        guard let embedding = NLEmbedding.sentenceEmbedding(for: .english) else {
            throw VectorStoreError.embeddingNotAvailable
        }

        // Remove any existing entries for this file to avoid duplicates on re-index.
        entries.removeAll { $0.fileId == fileId }

        for chunk in chunks {
            let trimmed = chunk.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            guard let vector = embedding.vector(for: trimmed) else {
                // Skip chunks that fail to embed rather than aborting the entire batch.
                #if DEBUG
                print("[VectorStoreService] Skipping chunk that failed to embed: \(trimmed.prefix(50))")
                #endif
                continue
            }

            let entry = VectorEntry(
                id: UUID(),
                text: trimmed,
                embedding: vector,
                fileId: fileId,
                projectId: projectId
            )
            entries.append(entry)
        }

        isDirty = true
        try await persist()
    }

    // MARK: - Search

    /// Search the vector store for chunks most similar to the query within a project.
    ///
    /// - Parameters:
    ///   - query: The search query text.
    ///   - projectId: Limit results to this project.
    ///   - topK: Maximum number of results to return (default: 5).
    /// - Returns: An array of search results sorted by descending similarity score.
    func search(query: String, projectId: UUID, topK: Int = 5) -> [SearchResult] {
        guard let embedding = NLEmbedding.sentenceEmbedding(for: .english) else {
            return []
        }

        guard let queryVector = embedding.vector(for: query) else {
            return []
        }

        let projectEntries = entries.filter { $0.projectId == projectId }
        guard !projectEntries.isEmpty else { return [] }

        // Compute cosine similarity for each entry.
        var scored: [(entry: VectorEntry, score: Float)] = []
        scored.reserveCapacity(projectEntries.count)

        for entry in projectEntries {
            let similarity = cosineSimilarity(queryVector, entry.embedding)
            scored.append((entry, Float(similarity)))
        }

        // Sort by descending similarity and take the top K.
        scored.sort { $0.score > $1.score }
        let topResults = scored.prefix(topK)

        return topResults.map { item in
            SearchResult(text: item.entry.text, score: item.score, fileId: item.entry.fileId)
        }
    }

    // MARK: - File Management

    /// Remove all indexed entries for a specific file.
    func removeEntries(forFileId fileId: UUID) async throws {
        entries.removeAll { $0.fileId == fileId }
        isDirty = true
        try await persist()
    }

    /// Remove all indexed entries for a specific project.
    func removeEntries(forProjectId projectId: UUID) async throws {
        entries.removeAll { $0.projectId == projectId }
        isDirty = true
        try await persist()
    }

    /// Remove all entries from the store.
    func removeAll() async throws {
        entries.removeAll()
        isDirty = true
        try await persist()
    }

    /// The total number of indexed vectors.
    var entryCount: Int { entries.count }

    /// The number of indexed vectors for a specific project.
    func entryCount(forProjectId projectId: UUID) -> Int {
        entries.filter { $0.projectId == projectId }.count
    }

    // MARK: - Persistence

    /// Write the current entries to disk.
    private func persist() async throws {
        guard isDirty else { return }

        let fm = FileManager.default
        let directory = storeFileURL.deletingLastPathComponent()
        if !fm.fileExists(atPath: directory.path) {
            do {
                try fm.createDirectory(at: directory, withIntermediateDirectories: true)
            } catch {
                throw VectorStoreError.persistenceFailed(underlying: error)
            }
        }

        do {
            let data = try encoder.encode(entries)
            try data.write(to: storeFileURL, options: .atomic)
            isDirty = false
        } catch {
            throw VectorStoreError.persistenceFailed(underlying: error)
        }
    }

    // MARK: - Cosine Similarity

    /// Compute the cosine similarity between two vectors.
    ///
    /// Returns a value between -1.0 (opposite) and 1.0 (identical).
    private func cosineSimilarity(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0.0 }

        var dotProduct: Double = 0.0
        var normA: Double = 0.0
        var normB: Double = 0.0

        for i in 0..<a.count {
            dotProduct += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }

        let denominator = sqrt(normA) * sqrt(normB)
        guard denominator > 0 else { return 0.0 }

        return dotProduct / denominator
    }
}

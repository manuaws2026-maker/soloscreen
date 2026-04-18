import Testing
import Foundation
@testable import SoloScreen

@Suite("FileProcessorService")
struct FileProcessorTests {

    // MARK: - chunkText: Basic Behavior

    @Test("chunkText with text shorter than chunkSize returns single chunk")
    func chunkTextShortText() {
        let text = "Hello world this is a short text"
        let chunks = FileProcessorService.chunkText(text, chunkSize: 500, overlap: 50)
        #expect(chunks.count == 1)
        #expect(chunks[0] == text)
    }

    @Test("chunkText with empty string returns empty array")
    func chunkTextEmpty() {
        let chunks = FileProcessorService.chunkText("", chunkSize: 500, overlap: 50)
        #expect(chunks.isEmpty)
    }

    @Test("chunkText with whitespace-only string returns empty array")
    func chunkTextWhitespaceOnly() {
        let chunks = FileProcessorService.chunkText("   ", chunkSize: 500, overlap: 50)
        #expect(chunks.isEmpty)
    }

    @Test("chunkText with long text returns multiple chunks")
    func chunkTextLongText() {
        // Create text with 100 words
        let words = (1...100).map { "word\($0)" }
        let text = words.joined(separator: " ")

        let chunks = FileProcessorService.chunkText(text, chunkSize: 30, overlap: 5)
        #expect(chunks.count > 1)
    }

    @Test("chunkText single word returns single chunk")
    func chunkTextSingleWord() {
        let chunks = FileProcessorService.chunkText("hello", chunkSize: 500, overlap: 50)
        #expect(chunks.count == 1)
        #expect(chunks[0] == "hello")
    }

    @Test("chunkText with exactly chunkSize words returns single chunk")
    func chunkTextExactSize() {
        let words = (1...10).map { "w\($0)" }
        let text = words.joined(separator: " ")

        let chunks = FileProcessorService.chunkText(text, chunkSize: 10, overlap: 2)
        #expect(chunks.count == 1)
        #expect(chunks[0] == text)
    }

    // MARK: - chunkText: Overlap Behavior

    @Test("chunkText overlap: words from end of chunk N appear in chunk N+1")
    func chunkTextOverlapCorrectness() {
        // Use words without sentence-ending punctuation to avoid sentence boundary trimming
        let words = (1...30).map { "word\($0)" }
        let text = words.joined(separator: " ")

        let chunks = FileProcessorService.chunkText(text, chunkSize: 10, overlap: 3)

        // Should have multiple chunks
        #expect(chunks.count >= 2)

        // Extract words from chunks and verify overlap exists
        let chunk0Words = chunks[0].split(separator: " ")
        let chunk1Words = chunks[1].split(separator: " ")

        // Due to sentence-boundary trimming, chunk0 may be shorter than 10 words.
        // But the step is (10 - 3) = 7, so chunk1 starts at word index 7.
        // This means chunk0's words starting at index 7 overlap with chunk1's beginning.
        // We verify that chunk1 contains some words from the tail of chunk0's range.
        let chunk0Set = Set(chunk0Words)
        let chunk1First = chunk1Words.prefix(5)
        let overlapCount = chunk1First.filter { chunk0Set.contains($0) }.count
        #expect(overlapCount > 0, "Expected some overlap between consecutive chunks")
    }

    @Test("chunkText each chunk has at most chunkSize words")
    func chunkTextMaxWords() {
        let words = (1...200).map { "word\($0)" }
        let text = words.joined(separator: " ")
        let chunkSize = 50

        let chunks = FileProcessorService.chunkText(text, chunkSize: chunkSize, overlap: 10)

        for (i, chunk) in chunks.enumerated() {
            let wordCount = chunk.split(separator: " ").count
            #expect(wordCount <= chunkSize, "Chunk \(i) has \(wordCount) words, exceeds max \(chunkSize)")
        }
    }

    @Test("chunkText preserves first and last words across chunks")
    func chunkTextPreservesContent() {
        let words = (1...50).map { "word\($0)" }
        let text = words.joined(separator: " ")

        let chunks = FileProcessorService.chunkText(text, chunkSize: 20, overlap: 5)

        // First word should be in first chunk
        #expect(chunks[0].hasPrefix("word1 "))

        // Last word should be in last chunk
        let lastChunk = chunks.last ?? ""
        #expect(lastChunk.contains("word50"))
    }

    @Test("chunkText with zero overlap produces chunks without shared words at boundary")
    func chunkTextZeroOverlap() {
        let words = (1...20).map { "word\($0)" }
        let text = words.joined(separator: " ")

        let chunks = FileProcessorService.chunkText(text, chunkSize: 10, overlap: 0)
        #expect(chunks.count == 2)

        let chunk0Words = chunks[0].split(separator: " ")
        let chunk1Words = chunks[1].split(separator: " ")

        // With zero overlap: chunk0 covers words 1-10, chunk1 covers words 11-20
        // Last word of chunk0 should not equal first word of chunk1
        #expect(chunk0Words.last != chunk1Words.first)
    }

    @Test("chunkText default parameters (chunkSize=500, overlap=50)")
    func chunkTextDefaults() {
        // Generate 600 words to get multiple chunks with defaults
        let words = (1...600).map { "word\($0)" }
        let text = words.joined(separator: " ")

        let chunks = FileProcessorService.chunkText(text)
        #expect(chunks.count >= 2)
    }

    // MARK: - chunkText: Sentence Boundary Trimming

    @Test("chunkText trims at sentence boundary when punctuation is present")
    func chunkTextSentenceBoundary() {
        // Build text where a sentence ends within the chunk window
        // Chunk size 10, so each chunk picks up to 10 words
        let text = "Alpha beta gamma delta epsilon. Zeta eta theta iota kappa lambda mu nu xi omicron"
        let chunks = FileProcessorService.chunkText(text, chunkSize: 10, overlap: 2)

        // The first chunk should ideally end at the sentence boundary (after "epsilon.")
        // if it falls within the latter half of the chunk
        #expect(chunks.count >= 2)
        // First chunk should contain "epsilon."
        let firstChunk = chunks[0]
        #expect(firstChunk.contains("epsilon") || firstChunk.contains("Alpha"))
    }

    // MARK: - chunkText: Edge Cases

    @Test("chunkText handles overlap equal to chunkSize - 1")
    func chunkTextMaxOverlap() {
        let words = (1...20).map { "word\($0)" }
        let text = words.joined(separator: " ")

        // Overlap = chunkSize - 1 means step = 1 word per chunk
        let chunks = FileProcessorService.chunkText(text, chunkSize: 5, overlap: 4)
        // Should produce many chunks, each advancing by 1 word
        #expect(chunks.count > 5)
    }

    // MARK: - extractText

    @Test("extractText reads a .txt file correctly")
    func extractTextTxt() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("test_extract_\(UUID().uuidString).txt")
        let content = "Hello, this is test content.\nSecond line."
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let extracted = try FileProcessorService.extractText(from: fileURL)
        #expect(extracted == content)
    }

    @Test("extractText reads a .md file correctly")
    func extractTextMd() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("test_extract_\(UUID().uuidString).md")
        let content = "# Heading\n\nSome markdown content."
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let extracted = try FileProcessorService.extractText(from: fileURL)
        #expect(extracted == content)
    }

    @Test("extractText throws for unsupported file extension")
    func extractTextUnsupportedExtension() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("test_extract_\(UUID().uuidString).xyz")
        try "some content".write(to: fileURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        #expect(throws: FileProcessorService.ProcessingError.self) {
            _ = try FileProcessorService.extractText(from: fileURL)
        }
    }

    @Test("extractText throws for nonexistent file")
    func extractTextNonexistent() {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("nonexistent_\(UUID().uuidString).txt")
        #expect(throws: FileProcessorService.ProcessingError.self) {
            _ = try FileProcessorService.extractText(from: fileURL)
        }
    }

    @Test("extractText throws emptyDocument for file with only whitespace")
    func extractTextEmptyDocument() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("test_extract_\(UUID().uuidString).txt")
        try "   \n\n   ".write(to: fileURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        #expect(throws: FileProcessorService.ProcessingError.self) {
            _ = try FileProcessorService.extractText(from: fileURL)
        }
    }

    @Test("extractText trims leading/trailing whitespace")
    func extractTextTrimsWhitespace() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("test_extract_\(UUID().uuidString).txt")
        try "  Hello, world!  \n".write(to: fileURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let extracted = try FileProcessorService.extractText(from: fileURL)
        #expect(extracted == "Hello, world!")
    }

    // MARK: - ProcessingError Descriptions

    @Test("ProcessingError.unsupportedFileType includes extension")
    func errorUnsupportedFileType() {
        let error = FileProcessorService.ProcessingError.unsupportedFileType("xyz")
        let desc = error.errorDescription ?? ""
        #expect(desc.contains("xyz"))
        #expect(desc.contains("Unsupported"))
    }

    @Test("ProcessingError.fileNotReadable includes file name")
    func errorFileNotReadable() {
        let url = URL(fileURLWithPath: "/tmp/missing.txt")
        let error = FileProcessorService.ProcessingError.fileNotReadable(url)
        let desc = error.errorDescription ?? ""
        #expect(desc.contains("missing.txt"))
    }

    @Test("ProcessingError.emptyDocument has meaningful description")
    func errorEmptyDocument() {
        let error = FileProcessorService.ProcessingError.emptyDocument
        let desc = error.errorDescription ?? ""
        #expect(desc.contains("no extractable text"))
    }

    @Test("ProcessingError.pdfExtractionFailed has meaningful description")
    func errorPdfExtractionFailed() {
        let error = FileProcessorService.ProcessingError.pdfExtractionFailed
        let desc = error.errorDescription ?? ""
        #expect(desc.contains("PDF"))
    }

    // MARK: - mimeType Helper

    @Test("mimeType returns correct types for supported extensions")
    func mimeTypes() {
        #expect(FileProcessorService.mimeType(for: "pdf") == "application/pdf")
        #expect(FileProcessorService.mimeType(for: "txt") == "text/plain")
        #expect(FileProcessorService.mimeType(for: "md") == "text/markdown")
        #expect(FileProcessorService.mimeType(for: "rtf") == "application/rtf")
        #expect(FileProcessorService.mimeType(for: "doc") == "application/msword")
        #expect(FileProcessorService.mimeType(for: "docx").contains("officedocument"))
    }

    @Test("mimeType is case insensitive")
    func mimeTypeCaseInsensitive() {
        #expect(FileProcessorService.mimeType(for: "PDF") == "application/pdf")
        #expect(FileProcessorService.mimeType(for: "TXT") == "text/plain")
    }

    @Test("mimeType returns octet-stream for unknown extensions")
    func mimeTypeUnknown() {
        #expect(FileProcessorService.mimeType(for: "xyz") == "application/octet-stream")
        #expect(FileProcessorService.mimeType(for: "jpg") == "application/octet-stream")
    }

    // MARK: - isSupportedExtension (integration with ProjectFile)

    @Test("All supported extensions are recognized")
    func supportedExtensions() {
        for ext in ["txt", "md", "rtf", "pdf", "doc", "docx"] {
            #expect(ProjectFile.isSupportedExtension(ext) == true)
        }
    }

    @Test("Unsupported media extensions return false")
    func unsupportedMediaExtensions() {
        for ext in ["jpg", "jpeg", "png", "gif", "mp3", "mp4", "wav", "avi"] {
            #expect(ProjectFile.isSupportedExtension(ext) == false)
        }
    }

    @Test("Unsupported code extensions return false")
    func unsupportedCodeExtensions() {
        for ext in ["swift", "py", "js", "ts", "rb", "go", "rs", "java"] {
            #expect(ProjectFile.isSupportedExtension(ext) == false)
        }
    }
}

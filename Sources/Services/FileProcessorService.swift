import Foundation
import PDFKit
import AppKit

/// Extracts text from various document formats and splits text into chunks for RAG.
///
/// This is a stateless utility, so all methods are static. Supported formats:
/// PDF, TXT, MD, RTF, DOC, DOCX.
enum FileProcessorService {

    // MARK: - Errors

    enum ProcessingError: LocalizedError {
        case unsupportedFileType(String)
        case fileNotReadable(URL)
        case pdfExtractionFailed
        case textExtractionFailed(underlying: Error)
        case emptyDocument

        var errorDescription: String? {
            switch self {
            case .unsupportedFileType(let ext):
                return "Unsupported file type: .\(ext). Supported types: txt, md, rtf, pdf, doc, docx."
            case .fileNotReadable(let url):
                return "Cannot read file at \(url.lastPathComponent)."
            case .pdfExtractionFailed:
                return "Failed to extract text from PDF."
            case .textExtractionFailed(let err):
                return "Text extraction failed: \(err.localizedDescription)"
            case .emptyDocument:
                return "The document contains no extractable text."
            }
        }
    }

    // MARK: - Text Extraction

    /// Extract text content from a file at the given URL.
    ///
    /// Dispatches to the appropriate extraction method based on file extension.
    /// - Parameter url: Path to the file on disk.
    /// - Returns: The extracted text content.
    static func extractText(from url: URL) throws -> String {
        guard FileManager.default.isReadableFile(atPath: url.path) else {
            throw ProcessingError.fileNotReadable(url)
        }

        let ext = url.pathExtension.lowercased()

        let text: String
        switch ext {
        case "pdf":
            text = try extractTextFromPDF(url)
        case "txt", "md":
            text = try extractTextFromPlainText(url)
        case "rtf":
            text = try extractTextFromRTF(url)
        case "doc":
            text = try extractTextFromDoc(url)
        case "docx":
            text = try extractTextFromDocx(url)
        default:
            throw ProcessingError.unsupportedFileType(ext)
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ProcessingError.emptyDocument
        }

        return trimmed
    }

    // MARK: - PDF Extraction

    /// Extract text from a PDF file page by page using PDFKit.
    private static func extractTextFromPDF(_ url: URL) throws -> String {
        guard let document = PDFDocument(url: url) else {
            throw ProcessingError.pdfExtractionFailed
        }

        let pageCount = document.pageCount
        guard pageCount > 0 else {
            throw ProcessingError.pdfExtractionFailed
        }

        var pages: [String] = []
        pages.reserveCapacity(pageCount)

        for pageIndex in 0..<pageCount {
            guard let page = document.page(at: pageIndex) else { continue }
            if let pageText = page.string, !pageText.isEmpty {
                pages.append(pageText)
            }
        }

        return pages.joined(separator: "\n\n")
    }

    // MARK: - Plain Text Extraction

    /// Read a plain text file (txt, md) as UTF-8.
    private static func extractTextFromPlainText(_ url: URL) throws -> String {
        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            // Fallback: try detecting the encoding.
            do {
                var encoding: String.Encoding = .utf8
                let content = try String(contentsOf: url, usedEncoding: &encoding)
                return content
            } catch {
                throw ProcessingError.textExtractionFailed(underlying: error)
            }
        }
    }

    // MARK: - RTF Extraction

    /// Extract text from an RTF file using NSAttributedString.
    private static func extractTextFromRTF(_ url: URL) throws -> String {
        do {
            let data = try Data(contentsOf: url)
            let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
                .documentType: NSAttributedString.DocumentType.rtf
            ]
            let attributedString = try NSAttributedString(
                data: data,
                options: options,
                documentAttributes: nil
            )
            return attributedString.string
        } catch {
            throw ProcessingError.textExtractionFailed(underlying: error)
        }
    }

    // MARK: - DOC Extraction

    /// Extract text from a .doc file.
    ///
    /// Attempts to use NSAttributedString's doc format reader. Falls back to
    /// reading as plain text if that fails, since some .doc files are plain text
    /// with a .doc extension.
    private static func extractTextFromDoc(_ url: URL) throws -> String {
        do {
            let data = try Data(contentsOf: url)

            // Try reading as a Word document format.
            let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
                .documentType: NSAttributedString.DocumentType.docFormat
            ]
            let attributedString = try NSAttributedString(
                data: data,
                options: options,
                documentAttributes: nil
            )
            return attributedString.string
        } catch {
            // Fallback: attempt to read as plain text.
            do {
                return try extractTextFromPlainText(url)
            } catch {
                throw ProcessingError.textExtractionFailed(underlying: error)
            }
        }
    }

    // MARK: - DOCX Extraction

    /// Extract text from a .docx file.
    ///
    /// DOCX files are ZIP archives containing XML. NSAttributedString can handle
    /// many DOCX files via the officeOpenXML document type. Falls back to plain text.
    private static func extractTextFromDocx(_ url: URL) throws -> String {
        do {
            let data = try Data(contentsOf: url)

            // Try reading as an Office Open XML document.
            let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
                .documentType: NSAttributedString.DocumentType.officeOpenXML
            ]
            let attributedString = try NSAttributedString(
                data: data,
                options: options,
                documentAttributes: nil
            )
            return attributedString.string
        } catch {
            // Fallback: try plain text.
            do {
                return try extractTextFromPlainText(url)
            } catch {
                throw ProcessingError.textExtractionFailed(underlying: error)
            }
        }
    }

    // MARK: - Text Chunking

    /// Split text into overlapping chunks for vector embedding and RAG retrieval.
    ///
    /// Chunks are split on sentence boundaries when possible for more coherent results.
    /// Each chunk overlaps with the next by `overlap` words to preserve context at boundaries.
    ///
    /// - Parameters:
    ///   - text: The full text to split.
    ///   - chunkSize: Target number of words per chunk (default: 500).
    ///   - overlap: Number of overlapping words between consecutive chunks (default: 50).
    /// - Returns: An array of text chunks.
    static func chunkText(_ text: String, chunkSize: Int = 500, overlap: Int = 50) -> [String] {
        let effectiveChunkSize = max(1, chunkSize)
        let effectiveOverlap = max(0, min(overlap, effectiveChunkSize - 1))

        let words = text.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard !words.isEmpty else { return [] }

        // If the text fits in a single chunk, return it as-is.
        if words.count <= effectiveChunkSize {
            return [words.joined(separator: " ")]
        }

        var chunks: [String] = []
        var startIndex = 0

        while startIndex < words.count {
            let endIndex = min(startIndex + effectiveChunkSize, words.count)
            let chunkWords = Array(words[startIndex..<endIndex])
            var chunk = chunkWords.joined(separator: " ")

            // Try to end the chunk at a sentence boundary for cleaner splits.
            if endIndex < words.count {
                chunk = trimToSentenceBoundary(chunk) ?? chunk
            }

            chunks.append(chunk)

            // Advance by (chunkSize - overlap) words.
            let step = effectiveChunkSize - effectiveOverlap
            startIndex += max(1, step)
        }

        return chunks
    }

    /// Attempt to trim a chunk to end at the last sentence boundary.
    ///
    /// Returns `nil` if no sentence boundary is found in the latter half of the text
    /// (we avoid trimming too aggressively).
    private static func trimToSentenceBoundary(_ text: String) -> String? {
        let sentenceEnders: [Character] = [".", "!", "?"]
        let halfwayIndex = text.index(text.startIndex, offsetBy: text.count / 2, limitedBy: text.endIndex) ?? text.startIndex

        // Search backwards from the end for the last sentence-ending character.
        if let lastSentenceEnd = text.lastIndex(where: { sentenceEnders.contains($0) }),
           lastSentenceEnd > halfwayIndex {
            let endIndex = text.index(after: lastSentenceEnd)
            return String(text[text.startIndex..<endIndex])
        }

        return nil
    }

    // MARK: - MIME Type Helper

    /// Determine the MIME type for a file extension.
    static func mimeType(for pathExtension: String) -> String {
        switch pathExtension.lowercased() {
        case "pdf":  return "application/pdf"
        case "txt":  return "text/plain"
        case "md":   return "text/markdown"
        case "rtf":  return "application/rtf"
        case "doc":  return "application/msword"
        case "docx": return "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        default:     return "application/octet-stream"
        }
    }
}

import Foundation

/// A parsed markdown block element.
enum MarkdownBlock {
    case paragraph(text: String)
    case heading(level: Int, text: String)
    case codeBlock(language: String?, code: String)
    case unorderedList(items: [String])
    case orderedList(items: [String])
    case horizontalRule
    /// Rendered as a grid: first row is the header, followed by data rows.
    /// Each row's cell count matches the header count (padded/truncated by
    /// the parser if needed).
    case table(headers: [String], rows: [[String]])
}

/// Line-by-line markdown parser that splits raw text into block elements.
/// Handles: paragraphs, headings, fenced code blocks, bullet/numbered lists,
/// and horizontal rules. Inline formatting (bold, italic, inline code, links)
/// is preserved in the text for SwiftUI's AttributedString to handle.
enum MarkdownParser {

    static func parse(_ input: String) -> [MarkdownBlock] {
        let lines = input.components(separatedBy: "\n")
        var blocks: [MarkdownBlock] = []

        var inCodeBlock = false
        var codeLanguage: String?
        var codeLines: [String] = []

        var paragraphLines: [String] = []
        var unorderedItems: [String] = []
        var orderedItems: [String] = []
        var tableBuffer: [String] = []      // `|a|b|c|` rows accumulate here
        var tableDetected = false           // true once we confirm a separator row (|---|---|)

        func flushTable() {
            guard tableDetected, tableBuffer.count >= 2 else {
                // Invalid table — flush the accumulated lines as a paragraph.
                for l in tableBuffer { paragraphLines.append(l) }
                tableBuffer.removeAll()
                tableDetected = false
                return
            }
            // tableBuffer layout: [header, separator, ...rows]
            let headers = parseTableRow(tableBuffer[0])
            let rows = tableBuffer.dropFirst(2).map { parseTableRow($0) }
            let columnCount = headers.count
            // Normalize each data row to match header column count.
            let normalized = rows.map { row -> [String] in
                if row.count >= columnCount { return Array(row.prefix(columnCount)) }
                return row + Array(repeating: "", count: columnCount - row.count)
            }
            blocks.append(.table(headers: headers, rows: normalized))
            tableBuffer.removeAll()
            tableDetected = false
        }

        func flushParagraph() {
            guard !paragraphLines.isEmpty else { return }
            let text = paragraphLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                blocks.append(.paragraph(text: text))
            }
            paragraphLines.removeAll()
        }

        func flushUnorderedList() {
            guard !unorderedItems.isEmpty else { return }
            blocks.append(.unorderedList(items: unorderedItems))
            unorderedItems.removeAll()
        }

        func flushOrderedList() {
            guard !orderedItems.isEmpty else { return }
            blocks.append(.orderedList(items: orderedItems))
            orderedItems.removeAll()
        }

        func flushAll() {
            flushTable()
            flushParagraph()
            flushUnorderedList()
            flushOrderedList()
        }

        for line in lines {
            // --- Inside a fenced code block ---
            if inCodeBlock {
                let stripped = line.trimmingCharacters(in: .whitespaces)
                if stripped.hasPrefix("```") && stripped.drop(while: { $0 == "`" }).allSatisfy(\.isWhitespace) {
                    blocks.append(.codeBlock(language: codeLanguage, code: codeLines.joined(separator: "\n")))
                    codeLines.removeAll()
                    codeLanguage = nil
                    inCodeBlock = false
                } else {
                    codeLines.append(line)
                }
                continue
            }

            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // --- Opening code fence ---
            if trimmed.hasPrefix("```") {
                flushAll()
                let lang = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                codeLanguage = lang.isEmpty ? nil : lang
                inCodeBlock = true
                continue
            }

            // --- Heading ---
            if let (level, text) = parseHeading(trimmed) {
                flushAll()
                blocks.append(.heading(level: level, text: text))
                continue
            }

            // --- Horizontal rule ---
            if isHorizontalRule(trimmed) && paragraphLines.isEmpty {
                flushAll()
                blocks.append(.horizontalRule)
                continue
            }

            // --- Unordered list item ---
            if let itemText = parseUnorderedListItem(trimmed) {
                flushParagraph()
                flushOrderedList()
                unorderedItems.append(itemText)
                continue
            }

            // --- Ordered list item ---
            if let itemText = parseOrderedListItem(trimmed) {
                flushParagraph()
                flushUnorderedList()
                orderedItems.append(itemText)
                continue
            }

            // --- Blank line ---
            if trimmed.isEmpty {
                flushAll()
                continue
            }

            // --- Markdown table rows (`| a | b | c |`) ---
            if isTableRow(trimmed) {
                // Second row must be a separator (`|---|---|`) — if the
                // buffer already has one line and this IS the separator,
                // mark the table as detected.
                if tableBuffer.count == 1 && isTableSeparatorRow(trimmed) {
                    tableDetected = true
                } else if !tableBuffer.isEmpty && !tableDetected {
                    // Second+ row but we never saw a separator — not a
                    // table. Dump accumulated rows as paragraph text.
                    for l in tableBuffer { paragraphLines.append(l) }
                    tableBuffer.removeAll()
                }
                flushUnorderedList()
                flushOrderedList()
                flushParagraph()
                tableBuffer.append(trimmed)
                continue
            } else if !tableBuffer.isEmpty {
                // Any non-table line ends the table.
                flushTable()
            }

            // --- Regular text (paragraph continuation) ---
            flushUnorderedList()
            flushOrderedList()
            paragraphLines.append(line)
        }

        // End of input — flush remaining. If code block is unclosed (streaming),
        // emit what we have.
        if inCodeBlock {
            blocks.append(.codeBlock(language: codeLanguage, code: codeLines.joined(separator: "\n")))
        }
        flushAll()

        return blocks
    }

    // MARK: - Helpers

    /// Parse "# heading text" → (level, text). Returns nil if not a heading.
    private static func parseHeading(_ line: String) -> (Int, String)? {
        var level = 0
        var i = line.startIndex
        while i < line.endIndex && line[i] == "#" && level < 6 {
            level += 1
            i = line.index(after: i)
        }
        guard level > 0, i < line.endIndex, line[i] == " " else { return nil }
        let text = String(line[line.index(after: i)...]).trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : (level, text)
    }

    /// Check if a line is a horizontal rule (---, ***, ___).
    private static func isHorizontalRule(_ line: String) -> Bool {
        let stripped = line.filter { !$0.isWhitespace }
        guard stripped.count >= 3, let first = stripped.first else { return false }
        return (first == "-" || first == "*" || first == "_") && stripped.allSatisfy({ $0 == first })
    }

    /// Parse "- item" or "* item" or "+ item" → item text.
    private static func parseUnorderedListItem(_ line: String) -> String? {
        guard let first = line.first, (first == "-" || first == "*" || first == "+") else { return nil }
        guard line.count >= 3 else { return nil }
        let afterMarker = line.index(line.startIndex, offsetBy: 1)
        guard line[afterMarker] == " " else { return nil }
        let text = String(line[line.index(afterMarker, offsetBy: 1)...])
        return text.isEmpty ? nil : text
    }

    /// Does the line look like a markdown table row — i.e. starts and ends
    /// with `|` (after trimming) and contains at least one more `|`?
    private static func isTableRow(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.hasPrefix("|"), t.hasSuffix("|"), t.count >= 3 else { return false }
        // Must have at least 2 `|` (start + end + an inner one).
        return t.filter({ $0 == "|" }).count >= 2
    }

    /// Detect the separator row: `|---|:---|---:|` (dashes + optional colons).
    private static func isTableSeparatorRow(_ line: String) -> Bool {
        let cells = parseTableRow(line)
        guard !cells.isEmpty else { return false }
        return cells.allSatisfy { cell in
            let stripped = cell.trimmingCharacters(in: .whitespaces)
            guard stripped.count >= 3 else { return false }
            // Accept leading/trailing `:` for alignment markers.
            let inner = stripped.trimmingCharacters(in: CharacterSet(charactersIn: ":"))
            return !inner.isEmpty && inner.allSatisfy { $0 == "-" }
        }
    }

    /// Split `| a | b | c |` → ["a", "b", "c"].
    private static func parseTableRow(_ line: String) -> [String] {
        var t = line.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("|") { t.removeFirst() }
        if t.hasSuffix("|") { t.removeLast() }
        return t.split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    /// Parse "1. item" → item text.
    private static func parseOrderedListItem(_ line: String) -> String? {
        var i = line.startIndex
        while i < line.endIndex && line[i].isNumber { i = line.index(after: i) }
        guard i > line.startIndex, i < line.endIndex, line[i] == "." else { return nil }
        i = line.index(after: i)
        guard i < line.endIndex, line[i] == " " else { return nil }
        let text = String(line[line.index(after: i)...])
        return text.isEmpty ? nil : text
    }
}

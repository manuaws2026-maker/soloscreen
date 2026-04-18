import Foundation

/// Matches a user's system-design question against a bundled library of
/// pre-written answers. When a confident match is found, `SoloScreen` serves
/// the pre-written answer directly (no LLM call). On a miss, the caller
/// falls through to the LLM — the System Design Help template prompt will
/// produce a response in the same shape.
@MainActor
final class SystemDesignStore {

    static let shared = SystemDesignStore()

    /// keyword/alias (lowercased) → filename (e.g. "uber" → "uber.sysdesign")
    private var index: [String: String] = [:]

    /// topic (filename stem, lowercased) → markdown-rendered body.
    private var articles: [String: String] = [:]

    private var isLoaded = false

    // MARK: - Public API

    struct Match {
        let topic: String      // e.g. "bitly"
        let title: String      // e.g. "Bitly"
        let markdown: String
    }

    /// Look up a pre-built design for the user's query. Returns nil when
    /// nothing matches confidently — caller should then call the LLM.
    func prebuiltDesign(for query: String) -> Match? {
        loadIfNeeded()
        guard !articles.isEmpty else { return nil }

        let q = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return nil }

        // Require at least one "system design" intent keyword OR a direct
        // topic match, to avoid false positives on coding questions that
        // happen to mention a product name.
        let designKeywords = ["design", "architect", "system design", "scale", "build"]
        let hasDesignKeyword = designKeywords.contains { q.contains($0) }

        // 1) Direct topic containment — query mentions the exact topic.
        for topic in articles.keys where q.contains(topic) {
            if let md = articles[topic] {
                return Match(topic: topic, title: Self.titleize(topic), markdown: md)
            }
        }

        // 2) Exact index alias match.
        if let filename = index[q] {
            let topic = filename.replacingOccurrences(of: ".sysdesign", with: "")
            if let md = articles[topic] {
                return Match(topic: topic, title: Self.titleize(topic), markdown: md)
            }
        }

        // 3) Fuzzy alias match — only when query has a design-intent keyword.
        guard hasDesignKeyword else { return nil }
        var best: (key: String, score: Double, filename: String)?
        for (key, filename) in index {
            let score = fuzzyScore(query: q, key: key)
            if score > (best?.score ?? 0) { best = (key, score, filename) }
        }
        if let match = best, match.score >= 0.4 {
            let topic = match.filename.replacingOccurrences(of: ".sysdesign", with: "")
            if let md = articles[topic] {
                return Match(topic: topic, title: Self.titleize(topic), markdown: md)
            }
        }

        return nil
    }

    /// All available topic names (sorted) — useful for debug/UI.
    var availableTopics: [String] {
        loadIfNeeded()
        return articles.keys.sorted()
    }

    // MARK: - Loading

    private func loadIfNeeded() {
        guard !isLoaded else { return }
        isLoaded = true

        guard let base = Bundle.module.resourceURL?
            .appendingPathComponent("system-design", isDirectory: true),
            FileManager.default.fileExists(atPath: base.path)
        else {
            // Fallback: SwiftPM sometimes flattens; look in bundle root.
            loadFromFlattenedBundle()
            return
        }

        loadFrom(directory: base)
    }

    private func loadFromFlattenedBundle() {
        guard let root = Bundle.module.resourceURL,
              let files = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        else { return }

        for file in files where file.pathExtension == "sysdesign" {
            registerArticle(at: file)
        }
        if let indexURL = files.first(where: { $0.lastPathComponent == "sysdesign-index.json" }) {
            loadIndex(from: indexURL)
        }
    }

    private func loadFrom(directory: URL) {
        loadIndex(from: directory.appendingPathComponent("sysdesign-index.json"))

        if let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            for file in files where file.pathExtension == "sysdesign" {
                registerArticle(at: file)
            }
        }

        #if DEBUG
        NSLog("[SystemDesignStore] loaded %d articles, %d index entries", articles.count, index.count)
        #endif
    }

    private func loadIndex(from url: URL) {
        guard let data = try? Data(contentsOf: url),
              let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: String]
        else { return }
        // Normalize keys.
        var out: [String: String] = [:]
        for (k, v) in parsed { out[k.lowercased()] = v }
        self.index = out
    }

    private func registerArticle(at file: URL) {
        guard let raw = try? String(contentsOf: file, encoding: .utf8) else { return }
        let topic = file.deletingPathExtension().lastPathComponent.lowercased()
        let markdown = Self.convertSysDesignToMarkdown(raw, title: Self.titleize(topic))
        articles[topic] = markdown
    }

    // MARK: - Format conversion (.sysdesign → markdown)

    /// Convert the `[SYSDESIGN] --- SECTION: ... [SAY]...[/SAY] [DETAIL]...[/DETAIL]`
    /// format to plain markdown that SoloScreen's existing MarkdownContentView renders.
    /// `[SAY]` text becomes normal prose (teleprompter voice); `[DETAIL]` content is
    /// already markdown — code fences, tables, mermaid fences — and is emitted verbatim.
    static func convertSysDesignToMarkdown(_ raw: String, title: String) -> String {
        var out = "# \(title)\n\n"

        // Strip the outer [SYSDESIGN] wrapper if present.
        var body = raw
        if let r = body.range(of: "[SYSDESIGN]") { body.removeSubrange(r) }
        if let r = body.range(of: "[/SYSDESIGN]") { body.removeSubrange(r) }

        // Split on section markers.
        let lines = body.components(separatedBy: "\n")
        var currentSection: String?
        var buffer = ""

        func flush() {
            guard let sec = currentSection else { return }
            let processed = renderSection(buffer)
            let heading = prettifyHeading(sec, sectionBody: buffer)
            out += "## \(heading)\n\n\(processed)\n\n"
            buffer = ""
        }

        for line in lines {
            if line.hasPrefix("--- SECTION:") {
                flush()
                currentSection = line
                    .replacingOccurrences(of: "--- SECTION:", with: "")
                    .trimmingCharacters(in: .whitespaces)
            } else if currentSection != nil {
                buffer += line + "\n"
            }
        }
        flush()

        return out
    }

    /// Inside a single section, extract [SAY]...[/SAY] and [DETAIL]...[/DETAIL]
    /// blocks. Emit SAY text as a prose paragraph, then DETAIL content (cleaned
    /// of tutorial/instructor artifacts that sometimes leaked in during source
    /// scraping).
    private static func renderSection(_ text: String) -> String {
        var out = ""
        if let say = extract(tag: "SAY", from: text) {
            out += say.trimmingCharacters(in: .whitespacesAndNewlines) + "\n\n"
        }
        if let detail = extract(tag: "DETAIL", from: text) {
            let cleaned = cleanDetail(detail)
            if !cleaned.isEmpty {
                out += cleaned + "\n"
            }
        }
        if out.isEmpty {
            out = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return out
    }

    // MARK: - Heading cleaner

    /// Section headings in the source files are sometimes truncated with an
    /// ellipsis — e.g. `Deep Dive: How would you efficiently calculate and
    /// update the averag...`. Reconstruct a better heading when we can:
    ///   1. If the section body has a `**Problem:** <full question>` line,
    ///      use that question as the title.
    ///   2. Otherwise, just strip the trailing `...`.
    private static func prettifyHeading(_ raw: String, sectionBody: String) -> String {
        var heading = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard heading.hasSuffix("...") else { return heading }

        // Look for `**Problem:** <full question>` in the section body.
        if let problemRange = sectionBody.range(of: "**Problem:**") {
            let tail = sectionBody[problemRange.upperBound...]
            let line = tail.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? ""
            let question = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if !question.isEmpty {
                // Preserve the "Deep Dive:" prefix if the original had it so the
                // rendered heading says e.g. "Deep Dive — <question>".
                if heading.lowercased().contains("deep dive") {
                    return "Deep Dive — \(question)"
                }
                return question
            }
        }

        // Fallback: strip the trailing ellipsis.
        while heading.hasSuffix(".") {
            heading.removeLast()
        }
        return heading.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Detail cleaner

    /// Telltale instructor/tutorial phrases that sometimes leak in from the
    /// HelloInterview-style source material. Paragraphs containing these are
    /// dropped from the output so the answer reads like a candidate's script
    /// rather than a textbook.
    private static let tutorialPhrases: [String] = [
        "your goal is to",
        "the next step is",
        "the next step in the framework",
        "this sets up a contract between",
        "usually, these map 1:1",
        "now, we have a few options",
        "let's dive into this"
    ]

    private static func cleanDetail(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Split into paragraphs while keeping fenced code blocks intact.
        var out: [String] = []
        var buffer: [String] = []
        var insideFence = false

        func flush() {
            let para = buffer.joined(separator: "\n")
            if !para.isEmpty, !isTutorialParagraph(para) {
                out.append(fixupParagraph(para))
            }
            buffer.removeAll()
        }

        for line in trimmed.components(separatedBy: "\n") {
            if line.hasPrefix("```") {
                // Closing fence flushes the code-containing buffer as-is.
                buffer.append(line)
                insideFence.toggle()
                if !insideFence {
                    let fenced = buffer.joined(separator: "\n")
                    out.append(sanitizeFencedBlock(fenced))
                    buffer.removeAll()
                }
                continue
            }
            if insideFence {
                buffer.append(line)
                continue
            }
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                flush()
            } else {
                buffer.append(line)
            }
        }
        flush()

        return out.joined(separator: "\n\n")
    }

    /// A paragraph is considered instructor/tutorial prose if it contains one
    /// of our known-bad phrases AND isn't inside a code block. Dropped wholesale.
    private static func isTutorialParagraph(_ text: String) -> Bool {
        let lower = text.lowercased()
        return tutorialPhrases.contains { lower.contains($0) }
    }

    /// Heuristic fixes for common source artifacts in plain prose paragraphs:
    /// - "ApproachOur goal…" → "Approach\n\nOur goal…" (missing space between
    ///   bold header and body text after concatenation)
    private static func fixupParagraph(_ text: String) -> String {
        // Insert a break between a standalone capitalized word at the start of
        // a line (which was likely a bold header) and the following sentence.
        let pattern = #"^(Approach|Challenges|Considerations|Alternatives considered|Why)([A-Z][a-z])"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let ns = text as NSString
        return regex.stringByReplacingMatches(
            in: text,
            range: NSRange(location: 0, length: ns.length),
            withTemplate: "**$1**\n\n$2"
        )
    }

    /// Clean up Mermaid diagrams that were damaged during source scraping.
    /// Specifically: drop node IDs that look like English prose fragments
    /// (`TheAppropriate`, `WhetherThe`, `AnyAdditional`) — if a mermaid block
    /// has any of these, the whole block is replaced with a terse note because
    /// trying to re-render garbage produces worse results than showing text.
    private static func sanitizeFencedBlock(_ block: String) -> String {
        let header = block.components(separatedBy: "\n").first ?? ""
        guard header.lowercased().contains("mermaid") else { return block }

        let badNodePattern = #"\b(The[A-Z][a-z]+[A-Z]|Whether[A-Z]|AnyAdditional|TheAppropriate)\b"#
        if let re = try? NSRegularExpression(pattern: badNodePattern),
           re.firstMatch(in: block, range: NSRange(location: 0, length: (block as NSString).length)) != nil {
            return "> *(Architecture diagram omitted — the pre-built source has a scraping artifact here. See the prose above for the flow.)*"
        }
        return block
    }

    private static func extract(tag: String, from text: String) -> String? {
        let open = "[\(tag)]"
        let close = "[/\(tag)]"
        guard let openRange = text.range(of: open),
              let closeRange = text.range(of: close),
              openRange.upperBound <= closeRange.lowerBound
        else { return nil }
        return String(text[openRange.upperBound..<closeRange.lowerBound])
    }

    // MARK: - Matching helpers

    private func fuzzyScore(query: String, key: String) -> Double {
        if query == key { return 1.0 }
        if query.contains(key) || key.contains(query) { return 0.85 }

        let qWords = Self.words(query)
        let kWords = Self.words(key)
        let intersection = qWords.intersection(kWords)
        let union = qWords.union(kWords)
        guard !union.isEmpty else { return 0 }

        let jaccard = Double(intersection.count) / Double(union.count)
        let significant = kWords.filter { $0.count > 3 }
        let sigBoost = significant.intersection(qWords).isEmpty ? 0.0 : 0.2
        return min(jaccard + sigBoost, 1.0)
    }

    private static func words(_ phrase: String) -> Set<String> {
        Set(
            phrase
                .replacingOccurrences(of: "-", with: " ")
                .replacingOccurrences(of: "_", with: " ")
                .split(separator: " ")
                .map { String($0).lowercased() }
        )
    }

    private static func titleize(_ topic: String) -> String {
        topic.replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }
}

import AppKit

/// Renders Mermaid diagrams to an NSImage via the `mermaid.ink` HTTP API.
/// No WKWebView or bundled JS needed.
///
/// How it works:
///   1. Build a JSON config `{"code":"…","mermaid":{"theme":"dark"}}`.
///   2. Base64-encode it, URL-escape it.
///   3. GET `https://mermaid.ink/img/<encoded>` — server responds with SVG bytes.
///   4. Load bytes directly into an `NSImage`.
///   5. Cache by source hash; retry on transient errors.
@MainActor
final class MermaidRenderer {
    static let shared = MermaidRenderer()

    private var cache: [Int: NSImage] = [:]
    private var cacheOrder: [Int] = []
    private var inflight: [Int: Task<NSImage?, Never>] = [:]
    private static let maxCache = 20

    private static let maxRetries = 3
    private static let retryDelays: [UInt64] = [500_000_000, 1_500_000_000, 3_000_000_000]

    func render(source: String) async -> NSImage? {
        let sanitized = Self.sanitizeMermaidSource(source)
        let key = sanitized.hashValue

        if let cached = cache[key] { return cached }
        if let existing = inflight[key] { return await existing.value }

        let task = Task<NSImage?, Never> { @MainActor in
            let image = await fetchSVG(source: sanitized)

            if let image {
                cache[key] = image
                cacheOrder.append(key)
                if cacheOrder.count > Self.maxCache {
                    let evict = cacheOrder.removeFirst()
                    cache.removeValue(forKey: evict)
                }
            }

            inflight.removeValue(forKey: key)
            return image
        }

        inflight[key] = task
        return await task.value
    }

    private func fetchSVG(source: String) async -> NSImage? {
        let config = "{\"code\":\(jsonEscape(source)),\"mermaid\":{\"theme\":\"dark\"}}"
        guard let encoded = config.data(using: .utf8)?.base64EncodedString()
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
        else { return nil }

        let urlString = "https://mermaid.ink/img/\(encoded)"
        guard let url = URL(string: urlString) else { return nil }

        for attempt in 0...Self.maxRetries {
            do {
                var request = URLRequest(url: url)
                request.timeoutInterval = 12

                let (data, response) = try await URLSession.shared.data(for: request)
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0

                if statusCode == 200, !data.isEmpty {
                    return NSImage(data: data)
                }

                let retryable = statusCode == 503 || statusCode == 429 || statusCode >= 500
                if !retryable || attempt == Self.maxRetries { return nil }
            } catch {
                if attempt == Self.maxRetries { return nil }
            }
            try? await Task.sleep(nanoseconds: Self.retryDelays[min(attempt, Self.retryDelays.count - 1)])
        }
        return nil
    }

    private func jsonEscape(_ s: String) -> String {
        let escaped = s
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
        return "\"\(escaped)\""
    }

    // MARK: - Source sanitizer

    /// Fix common mermaid syntax issues that LLMs often produce:
    ///  • `A <-- B` reverse arrows (not supported) → `B --> A`
    ///  • `Node[text (with) chars]` unquoted labels → `Node["text (with) chars"]`
    ///  • `{region}` curly braces inside labels → `(region)` (avoid diamond parse)
    static func sanitizeMermaidSource(_ source: String) -> String {
        var lines = source.components(separatedBy: "\n")

        let reverseArrow = try! NSRegularExpression(
            pattern: #"^(\s*)(.*?)\s+(<-[-.]+-?>?)\s+(.*?)\s*$"#
        )
        for i in lines.indices {
            let line = lines[i]
            let ns = line as NSString
            if let m = reverseArrow.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) {
                let indent = ns.substring(with: m.range(at: 1))
                let left = ns.substring(with: m.range(at: 2))
                let arrow = ns.substring(with: m.range(at: 3))
                let right = ns.substring(with: m.range(at: 4))
                let forwardArrow = arrow
                    .replacingOccurrences(of: "<-", with: "-")
                    .replacingOccurrences(of: "->", with: "->")
                    + (arrow.hasSuffix(">") ? "" : ">")
                let clean = forwardArrow.hasPrefix("--") ? forwardArrow : "-->"
                lines[i] = "\(indent)\(right) \(clean) \(left)"
            }
        }

        var result = lines.joined(separator: "\n")

        let boxPattern = try! NSRegularExpression(
            pattern: #"(\w+)\[(?!\"|'|\([\"\'])([^\]\[]*[(/&)][^\]\[]*)\]"#
        )
        let ns = result as NSString
        let matches = boxPattern.matches(in: result, range: NSRange(location: 0, length: ns.length))
        for match in matches.reversed() {
            let fullRange = match.range
            let id = ns.substring(with: match.range(at: 1))
            let label = ns.substring(with: match.range(at: 2))
            let trimmed = label.trimmingCharacters(in: .whitespaces)
            let replacement: String
            if trimmed.hasPrefix("(") && trimmed.hasSuffix(")") {
                let inner = String(trimmed.dropFirst().dropLast())
                replacement = "\(id)[(\"\(inner)\")]"
            } else {
                replacement = "\(id)[\"\(label)\"]"
            }
            result = (result as NSString).replacingCharacters(in: fullRange, with: replacement)
        }

        let curlyInLabel = try! NSRegularExpression(pattern: #"\{(\w+)\}"#)
        result = curlyInLabel.stringByReplacingMatches(
            in: result,
            range: NSRange(location: 0, length: (result as NSString).length),
            withTemplate: "($1)"
        )

        return result
    }
}

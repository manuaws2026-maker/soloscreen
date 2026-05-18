import SwiftUI
import AppKit

enum CodeLanguage: String {
    case swift, java, python, javascript, typescript, go, rust
    case c, cpp, csharp, kotlin, ruby, php, scala
    case json, yaml, xml, html, css, markdown, shell, sql
    case plain

    static func from(extension ext: String) -> CodeLanguage {
        switch ext.lowercased() {
        case "swift": return .swift
        case "java": return .java
        case "py", "pyw": return .python
        case "js", "jsx", "mjs", "cjs": return .javascript
        case "ts", "tsx": return .typescript
        case "go": return .go
        case "rs": return .rust
        case "c", "h": return .c
        case "cpp", "cc", "cxx", "hpp", "hh", "hxx": return .cpp
        case "cs": return .csharp
        case "kt", "kts": return .kotlin
        case "rb": return .ruby
        case "php": return .php
        case "scala", "sc": return .scala
        case "json": return .json
        case "yaml", "yml": return .yaml
        case "xml", "plist": return .xml
        case "html", "htm": return .html
        case "css", "scss", "sass", "less": return .css
        case "md", "markdown": return .markdown
        case "sh", "bash", "zsh", "fish": return .shell
        case "sql": return .sql
        default: return .plain
        }
    }

    var displayName: String {
        switch self {
        case .swift: return "Swift"
        case .java: return "Java"
        case .python: return "Python"
        case .javascript: return "JavaScript"
        case .typescript: return "TypeScript"
        case .go: return "Go"
        case .rust: return "Rust"
        case .c: return "C"
        case .cpp: return "C++"
        case .csharp: return "C#"
        case .kotlin: return "Kotlin"
        case .ruby: return "Ruby"
        case .php: return "PHP"
        case .scala: return "Scala"
        case .json: return "JSON"
        case .yaml: return "YAML"
        case .xml: return "XML"
        case .html: return "HTML"
        case .css: return "CSS"
        case .markdown: return "Markdown"
        case .shell: return "Shell"
        case .sql: return "SQL"
        case .plain: return "Plain"
        }
    }
}

/// VS Code Dark+ inspired palette.
enum SyntaxPalette {
    static let plain     = Color(hex: "D4D4D4")
    static let keyword   = Color(hex: "C586C0")  // purple — control flow
    static let storage   = Color(hex: "569CD6")  // blue — declarations
    static let type      = Color(hex: "4EC9B0")  // teal — types
    static let string    = Color(hex: "CE9178")  // orange
    static let number    = Color(hex: "B5CEA8")  // light green
    static let comment   = Color(hex: "6A9955")  // green
    static let function  = Color(hex: "DCDCAA")  // yellow
    static let constant  = Color(hex: "4FC1FF")  // light blue
    static let attribute = Color(hex: "9CDCFE")  // pale blue

    static func nsColor(_ swiftUIColor: Color) -> NSColor { NSColor(swiftUIColor) }
}

struct SyntaxHighlighter {
    /// Returns an NSAttributedString with foreground colors set per token.
    /// Background and font are set by the caller (the text view).
    static func highlight(_ source: String, language: CodeLanguage, font: NSFont) -> NSAttributedString {
        let utf16Length = (source as NSString).length
        var colors = [Color?](repeating: nil, count: utf16Length)

        let rules = ruleset(for: language)
        let fullRange = NSRange(location: 0, length: utf16Length)

        for rule in rules {
            guard let regex = try? NSRegularExpression(pattern: rule.pattern, options: rule.options) else { continue }
            regex.enumerateMatches(in: source, options: [], range: fullRange) { match, _, _ in
                guard let match else { return }
                guard rule.captureGroup < match.numberOfRanges else { return }
                let r = match.range(at: rule.captureGroup)
                if r.location == NSNotFound { return }
                // Don't overwrite a color that's already been claimed by an earlier
                // (higher-priority) rule. Comments and strings come first; later
                // keyword matches that fall inside them should be ignored.
                let end = min(r.location + r.length, colors.count)
                for i in r.location..<end {
                    if colors[i] == nil { colors[i] = rule.color }
                }
            }
        }

        let attr = NSMutableAttributedString(string: source)
        attr.addAttribute(.font, value: font, range: fullRange)
        attr.addAttribute(.foregroundColor, value: SyntaxPalette.nsColor(SyntaxPalette.plain), range: fullRange)

        // Coalesce adjacent same-color runs and apply.
        var runStart = 0
        var runColor: Color? = colors.first ?? nil
        var i = 1
        while i <= utf16Length {
            let c = i < utf16Length ? colors[i] : nil
            if i == utf16Length || c != runColor {
                if let color = runColor {
                    let range = NSRange(location: runStart, length: i - runStart)
                    attr.addAttribute(.foregroundColor, value: SyntaxPalette.nsColor(color), range: range)
                }
                runStart = i
                runColor = c
            }
            i += 1
        }
        return attr
    }

    // MARK: - Rules

    private struct Rule {
        let pattern: String
        let color: Color
        let options: NSRegularExpression.Options
        let captureGroup: Int

        init(_ pattern: String, _ color: Color, options: NSRegularExpression.Options = [], capture: Int = 0) {
            self.pattern = pattern
            self.color = color
            self.options = options
            self.captureGroup = capture
        }
    }

    private static func ruleset(for language: CodeLanguage) -> [Rule] {
        switch language {
        case .swift:    return swiftRules
        case .java, .kotlin, .scala: return jvmRules
        case .python:   return pythonRules
        case .javascript, .typescript: return jsRules
        case .go:       return goRules
        case .rust:     return rustRules
        case .c, .cpp, .csharp: return cFamilyRules
        case .ruby:     return rubyRules
        case .php:      return phpRules
        case .json:     return jsonRules
        case .yaml:     return yamlRules
        case .xml, .html: return xmlRules
        case .css:      return cssRules
        case .markdown: return markdownRules
        case .shell:    return shellRules
        case .sql:      return sqlRules
        case .plain:    return []
        }
    }

    // First-claim-wins: ordering matters. Comments and strings always go first
    // so keywords inside them aren't recolored.

    private static let stringDouble    = Rule(#""([^"\\]|\\.)*""#, SyntaxPalette.string)
    private static let stringSingle    = Rule(#"'([^'\\]|\\.)*'"#, SyntaxPalette.string)
    private static let stringBacktick  = Rule(#"`([^`\\]|\\.)*`"#, SyntaxPalette.string)
    private static let lineCommentSlash = Rule(#"//[^\n]*"#, SyntaxPalette.comment)
    private static let blockCommentC    = Rule(#"/\*[\s\S]*?\*/"#, SyntaxPalette.comment)
    private static let lineCommentHash  = Rule(#"#[^\n]*"#, SyntaxPalette.comment)
    private static let lineCommentDash  = Rule(#"--[^\n]*"#, SyntaxPalette.comment)
    private static let numberLiteral    = Rule(#"\b(0[xX][0-9a-fA-F_]+|0[bB][01_]+|[0-9][0-9_]*(\.[0-9_]+)?([eE][+-]?[0-9_]+)?[fFdDlLuU]?)\b"#, SyntaxPalette.number)
    private static let funcCall         = Rule(#"\b([a-zA-Z_][a-zA-Z0-9_]*)\s*\("#, SyntaxPalette.function, capture: 1)

    private static func keywordRule(_ words: [String], color: Color = SyntaxPalette.keyword) -> Rule {
        Rule("\\b(?:\(words.joined(separator: "|")))\\b", color)
    }

    private static let swiftRules: [Rule] = [
        lineCommentSlash, blockCommentC, stringDouble, numberLiteral,
        keywordRule([
            "if","else","guard","switch","case","default","for","while","repeat","break","continue","return","do","try","throw","throws","rethrows","catch","defer","where","in","is","as","fallthrough"
        ]),
        keywordRule([
            "class","struct","enum","protocol","extension","func","var","let","init","deinit","subscript","typealias","associatedtype","import","open","public","internal","private","fileprivate","static","final","lazy","weak","unowned","mutating","nonmutating","convenience","required","override","async","await","actor","inout","some","any"
        ], color: SyntaxPalette.storage),
        keywordRule(["true","false","nil","self","Self","super"], color: SyntaxPalette.constant),
        Rule(#"@[a-zA-Z_][a-zA-Z0-9_]*"#, SyntaxPalette.attribute),
        funcCall,
        Rule(#"\b[A-Z][a-zA-Z0-9_]*\b"#, SyntaxPalette.type),
    ]

    private static let jvmRules: [Rule] = [
        lineCommentSlash, blockCommentC, stringDouble, stringSingle, numberLiteral,
        keywordRule([
            "if","else","switch","case","default","for","while","do","break","continue","return","try","catch","finally","throw","throws","yield","when"
        ]),
        keywordRule([
            "class","interface","enum","object","trait","record","extends","implements","abstract","final","sealed","static","public","private","protected","internal","package","import","new","this","super","void","var","val","def","fun","let","const","override","open","data"
        ], color: SyntaxPalette.storage),
        keywordRule(["true","false","null","None"], color: SyntaxPalette.constant),
        Rule(#"@[a-zA-Z_][a-zA-Z0-9_]*"#, SyntaxPalette.attribute),
        funcCall,
        Rule(#"\b(int|long|short|byte|double|float|boolean|char)\b"#, SyntaxPalette.storage),
        Rule(#"\b[A-Z][a-zA-Z0-9_]*\b"#, SyntaxPalette.type),
    ]

    private static let pythonRules: [Rule] = [
        lineCommentHash, stringDouble, stringSingle, numberLiteral,
        keywordRule([
            "if","elif","else","for","while","break","continue","return","try","except","finally","raise","with","yield","pass","async","await","match","case"
        ]),
        keywordRule([
            "def","class","import","from","as","global","nonlocal","lambda","del","is","in","not","and","or"
        ], color: SyntaxPalette.storage),
        keywordRule(["True","False","None","self","cls"], color: SyntaxPalette.constant),
        Rule(#"@[a-zA-Z_][a-zA-Z0-9_\.]*"#, SyntaxPalette.attribute),
        funcCall,
        Rule(#"\b(int|str|float|bool|list|dict|tuple|set|bytes|bytearray|object)\b"#, SyntaxPalette.type),
    ]

    private static let jsRules: [Rule] = [
        lineCommentSlash, blockCommentC, stringDouble, stringSingle, stringBacktick, numberLiteral,
        keywordRule([
            "if","else","switch","case","default","for","while","do","break","continue","return","try","catch","finally","throw","yield"
        ]),
        keywordRule([
            "var","let","const","function","class","extends","interface","type","enum","import","export","from","as","default","new","this","super","async","await","static","public","private","protected","readonly","abstract","implements","namespace","declare","of","in","typeof","instanceof","void","delete"
        ], color: SyntaxPalette.storage),
        keywordRule(["true","false","null","undefined","NaN","Infinity"], color: SyntaxPalette.constant),
        Rule(#"@[a-zA-Z_][a-zA-Z0-9_]*"#, SyntaxPalette.attribute),
        funcCall,
        Rule(#"\b(string|number|boolean|object|symbol|bigint|any|unknown|never)\b"#, SyntaxPalette.storage),
        Rule(#"\b[A-Z][a-zA-Z0-9_]*\b"#, SyntaxPalette.type),
    ]

    private static let goRules: [Rule] = [
        lineCommentSlash, blockCommentC, stringDouble, stringBacktick, numberLiteral,
        keywordRule(["if","else","switch","case","default","for","break","continue","return","go","defer","select","range","fallthrough"]),
        keywordRule(["package","import","func","var","const","type","struct","interface","map","chan"], color: SyntaxPalette.storage),
        keywordRule(["true","false","nil","iota"], color: SyntaxPalette.constant),
        funcCall,
        Rule(#"\b(string|bool|byte|rune|int|int8|int16|int32|int64|uint|uint8|uint16|uint32|uint64|uintptr|float32|float64|complex64|complex128|error)\b"#, SyntaxPalette.storage),
        Rule(#"\b[A-Z][a-zA-Z0-9_]*\b"#, SyntaxPalette.type),
    ]

    private static let rustRules: [Rule] = [
        lineCommentSlash, blockCommentC, stringDouble, numberLiteral,
        Rule(#"#!?\[[^\]]*\]"#, SyntaxPalette.attribute),
        keywordRule(["if","else","match","for","while","loop","break","continue","return"]),
        keywordRule([
            "fn","let","mut","const","static","struct","enum","trait","impl","mod","use","pub","crate","super","self","Self","as","where","ref","move","async","await","dyn","unsafe","extern","type","box"
        ], color: SyntaxPalette.storage),
        keywordRule(["true","false","None","Some","Ok","Err"], color: SyntaxPalette.constant),
        funcCall,
        Rule(#"\b(i8|i16|i32|i64|i128|isize|u8|u16|u32|u64|u128|usize|f32|f64|bool|char|str)\b"#, SyntaxPalette.storage),
        Rule(#"\b[A-Z][a-zA-Z0-9_]*\b"#, SyntaxPalette.type),
    ]

    private static let cFamilyRules: [Rule] = [
        lineCommentSlash, blockCommentC, stringDouble, stringSingle, numberLiteral,
        Rule(#"^\s*#\s*\w+"#, SyntaxPalette.attribute, options: [.anchorsMatchLines]),
        keywordRule(["if","else","switch","case","default","for","while","do","break","continue","return","goto","try","catch","throw","finally"]),
        keywordRule([
            "class","struct","enum","union","namespace","template","typename","public","private","protected","virtual","override","final","static","const","constexpr","mutable","volatile","inline","extern","auto","using","typedef","new","delete","this","sizeof","operator","friend","var","record","internal","sealed","async","await","readonly","ref","out"
        ], color: SyntaxPalette.storage),
        keywordRule(["true","false","NULL","nullptr","null"], color: SyntaxPalette.constant),
        funcCall,
        Rule(#"\b(int|long|short|char|float|double|bool|void|unsigned|signed)\b"#, SyntaxPalette.storage),
        Rule(#"\b[A-Z][a-zA-Z0-9_]*\b"#, SyntaxPalette.type),
    ]

    private static let rubyRules: [Rule] = [
        lineCommentHash, stringDouble, stringSingle, numberLiteral,
        keywordRule(["if","elsif","else","unless","case","when","then","for","while","until","do","break","next","return","redo","retry","begin","rescue","ensure","yield","end"]),
        keywordRule(["def","class","module","require","require_relative","include","extend","attr_accessor","attr_reader","attr_writer","alias","lambda","proc"], color: SyntaxPalette.storage),
        keywordRule(["true","false","nil","self"], color: SyntaxPalette.constant),
        Rule(#":\w+"#, SyntaxPalette.constant),
        Rule(#"@@?[a-zA-Z_][a-zA-Z0-9_]*"#, SyntaxPalette.attribute),
        funcCall,
        Rule(#"\b[A-Z][a-zA-Z0-9_]*\b"#, SyntaxPalette.type),
    ]

    private static let phpRules: [Rule] = [
        lineCommentSlash, lineCommentHash, blockCommentC, stringDouble, stringSingle, numberLiteral,
        keywordRule(["if","else","elseif","switch","case","default","for","foreach","while","do","break","continue","return","try","catch","finally","throw","yield"]),
        keywordRule(["class","interface","trait","extends","implements","abstract","final","public","private","protected","static","function","var","const","new","clone","namespace","use","as","global","echo","print","require","include","require_once","include_once"], color: SyntaxPalette.storage),
        keywordRule(["true","false","null","TRUE","FALSE","NULL"], color: SyntaxPalette.constant),
        Rule(#"\$[a-zA-Z_][a-zA-Z0-9_]*"#, SyntaxPalette.attribute),
        funcCall,
        Rule(#"\b[A-Z][a-zA-Z0-9_]*\b"#, SyntaxPalette.type),
    ]

    private static let jsonRules: [Rule] = [
        Rule(#""([^"\\]|\\.)*"(?=\s*:)"#, SyntaxPalette.attribute),
        stringDouble,
        numberLiteral,
        keywordRule(["true","false","null"], color: SyntaxPalette.constant),
    ]

    private static let yamlRules: [Rule] = [
        lineCommentHash,
        Rule(#"^\s*[-]?\s*([a-zA-Z_][\w\-]*)\s*:"#, SyntaxPalette.attribute, options: [.anchorsMatchLines], capture: 1),
        stringDouble, stringSingle, numberLiteral,
        keywordRule(["true","false","null","yes","no","on","off"], color: SyntaxPalette.constant),
    ]

    private static let xmlRules: [Rule] = [
        Rule(#"<!--[\s\S]*?-->"#, SyntaxPalette.comment),
        Rule(#"</?([a-zA-Z][\w\-]*)"#, SyntaxPalette.storage, capture: 1),
        Rule(#"\b([a-zA-Z\-:]+)\s*="#, SyntaxPalette.attribute, capture: 1),
        stringDouble, stringSingle,
    ]

    private static let cssRules: [Rule] = [
        blockCommentC,
        Rule(#"([.#]?[a-zA-Z\-_][\w\-]*)\s*\{"#, SyntaxPalette.type, capture: 1),
        Rule(#"\b([a-zA-Z\-]+)\s*:"#, SyntaxPalette.attribute, capture: 1),
        stringDouble, stringSingle, numberLiteral,
        Rule(#"#[0-9a-fA-F]{3,8}\b"#, SyntaxPalette.constant),
        Rule(#"!important\b"#, SyntaxPalette.keyword),
    ]

    private static let markdownRules: [Rule] = [
        Rule(#"^#{1,6}\s.*$"#, SyntaxPalette.storage, options: [.anchorsMatchLines]),
        Rule(#"```[\s\S]*?```"#, SyntaxPalette.string),
        Rule(#"`[^`\n]+`"#, SyntaxPalette.string),
        Rule(#"\*\*[^*]+\*\*"#, SyntaxPalette.constant),
        Rule(#"\[[^\]]+\]\([^)]+\)"#, SyntaxPalette.function),
        Rule(#"^>\s.*$"#, SyntaxPalette.comment, options: [.anchorsMatchLines]),
    ]

    private static let shellRules: [Rule] = [
        lineCommentHash, stringDouble, stringSingle, numberLiteral,
        keywordRule(["if","then","else","elif","fi","case","esac","for","while","do","done","in","function","return","break","continue","exit"]),
        keywordRule(["export","local","readonly","declare","alias","source","unset"], color: SyntaxPalette.storage),
        Rule(#"\$\{?[a-zA-Z_][a-zA-Z0-9_]*\}?"#, SyntaxPalette.attribute),
        funcCall,
    ]

    private static let sqlRules: [Rule] = [
        lineCommentDash, blockCommentC, stringSingle, stringDouble, numberLiteral,
        Rule(#"\b(SELECT|FROM|WHERE|INSERT|INTO|VALUES|UPDATE|SET|DELETE|CREATE|DROP|ALTER|TABLE|INDEX|VIEW|JOIN|INNER|LEFT|RIGHT|OUTER|FULL|ON|AS|GROUP|BY|ORDER|HAVING|LIMIT|OFFSET|UNION|ALL|DISTINCT|CASE|WHEN|THEN|ELSE|END|AND|OR|NOT|IN|EXISTS|BETWEEN|LIKE|IS|NULL|TRUE|FALSE|PRIMARY|KEY|FOREIGN|REFERENCES|CONSTRAINT|UNIQUE|CHECK|DEFAULT|WITH|RETURNING|RECURSIVE)\b"#, SyntaxPalette.keyword, options: [.caseInsensitive]),
        Rule(#"\b(INT|INTEGER|BIGINT|SMALLINT|VARCHAR|CHAR|TEXT|DATE|TIME|TIMESTAMP|BOOLEAN|BOOL|FLOAT|DOUBLE|DECIMAL|NUMERIC|UUID|JSON|JSONB|SERIAL)\b"#, SyntaxPalette.type, options: [.caseInsensitive]),
    ]
}

import SwiftUI

/// Renders parsed markdown blocks as a vertical stack of styled SwiftUI views.
///
/// Conforms to `Equatable` so SwiftUI can skip body evaluation when the
/// content hasn't changed. This is critical when the parent uses a
/// non-lazy `VStack` (for correct scroll behaviour) — without it, every
/// streaming token would re-parse markdown for ALL messages in the chat.
struct MarkdownContentView: View, Equatable {
    let content: String
    let accentTeal: Color
    let borderColor: Color

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.content == rhs.content
    }

    private let codeBg = Color(hex: "0D1117")
    private let codeHeaderBg = Color(hex: "1C2128")

    private var blocks: [MarkdownBlock] {
        MarkdownParser.parse(content)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(for: block)
            }
        }
    }

    @ViewBuilder
    private func blockView(for block: MarkdownBlock) -> some View {
        switch block {
        case .paragraph(let text):
            paragraphView(text)
                .padding(.horizontal, 14)

        case .heading(let level, let text):
            headingView(level: level, text: text)
                .padding(.horizontal, 14)

        case .codeBlock(let language, let code):
            if language?.lowercased() == "mermaid" {
                // Render the diagram as an image via mermaid.ink (no
                // local JS renderer needed).
                MermaidDiagramView(source: code,
                                   accentTeal: accentTeal,
                                   borderColor: borderColor,
                                   codeBg: codeBg)
                    .padding(.horizontal, 6)
            } else {
                CodeBlockView(
                    language: language,
                    code: code,
                    accentTeal: accentTeal,
                    borderColor: borderColor,
                    codeBg: codeBg,
                    codeHeaderBg: codeHeaderBg
                )
                .padding(.horizontal, 6)
            }

        case .unorderedList(let items):
            unorderedListView(items)
                .padding(.horizontal, 14)

        case .orderedList(let items):
            orderedListView(items)
                .padding(.horizontal, 14)

        case .table(let headers, let rows):
            MarkdownTableView(
                headers: headers,
                rows: rows,
                accentTeal: accentTeal,
                borderColor: borderColor,
                surfaceColor: codeHeaderBg
            )
            .padding(.horizontal, 14)

        case .horizontalRule:
            Rectangle()
                .fill(borderColor)
                .frame(height: 1)
                .padding(.horizontal, 14)
                .padding(.vertical, 2)
        }
    }

    // MARK: - Paragraph

    private func paragraphView(_ text: String) -> some View {
        Text(.init(text))
            .font(.system(size: 14))
            .foregroundStyle(.white.opacity(0.9))
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Heading

    private func headingView(level: Int, text: String) -> some View {
        let fontSize: CGFloat
        let weight: Font.Weight
        switch level {
        case 1: fontSize = 22; weight = .bold
        case 2: fontSize = 18; weight = .bold
        case 3: fontSize = 16; weight = .semibold
        default: fontSize = 14; weight = .semibold
        }
        return Text(.init(text))
            .font(.system(size: fontSize, weight: weight))
            .foregroundStyle(.white.opacity(0.95))
            .textSelection(.enabled)
            .padding(.top, level <= 2 ? 6 : 2)
    }

    // MARK: - Lists

    private func unorderedListView(_ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .top, spacing: 6) {
                    Text("•")
                        .font(.system(size: 14))
                        .foregroundStyle(accentTeal.opacity(0.7))
                    Text(.init(item))
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.9))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func orderedListView(_ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .top, spacing: 6) {
                    Text("\(index + 1).")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(accentTeal.opacity(0.7))
                        .frame(width: 20, alignment: .trailing)
                    Text(.init(item))
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.9))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

// MARK: - Code Block View

struct CodeBlockView: View {
    let language: String?
    let code: String
    let accentTeal: Color
    let borderColor: Color
    let codeBg: Color
    let codeHeaderBg: Color
    @State private var showCopied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with language + copy button
            HStack {
                Text(language ?? "code")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.5))

                Spacer()

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code, forType: .string)
                    showCopied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        showCopied = false
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: showCopied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 10))
                        Text(showCopied ? "Copied" : "Copy")
                            .font(.system(size: 10))
                    }
                    .foregroundStyle(showCopied ? .green : .white.opacity(0.5))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(codeHeaderBg)

            // Code content
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.85))
                    .textSelection(.enabled)
                    .padding(12)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(codeBg)
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(borderColor, lineWidth: 1))
        )
    }
}

// MARK: - Mermaid Diagram View

struct MermaidDiagramView: View {
    let source: String
    let accentTeal: Color
    let borderColor: Color
    let codeBg: Color

    @EnvironmentObject var appState: AppState
    @State private var image: NSImage?
    @State private var status: RenderStatus = .loading
    @State private var diagramNumber: Int?

    enum RenderStatus { case loading, ok, failed }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Header
            HStack(spacing: 6) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.system(size: 11))
                    .foregroundStyle(accentTeal.opacity(0.7))
                Text("Diagram")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.65))

                if let num = diagramNumber {
                    Text("#\(num)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(accentTeal)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(accentTeal.opacity(0.12))
                        )
                }

                Spacer()

                if status == .ok {
                    Button { expand() } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.system(size: 10))
                            Text("Expand")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundStyle(accentTeal.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                    .help("Expand diagram (⌃⇧\(diagramNumber ?? 0))")
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 6)

            switch status {
            case .loading:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Rendering diagram…")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 24)

            case .ok:
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 8)
                        .padding(.bottom, 8)
                        .onTapGesture { expand() }
                        .help("Click to expand")
                }

            case .failed:
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow.opacity(0.8))
                    Text("Couldn't render this diagram. Raw source below.")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.55))
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 6)
            }

            if status == .failed {
                ScrollView {
                    Text(source)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.8))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                }
                .frame(maxHeight: 180)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(codeBg)
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(borderColor, lineWidth: 1))
        )
        .onAppear { renderDiagram() }
        .onTapGesture { expand() }
    }

    private func renderDiagram() {
        Task { @MainActor in
            if let rendered = await MermaidRenderer.shared.render(source: source) {
                self.image = rendered
                self.status = .ok
                self.diagramNumber = appState.registerDiagram(source: source, image: rendered)
            } else {
                self.status = .failed
            }
        }
    }

    private func expand() {
        guard let image else { return }
        _ = appState.registerDiagram(source: source, image: image)
        appState.lastDiagramSource = source
        appState.lastDiagramImage = image
        appState.showExpandedDiagram = true
    }
}

// MARK: - Zoomable Diagram Overlay

struct ZoomableDiagramOverlay: View {
    let image: NSImage
    let source: String
    let onClose: () -> Void
    @State private var zoom: CGFloat = 1.0

    private let minZoom: CGFloat = 0.5
    private let maxZoom: CGFloat = 4.0
    private let step: CGFloat = 0.25

    var body: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture { onClose() }

            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "point.3.connected.trianglepath.dotted")
                        .foregroundStyle(Color(hex: "22C55E"))
                    Text("Diagram")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))

                    Spacer()

                    Button { zoom = max(minZoom, zoom - step) } label: {
                        Image(systemName: "minus.magnifyingglass").font(.system(size: 13))
                    }
                    .buttonStyle(.borderless)
                    .disabled(zoom <= minZoom)

                    Text("\(Int(zoom * 100))%")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(width: 44)

                    Button { zoom = min(maxZoom, zoom + step) } label: {
                        Image(systemName: "plus.magnifyingglass").font(.system(size: 13))
                    }
                    .buttonStyle(.borderless)
                    .disabled(zoom >= maxZoom)

                    Button { zoom = 1.0 } label: {
                        Image(systemName: "arrow.counterclockwise").font(.system(size: 12))
                    }
                    .buttonStyle(.borderless)
                    .help("Reset zoom")

                    Divider().frame(height: 16)

                    Button {
                        onClose()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "xmark").font(.system(size: 11, weight: .semibold))
                            Text("⌃⇧D")
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.5))
                        }
                    }
                    .buttonStyle(.borderless)
                    .keyboardShortcut(.escape, modifiers: [])
                    .help("Close (Esc or ⌃⇧D)")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color(hex: "161B22"))

                Divider().overlay(Color(hex: "30363D"))

                ScrollView([.horizontal, .vertical]) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: image.size.width * zoom, height: image.size.height * zoom)
                        .padding(24)
                        .animation(.easeOut(duration: 0.15), value: zoom)
                }
                .background(Color(hex: "0D1117"))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(hex: "0D1117"))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color(hex: "30363D"), lineWidth: 1))
                    .padding(24)
            )
            .shadow(color: .black.opacity(0.35), radius: 14, y: 4)
        }
    }
}

// MARK: - Markdown Table View

struct MarkdownTableView: View {
    let headers: [String]
    let rows: [[String]]
    let accentTeal: Color
    let borderColor: Color
    let surfaceColor: Color

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                // Header row
                GridRow {
                    ForEach(Array(headers.enumerated()), id: \.offset) { _, header in
                        Text(header)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.9))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .background(surfaceColor)

                Divider().overlay(borderColor)

                // Data rows
                ForEach(Array(rows.enumerated()), id: \.offset) { rowIdx, row in
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                            Text(.init(cell))
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.8))
                                .textSelection(.enabled)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .background(rowIdx % 2 == 0 ? Color.clear : surfaceColor.opacity(0.4))
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(hex: "0D1117"))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(borderColor, lineWidth: 1))
        )
    }
}

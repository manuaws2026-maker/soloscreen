import SwiftUI
import AppKit
import UniformTypeIdentifiers

extension Notification.Name {
    static let codeViewerToggleSearch = Notification.Name("codeViewerToggleSearch")
}

// MARK: - Model

struct CodeFileTab: Identifiable, Equatable {
    let id: URL
    var url: URL { id }
    var name: String { url.lastPathComponent }
    var language: CodeLanguage { CodeLanguage.from(extension: url.pathExtension) }
    /// Loaded contents — nil while loading, "" for unreadable.
    var contents: String?
    var loadError: String?
}

struct CodeFolderNode: Identifiable {
    let id: URL
    let url: URL
    let name: String
    let isDirectory: Bool
    /// Lazy-loaded children for directories. nil = not yet loaded.
    var children: [CodeFolderNode]?

    init(url: URL) {
        self.id = url
        self.url = url
        self.name = url.lastPathComponent
        self.isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        self.children = nil
    }

    /// Hidden files (dotfiles) are folded together — too noisy for an interview view.
    static func loadChildren(of url: URL) -> [CodeFolderNode] {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return contents
            .map { CodeFolderNode(url: $0) }
            .sorted { lhs, rhs in
                if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }
}

@MainActor
final class CodeViewerState: ObservableObject {
    @Published var rootFolder: URL?
    @Published var rootNode: CodeFolderNode?
    @Published var expandedDirs: Set<URL> = []
    @Published var tabs: [CodeFileTab] = []
    @Published var activeTabID: URL?

    /// 5 MB cutoff. Beyond this we show a placeholder rather than locking up the
    /// regex highlighter and TextKit on a binary or generated file.
    private let maxFileSize: Int64 = 5 * 1024 * 1024

    func presentFolderPicker() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Open Folder"
        panel.title = "Select a folder to browse"
        panel.level = .modalPanel
        if panel.runModal() == .OK, let url = panel.url {
            openFolder(url)
        }
    }

    func openFolder(_ url: URL) {
        rootFolder = url
        var node = CodeFolderNode(url: url)
        node.children = CodeFolderNode.loadChildren(of: url)
        rootNode = node
        expandedDirs = [url]
    }

    func toggleExpanded(_ url: URL) {
        if expandedDirs.contains(url) {
            expandedDirs.remove(url)
        } else {
            expandedDirs.insert(url)
        }
    }

    /// DFS through every subdirectory under `url` (and `url` itself) and add
    /// each to `expandedDirs`. We compute the new set locally and assign once
    /// at the end so SwiftUI receives a single objectWillChange instead of
    /// O(n) for large trees.
    func expandAll(under url: URL) {
        var newExpanded = expandedDirs
        var stack: [URL] = [url]
        // Cap to avoid pathological cases on huge node_modules-style trees.
        let maxVisits = 5000
        var visits = 0
        while let current = stack.popLast(), visits < maxVisits {
            visits += 1
            newExpanded.insert(current)
            guard let children = try? FileManager.default.contentsOfDirectory(
                at: current,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            for child in children {
                let isDir = (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                if isDir { stack.append(child) }
            }
        }
        expandedDirs = newExpanded
    }

    /// Remove every directory at-or-under `url` from `expandedDirs`.
    func collapseAll(under url: URL) {
        let prefix = url.path
        expandedDirs = expandedDirs.filter { dir in
            let p = dir.path
            return !(p == prefix || p.hasPrefix(prefix + "/"))
        }
    }

    func openFile(_ url: URL) {
        if tabs.contains(where: { $0.id == url }) {
            activeTabID = url
            return
        }
        var tab = CodeFileTab(id: url, contents: nil, loadError: nil)

        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
            if let size = attrs[.size] as? NSNumber, size.int64Value > maxFileSize {
                tab.loadError = "File too large to display (\(ByteCountFormatter.string(fromByteCount: size.int64Value, countStyle: .file)))."
            } else {
                let data = try Data(contentsOf: url)
                if let text = String(data: data, encoding: .utf8) {
                    tab.contents = text
                } else if let text = String(data: data, encoding: .isoLatin1) {
                    tab.contents = text
                } else {
                    tab.loadError = "Binary file — preview not available."
                }
            }
        } catch {
            tab.loadError = error.localizedDescription
        }

        tabs.append(tab)
        activeTabID = url
    }

    func closeTab(_ url: URL) {
        guard let idx = tabs.firstIndex(where: { $0.id == url }) else { return }
        tabs.remove(at: idx)
        if activeTabID == url {
            activeTabID = tabs.indices.contains(idx) ? tabs[idx].id
                        : (tabs.last?.id)
        }
    }

    var activeTab: CodeFileTab? {
        guard let id = activeTabID else { return nil }
        return tabs.first(where: { $0.id == id })
    }
}

// MARK: - Root View

struct CodeViewerView: View {
    @ObservedObject var state: CodeViewerState
    var onClose: () -> Void
    var onMinimize: () -> Void
    var onOpacityChange: (Double) -> Void

    @State private var sidebarVisible: Bool = true
    @State private var windowOpacity: Double = 1.0
    @State private var wrapText: Bool = false

    private let bgColor = Color(hex: "1E1E1E")
    private let sidebarColor = Color(hex: "252526")
    private let chromeColor = Color(hex: "2D2D30")
    private let borderColor = Color.white.opacity(0.08)

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            Divider().background(borderColor)
            HStack(spacing: 0) {
                if sidebarVisible {
                    sidebar
                        .frame(width: 260)
                        .frame(maxHeight: .infinity)
                        .background(sidebarColor)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                    Divider().background(borderColor)
                }
                editorArea
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(bgColor)
    }

    // MARK: Title bar

    private var titleBar: some View {
        HStack(spacing: 8) {
            // Sidebar toggle
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    sidebarVisible.toggle()
                }
            } label: {
                Image(systemName: sidebarVisible ? "sidebar.left" : "sidebar.leading")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 22, height: 22)
                    .background(Color.white.opacity(0.06))
                    .cornerRadius(5)
            }
            .buttonStyle(.plain)
            .help(sidebarVisible ? "Hide sidebar" : "Show sidebar")
            .padding(.leading, 8)

            // Drag area + folder name
            HStack(spacing: 6) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.6))
                Text(state.rootFolder?.lastPathComponent ?? "Code Viewer")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
            }

            Spacer()

            Button {
                state.presentFolderPicker()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "folder.badge.plus").font(.system(size: 11))
                    Text("Open Folder").font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(.white.opacity(0.85))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.08))
                .cornerRadius(5)
            }
            .buttonStyle(.plain)

            Button {
                NotificationCenter.default.post(name: .codeViewerToggleSearch, object: nil)
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 22, height: 22)
                    .background(Color.white.opacity(0.06))
                    .cornerRadius(5)
            }
            .buttonStyle(.plain)
            .help("Find in file (⌘F)")

            Button {
                wrapText.toggle()
            } label: {
                Image(systemName: wrapText ? "text.justifyleft" : "text.alignleft")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(wrapText ? 0.9 : 0.6))
                    .frame(width: 22, height: 22)
                    .background(Color.white.opacity(wrapText ? 0.14 : 0.06))
                    .cornerRadius(5)
            }
            .buttonStyle(.plain)
            .help(wrapText ? "Disable line wrapping" : "Wrap long lines")

            // Opacity slider
            HStack(spacing: 4) {
                Image(systemName: "sun.min")
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.5))
                Slider(value: $windowOpacity, in: 0.3...1.0)
                    .controlSize(.mini)
                    .frame(width: 80)
                    .onChange(of: windowOpacity) { _, new in
                        onOpacityChange(new)
                    }
                Image(systemName: "sun.max")
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.white.opacity(0.04))
            .cornerRadius(5)
            .help("Window opacity")

            Button(action: onMinimize) {
                Image(systemName: "minus")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 22, height: 22)
                    .background(Color.white.opacity(0.06))
                    .cornerRadius(5)
            }
            .buttonStyle(.plain)
            .help("Minimize to dot")

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 22, height: 22)
                    .background(Color.white.opacity(0.06))
                    .cornerRadius(5)
            }
            .buttonStyle(.plain)
            .help("Close")
            .padding(.trailing, 8)
        }
        .frame(height: 32)
        .background(chromeColor)
    }

    // MARK: Sidebar

    private var sidebar: some View {
        Group {
            if let root = state.rootNode {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        FolderTreeRow(node: root, depth: 0, state: state)
                    }
                    .padding(.vertical, 6)
                }
            } else {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "folder")
                        .font(.system(size: 32))
                        .foregroundStyle(.white.opacity(0.3))
                    Text("No folder open")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.5))
                    Button("Open Folder…") {
                        state.presentFolderPicker()
                    }
                    .controlSize(.small)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: Editor area (tabs + code)

    private var editorArea: some View {
        VStack(spacing: 0) {
            if !state.tabs.isEmpty {
                tabBar
                Divider().background(borderColor)
            }
            if let tab = state.activeTab {
                CodeFileView(tab: tab, wrapText: wrapText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                emptyEditorState
            }
        }
    }

    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(state.tabs) { tab in
                    TabChip(
                        tab: tab,
                        isActive: tab.id == state.activeTabID,
                        onSelect: { state.activeTabID = tab.id },
                        onClose: { state.closeTab(tab.id) }
                    )
                }
            }
        }
        .frame(height: 32)
        .background(chromeColor)
    }

    private var emptyEditorState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "doc.text")
                .font(.system(size: 40))
                .foregroundStyle(.white.opacity(0.2))
            Text("Select a file from the sidebar")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.4))
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(bgColor)
    }
}

// MARK: - Folder Tree Row (recursive)

private struct FolderTreeRow: View {
    let node: CodeFolderNode
    let depth: Int
    @ObservedObject var state: CodeViewerState

    @State private var isHovered: Bool = false

    private var isExpanded: Bool { state.expandedDirs.contains(node.url) }
    private var isActive: Bool { state.activeTabID == node.url }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            row
            if node.isDirectory && isExpanded, let children = childrenLoaded {
                ForEach(children) { child in
                    FolderTreeRow(node: child, depth: depth + 1, state: state)
                }
            }
        }
    }

    private var childrenLoaded: [CodeFolderNode]? {
        if let cached = node.children { return cached }
        // Lazy load on first expand. Computing here keeps the model simple at
        // the cost of recomputing if a directory is collapsed/expanded — fine
        // for typical interview-sized projects.
        return CodeFolderNode.loadChildren(of: node.url)
    }

    private var row: some View {
        ZStack {
            // Main click target — fills the row, handles open/toggle.
            Button {
                if node.isDirectory {
                    state.toggleExpanded(node.url)
                } else {
                    state.openFile(node.url)
                }
            } label: {
                HStack(spacing: 4) {
                    if node.isDirectory {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.55))
                            .frame(width: 12)
                    } else {
                        Spacer().frame(width: 12)
                    }
                    Image(systemName: node.isDirectory ? "folder.fill" : "doc")
                        .font(.system(size: 11))
                        .foregroundStyle(node.isDirectory ? Color(hex: "DCB67A") : .white.opacity(0.6))
                    Text(node.name)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(isActive ? 1.0 : 0.85))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    // Reserve space so the hover icon doesn't shift the row layout.
                    if node.isDirectory {
                        Color.clear.frame(width: 22, height: 1)
                    }
                }
                .padding(.leading, CGFloat(depth) * 12 + 6)
                .padding(.trailing, 6)
                .padding(.vertical, 3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Hover-revealed expand-all icon for directories. Sits on the
            // right edge inside the same row, layered above the main button so
            // a click on it doesn't toggle expansion.
            if node.isDirectory && isHovered {
                HStack {
                    Spacer()
                    Button {
                        state.expandAll(under: node.url)
                    } label: {
                        Image(systemName: "rectangle.expand.vertical")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.7))
                            .frame(width: 22, height: 22)
                            .background(Color.white.opacity(0.1))
                            .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                    .help("Expand all subfolders")
                    .padding(.trailing, 4)
                }
            }
        }
        .background(isActive ? Color.white.opacity(0.08) : (isHovered ? Color.white.opacity(0.04) : Color.clear))
        .onHover { isHovered = $0 }
        .contextMenu {
            if node.isDirectory {
                Button("Expand All Subfolders") { state.expandAll(under: node.url) }
                Button("Collapse All Subfolders") { state.collapseAll(under: node.url) }
            }
        }
    }
}

// MARK: - Tab Chip

private struct TabChip: View {
    let tab: CodeFileTab
    let isActive: Bool
    let onSelect: () -> Void
    let onClose: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "doc")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.5))
            Text(tab.name)
                .font(.system(size: 12))
                .foregroundStyle(isActive ? .white : .white.opacity(0.65))
                .lineLimit(1)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(hovering || isActive ? 0.7 : 0.0))
                    .frame(width: 14, height: 14)
                    .background(Color.white.opacity(hovering ? 0.08 : 0))
                    .cornerRadius(3)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxHeight: .infinity)
        .background(isActive ? Color(hex: "1E1E1E") : Color.clear)
        .overlay(alignment: .top) {
            if isActive {
                Rectangle().fill(Color(hex: "569CD6")).frame(height: 1.5)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { onSelect() }
    }
}

// MARK: - Code File View

private struct CodeFileView: View {
    let tab: CodeFileTab
    let wrapText: Bool

    var body: some View {
        if let err = tab.loadError {
            errorState(err)
        } else if let contents = tab.contents {
            HighlightedCodeView(text: contents, language: tab.language, wrapText: wrapText)
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 28))
                .foregroundStyle(.orange.opacity(0.7))
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Highlighted Code View (NSTextView)

/// NSTextView-backed code editor. Native horizontal/vertical scrolling, native
/// multi-line text selection, native ⌘F find bar, and a custom NSRulerView
/// rendering line numbers in the left margin.
private struct HighlightedCodeView: NSViewRepresentable {
    let text: String
    let language: CodeLanguage
    let wrapText: Bool

    private static let codeFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    private static let bgColor = NSColor(red: 0x1E/255.0, green: 0x1E/255.0, blue: 0x1E/255.0, alpha: 1.0)

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = false
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = Self.bgColor

        // TextKit stack — explicitly created so the text container is sized to
        // allow horizontal overflow (long lines extend off-screen and scroll).
        let container = NSTextContainer(containerSize: NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        ))
        container.widthTracksTextView = false
        container.heightTracksTextView = false

        let layoutManager = NSLayoutManager()
        layoutManager.addTextContainer(container)

        let textStorage = NSTextStorage()
        textStorage.addLayoutManager(layoutManager)

        let textView = NSTextView(
            frame: NSRect(origin: .zero, size: scrollView.contentSize),
            textContainer: container
        )
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.allowsUndo = false
        textView.drawsBackground = true
        textView.backgroundColor = Self.bgColor
        textView.textContainerInset = NSSize(width: 4, height: 6)
        textView.isHorizontallyResizable = true
        textView.isVerticallyResizable = true
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.autoresizingMask = []  // we manage size via container
        // Native ⌘F find bar.
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false

        scrollView.documentView = textView

        // Line number ruler.
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true
        let ruler = LineNumberRulerView(textView: textView)
        scrollView.verticalRulerView = ruler

        // Apply initial text + colors + wrap mode.
        applyText(to: textView, coordinator: context.coordinator)
        applyWrapMode(scrollView: scrollView, textView: textView)
        // Stash refs so the toggle-search notification can target this textView.
        context.coordinator.attach(scrollView: scrollView, textView: textView)

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        applyText(to: textView, coordinator: context.coordinator)
        applyWrapMode(scrollView: scrollView, textView: textView)
        scrollView.verticalRulerView?.needsDisplay = true
    }

    private func applyText(to textView: NSTextView, coordinator: Coordinator) {
        // Skip the (expensive) regex pass when neither text nor language changed.
        if coordinator.lastText == text && coordinator.lastLanguage == language { return }
        coordinator.lastText = text
        coordinator.lastLanguage = language

        let attr = SyntaxHighlighter.highlight(text, language: language, font: Self.codeFont)
        textView.textStorage?.setAttributedString(attr)
        textView.font = Self.codeFont
    }

    /// Switch the text container between fit-to-width (wrap) and unbounded
    /// (horizontal scroll). Called on every update so the toggle is live.
    private func applyWrapMode(scrollView: NSScrollView, textView: NSTextView) {
        guard let container = textView.textContainer else { return }
        if wrapText {
            // Width tracks the text view; text view width matches the visible area.
            let width = scrollView.contentSize.width - 50  // minus ruler width
            container.widthTracksTextView = true
            container.containerSize = NSSize(width: max(0, width), height: CGFloat.greatestFiniteMagnitude)
            textView.isHorizontallyResizable = false
            scrollView.hasHorizontalScroller = false
            // Force-resize the textView to match container width.
            var frame = textView.frame
            frame.size.width = max(0, width)
            textView.frame = frame
        } else {
            container.widthTracksTextView = false
            container.containerSize = NSSize(
                width: CGFloat.greatestFiniteMagnitude,
                height: CGFloat.greatestFiniteMagnitude
            )
            textView.isHorizontallyResizable = true
            scrollView.hasHorizontalScroller = true
        }
        textView.layoutManager?.ensureLayout(for: container)
        textView.needsDisplay = true
    }

    final class Coordinator {
        var lastText: String?
        var lastLanguage: CodeLanguage?
        weak var scrollView: NSScrollView?
        weak var textView: NSTextView?
        private var token: NSObjectProtocol?

        func attach(scrollView: NSScrollView, textView: NSTextView) {
            self.scrollView = scrollView
            self.textView = textView
            // Listen for the magnifying-glass title-bar button + ⌘F-from-elsewhere.
            token = NotificationCenter.default.addObserver(
                forName: .codeViewerToggleSearch,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.showFindBar()
            }
        }

        deinit {
            if let token { NotificationCenter.default.removeObserver(token) }
        }

        private func showFindBar() {
            guard let textView else { return }
            // Make the textView first responder so the find bar attaches here.
            textView.window?.makeFirstResponder(textView)
            let item = NSMenuItem()
            item.tag = NSTextFinder.Action.showFindInterface.rawValue
            textView.performTextFinderAction(item)
        }
    }
}

// MARK: - Line Number Ruler

private final class LineNumberRulerView: NSRulerView {
    private static let bgColor = NSColor(red: 0x1E/255.0, green: 0x1E/255.0, blue: 0x1E/255.0, alpha: 1.0)
    private static let labelColor = NSColor.white.withAlphaComponent(0.35)
    private static let labelFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)

    init(textView: NSTextView) {
        super.init(scrollView: textView.enclosingScrollView, orientation: .verticalRuler)
        clientView = textView
        ruleThickness = 50

        NotificationCenter.default.addObserver(
            self, selector: #selector(invalidate),
            name: NSText.didChangeNotification, object: textView
        )
        if let clipView = textView.enclosingScrollView?.contentView {
            clipView.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(
                self, selector: #selector(invalidate),
                name: NSView.boundsDidChangeNotification, object: clipView
            )
        }
        NotificationCenter.default.addObserver(
            self, selector: #selector(invalidate),
            name: NSView.frameDidChangeNotification, object: textView
        )
    }

    required init(coder: NSCoder) { fatalError() }

    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func invalidate() { needsDisplay = true }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView = clientView as? NSTextView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return }

        Self.bgColor.setFill()
        bounds.fill()

        // Subtle right border.
        NSColor.white.withAlphaComponent(0.06).setFill()
        NSRect(x: bounds.maxX - 0.5, y: bounds.minY, width: 0.5, height: bounds.height).fill()

        let attrs: [NSAttributedString.Key: Any] = [
            .font: Self.labelFont,
            .foregroundColor: Self.labelColor,
        ]

        let nsString = textView.string as NSString
        let inset = textView.textContainerInset.height
        let visibleRect = textView.visibleRect

        // Iterate every line in the document; draw labels only for ones whose
        // first line fragment falls inside the visible rect. O(n) per scroll —
        // fine for typical interview-sized files.
        var lineNumber = 1
        var charIdx = 0
        let totalLength = nsString.length

        // Always draw line 1 even on an empty file.
        if totalLength == 0 {
            drawLabel("1", atY: inset - visibleRect.origin.y, attrs: attrs)
            return
        }

        while charIdx < totalLength {
            let lineRange = nsString.lineRange(for: NSRange(location: charIdx, length: 0))
            let glyphRange = layoutManager.glyphRange(forCharacterRange: lineRange, actualCharacterRange: nil)
            // Only the FIRST line fragment of a logical line gets a number.
            var fragmentRange = NSRange()
            let fragmentRect = layoutManager.lineFragmentRect(
                forGlyphAt: glyphRange.location,
                effectiveRange: &fragmentRange
            )

            let yInTextView = fragmentRect.minY + inset
            let yInRuler = yInTextView - visibleRect.origin.y

            // Cull lines outside the ruler's visible bounds.
            if yInRuler + fragmentRect.height >= 0 && yInRuler <= bounds.height {
                drawLabel("\(lineNumber)", atY: yInRuler, attrs: attrs, height: fragmentRect.height)
            }

            lineNumber += 1
            let nextIdx = NSMaxRange(lineRange)
            if nextIdx <= charIdx { break }   // safety
            charIdx = nextIdx
        }

        // Trailing empty line if the document ends with a newline.
        if totalLength > 0 && nsString.character(at: totalLength - 1) == 0x0A {
            let extra = layoutManager.extraLineFragmentRect
            if !extra.isEmpty {
                let yInRuler = extra.minY + inset - visibleRect.origin.y
                if yInRuler + extra.height >= 0 && yInRuler <= bounds.height {
                    drawLabel("\(lineNumber)", atY: yInRuler, attrs: attrs, height: extra.height)
                }
            }
        }
    }

    private func drawLabel(_ text: String, atY y: CGFloat, attrs: [NSAttributedString.Key: Any], height: CGFloat = 16) {
        let label = text as NSString
        let labelSize = label.size(withAttributes: attrs)
        let drawRect = NSRect(
            x: ruleThickness - labelSize.width - 8,
            y: y + max(0, (height - labelSize.height) / 2),
            width: labelSize.width,
            height: labelSize.height
        )
        label.draw(in: drawRect, withAttributes: attrs)
    }
}

// MARK: - Code Viewer Dot

/// Floating circular dot shown when the code viewer is minimized. Tapping
/// restores the full window. Mirrors the visual language of the main app's
/// minimize-to-dot behavior so it feels native to either host (TopCoder /
/// SoloScreen).
struct CodeViewerDotView: View {
    let onTap: () -> Void
    @State private var isHovered = false

    private let accent = Color(hex: "569CD6")

    var body: some View {
        Button(action: onTap) {
            ZStack {
                Circle()
                    .fill(Color.black)
                    .frame(width: 44, height: 44)
                Image(systemName: "folder.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(accent)
                Circle()
                    .stroke(accent.opacity(0.85), lineWidth: 1.8)
                    .frame(width: 44, height: 44)
            }
            .shadow(color: accent.opacity(0.35), radius: 8)
            .scaleEffect(isHovered ? 1.08 : 1.0)
            .opacity(isHovered ? 1.0 : 0.92)
            .animation(.easeOut(duration: 0.18), value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help("Restore code viewer")
    }
}

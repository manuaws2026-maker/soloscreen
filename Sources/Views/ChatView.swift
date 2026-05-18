import SwiftUI

struct ChatView: View {
    @EnvironmentObject var appState: AppState
    @State private var scrollTracker = ChatScrollTracker.State()

    private let bgColor = Color(hex: "0D1117")
    private let surfaceColor = Color(hex: "161B22")
    private let borderColor = Color(hex: "30363D")
    private let accentTeal = Color(hex: "22C55E")

    var body: some View {
        VStack(spacing: 0) {
            if appState.activeSession != nil {
                messageScrollView
            }

            InputArea()
        }
        .background(bgColor)
    }

    // MARK: - Empty Conversation

    private var emptyConversation: some View {
        VStack(spacing: 16) {
            Spacer()

            Group {
                if let url = Bundle.module.url(forResource: "BrainIcon", withExtension: "png"),
                   let nsImg = NSImage(contentsOf: url) {
                    Image(nsImage: nsImg)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    Image(systemName: "brain.head.profile")
                        .foregroundStyle(accentTeal.opacity(0.5))
                }
            }
            .frame(width: 80, height: 80)

            VStack(spacing: 8) {
                Text("Start a conversation")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))

                Text("Ask anything. SoloScreen stays invisible to screen share.")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.45))
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Message Scroll View

    /// Non-system messages for the active session.
    private var visibleMessages: [Message] {
        appState.activeSession?.messages.filter { $0.role != .system } ?? []
    }

    /// Scroll strategy — completely bypasses SwiftUI's ScrollViewReader /
    /// `proxy.scrollTo` which is unreliable with LazyVStack + dynamic
    /// markdown content (SwiftUI estimates heights for unrendered items →
    /// overshoots into blank space).
    ///
    /// Instead, the `ChatScrollTracker` observes the real NSScrollView's
    /// `documentView.frame` changes at the AppKit level and pins to the
    /// actual bottom whenever content size changes. This handles:
    ///  • New messages appearing (instant or streamed)
    ///  • Markdown layout shifts (code blocks expanding, tables rendering)
    ///  • Async content loading (Mermaid diagram images)
    ///
    /// The SwiftUI onChange handlers only need to reset the
    /// `userScrolledAway` flag — the AppKit observer does the scroll.
    private var messageScrollView: some View {
        ScrollView {
            // VStack (NOT LazyVStack). LazyVStack estimates heights for
            // off-screen items → scrollTo/pinToBottom overshoots into
            // blank space when a large response (system design) appears.
            // VStack measures every item so the document height is always
            // correct. Performance is fine: MarkdownContentView uses
            // .equatable() so unchanged messages skip body evaluation.
            VStack(spacing: 4) {
                ChatScrollTracker(state: scrollTracker)
                    .frame(width: 0, height: 0)

                let messages = visibleMessages
                if messages.isEmpty {
                    emptyConversation
                } else {
                    ForEach(messages) { message in
                        MessageBubble(message: message)
                            .equatable()
                            .id(message.id)
                    }
                }

                if appState.isStreaming {
                    streamingIndicator
                }
            }
            .padding(.vertical, 12)
        }
        .onAppear {
            scrollTracker.userScrolledAway = false
        }
        // New message added → user expects to see it, so reset the
        // "scrolled away" flag. The document-frame observer on the
        // NSScrollView handles the actual scroll-to-bottom.
        .onChange(of: appState.activeSession?.messages.count) { _, _ in
            // Pre-built answers (system design) set this flag so we
            // don't auto-scroll to the bottom of a huge response.
            if appState.skipNextAutoScroll {
                appState.skipNextAutoScroll = false
                scrollTracker.userScrolledAway = true
            } else {
                scrollTracker.userScrolledAway = false
            }
        }
        .onChange(of: appState.isStreaming) { _, streaming in
            if !streaming {
                scrollTracker.userScrolledAway = false
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .soloScreenScrollUp)) { _ in
            scrollByPage(direction: .up)
        }
        .onReceive(NotificationCenter.default.publisher(for: .soloScreenScrollDown)) { _ in
            scrollByPage(direction: .down)
        }
    }

    enum ScrollDirection { case up, down }

    private func scrollByPage(direction: ScrollDirection) {
        let scrollView: NSScrollView? = scrollTracker.scrollView
            ?? Self.findChatScrollView()
        guard let scrollView,
              let documentView = scrollView.documentView else { return }

        let clipView = scrollView.contentView
        let pageHeight = clipView.bounds.height * 0.8
        var newOrigin = clipView.bounds.origin
        switch direction {
        case .up:
            newOrigin.y = max(0, newOrigin.y - pageHeight)
        case .down:
            let maxY = max(0, documentView.bounds.height - clipView.bounds.height)
            newOrigin.y = min(maxY, newOrigin.y + pageHeight)
        }

        scrollTracker.isProgrammaticScroll = true
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            clipView.animator().setBoundsOrigin(newOrigin)
            scrollView.reflectScrolledClipView(clipView)
        }, completionHandler: {
            scrollTracker.isProgrammaticScroll = false
        })
    }

    private static func findChatScrollView() -> NSScrollView? {
        var best: NSScrollView?
        var bestHeight: CGFloat = 0
        for window in NSApp.windows where window.isVisible {
            walkViews(window.contentView) { sv in
                if sv.frame.height > bestHeight {
                    best = sv
                    bestHeight = sv.frame.height
                }
            }
        }
        return best
    }

    private static func walkViews(_ view: NSView?, visitor: (NSScrollView) -> Void) {
        guard let view else { return }
        if let sv = view as? NSScrollView { visitor(sv) }
        for sub in view.subviews { walkViews(sub, visitor: visitor) }
    }

    // MARK: - Streaming Indicator

    private var streamingIndicator: some View {
        HStack(spacing: 0) {
            HStack(spacing: 12) {
                PulsingDotsView()

                Button {
                    appState.cancelStreaming()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "stop.circle.fill")
                            .font(.system(size: 12))
                        Text("Stop")
                            .font(.system(size: 12))
                    }
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(.white.opacity(0.06))
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Spacer()
        }
        .padding(.horizontal, 16)
    }
}

// MARK: - Chat Scroll Tracker

/// Bridges the SwiftUI ScrollView to its underlying NSScrollView so we can
/// observe and control scrolling at the AppKit level — far more reliable
/// than SwiftUI's ScrollViewReader for dynamic content.
///
/// Key mechanism: observes `NSView.frameDidChangeNotification` on the
/// scroll view's `documentView`. Whenever the document height changes
/// (new message, streaming token, markdown layout shift, diagram image
/// load) the tracker automatically pins to bottom — unless the user has
/// scrolled away. This replaces all `proxy.scrollTo` calls.
struct ChatScrollTracker: NSViewRepresentable {

    final class State {
        weak var scrollView: NSScrollView?
        var userScrolledAway = false
        var isProgrammaticScroll = false
    }

    let state: State

    func makeCoordinator() -> Coordinator { Coordinator(state: state) }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            guard let scrollView = view.enclosingScrollView else { return }
            state.scrollView = scrollView

            let coordinator = context.coordinator

            // 1. Track user scroll gestures.
            NotificationCenter.default.addObserver(
                coordinator,
                selector: #selector(Coordinator.didEndLiveScroll(_:)),
                name: NSScrollView.didEndLiveScrollNotification,
                object: scrollView
            )

            scrollView.contentView.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(
                coordinator,
                selector: #selector(Coordinator.boundsDidChange(_:)),
                name: NSView.boundsDidChangeNotification,
                object: scrollView.contentView
            )

            // 2. Auto-pin: observe the document view's ACTUAL frame so
            //    we respond to real layout, not SwiftUI size estimates.
            if let docView = scrollView.documentView {
                docView.postsFrameChangedNotifications = true
                NotificationCenter.default.addObserver(
                    coordinator,
                    selector: #selector(Coordinator.documentFrameDidChange(_:)),
                    name: NSView.frameDidChangeNotification,
                    object: docView
                )
            }

            // Initial pin — scroll to bottom on first layout.
            coordinator.pinToBottom()
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    final class Coordinator: NSObject {
        let state: State

        init(state: State) { self.state = state }

        // -- User scroll detection --

        @objc func didEndLiveScroll(_ note: Notification) {
            updateUserScrolledAway()
        }

        @objc func boundsDidChange(_ note: Notification) {
            if state.isProgrammaticScroll { return }
            updateUserScrolledAway()
        }

        private func updateUserScrolledAway() {
            guard let sv = state.scrollView,
                  let doc = sv.documentView else { return }
            let contentH = doc.frame.height
            let viewportH = sv.contentView.bounds.height
            guard contentH > viewportH else { return }
            let dist = contentH - viewportH - sv.contentView.bounds.origin.y
            state.userScrolledAway = dist >= 40
        }

        // -- Auto-pin to bottom --

        /// Called whenever the document view's frame changes — i.e.,
        /// whenever the content height changes for ANY reason (new
        /// messages, streaming, markdown re-layout, image loads, etc.).
        /// Pins to bottom unless the user has scrolled away.
        @objc func documentFrameDidChange(_ note: Notification) {
            guard !state.userScrolledAway else { return }
            pinToBottom()
        }

        /// Scrolls the real NSScrollView to its actual bottom edge.
        /// Uses the true document height — never estimates.
        func pinToBottom() {
            guard let sv = state.scrollView,
                  let doc = sv.documentView else { return }
            let contentH = doc.frame.height
            let viewportH = sv.contentView.bounds.height
            guard contentH > viewportH else { return }

            let maxY = contentH - viewportH
            let currentY = sv.contentView.bounds.origin.y

            // Already at bottom — skip redundant scroll.
            guard abs(maxY - currentY) > 0.5 else { return }

            state.isProgrammaticScroll = true
            sv.contentView.setBoundsOrigin(NSPoint(x: 0, y: maxY))
            sv.reflectScrolledClipView(sv.contentView)
            // boundsDidChange fires synchronously above while the flag
            // is true, so it's correctly ignored. Clear on next tick.
            DispatchQueue.main.async {
                self.state.isProgrammaticScroll = false
            }
        }

        deinit { NotificationCenter.default.removeObserver(self) }
    }
}

// MARK: - Pulsing Dots

struct PulsingDotsView: View {
    @State private var animating = false

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(Color(hex: "22C55E").opacity(0.7))
                    .frame(width: 6, height: 6)
                    .scaleEffect(animating ? 1.0 : 0.5)
                    .opacity(animating ? 1.0 : 0.3)
                    .animation(
                        .easeInOut(duration: 0.6)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.2),
                        value: animating
                    )
            }
        }
        .onAppear {
            animating = true
        }
    }
}

// MARK: - Notification Names

// MARK: - ChatTopBar (full-width, rendered above the sidebar + chat row)

/// The header bar with window controls, sidebar toggle, model pill, status
/// indicators (stealth-off warning, extreme stealth banner, free-tier chip),
/// and a settings button. Lives in `MainView` so it spans the entire window
/// width regardless of sidebar visibility.
struct ChatTopBar: View {
    @EnvironmentObject var appState: AppState
    @State private var showShortcutsPopover: Bool = false

    private let surfaceColor = Color(hex: "161B22")
    private let borderColor = Color(hex: "30363D")
    private let accentTeal = Color(hex: "22C55E")

    var body: some View {
        GeometryReader { geo in
            content(width: geo.size.width)
        }
        // Extreme stealth mode shows the keyboard icon with a shortcut hint
        // below it, so the bar grows taller to give those elements room.
        .frame(height: appState.settings.extremeStealthEnabled ? 52 : 40)
        .background(Color(hex: "0D1117"))
        .animation(.easeInOut(duration: 0.2), value: appState.settings.extremeStealthEnabled)
    }

    @ViewBuilder
    private func content(width: CGFloat) -> some View {
        let isVeryNarrow = width < 380

        HStack(spacing: 10) {
            // Hide the traffic-light window controls (close + minimize) in
            // super stealth — keeps the bar as clean as possible. Same actions
            // remain reachable via ⌃⇧Space (hide) and ⌃⇧M (minimize to dot).
            if !appState.settings.extremeStealthEnabled {
                HStack(spacing: 6) {
                    windowControlButton(color: Color(hex: "FF5F57"), symbol: "X") {
                        NSApp.keyWindow?.orderOut(nil)
                    }
                    .help("Hide window")

                    windowControlButton(color: Color(hex: "FEBC2E"), symbol: "_") {
                        NotificationCenter.default.post(name: .soloScreenMinimizeWindow, object: nil)
                    }
                    .help("Minimize")
                }
            }

            // Labeled "Chats" pill — replaces the icon-only sidebar toggle so
            // users immediately see there's a chat list to open. Shows the
            // current chat title when one is active, falls back to "Chats".
            if !appState.settings.extremeStealthEnabled {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        appState.sidebarVisible.toggle()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "bubble.left.and.bubble.right.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(accentTeal.opacity(0.8))
                        Text(activeChatLabel)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.8))
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .frame(maxWidth: 220)
                    .background(
                        Capsule()
                            .fill(surfaceColor)
                            .overlay(Capsule().strokeBorder(borderColor, lineWidth: 1))
                    )
                }
                .buttonStyle(.plain)
                .help(appState.sidebarVisible ? "Hide chat list" : "Show chat list")
            }

            // Model pill — hidden in narrow top bars to free space for the
            // live-listen, visible, and clear-chat controls, and also hidden
            // in extreme stealth to keep the bar minimal. Still reachable
            // via ⌃⇧P or Settings.
            if let session = appState.activeSession,
               !isVeryNarrow,
               !appState.settings.extremeStealthEnabled {
                Button {
                    appState.settingsInitialTab = "AI Provider"
                    appState.showSettings = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "cpu")
                            .font(.system(size: 11))
                            .foregroundStyle(accentTeal.opacity(0.7))

                        Text(session.model)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.7))
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(surfaceColor)
                            .overlay(Capsule().strokeBorder(borderColor, lineWidth: 1))
                    )
                }
                .buttonStyle(.plain)
                .help("Change model (⌃⇧P)")
            }

            Spacer()

            // Live Listen — idle button OR (bar graph + AI Help + Stop) when active.
            LiveListenControls()
                .environmentObject(appState)

            // Stealth pill moved out of the top bar — see the green banner
            // rendered by MainView directly below the top bar when extreme
            // stealth is active. The keyboard-shortcuts popover + hide
            // buttons still live in the top bar so the user can interact in
            // super stealth without hunting for traffic lights (which are
            // also hidden in that mode).
            if appState.settings.extremeStealthEnabled {
                VStack(spacing: 2) {
                    Button {
                        showShortcutsPopover.toggle()
                    } label: {
                        Image(systemName: "keyboard")
                            .font(.system(size: 12))
                            .foregroundStyle(.green.opacity(0.7))
                            .frame(width: 26, height: 22)
                            .background(Capsule().fill(.green.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                    .help("Shortcuts ⌃⇧/")
                    .popover(isPresented: $showShortcutsPopover, arrowEdge: .bottom) {
                        shortcutsPopoverContent
                    }

                    Text("⌃⇧/")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.green.opacity(0.65))
                        .lineLimit(1)
                }

                VStack(spacing: 2) {
                    Button {
                        NSApp.keyWindow?.orderOut(nil)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.green.opacity(0.7))
                            .frame(width: 26, height: 22)
                            .background(Capsule().fill(.green.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                    .help("Hide window (⌃⇧W)")

                    Text("⌃⇧W")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.green.opacity(0.65))
                        .lineLimit(1)
                }
            }

            // Visible-to-capture indicator moved out of the top bar — see the
            // red banner rendered by MainView below the top bar when stealth
            // is OFF. Keeps the top bar clean.

            // (Free-tier pill removed.)

            // Clear-chat button — active only when there are messages to wipe.
            VStack(spacing: 2) {
                Button {
                    appState.clearCurrentChat()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 13))
                        .foregroundStyle(hasMessages ? .white.opacity(0.7) : .white.opacity(0.25))
                }
                .buttonStyle(.plain)
                .disabled(!hasMessages)
                .help("Clear chat context (⌃⇧K)")

                if appState.settings.extremeStealthEnabled {
                    Text("⌃⇧K")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.green.opacity(0.65))
                        .lineLimit(1)
                }
            }

            // Code Viewer button — opens a separate stealth window for browsing
            // a folder. Hidden in extreme stealth to keep the bar minimal.
            if !appState.settings.extremeStealthEnabled {
                Button {
                    appState.showCodeViewer = true
                } label: {
                    Image(systemName: "folder")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.55))
                }
                .buttonStyle(.plain)
                .help("Open code viewer")
            }

            // Settings gear hidden in extreme stealth — keep the bar minimal.
            // Settings can still be opened from the sidebar's chevron menu or
            // via the status-bar icon if shown.
            if !appState.settings.extremeStealthEnabled {
                Button {
                    appState.showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.55))
                }
                .buttonStyle(.plain)
                .help("Settings")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .onReceive(NotificationCenter.default.publisher(for: .soloScreenShowShortcuts)) { _ in
            showShortcutsPopover.toggle()
        }
    }

    private var hasMessages: Bool {
        guard let session = appState.activeSession else { return false }
        return session.messages.contains { $0.role != .system }
    }

    /// Always show "Chats" in the top-bar pill — the session title lives
    /// in the sidebar, not the top bar.
    private var activeChatLabel: String { "Chats" }

    private func windowControlButton(color: Color, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                Circle().fill(color).frame(width: 12, height: 12)
                Text(symbol)
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(.black.opacity(0.55))
            }
        }
        .buttonStyle(.plain)
    }

    private var shortcutsPopoverContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("KEYBOARD SHORTCUTS")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.green.opacity(0.75))
                    .tracking(0.5)
                Text("⌃⇧ = Ctrl + Shift (hold both, then press the key).")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.55))
            }

            Divider()

            shortcutCategory("Window") {
                shortcutRow("Ctrl + Shift + Space", "Show / Hide")
                shortcutRow("Ctrl + Shift + M", "Minimize to dot")
                shortcutRow("Ctrl + Shift + E", "Toggle Extreme Stealth")
                shortcutRow("Ctrl + Shift + =", "Opacity up (more opaque)")
                shortcutRow("Ctrl + Shift + −", "Opacity down (more transparent)")
            }

            shortcutCategory("Chat") {
                shortcutRow("Ctrl + Shift + N", "New chat")
                shortcutRow("Ctrl + Shift + I", "Focus input")
                shortcutRow("Ctrl + Shift + K", "Clear chat")
                shortcutRow("Ctrl + Shift + ↑ / ↓", "Scroll messages")
                shortcutRow("Return", "Send message")
                shortcutRow("Escape", "Stop streaming")
            }

            shortcutCategory("Input") {
                shortcutRow("Ctrl + Shift + S", "Screenshot")
                shortcutRow("Ctrl + Shift + R", "Mic dictation")
                shortcutRow("Ctrl + Shift + A", "Attach file")
            }

            shortcutCategory("Live Listen") {
                shortcutRow("Ctrl + Shift + T", "Start / Stop listening")
                shortcutRow("Ctrl + Shift + H", "AI Help on transcript")
            }

            shortcutCategory("View") {
                shortcutRow("Ctrl + Shift + D", "Expand / close diagram")
                shortcutRow("Ctrl + Shift + W", "Hide window")
            }

            shortcutCategory("Settings") {
                shortcutRow("Ctrl + Shift + P", "Change model")
                shortcutRow("Ctrl + Shift + /", "Show this shortcuts list")
            }
        }
        .padding(14)
        .frame(width: 310)
    }

    @ViewBuilder
    private func shortcutCategory<Content: View>(_ title: String, @ViewBuilder _ rows: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(0.5)
                .foregroundStyle(.white.opacity(0.4))
            VStack(alignment: .leading, spacing: 2) {
                rows()
            }
        }
    }

    private func shortcutRow(_ keys: String, _ action: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(keys)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(.green.opacity(0.85))
                .frame(width: 160, alignment: .leading)
            Text(action)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.75))
        }
    }
}

extension Notification.Name {
    static let soloScreenMinimizeWindow = Notification.Name("soloScreenMinimizeWindow")
    static let soloScreenScrollUp = Notification.Name("soloScreenScrollUp")
    static let soloScreenScrollDown = Notification.Name("soloScreenScrollDown")
    static let soloScreenShowShortcuts = Notification.Name("soloScreenShowShortcuts")
    static let soloScreenFocusInput = Notification.Name("soloScreenFocusInput")
    static let soloScreenInsertDictation = Notification.Name("soloScreenInsertDictation")
    static let soloScreenRequestLiveHelp = Notification.Name("soloScreenRequestLiveHelp")
    static let soloScreenCloseLiveHelp = Notification.Name("soloScreenCloseLiveHelp")
    static let soloScreenHideForOnboarding = Notification.Name("soloScreenHideForOnboarding")
    static let soloScreenDidRestore = Notification.Name("soloScreenDidRestore")
}

// MARK: - Live Listen Controls (top-bar)

struct LiveListenControls: View {
    @EnvironmentObject var appState: AppState

    private let accentTeal = Color(hex: "22C55E")
    private let borderColor = Color(hex: "30363D")

    var body: some View {
        if appState.isLiveListening {
            HStack(spacing: 12) {
                LiveAudioBars(levels: appState.liveAudioLevels)
                    .frame(width: 68, height: 22)
                    .padding(.leading, 4)

                VStack(spacing: 2) {
                    Button {
                        appState.requestLiveHelp()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 11))
                            Text("AI Help")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundStyle(accentTeal)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(accentTeal.opacity(0.14))
                                .overlay(Capsule().strokeBorder(accentTeal.opacity(0.45), lineWidth: 1))
                        )
                    }
                    .buttonStyle(.plain)
                    .help("Answer the most recent question from the transcript (⌃⇧H)")

                    stealthHint("⌃⇧H")
                }

                VStack(spacing: 2) {
                    Button {
                        appState.toggleTranscription()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "stop.fill")
                                .font(.system(size: 10))
                            Text("Stop")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundStyle(.red.opacity(0.9))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(.red.opacity(0.10))
                                .overlay(Capsule().strokeBorder(.red.opacity(0.4), lineWidth: 1))
                        )
                    }
                    .buttonStyle(.plain)
                    .help("Stop live listening (⌃⇧T)")

                    stealthHint("⌃⇧T")
                }
            }
        } else {
            VStack(spacing: 2) {
                Button {
                    appState.toggleTranscription()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "waveform")
                            .font(.system(size: 11))
                        Text("Listen Live")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(.white.opacity(0.75))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.05))
                            .overlay(Capsule().strokeBorder(borderColor, lineWidth: 1))
                    )
                }
                .buttonStyle(.plain)
                .help("Start listening to system audio (⌃⇧T)")

                stealthHint("⌃⇧T")
            }
        }
    }

    @ViewBuilder
    private func stealthHint(_ keys: String) -> some View {
        if appState.settings.extremeStealthEnabled {
            Text(keys)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(.green.opacity(0.65))
                .lineLimit(1)
        }
    }
}

/// Equalizer-style bar graph animating from a rolling level buffer.
/// Bars have fixed width, render centered vertically with a min-height floor
/// so quiet audio still shows as a thin line, and animate smoothly.
struct LiveAudioBars: View {
    let levels: [CGFloat]

    var body: some View {
        GeometryReader { geo in
            let spacing: CGFloat = 2
            let count = max(levels.count, 1)
            let barWidth = max(2, (geo.size.width - spacing * CGFloat(count - 1)) / CGFloat(count))
            let maxH = geo.size.height
            let minBarHeight: CGFloat = 3
            let accent = Color(hex: "22C55E")

            HStack(alignment: .center, spacing: spacing) {
                ForEach(Array(levels.enumerated()), id: \.offset) { _, level in
                    let clamped = max(0, min(1, level))
                    // Map 0..1 level onto (minBarHeight..maxH) so silence
                    // still shows a visible baseline instead of collapsing.
                    let h = minBarHeight + (maxH - minBarHeight) * clamped
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [accent, accent.opacity(0.65)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: barWidth, height: h)
                        .animation(.linear(duration: 0.2), value: level)
                }
            }
            .frame(width: geo.size.width, height: maxH, alignment: .center)
        }
    }
}

// MARK: - Language Picker Modal

/// Shown once on the user's first coding / system-design chat so future
/// sessions can auto-apply their preferred language without asking.
struct LanguagePickerModal: View {
    @EnvironmentObject var appState: AppState
    @State private var selected: String = "Python"

    private let surfaceColor = Color(hex: "161B22")
    private let borderColor = Color(hex: "30363D")
    private let accentTeal = Color(hex: "22C55E")

    static let choices: [String] = [
        "Python", "JavaScript", "TypeScript", "Java", "C++", "C#",
        "Go", "Rust", "Swift", "Kotlin", "Ruby", "PHP", "SQL"
    ]

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()

            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Pick your preferred language")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.95))
                    Spacer()
                }

                Text("We'll use this for coding and system-design chats from now on. You can change it in Settings → Templates.")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                    ForEach(Self.choices, id: \.self) { lang in
                        Button {
                            selected = lang
                        } label: {
                            HStack {
                                Text(lang)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(selected == lang ? .white : .white.opacity(0.85))
                                Spacer()
                                if selected == lang {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(.white)
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(selected == lang ? accentTeal : surfaceColor)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .strokeBorder(selected == lang ? accentTeal : borderColor, lineWidth: 1)
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                HStack {
                    Button("Skip") {
                        appState.dismissLanguagePicker()
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Button("Use \(selected)") {
                        appState.applyLanguageChoice(selected)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(accentTeal)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(20)
            .frame(maxWidth: 440)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(surfaceColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(borderColor, lineWidth: 1)
                    )
            )
            .shadow(color: .black.opacity(0.4), radius: 16, y: 4)
            .padding(32)
        }
        .onAppear {
            if let existing = appState.settings.preferredCodingLanguage,
               Self.choices.contains(existing) {
                selected = existing
            }
        }
    }
}

// MARK: - Live Help Modal

struct LiveHelpModal: View {
    @EnvironmentObject var appState: AppState
    @State private var followupInput: String = ""
    @FocusState private var inputFocused: Bool

    private let surfaceColor = Color(hex: "161B22")
    private let borderColor = Color(hex: "30363D")
    private let accentTeal = Color(hex: "22C55E")
    private let bgColor = Color(hex: "0D1117")

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture { appState.closeLiveHelpModal() }

            VStack(alignment: .leading, spacing: 0) {
                // Header
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 13))
                        .foregroundStyle(accentTeal)
                    Text("Live Help")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))

                    if appState.isLiveHelpStreaming {
                        ProgressView()
                            .controlSize(.small)
                            .tint(accentTeal)
                    }

                    Spacer()

                    Button {
                        appState.closeLiveHelpModal()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.7))
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(.white.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.escape, modifiers: [])
                    .help("Close (Esc)")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)

                Divider().overlay(borderColor)

                // Conversation
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            ForEach(appState.liveHelpMessages) { msg in
                                liveHelpMessageRow(msg)
                                    .id(msg.id)
                            }
                            if appState.isLiveHelpStreaming && appState.liveHelpMessages.last?.content.isEmpty == true {
                                HStack(spacing: 6) {
                                    ProgressView().controlSize(.small).tint(accentTeal)
                                    Text("Thinking…")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.white.opacity(0.5))
                                }
                                .padding(.horizontal, 14)
                            }
                        }
                        .padding(.vertical, 12)
                    }
                    .onChange(of: appState.liveHelpMessages.last?.content) { _, _ in
                        // Auto-scroll to bottom as new content streams.
                        if let lastId = appState.liveHelpMessages.last?.id {
                            withAnimation(.easeOut(duration: 0.15)) {
                                proxy.scrollTo(lastId, anchor: .bottom)
                            }
                        }
                    }
                }

                Divider().overlay(borderColor)

                // Follow-up input box
                HStack(spacing: 8) {
                    TextField("Ask a follow-up…", text: $followupInput, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .lineLimit(1...4)
                        .focused($inputFocused)
                        .onSubmit { send() }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(bgColor)
                                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(borderColor, lineWidth: 1))
                        )

                    Button(action: send) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(canSend ? accentTeal : .white.opacity(0.2))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSend)
                    .keyboardShortcut(.return, modifiers: [])
                }
                .padding(12)
            }
            .frame(maxWidth: 560, maxHeight: 500)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(surfaceColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(borderColor, lineWidth: 1)
                    )
            )
            .shadow(color: .black.opacity(0.4), radius: 16, y: 4)
            .padding(32)
        }
        .onReceive(NotificationCenter.default.publisher(for: .soloScreenCloseLiveHelp)) { _ in
            appState.closeLiveHelpModal()
        }
    }

    private var canSend: Bool {
        !followupInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !appState.isLiveHelpStreaming
    }

    private func send() {
        let text = followupInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !appState.isLiveHelpStreaming else { return }
        followupInput = ""
        appState.sendLiveHelpFollowup(text)
    }

    @ViewBuilder
    private func liveHelpMessageRow(_ msg: AppState.LiveHelpMessage) -> some View {
        // Hide the synthesized "(analyze latest question from transcript)"
        // placeholder — it's an internal prompt, not something to show.
        let isSynthetic = msg.role == .user
            && msg.content.contains("analyze latest question from transcript")
        if !isSynthetic {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: msg.role == .user ? "person.fill" : "sparkles")
                    .font(.system(size: 11))
                    .foregroundStyle(msg.role == .user ? .white.opacity(0.65) : accentTeal)
                    .frame(width: 20, alignment: .center)
                    .padding(.top, 2)

                Text(.init(msg.content))
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.9))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 14)
        }
    }
}

#Preview {
    ChatView()
        .environmentObject(AppState())
}

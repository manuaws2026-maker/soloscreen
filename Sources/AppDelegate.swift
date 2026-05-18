import AppKit
import Combine
import SwiftUI

/// Application delegate that configures SoloScreen as a menu-bar-only app
/// with a stealth floating overlay window.
///
/// Sets the activation policy to `.accessory` (no dock icon), creates a
/// status bar item for quick access, and initialises the stealth window
/// with the main SwiftUI view hierarchy.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {

    // MARK: - Properties

    private var statusBarItem: NSStatusItem?
    private var stealthWindowManager: StealthWindowManager?
    private var appState: AppState?
    private var shortcutService: ShortcutService?
    private var settingsCancellable: AnyCancellable?
    private var showSettingsCancellable: AnyCancellable?
    private var showDiagramCancellable: AnyCancellable?
    private var showOnboardingCancellable: AnyCancellable?
    private var settingsWindow: NSWindow?
    private var diagramWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private var codeViewerWindow: NSWindow?
    private var codeViewerDotPanel: KeyablePanel?
    private var codeViewerFrameBeforeMinimize: NSRect?
    private var codeViewerState = CodeViewerState()
    private var showCodeViewerCancellable: AnyCancellable?
    private var minimizeObserver: Any?

    // MARK: - Application Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide from Dock and Cmd-Tab switcher.
        NSApplication.shared.setActivationPolicy(.accessory)

        // Create the central app state.
        let state = AppState()
        self.appState = state

        // Build the root SwiftUI view with the app state injected.
        let mainView = MainView()
            .environmentObject(state)

        // Create and configure the stealth overlay window.
        let windowManager = StealthWindowManager()
        windowManager.setupWindow(contentView: mainView)
        self.stealthWindowManager = windowManager

        // Apply persisted stealth settings.
        windowManager.setOpacity(state.settings.overlayOpacity)
        windowManager.setExtremeStealth(state.settings.extremeStealthEnabled)

        // Install a main menu with standard Edit actions (Cmd+C/V/X/A).
        // Without this, paste doesn't work in text fields because .accessory
        // apps have no menu bar and no default Edit menu.
        setupMainMenu()

        // Status bar item is created lazily based on stealth — see
        // observeSettings below. In stealth mode there is no menu bar icon
        // (it would be visible in screen shares and defeat stealth).

        // Register global keyboard shortcuts.
        setupShortcuts()

        // Observe settings changes and propagate to the window manager.
        observeSettings(state: state, windowManager: windowManager)

        // Open / close the floating Settings window based on app state.
        // No `.removeDuplicates()` — clicking the gear while the state is
        // already `true` must still re-surface the window in case it got
        // hidden by space switching or an accidental orderOut.
        showSettingsCancellable = state.$showSettings
            .receive(on: DispatchQueue.main)
            .sink { [weak self] shouldShow in
                if shouldShow {
                    self?.showSettingsWindow(appState: state)
                } else {
                    self?.closeSettingsWindow()
                }
            }

        // Open / close the floating Diagram expansion window.
        showDiagramCancellable = state.$showExpandedDiagram
            .receive(on: DispatchQueue.main)
            .sink { [weak self] shouldShow in
                if shouldShow {
                    self?.showDiagramWindow(appState: state)
                } else {
                    self?.closeDiagramWindow()
                }
            }

        // Open / close the floating Code Viewer window.
        showCodeViewerCancellable = state.$showCodeViewer
            .receive(on: DispatchQueue.main)
            .sink { [weak self] shouldShow in
                if shouldShow {
                    self?.showCodeViewerWindow(appState: state)
                } else {
                    self?.closeCodeViewerWindow()
                }
            }

        // Open / close the centered Onboarding window.
        showOnboardingCancellable = state.$showOnboarding
            .receive(on: DispatchQueue.main)
            .sink { [weak self] shouldShow in
                if shouldShow {
                    self?.showOnboardingWindow(appState: state)
                } else {
                    self?.closeOnboardingWindow()
                }
            }

        // Listen for minimize requests from SwiftUI views.
        // Every time any window (main panel, settings, sheets, popovers that
        // back onto NSWindow) becomes key, enforce the current stealth +
        // opacity settings on it. Catches SwiftUI .sheet windows we don't
        // construct ourselves.
        NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self, let window = note.object as? NSWindow else { return }
            guard let s = self.appState?.settings else { return }
            window.sharingType = s.stealthEnabled ? .none : .readOnly
            // Stick with solid opacity for the main panel / settings; leave
            // child popovers alone (they look weird dimmed).
        }
        NotificationCenter.default.addObserver(
            forName: NSWindow.didUpdateNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self, let window = note.object as? NSWindow else { return }
            guard let s = self.appState?.settings else { return }
            // Redundant but defends against transient windows that never
            // become key (some sheets on older macOS versions).
            window.sharingType = s.stealthEnabled ? .none : .readOnly
        }

        minimizeObserver = NotificationCenter.default.addObserver(
            forName: .soloScreenMinimizeWindow,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.stealthWindowManager?.toggleMinimize()
            }
        }

        // Hide main panel for onboarding (when user clicks API key link).
        NotificationCenter.default.addObserver(
            forName: .soloScreenHideForOnboarding,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.stealthWindowManager?.minimize()
            }
        }

        // Restore onboarding when the dot is clicked (main panel restored).
        NotificationCenter.default.addObserver(
            forName: .soloScreenDidRestore,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self,
                      self.appState?.showOnboarding == true,
                      let w = self.onboardingWindow else { return }
                w.level = .floating
                w.orderFrontRegardless()
                w.makeKeyAndOrderFront(nil)
            }
        }

        // Prompt for permissions the app relies on (Screen Recording for
        // Live Listen). Done after the UI is up so the system dialog isn't
        // the first thing the user sees.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.requestScreenRecordingPermissionIfNeeded()
        }
    }

    // MARK: - Permissions

    /// ScreenCaptureKit (used by Live Listen to capture system audio) is
    /// gated on the Screen Recording permission. Ask for it once on launch;
    /// macOS only shows its native dialog the first time — after that the
    /// app needs to be toggled on manually in System Settings.
    private func requestScreenRecordingPermissionIfNeeded() {
        if CGPreflightScreenCaptureAccess() {
            return
        }
        // Kicks off the system prompt the first time; if the user previously
        // declined, returns false silently without dialog — in that case we
        // surface a banner with a button to jump to System Settings.
        let granted = CGRequestScreenCaptureAccess()
        if !granted {
            appState?.setError(
                "Live Listen needs the Screen Recording permission to hear system audio. Enable SoloScreen in System Settings → Privacy & Security → Screen Recording.",
                systemSettingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
            )
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        // Restore the onboarding window + main panel if they were
        // hidden (user went to browser to copy an API key).
        if appState?.showOnboarding == true, let w = onboardingWindow, !w.isVisible {
            // Restore main panel first (from dot)
            stealthWindowManager?.restore()
            // Then bring onboarding back on top
            w.level = .floating
            w.orderFrontRegardless()
            w.makeKeyAndOrderFront(nil)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Persist all state before quitting.
        appState?.saveAllState()
        stealthWindowManager?.tearDown()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Keep the app running even when all windows are closed (menu bar app).
        false
    }

    // MARK: - Main Menu (for standard keyboard shortcuts)

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        // App menu (required but can be minimal)
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "Quit SoloScreen", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // Edit menu — enables Cmd+C/V/X/A in text fields
        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
        editMenu.addItem(NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "Z"))
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        NSApplication.shared.mainMenu = mainMenu
    }

    // MARK: - Status Bar

    private func setupStatusBar() {
        statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusBarItem?.button {
            if let brain = loadBrainIcon() {
                let composed = composeMenuBarIcon(brain: brain)
                composed.isTemplate = false  // keep colorful gradient
                button.image = composed
            } else {
                // Fallback if the resource is missing
                button.image = NSImage(
                    systemSymbolName: "eye.slash.circle.fill",
                    accessibilityDescription: "SoloScreen"
                )
                button.image?.size = NSSize(width: 18, height: 18)
                button.image?.isTemplate = true
            }
        }

        // Menu items are built dynamically in `menuNeedsUpdate(_:)` so they
        // reflect the current panel state (visible / hidden / minimized).
        let menu = NSMenu()
        menu.delegate = self
        statusBarItem?.menu = menu
    }

    // MARK: - Dynamic Status Bar Menu

    /// Rebuild the status-bar menu based on the current panel state so the
    /// items always match what the user can actually do right now.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let state = stealthWindowManager?.state ?? .visible

        switch state {
        case .visible:
            menu.addItem(makeItem("Hide Window", action: #selector(hideWindowAction), shortcut: "space", mods: [.control, .shift]))
            menu.addItem(makeItem("Minimize to Dot", action: #selector(minimizeToDotAction), shortcut: "m", mods: [.control, .shift]))
        case .hidden:
            menu.addItem(makeItem("Show Window", action: #selector(showWindowAction), shortcut: "space", mods: [.control, .shift]))
        case .minimized:
            menu.addItem(makeItem("Restore Window", action: #selector(restoreFromDotAction), shortcut: "m", mods: [.control, .shift]))
            menu.addItem(makeItem("Hide Completely", action: #selector(hideCompletelyAction), shortcut: "", mods: []))
        }

        menu.addItem(NSMenuItem.separator())

        menu.addItem(makeItem("New Session", action: #selector(createNewSession), shortcut: "n", mods: [.command, .shift]))
        menu.addItem(makeItem("Settings…", action: #selector(openSettings), shortcut: ",", mods: .command))

        menu.addItem(NSMenuItem.separator())

        menu.addItem(makeItem("Quit SoloScreen", action: #selector(quitApp), shortcut: "q", mods: .command))
    }

    private func makeItem(_ title: String, action: Selector, shortcut: String, mods: NSEvent.ModifierFlags) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: shortcut)
        item.keyEquivalentModifierMask = mods
        item.target = self
        return item
    }

    // MARK: - Menu Bar Icon Composition

    private func loadBrainIcon() -> NSImage? {
        guard let url = Bundle.module.url(forResource: "BrainIcon", withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }

    /// Draw the brain directly at 22×22 with a fully transparent background
    /// so it composites naturally on any menu bar wallpaper/tint.
    private func composeMenuBarIcon(brain: NSImage) -> NSImage {
        let size: CGFloat = 22
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        defer { image.unlockFocus() }

        let rect = NSRect(x: 0, y: 0, width: size, height: size)
        brain.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1.0)
        return image
    }

    // MARK: - Status Bar Actions

    @objc private func toggleOverlayVisibility() {
        stealthWindowManager?.toggleVisibility()
    }

    @objc private func hideWindowAction() {
        stealthWindowManager?.hide()
    }

    @objc private func showWindowAction() {
        stealthWindowManager?.show()
    }

    @objc private func minimizeToDotAction() {
        stealthWindowManager?.minimize()
    }

    @objc private func restoreFromDotAction() {
        stealthWindowManager?.restore()
    }

    @objc private func hideCompletelyAction() {
        stealthWindowManager?.hideCompletely()
    }

    @objc private func createNewSession() {
        // If minimized, restore the full window so the new chat is actually visible.
        if stealthWindowManager?.state == .minimized {
            stealthWindowManager?.restore()
        } else {
            stealthWindowManager?.show()
        }
        appState?.createSession()
    }

    @objc private func openSettings() {
        if stealthWindowManager?.state == .minimized {
            stealthWindowManager?.restore()
        } else {
            stealthWindowManager?.show()
        }
        appState?.showSettings = true
    }

    @objc private func quitApp() {
        appState?.saveAllState()
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Settings Observation

    /// Watch for changes to AppState settings and propagate them to the window manager.
    private func observeSettings(state: AppState, windowManager: StealthWindowManager) {
        settingsCancellable = state.$settings
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] settings in
                guard let self else { return }
                windowManager.setStealth(settings.stealthEnabled)
                windowManager.setExtremeStealth(settings.extremeStealthEnabled)
                windowManager.setOpacity(settings.overlayOpacity)

                // Keep the settings window's stealth + opacity in sync.
                // (We deliberately DON'T apply extreme stealth / click-through
                // here — settings has sliders and toggles the user needs to
                // actually interact with.)
                self.applyStealthToSettingsWindow(
                    stealthEnabled: settings.stealthEnabled,
                    opacity: settings.overlayOpacity
                )

                // Status bar icon: only show when NOT in stealth, because the
                // menu bar is captured by screen share / recordings and would
                // otherwise leak SoloScreen's presence.
                self.updateStatusBarVisibility(stealth: settings.stealthEnabled)

                // Auto-collapse sidebar in extreme stealth to maximize content area.
                if settings.extremeStealthEnabled {
                    self.appState?.sidebarVisible = false
                }
            }
    }

    private func applyStealthToSettingsWindow(stealthEnabled: Bool, opacity: Double) {
        guard let w = settingsWindow else { return }
        w.sharingType = stealthEnabled ? .none : .readOnly
        w.alphaValue = CGFloat(max(0.25, min(1.0, opacity)))
        // Also sweep any child sheets / popovers that SwiftUI may have
        // spawned off the settings window (template editor, alerts, etc.).
        for child in w.childWindows ?? [] {
            child.sharingType = stealthEnabled ? .none : .readOnly
        }
        // And any other NSApp-owned windows in flight — covers SwiftUI
        // sheets that aren't registered as child-windows on macOS 14+.
        for window in NSApp.windows {
            window.sharingType = stealthEnabled ? .none : .readOnly
        }
    }

    // MARK: - Settings Window

    /// Open a floating Settings window centered on the screen. A regular
    /// titled NSWindow — NOT a sheet — so it doesn't anchor to our
    /// right-edge panel. sharingType = .none so API keys inside stay hidden
    /// from screen capture.
    private func showSettingsWindow(appState: AppState) {
        if let w = settingsWindow {
            // Pull forward even if it's already "open" — the user may have
            // space-switched away and `.transient` hid it from view.
            NSApp.activate(ignoringOtherApps: true)
            w.orderFrontRegardless()
            w.makeKeyAndOrderFront(nil)
            return
        }

        let contentRect = NSRect(x: 0, y: 0, width: 820, height: 760)
        let window = NSWindow(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "SoloScreen Settings"
        // Force a dark titlebar + let the SettingsView's black bg extend
        // under it so the header matches the content seamlessly.
        window.appearance = NSAppearance(named: .darkAqua)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden   // the SettingsView already renders its own "Settings" heading
        window.backgroundColor = NSColor(red: 0x0D/255.0, green: 0x11/255.0, blue: 0x17/255.0, alpha: 1.0)
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        // Hide from Mission Control / Exposé / Window menu / window list so
        // the settings window doesn't betray the app's presence the way the
        // main stealth panel carefully avoids.
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        window.isExcludedFromWindowsMenu = true
        window.hidesOnDeactivate = false
        // Match the main panel's stealth + opacity settings.
        let s = appState.settings
        window.sharingType = s.stealthEnabled ? .none : .readOnly
        window.alphaValue = CGFloat(max(0.25, min(1.0, s.overlayOpacity)))
        window.minSize = NSSize(width: 720, height: 680)
        window.delegate = self       // sync close button → appState.showSettings = false
        window.center()

        let host = NSHostingController(
            rootView: SettingsView().environmentObject(appState)
        )
        window.contentViewController = host

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.settingsWindow = window
    }

    private func closeSettingsWindow() {
        settingsWindow?.close()
    }

    // MARK: - Diagram Window

    /// Open the diagram expansion in a dedicated stealth NSWindow centered
    /// on screen — follows the exact same pattern as Settings.
    private func showDiagramWindow(appState: AppState) {
        guard let image = appState.lastDiagramImage,
              let source = appState.lastDiagramSource else { return }

        if let w = diagramWindow {
            // Update content, resize to fit, and bring forward.
            let host = NSHostingController(
                rootView: ZoomableDiagramOverlay(
                    image: image,
                    source: source,
                    onClose: { [weak self] in
                        self?.appState?.showExpandedDiagram = false
                    }
                )
            )
            w.contentViewController = host
            // Keep existing window size — just update content.
            NSApp.activate(ignoringOtherApps: true)
            w.orderFrontRegardless()
            w.makeKeyAndOrderFront(nil)
            return
        }

        // Size the window to 70% of screen, capped to reasonable bounds.
        let screen = NSScreen.main ?? NSScreen.screens.first
        let screenFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let winW = min(screenFrame.width * 0.7, 900)
        let winH = min(screenFrame.height * 0.7, 700)

        let contentRect = NSRect(x: 0, y: 0, width: winW, height: winH)
        let window = NSWindow(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Diagram"
        window.appearance = NSAppearance(named: .darkAqua)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = NSColor(red: 0x0D/255.0, green: 0x11/255.0, blue: 0x17/255.0, alpha: 1.0)
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        window.isExcludedFromWindowsMenu = true
        window.hidesOnDeactivate = false
        let s = appState.settings
        window.sharingType = s.stealthEnabled ? .none : .readOnly
        window.alphaValue = CGFloat(max(0.25, min(1.0, s.overlayOpacity)))
        window.minSize = NSSize(width: 500, height: 400)
        window.delegate = self
        window.center()

        let host = NSHostingController(
            rootView: ZoomableDiagramOverlay(
                image: image,
                source: source,
                onClose: { [weak self] in
                    self?.appState?.showExpandedDiagram = false
                }
            )
        )
        window.contentViewController = host
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.diagramWindow = window
    }

    private func closeDiagramWindow() {
        diagramWindow?.close()
    }

    // MARK: - Code Viewer Window

    /// Open a floating Code Viewer window. A regular titled NSWindow that
    /// follows the same stealth + opacity rules as Settings/Diagram so it's
    /// hidden from screen capture when stealth is on. Floating level so it
    /// stays above the user's other windows like the main panel does.
    private func showCodeViewerWindow(appState: AppState) {
        // If we minimized to a dot, restore from there instead of creating a
        // brand-new window.
        if codeViewerDotPanel?.isVisible == true {
            restoreCodeViewerFromDot()
            return
        }

        if let w = codeViewerWindow {
            NSApp.activate(ignoringOtherApps: true)
            w.orderFrontRegardless()
            w.makeKeyAndOrderFront(nil)
            // Prompt for a folder if none has been opened yet.
            if codeViewerState.rootFolder == nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                    self?.codeViewerState.presentFolderPicker()
                }
            }
            return
        }

        let screen = NSScreen.main ?? NSScreen.screens.first
        let screenFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let winW = min(screenFrame.width * 0.7, 1100)
        let winH = min(screenFrame.height * 0.8, 720)

        let contentRect = NSRect(x: 0, y: 0, width: winW, height: winH)
        // Borderless KeyablePanel — no native macOS title bar, so we don't get
        // a duplicate title bar on top of CodeViewerView's own chrome. Same
        // pattern the main stealth panel uses.
        let window = KeyablePanel(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = NSColor(red: 0x1E/255.0, green: 0x1E/255.0, blue: 0x1E/255.0, alpha: 1.0)
        window.isOpaque = true
        window.hasShadow = true
        // Drag from any non-button area in the custom title bar.
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.isFloatingPanel = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        window.hidesOnDeactivate = false
        let s = appState.settings
        window.sharingType = s.stealthEnabled ? .none : .readOnly
        window.minSize = NSSize(width: 600, height: 360)
        window.delegate = self
        window.center()

        // Use NSHostingView (not NSHostingController) so the SwiftUI view fills
        // the window via autoresizing instead of intrinsic-content sizing —
        // CodeViewerView is fully flexible in both axes.
        let hostingView = NSHostingView(
            rootView: CodeViewerView(
                state: codeViewerState,
                onClose: { [weak self] in
                    self?.appState?.showCodeViewer = false
                },
                onMinimize: { [weak self] in
                    self?.minimizeCodeViewerToDot()
                },
                onOpacityChange: { [weak self] alpha in
                    self?.codeViewerWindow?.alphaValue = CGFloat(alpha)
                }
            )
        )
        hostingView.frame = window.contentView?.bounds ?? contentRect
        hostingView.autoresizingMask = [.width, .height]
        window.contentView = hostingView
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.codeViewerWindow = window

        // First time: prompt the user to pick a folder so they don't stare
        // at an empty sidebar wondering what to do.
        if codeViewerState.rootFolder == nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                self?.codeViewerState.presentFolderPicker()
            }
        }
    }

    private func closeCodeViewerWindow() {
        codeViewerDotPanel?.orderOut(nil)
        codeViewerWindow?.close()
    }

    // MARK: - Code Viewer Dot

    private func minimizeCodeViewerToDot() {
        guard let main = codeViewerWindow else { return }
        codeViewerFrameBeforeMinimize = main.frame

        if codeViewerDotPanel == nil {
            setupCodeViewerDotPanel()
        }
        guard let dot = codeViewerDotPanel else { return }
        // Stealth state should match the main panel's setting.
        dot.sharingType = (appState?.settings.stealthEnabled ?? true) ? .none : .readOnly

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.18
            main.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self else { return }
            self.codeViewerWindow?.orderOut(nil)
            dot.alphaValue = 0
            dot.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.15
                dot.animator().alphaValue = 1.0
            }
        })
    }

    private func restoreCodeViewerFromDot() {
        guard let main = codeViewerWindow, let dot = codeViewerDotPanel else { return }

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            dot.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self else { return }
            dot.orderOut(nil)

            if let saved = self.codeViewerFrameBeforeMinimize {
                main.setFrame(saved, display: true)
            }
            main.alphaValue = 0
            main.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.2
                main.animator().alphaValue = 1.0
            }
            self.codeViewerFrameBeforeMinimize = nil
        })
    }

    private func setupCodeViewerDotPanel() {
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size: CGFloat = 44
        // Sit to the LEFT of the main app's minimize dot so both can coexist
        // without colliding when the user has minimized both.
        let frame = NSRect(
            x: screenFrame.maxX - size - 16 - size - 8,
            y: screenFrame.minY + 16,
            width: size, height: size
        )

        let dot = KeyablePanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        dot.sharingType = (appState?.settings.stealthEnabled ?? true) ? .none : .readOnly
        dot.level = .floating
        dot.isFloatingPanel = true
        dot.isOpaque = false
        dot.backgroundColor = .clear
        dot.hasShadow = false
        dot.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        dot.isMovableByWindowBackground = true

        let host = NSHostingView(rootView: CodeViewerDotView { [weak self] in
            self?.restoreCodeViewerFromDot()
        })
        host.frame = dot.contentView?.bounds ?? frame
        host.autoresizingMask = [.width, .height]
        dot.contentView = host
        dot.contentView?.wantsLayer = true
        dot.contentView?.layer?.cornerRadius = size / 2
        dot.contentView?.layer?.masksToBounds = true

        codeViewerDotPanel = dot
    }

    // MARK: - Onboarding Window

    private func showOnboardingWindow(appState: AppState) {
        if let w = onboardingWindow {
            w.level = .floating
            NSApp.activate(ignoringOtherApps: true)
            w.orderFrontRegardless()
            w.makeKeyAndOrderFront(nil)
            return
        }

        let winW: CGFloat = 560
        let winH: CGFloat = 640
        let contentRect = NSRect(x: 0, y: 0, width: winW, height: winH)
        let window = NSWindow(
            contentRect: contentRect,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "SoloScreen"
        window.appearance = NSAppearance(named: .darkAqua)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = NSColor(red: 0x0D/255.0, green: 0x11/255.0, blue: 0x17/255.0, alpha: 1.0)
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        // No .transient — onboarding must survive app deactivation
        // when user switches to browser to copy API keys. Float above
        // other windows so it stays visible alongside the browser.
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isExcludedFromWindowsMenu = true
        window.hidesOnDeactivate = false
        window.level = .floating
        // Fixed size — no resizing.
        window.minSize = NSSize(width: winW, height: winH)
        window.maxSize = NSSize(width: winW, height: winH)
        let s = appState.settings
        window.sharingType = s.stealthEnabled ? .none : .readOnly
        window.delegate = self
        window.center()

        let host = NSHostingController(
            rootView: OnboardingView().environmentObject(appState)
        )
        // Pin the hosting view's size so SwiftUI doesn't expand to fill the screen.
        host.sizingOptions = []
        host.preferredContentSize = NSSize(width: winW, height: winH)
        window.contentViewController = host
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.onboardingWindow = window
    }

    private func closeOnboardingWindow() {
        onboardingWindow?.close()
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        guard let win = notification.object as? NSWindow else { return }

        if win === settingsWindow {
            settingsWindow = nil
            if appState?.showSettings == true {
                appState?.showSettings = false
            }
        } else if win === diagramWindow {
            diagramWindow = nil
            if appState?.showExpandedDiagram == true {
                appState?.showExpandedDiagram = false
            }
        } else if win === codeViewerWindow {
            codeViewerWindow = nil
            if appState?.showCodeViewer == true {
                appState?.showCodeViewer = false
            }
        } else if win === onboardingWindow {
            onboardingWindow = nil
            if appState?.showOnboarding == true {
                appState?.showOnboarding = false
            }
        }
    }

    private func updateStatusBarVisibility(stealth: Bool) {
        if stealth {
            teardownStatusBar()
        } else if statusBarItem == nil {
            setupStatusBar()
        }
    }

    private func teardownStatusBar() {
        if let item = statusBarItem {
            NSStatusBar.system.removeStatusItem(item)
            statusBarItem = nil
        }
    }

    // MARK: - Keyboard Shortcuts

    private func setupShortcuts() {
        let service = ShortcutService()
        self.shortcutService = service

        service.register(callbacks: ShortcutService.Callbacks(
            toggleVisibility: { [weak self] in
                self?.stealthWindowManager?.toggleVisibility()
            },
            newSession: { [weak self] in
                self?.appState?.createSession()
                self?.stealthWindowManager?.show()
            },
            toggleMinimize: { [weak self] in
                self?.stealthWindowManager?.toggleMinimize()
            },
            toggleExtremeStealth: { [weak self] in
                guard let self, let state = self.appState else { return }
                state.settings.extremeStealthEnabled.toggle()
                self.stealthWindowManager?.setExtremeStealth(state.settings.extremeStealthEnabled)
            },
            focusInput: {
                NotificationCenter.default.post(name: .soloScreenFocusInput, object: nil)
            },
            showShortcuts: {
                NotificationCenter.default.post(name: .soloScreenShowShortcuts, object: nil)
            },
            captureScreenshot: { [weak self] in
                // Capture and attach to the pending strip — the user sends
                // manually (possibly with multiple screenshots + a prompt).
                self?.appState?.captureScreenshot()
            },
            toggleMicRecording: { [weak self] in
                self?.appState?.toggleMicRecording()
            },
            toggleTranscription: { [weak self] in
                self?.appState?.toggleTranscription()
            },
            attachFile: { [weak self] in
                self?.appState?.showFilePicker = true
                self?.stealthWindowManager?.show()
            },
            scrollUp: {
                NotificationCenter.default.post(name: .soloScreenScrollUp, object: nil)
            },
            scrollDown: {
                NotificationCenter.default.post(name: .soloScreenScrollDown, object: nil)
            },
            cancelStreaming: { [weak self] in
                self?.appState?.cancelStreaming()
            },
            requestLiveHelp: { [weak self] in
                self?.appState?.requestLiveHelp()
            },
            clearChat: { [weak self] in
                self?.appState?.clearCurrentChat()
            },
            showModelSelector: { [weak self] in
                guard let self else { return }
                self.appState?.settingsInitialTab = "AI Provider"
                self.appState?.showSettings = true
            },
            opacityUp: { [weak self] in
                self?.appState?.increaseOpacity()
            },
            opacityDown: { [weak self] in
                self?.appState?.decreaseOpacity()
            },
            hideWindow: { [weak self] in
                self?.stealthWindowManager?.hide()
            },
            toggleDiagram: { [weak self] in
                self?.appState?.toggleExpandedDiagram()
            },
            expandDiagram: { [weak self] number in
                self?.appState?.expandDiagram(number: number)
            }
        ))
    }
}

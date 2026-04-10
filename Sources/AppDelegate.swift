import AppKit
import SwiftUI

/// Application delegate that configures SubtleAI as a menu-bar-only app
/// with a stealth floating overlay window.
///
/// Sets the activation policy to `.accessory` (no dock icon), creates a
/// status bar item for quick access, and initialises the stealth window
/// with the main SwiftUI view hierarchy.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Properties

    private var statusBarItem: NSStatusItem?
    private var stealthWindowManager: StealthWindowManager?
    private var appState: AppState?
    private var shortcutService: ShortcutService?

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

        // Set up the status bar item.
        setupStatusBar()

        // Register global keyboard shortcuts.
        setupShortcuts()
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

    // MARK: - Status Bar

    private func setupStatusBar() {
        statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusBarItem?.button {
            button.image = NSImage(
                systemSymbolName: "bubble.left.and.text.bubble.right.fill",
                accessibilityDescription: "SubtleAI"
            )
            button.image?.size = NSSize(width: 18, height: 18)
            button.image?.isTemplate = true
        }

        let menu = NSMenu()

        let showHideItem = NSMenuItem(
            title: "Show / Hide",
            action: #selector(toggleOverlayVisibility),
            keyEquivalent: ""
        )
        showHideItem.target = self
        menu.addItem(showHideItem)

        menu.addItem(NSMenuItem.separator())

        let newSessionItem = NSMenuItem(
            title: "New Session",
            action: #selector(createNewSession),
            keyEquivalent: "n"
        )
        newSessionItem.keyEquivalentModifierMask = [.command, .shift]
        newSessionItem.target = self
        menu.addItem(newSessionItem)

        let settingsItem = NSMenuItem(
            title: "Settings...",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.keyEquivalentModifierMask = .command
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(
            title: "Quit SubtleAI",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.keyEquivalentModifierMask = .command
        quitItem.target = self
        menu.addItem(quitItem)

        statusBarItem?.menu = menu
    }

    // MARK: - Status Bar Actions

    @objc private func toggleOverlayVisibility() {
        stealthWindowManager?.toggleVisibility()
    }

    @objc private func createNewSession() {
        appState?.createSession()
        stealthWindowManager?.show()
    }

    @objc private func openSettings() {
        appState?.showSettings = true
        stealthWindowManager?.show()
    }

    @objc private func quitApp() {
        appState?.saveAllState()
        NSApplication.shared.terminate(nil)
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
            captureScreenshot: { [weak self] in
                self?.appState?.captureScreenshot()
            },
            toggleMicRecording: { [weak self] in
                self?.appState?.toggleMicRecording()
            },
            cancelStreaming: { [weak self] in
                self?.appState?.cancelStreaming()
            }
        ))
    }
}

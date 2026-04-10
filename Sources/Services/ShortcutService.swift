import AppKit

/// Registers global keyboard shortcuts using NSEvent monitors.
///
/// Uses `addGlobalMonitorForEvents` (when app is in background) and
/// `addLocalMonitorForEvents` (when app has focus) to catch key combos
/// like Cmd+Shift+Space to toggle the stealth overlay, Cmd+Shift+S for
/// screenshots, etc. Requires Accessibility permission for global monitoring.
@MainActor
final class ShortcutService {

    // MARK: - Callbacks

    struct Callbacks {
        let toggleVisibility: () -> Void
        let newSession: () -> Void
        let toggleMinimize: () -> Void
        let captureScreenshot: () -> Void
        let toggleMicRecording: () -> Void
        let cancelStreaming: () -> Void
    }

    // MARK: - State

    private var callbacks: Callbacks?
    private var globalMonitor: Any?
    private var localMonitor: Any?

    // MARK: - Registration

    func register(callbacks: Callbacks) {
        self.callbacks = callbacks
        setupMonitors()
    }

    // MARK: - Monitor Setup

    private func setupMonitors() {
        // Global monitor: catches key events when the app is NOT focused.
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            Task { @MainActor in
                self?.handleKeyEvent(event)
            }
        }

        // Local monitor: catches key events when the app IS focused.
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            Task { @MainActor in
                self?.handleKeyEvent(event)
            }
            return event
        }
    }

    // MARK: - Event Handling

    private func handleKeyEvent(_ event: NSEvent) {
        guard let callbacks else { return }

        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let cmdShift: NSEvent.ModifierFlags = [.command, .shift]

        // Cmd+Shift+Space: Toggle visibility
        if modifiers == cmdShift && event.keyCode == 49 {
            callbacks.toggleVisibility()
            return
        }

        // Cmd+Shift+N: New session
        if modifiers == cmdShift && event.charactersIgnoringModifiers == "n" {
            callbacks.newSession()
            return
        }

        // Cmd+Shift+M: Toggle minimize
        if modifiers == cmdShift && event.charactersIgnoringModifiers == "m" {
            callbacks.toggleMinimize()
            return
        }

        // Cmd+Shift+S: Capture screenshot
        if modifiers == cmdShift && event.charactersIgnoringModifiers == "s" {
            callbacks.captureScreenshot()
            return
        }

        // Cmd+Shift+R: Toggle mic recording
        if modifiers == cmdShift && event.charactersIgnoringModifiers == "r" {
            callbacks.toggleMicRecording()
            return
        }

        // Escape: Cancel streaming (only when no modifiers are held)
        if event.keyCode == 53 && modifiers.isEmpty {
            callbacks.cancelStreaming()
            return
        }
    }

    // MARK: - Cleanup

    func tearDown() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
        globalMonitor = nil
        localMonitor = nil
        callbacks = nil
    }
}

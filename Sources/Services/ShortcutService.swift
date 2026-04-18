import AppKit

/// Registers global keyboard shortcuts using NSEvent monitors.
///
/// Uses `addGlobalMonitorForEvents` (when app is in background) and
/// `addLocalMonitorForEvents` (when app has focus) to catch key combos.
/// All shortcuts use Ctrl+Shift to avoid conflicts with other apps.
/// Requires Accessibility permission for global monitoring.
@MainActor
final class ShortcutService {

    // MARK: - Callbacks

    struct Callbacks {
        let toggleVisibility: () -> Void
        let newSession: () -> Void
        let toggleMinimize: () -> Void
        let toggleExtremeStealth: () -> Void
        let focusInput: () -> Void
        let showShortcuts: () -> Void
        let captureScreenshot: () -> Void
        let toggleMicRecording: () -> Void
        let toggleTranscription: () -> Void
        let attachFile: () -> Void
        let scrollUp: () -> Void
        let scrollDown: () -> Void
        let cancelStreaming: () -> Void
        let requestLiveHelp: () -> Void
        let clearChat: () -> Void
        let showModelSelector: () -> Void
        let opacityUp: () -> Void
        let opacityDown: () -> Void
        let hideWindow: () -> Void
        let toggleDiagram: () -> Void
        /// 1-based. Fires when the user presses ⌃⇧1 … ⌃⇧9.
        let expandDiagram: (Int) -> Void
    }

    // MARK: - State

    private var callbacks: Callbacks?
    private var globalMonitor: Any?
    private var localMonitor: Any?

    /// Timestamp of the last handled event. Used to dedupe keypresses that
    /// fire in both the global and local monitors (can happen because the
    /// stealth panel is non-activating, so the app's "active" state is
    /// ambiguous and both monitors receive the same event).
    private var lastHandledEventTimestamp: TimeInterval = -1

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

    // MARK: - macOS Key Codes

    // Using keyCode instead of charactersIgnoringModifiers because the
    // Control modifier can produce control characters that don't match
    // simple letter comparisons.
    private enum Key {
        static let space: UInt16 = 49
        static let escape: UInt16 = 53
        static let upArrow: UInt16 = 126
        static let downArrow: UInt16 = 125
        static let slash: UInt16 = 44  // / key
        static let a: UInt16 = 0
        static let e: UInt16 = 14
        static let i: UInt16 = 34
        static let m: UInt16 = 46
        static let n: UInt16 = 45
        static let r: UInt16 = 15
        static let s: UInt16 = 1
        static let t: UInt16 = 17
        static let h: UInt16 = 4
        static let k: UInt16 = 40
        static let p: UInt16 = 35
        static let equal: UInt16 = 24   // `=` key (⌃⇧= — opacity up)
        static let minus: UInt16 = 27   // `-` key (⌃⇧- — opacity down)
        static let d: UInt16 = 2        // `d` key (⌃⇧D — toggle diagram)
        static let w: UInt16 = 13       // `w` key (⌃⇧W — hide window)
        // Number-row keys for ⌃⇧1 … ⌃⇧9 → expand diagram N.
        static let num1: UInt16 = 18
        static let num2: UInt16 = 19
        static let num3: UInt16 = 20
        static let num4: UInt16 = 21
        static let num5: UInt16 = 23
        static let num6: UInt16 = 22
        static let num7: UInt16 = 26
        static let num8: UInt16 = 28
        static let num9: UInt16 = 25
    }

    // MARK: - Event Handling

    private func handleKeyEvent(_ event: NSEvent) {
        guard let callbacks else { return }

        // Dedupe: a global monitor and a local monitor can both fire for the
        // same hardware event on a nonactivating panel. Time-window check is
        // safer than exact equality in case timestamps differ by a hair.
        let delta = event.timestamp - lastHandledEventTimestamp
        if delta >= 0 && delta < 0.08 { return }
        lastHandledEventTimestamp = event.timestamp

        let modifiers = event.modifierFlags
        let code = event.keyCode

        // Check Ctrl+Shift held, without Command or Option.
        let isCtrlShift = modifiers.contains(.control)
            && modifiers.contains(.shift)
            && !modifiers.contains(.command)
            && !modifiers.contains(.option)

        guard isCtrlShift || (code == Key.escape && !modifiers.contains(.command)) else {
            return
        }

        switch code {
        // Ctrl+Shift combos
        case Key.space: callbacks.toggleVisibility()
        case Key.n:     callbacks.newSession()
        case Key.m:     callbacks.toggleMinimize()
        case Key.e:     callbacks.toggleExtremeStealth()
        case Key.i:     callbacks.focusInput()
        case Key.slash: callbacks.showShortcuts()
        case Key.s:     callbacks.captureScreenshot()
        case Key.r:     callbacks.toggleMicRecording()
        case Key.t:     callbacks.toggleTranscription()
        case Key.a:     callbacks.attachFile()
        case Key.upArrow:   callbacks.scrollUp()
        case Key.downArrow: callbacks.scrollDown()
        case Key.h:         callbacks.requestLiveHelp()
        case Key.k:         callbacks.clearChat()
        case Key.p:         callbacks.showModelSelector()
        case Key.equal:     callbacks.opacityUp()
        case Key.minus:     callbacks.opacityDown()
        case Key.d:         callbacks.toggleDiagram()
        case Key.w:         callbacks.hideWindow()
        case Key.num1:      callbacks.expandDiagram(1)
        case Key.num2:      callbacks.expandDiagram(2)
        case Key.num3:      callbacks.expandDiagram(3)
        case Key.num4:      callbacks.expandDiagram(4)
        case Key.num5:      callbacks.expandDiagram(5)
        case Key.num6:      callbacks.expandDiagram(6)
        case Key.num7:      callbacks.expandDiagram(7)
        case Key.num8:      callbacks.expandDiagram(8)
        case Key.num9:      callbacks.expandDiagram(9)

        // Escape (no modifiers)
        case Key.escape: callbacks.cancelStreaming()

        default: break
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

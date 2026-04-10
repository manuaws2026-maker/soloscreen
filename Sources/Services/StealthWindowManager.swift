import AppKit
import SwiftUI

/// Manages the stealth overlay panel that is invisible to screen capture.
///
/// The panel uses `sharingType = .none` so it never appears in screen recordings,
/// screenshots taken by other apps, or screen-sharing sessions.
/// It floats above all windows and can be toggled to "extreme stealth" mode
/// where it also ignores mouse events (full click-through).
@MainActor
final class StealthWindowManager {

    // MARK: - State

    private var panel: NSPanel?
    private var isVisible: Bool = true
    private var isMinimized: Bool = false

    /// The current window reference, if created. Useful for exclusion in screen captures.
    var window: NSWindow? { panel }

    // MARK: - Setup

    /// Create and display the stealth overlay panel hosting the provided SwiftUI view.
    ///
    /// - Parameter contentView: The SwiftUI root view to host in the panel.
    func setupWindow<Content: View>(contentView: Content) {
        // Define a reasonable default frame (right side of main screen).
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 400, height: 700)
        let panelWidth: CGFloat = 380
        let panelHeight: CGFloat = min(700, screenFrame.height - 40)
        let panelX = screenFrame.maxX - panelWidth - 20
        let panelY = screenFrame.midY - panelHeight / 2

        let frame = NSRect(x: panelX, y: panelY, width: panelWidth, height: panelHeight)

        let stealthPanel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )

        // --- Stealth Configuration ---
        // .none means the window content is excluded from all screen captures.
        stealthPanel.sharingType = .none

        // Floating level ensures the panel stays above normal windows.
        stealthPanel.level = .floating

        // Non-activating: clicking the panel does not steal focus from other apps.
        stealthPanel.isFloatingPanel = true
        stealthPanel.becomesKeyOnlyIfNeeded = true

        // Appearance: dark translucent background with rounded corners.
        stealthPanel.isOpaque = false
        stealthPanel.backgroundColor = NSColor.black.withAlphaComponent(0.85)
        stealthPanel.hasShadow = true

        // Do not show in dock or Cmd-Tab switcher.
        stealthPanel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .transient
        ]

        // Allow the panel to be moved by dragging its background.
        stealthPanel.isMovableByWindowBackground = true

        // Allow resizing within reasonable bounds.
        stealthPanel.minSize = NSSize(width: 300, height: 400)
        stealthPanel.maxSize = NSSize(width: 600, height: screenFrame.height)

        // Host the SwiftUI view.
        let hostingView = NSHostingView(rootView: contentView)
        hostingView.frame = stealthPanel.contentView?.bounds ?? frame
        hostingView.autoresizingMask = [.width, .height]

        // Ensure the hosting view and its layer have a transparent background
        // so the panel's own backgroundColor shows through.
        hostingView.layer?.backgroundColor = .clear
        stealthPanel.contentView = hostingView

        // Make the content view's corners rounded.
        stealthPanel.contentView?.wantsLayer = true
        stealthPanel.contentView?.layer?.cornerRadius = 12
        stealthPanel.contentView?.layer?.masksToBounds = true

        stealthPanel.orderFrontRegardless()

        self.panel = stealthPanel
        self.isVisible = true
        self.isMinimized = false
    }

    // MARK: - Visibility

    /// Toggle the overlay between visible and hidden.
    func toggleVisibility() {
        guard let panel else { return }

        if isVisible {
            panel.orderOut(nil)
        } else {
            panel.orderFrontRegardless()
        }
        isVisible.toggle()
        isMinimized = false
    }

    /// Explicitly show the overlay.
    func show() {
        guard let panel, !isVisible else { return }
        panel.orderFrontRegardless()
        isVisible = true
        isMinimized = false
    }

    /// Explicitly hide the overlay.
    func hide() {
        guard let panel, isVisible else { return }
        panel.orderOut(nil)
        isVisible = false
    }

    // MARK: - Extreme Stealth

    /// Enable or disable extreme stealth mode.
    ///
    /// When enabled, the panel ignores all mouse events — clicks pass through
    /// to whatever is underneath. The user can still toggle it off via keyboard shortcuts.
    /// - Parameter enabled: Whether extreme stealth should be active.
    func setExtremeStealth(_ enabled: Bool) {
        guard let panel else { return }
        panel.ignoresMouseEvents = enabled

        // In extreme stealth mode, reduce opacity slightly to signal the mode.
        if enabled {
            panel.alphaValue = max(panel.alphaValue, 0.3)
        }
    }

    // MARK: - Opacity

    /// Set the panel opacity.
    ///
    /// - Parameter opacity: A value between 0.0 (fully transparent) and 1.0 (fully opaque).
    func setOpacity(_ opacity: Double) {
        guard let panel else { return }
        panel.alphaValue = CGFloat(max(0.05, min(1.0, opacity)))
    }

    /// Returns the current opacity of the panel.
    var currentOpacity: Double {
        Double(panel?.alphaValue ?? 1.0)
    }

    // MARK: - Minimize / Restore

    /// Minimize the panel to a tiny sliver at the edge of the screen.
    func minimize() {
        guard let panel, !isMinimized else { return }
        isMinimized = true

        // Store the current frame so we can restore it later.
        panelFrameBeforeMinimize = panel.frame

        let screenFrame = NSScreen.main?.visibleFrame ?? panel.frame
        let miniFrame = NSRect(
            x: screenFrame.maxX - 8,
            y: screenFrame.midY - 30,
            width: 8,
            height: 60
        )
        panel.setFrame(miniFrame, display: true, animate: true)
        panel.alphaValue = 0.3
    }

    /// Restore the panel from its minimized state.
    func restore() {
        guard let panel, isMinimized else { return }
        isMinimized = false

        if let savedFrame = panelFrameBeforeMinimize {
            panel.setFrame(savedFrame, display: true, animate: true)
        }
        panel.alphaValue = 1.0
        panelFrameBeforeMinimize = nil
    }

    /// Toggle between minimized and restored states.
    func toggleMinimize() {
        if isMinimized {
            restore()
        } else {
            minimize()
        }
    }

    // MARK: - Private State

    private var panelFrameBeforeMinimize: NSRect?

    // MARK: - Cleanup

    /// Close the panel and release resources.
    func tearDown() {
        panel?.orderOut(nil)
        panel?.close()
        panel = nil
        isVisible = false
        isMinimized = false
        panelFrameBeforeMinimize = nil
    }
}

import AppKit
import SwiftUI

/// Custom NSPanel subclass that can become key window even when non-activating.
///
/// A standard `NSPanel` with `nonactivatingPanel` style won't become key,
/// which prevents text fields from receiving keyboard input (including Cmd+V paste).
/// Overriding `canBecomeKey` fixes this while still keeping the panel non-activating
/// (it won't steal focus from other apps when merely displayed).
class KeyablePanel: NSPanel {
    /// Temporarily allow key status for keyboard input focus (⌃⇧I).
    /// Set to true, call makeFirstResponder, then set back to false.
    var allowKeyTemporarily = false

    override var canBecomeKey: Bool { !ignoresMouseEvents || allowKeyTemporarily }
    override var canBecomeMain: Bool { false }
}

/// Manages the stealth overlay panel that is invisible to screen capture.
///
/// The panel uses `sharingType = .none` so it never appears in screen recordings,
/// screenshots taken by other apps, or screen-sharing sessions.
/// It floats above all windows and can be toggled to "extreme stealth" mode
/// where it also ignores mouse events (full click-through).
@MainActor
final class StealthWindowManager {

    // MARK: - State

    private var panel: KeyablePanel?
    private var dotPanel: KeyablePanel?
    private var mainHostingView: NSView?
    private var isVisible: Bool = true
    private var isMinimized: Bool = false

    /// The current window reference, if created. Useful for exclusion in screen captures.
    var window: NSWindow? { panel }

    /// Three orthogonal visibility states. Used by the status-bar menu to
    /// show contextual items.
    enum PanelState {
        case visible     // main panel on screen
        case hidden      // nothing on screen (main panel orderedOut, dot hidden)
        case minimized   // dot visible, main panel orderedOut
    }

    var state: PanelState {
        if isMinimized { return .minimized }
        return isVisible ? .visible : .hidden
    }

    /// Fully hide everything — both the main panel and the dot (if any).
    /// Used from the status-bar menu when minimized state also wants to
    /// dismiss the floating dot.
    func hideCompletely() {
        panel?.orderOut(nil)
        dotPanel?.orderOut(nil)
        isVisible = false
        isMinimized = false
    }

    // MARK: - Setup

    /// Create and display the stealth overlay panel hosting the provided SwiftUI view.
    ///
    /// - Parameter contentView: The SwiftUI root view to host in the panel.
    func setupWindow<Content: View>(contentView: Content) {
        // Launch position: full-height strip anchored to the right edge.
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 400, height: 700)
        let panelWidth: CGFloat = 520
        let panelHeight: CGFloat = screenFrame.height
        let panelX = screenFrame.maxX - panelWidth
        let panelY = screenFrame.origin.y  // bottom in Cocoa coords → spans full height

        let frame = NSRect(x: panelX, y: panelY, width: panelWidth, height: panelHeight)

        let stealthPanel = KeyablePanel(
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

        // Non-activating but keyable: clicking a text field makes the panel key
        // so it receives keyboard input (including Cmd+V paste), without stealing
        // focus from the frontmost app for non-text interactions.
        stealthPanel.isFloatingPanel = true
        stealthPanel.becomesKeyOnlyIfNeeded = false

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
        // Hard floor on how narrow the window can be dragged — below this
        // top-bar elements (Chats pill, model pill, Listen Live, trash,
        // gear) start clipping or wrapping. Keep drawer-mode available by
        // staying below the sidebar narrow-threshold (560).
        stealthPanel.minSize = NSSize(width: 500, height: 400)
        stealthPanel.maxSize = NSSize(width: 1000, height: screenFrame.height)

        // Host the SwiftUI view.
        let hostingView = NSHostingView(rootView: contentView)
        hostingView.frame = stealthPanel.contentView?.bounds ?? frame
        hostingView.autoresizingMask = [.width, .height]

        // Ensure the hosting view and its layer have a transparent background
        // so the panel's own backgroundColor shows through.
        hostingView.layer?.backgroundColor = .clear
        stealthPanel.contentView = hostingView
        self.mainHostingView = hostingView

        // Create a dedicated dot panel for the minimized state.
        let dotSize: CGFloat = 44
        let dotFrame = NSRect(
            x: screenFrame.maxX - dotSize - 16,
            y: screenFrame.minY + 16,
            width: dotSize,
            height: dotSize
        )

        let dotStealthPanel = KeyablePanel(
            contentRect: dotFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        dotStealthPanel.sharingType = .none
        dotStealthPanel.level = .floating
        dotStealthPanel.isFloatingPanel = true
        dotStealthPanel.isOpaque = false
        dotStealthPanel.backgroundColor = .clear
        dotStealthPanel.hasShadow = false
        dotStealthPanel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .transient
        ]
        dotStealthPanel.isMovableByWindowBackground = true

        let dotView = NSHostingView(rootView: DotView(onTap: { [weak self] in
            self?.restore()
        }))
        dotView.frame = dotStealthPanel.contentView?.bounds ?? dotFrame
        dotView.autoresizingMask = [.width, .height]
        dotStealthPanel.contentView = dotView
        dotStealthPanel.contentView?.wantsLayer = true
        dotStealthPanel.contentView?.layer?.cornerRadius = dotSize / 2
        dotStealthPanel.contentView?.layer?.masksToBounds = true
        dotStealthPanel.orderOut(nil)
        self.dotPanel = dotStealthPanel

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
            if isMinimized {
                dotPanel?.orderOut(nil)
            } else {
                panel.orderOut(nil)
            }
        } else {
            if isMinimized {
                dotPanel?.orderFrontRegardless()
            } else {
                panel.orderFrontRegardless()
            }
        }
        isVisible.toggle()
    }

    /// Explicitly show the overlay (restores from minimized if needed).
    func show() {
        guard !isVisible else { return }
        if isMinimized {
            restore()
        } else {
            panel?.orderFrontRegardless()
        }
        isVisible = true
    }

    /// Explicitly hide the overlay.
    func hide() {
        guard isVisible else { return }
        if isMinimized {
            dotPanel?.orderOut(nil)
        } else {
            panel?.orderOut(nil)
        }
        isVisible = false
    }

    // MARK: - Stealth Control

    /// Enable or disable stealth mode (invisible to screen capture).
    ///
    /// When enabled, the panel uses `sharingType = .none` so it never appears
    /// in screen recordings or screen-sharing sessions.
    /// When disabled, the panel becomes a normal window visible to screen capture.
    /// - Parameter enabled: Whether stealth should be active.
    func setStealth(_ enabled: Bool) {
        guard let panel else { return }
        panel.sharingType = enabled ? .none : .readOnly
        // Sharp corners + shadow when visible (looks like a real warning
        // frame). Rounded corners when stealthed.
        panel.contentView?.layer?.cornerRadius = enabled ? 12 : 0
        panel.hasShadow = !enabled
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

    /// Minimize the panel to a small dot at the bottom-right corner of the screen.
    /// Hides the main panel and shows a dedicated dot panel.
    func minimize() {
        guard let panel, dotPanel != nil, !isMinimized else { return }
        isMinimized = true

        panelFrameBeforeMinimize = panel.frame

        // Fade out main panel, then show the dot panel.
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().alphaValue = 0
        }, completionHandler: {
            MainActor.assumeIsolated { [weak self] in
                guard let self else { return }

                self.panel?.orderOut(nil)

                self.dotPanel?.alphaValue = 0
                self.dotPanel?.orderFrontRegardless()

                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.15
                    self.dotPanel?.animator().alphaValue = 1.0
                }
            }
        })
    }

    /// Restore the panel from its minimized dot state.
    func restore() {
        guard let panel, let dotPanel, isMinimized else { return }
        isMinimized = false

        // Fade out the dot panel, then show the main panel.
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            dotPanel.animator().alphaValue = 0
        }, completionHandler: {
            MainActor.assumeIsolated { [weak self] in
                guard let self else { return }

                self.dotPanel?.orderOut(nil)

                if let savedFrame = self.panelFrameBeforeMinimize {
                    self.panel?.setFrame(savedFrame, display: true)
                }
                self.panel?.alphaValue = 0
                self.panel?.orderFrontRegardless()

                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.2
                    panel.animator().alphaValue = 1.0
                }
                self.panelFrameBeforeMinimize = nil
            }
        })
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
        dotPanel?.orderOut(nil)
        dotPanel?.close()
        dotPanel = nil
        panel?.orderOut(nil)
        panel?.close()
        panel = nil
        isVisible = false
        isMinimized = false
        panelFrameBeforeMinimize = nil
    }
}

// MARK: - Minimized Dot View

/// Small teal dot shown when the app is minimized. Clicking restores the full window.
private struct DotView: View {
    let onTap: () -> Void
    @State private var isHovered = false

    /// Load the brain icon via NSImage so we work regardless of asset catalog
    /// semantics. `Image(_:bundle:)` can silently render blank for raw PNG
    /// resources in an executable target's SwiftPM bundle.
    private static let brainImage: NSImage? = {
        if let url = Bundle.module.url(forResource: "BrainIcon", withExtension: "png") {
            return NSImage(contentsOf: url)
        }
        return nil
    }()

    var body: some View {
        Button(action: onTap) {
            ZStack {
                // Black surface — the green icon reads sharpest on black.
                Circle()
                    .fill(Color.black)
                    .frame(width: 44, height: 44)

                if let img = Self.brainImage {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 42, height: 42)
                } else {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 26, weight: .medium))
                        .foregroundStyle(Color(hex: "22C55E"))
                }

                Circle()
                    .stroke(Color.green.opacity(0.85), lineWidth: 1.8)
                    .frame(width: 44, height: 44)
            }
            .shadow(color: Color.green.opacity(0.35), radius: 8)
            .scaleEffect(isHovered ? 1.1 : 1.0)
            .opacity(isHovered ? 1.0 : 0.92)
            .animation(.easeOut(duration: 0.2), value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

import AppKit

/// Application entry point for SoloScreen.
///
/// Uses a manual NSApplication run loop instead of SwiftUI's @main App protocol
/// because SoloScreen needs direct control over window creation via NSPanel for
/// stealth mode (sharingType = .none). The AppDelegate handles all setup:
/// status bar item, stealth window, keyboard shortcuts, and app state.
@main
struct SoloScreenApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()

        // Hold a strong reference to the delegate for the lifetime of the process.
        // NSApplication.delegate is unowned, so we keep it alive here.
        app.delegate = delegate

        // Enter the run loop. This call does not return until the app terminates.
        app.run()
    }
}

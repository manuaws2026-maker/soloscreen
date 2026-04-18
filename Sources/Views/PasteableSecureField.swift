import AppKit
import SwiftUI

/// An `NSSecureTextField` wrapper that reliably supports Cmd+V paste
/// even inside non-activating NSPanel windows.
///
/// SwiftUI's `SecureField` doesn't receive paste events in `.accessory`
/// apps hosted in non-activating panels because the standard Edit menu
/// action `NSText.paste(_:)` doesn't reach SwiftUI's internal text storage.
/// This wrapper uses AppKit's `NSSecureTextField` directly, which
/// participates in the normal responder chain and handles paste natively.
struct PasteableSecureField: NSViewRepresentable {
    let placeholder: String
    @Binding var text: String

    func makeNSView(context: Context) -> NSSecureTextField {
        let field = NSSecureTextField()
        field.placeholderString = placeholder
        field.stringValue = text
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 13)
        field.textColor = .white
        field.delegate = context.coordinator
        field.cell?.sendsActionOnEndEditing = false
        return field
    }

    func updateNSView(_ nsView: NSSecureTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            text.wrappedValue = field.stringValue
        }
    }
}

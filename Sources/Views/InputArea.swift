import SwiftUI
import UniformTypeIdentifiers

struct InputArea: View {
    @EnvironmentObject var appState: AppState
    @State private var messageText: String = ""
    @State private var textEditorHeight: CGFloat = 36
    @State private var showFilePicker: Bool = false

    private let bgColor = Color(hex: "0D1117")
    private let surfaceColor = Color(hex: "161B22")
    private let borderColor = Color(hex: "30363D")
    private let accentTeal = Color(hex: "00BCD4")

    private let minHeight: CGFloat = 36
    private let maxHeight: CGFloat = 120 // ~5 lines
    private let lineHeight: CGFloat = 21

    private var canSend: Bool {
        !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !appState.isStreaming
    }

    var body: some View {
        VStack(spacing: 0) {
            Divider()
                .overlay(borderColor)

            // Pending screenshots
            if !appState.pendingScreenshots.isEmpty {
                pendingScreenshotsBar
            }

            // Transcription indicator
            if appState.isTranscribing {
                transcriptionIndicator
            }

            // Input row
            inputRow
        }
        .background(surfaceColor)
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.text, .sourceCode, .json, .xml, .yaml, .plainText, .pdf],
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result)
        }
    }

    // MARK: - Pending Screenshots

    private var pendingScreenshotsBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(appState.pendingScreenshots.enumerated()), id: \.offset) { index, data in
                    ZStack(alignment: .topTrailing) {
                        if let nsImage = NSImage(data: data) {
                            Image(nsImage: nsImage)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 64, height: 48)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .strokeBorder(borderColor, lineWidth: 1)
                                )
                        }

                        Button {
                            withAnimation(.easeOut(duration: 0.15)) {
                                appState.removeScreenshot(at: index)
                            }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(.white.opacity(0.8))
                                .background(Circle().fill(Color.black.opacity(0.6)))
                        }
                        .buttonStyle(.plain)
                        .offset(x: 4, y: -4)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Transcription Indicator

    private var transcriptionIndicator: some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform")
                .font(.system(size: 12))
                .foregroundStyle(accentTeal)
                .symbolEffect(.variableColor.iterative)

            Text("Live transcription active")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.5))

            if !appState.transcriptText.isEmpty {
                Text(appState.transcriptText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(accentTeal.opacity(0.06))
    }

    // MARK: - Input Row

    private var inputRow: some View {
        HStack(alignment: .bottom, spacing: 8) {
            // Left action buttons
            leftActions

            // Text editor
            textInput

            // Send button
            sendButton
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - Left Actions

    private var leftActions: some View {
        HStack(spacing: 4) {
            // Screenshot button
            ToolbarIconButton(
                icon: "camera",
                isActive: false,
                activeColor: accentTeal,
                help: "Capture Screenshot"
            ) {
                appState.captureScreenshot()
            }

            // Mic button
            ToolbarIconButton(
                icon: appState.isRecordingMic ? "mic.fill" : "mic",
                isActive: appState.isRecordingMic,
                activeColor: .red,
                help: appState.isRecordingMic ? "Stop Recording" : "Start Recording"
            ) {
                appState.toggleMicRecording()
            }

            // Transcription button
            ToolbarIconButton(
                icon: "waveform",
                isActive: appState.isTranscribing,
                activeColor: accentTeal,
                help: appState.isTranscribing ? "Stop Transcription" : "Start Live Transcription"
            ) {
                appState.toggleTranscription()
            }

            // File attachment button
            ToolbarIconButton(
                icon: "paperclip",
                isActive: false,
                activeColor: accentTeal,
                help: "Attach File"
            ) {
                showFilePicker = true
            }
        }
    }

    // MARK: - Text Input

    private var textInput: some View {
        ZStack(alignment: .topLeading) {
            // Placeholder
            if messageText.isEmpty {
                Text("Message SubtleAI...")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.3))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .allowsHitTesting(false)
            }

            // Growing TextEditor
            GrowingTextEditor(
                text: $messageText,
                minHeight: minHeight,
                maxHeight: maxHeight,
                onCommit: sendIfPossible
            )
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(bgColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(borderColor, lineWidth: 1)
                )
        )
    }

    // MARK: - Send Button

    private var sendButton: some View {
        Button {
            sendIfPossible()
        } label: {
            Image(systemName: appState.isStreaming ? "stop.fill" : "arrow.up")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(canSend || appState.isStreaming ? .white : .white.opacity(0.25))
                .frame(width: 32, height: 32)
                .background(
                    Circle()
                        .fill(canSend || appState.isStreaming ? accentTeal : accentTeal.opacity(0.15))
                )
        }
        .buttonStyle(.plain)
        .help(appState.isStreaming ? "Stop generating" : "Send message")
    }

    // MARK: - Actions

    private func sendIfPossible() {
        if appState.isStreaming {
            appState.cancelStreaming()
            return
        }

        let trimmed = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let attachments = appState.pendingScreenshots.map { data in
            Message.Attachment(
                id: UUID(),
                type: .screenshot,
                data: data,
                fileName: "screenshot.png",
                mimeType: "image/png"
            )
        }

        appState.sendMessage(trimmed, attachments: attachments)
        messageText = ""
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            guard url.startAccessingSecurityScopedResource() else { return }
            defer { url.stopAccessingSecurityScopedResource() }

            if let data = try? Data(contentsOf: url) {
                let attachment = Message.Attachment(
                    id: UUID(),
                    type: .file,
                    data: data,
                    fileName: url.lastPathComponent,
                    mimeType: url.mimeType
                )
                appState.sendMessage("", attachments: [attachment])
            }
        case .failure:
            break
        }
    }
}

// MARK: - Growing Text Editor

private struct GrowingTextEditor: NSViewRepresentable {
    @Binding var text: String
    let minHeight: CGFloat
    let maxHeight: CGFloat
    let onCommit: () -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView

        textView.delegate = context.coordinator
        textView.font = NSFont.systemFont(ofSize: 14)
        textView.textColor = NSColor.white.withAlphaComponent(0.9)
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.insertionPointColor = NSColor(Color(hex: "00BCD4"))

        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder

        let heightConstraint = scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: minHeight)
        heightConstraint.isActive = true
        context.coordinator.heightConstraint = heightConstraint

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
            context.coordinator.updateHeight(textView: textView, scrollView: scrollView)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        let parent: GrowingTextEditor
        var heightConstraint: NSLayoutConstraint?

        init(parent: GrowingTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            if let scrollView = textView.enclosingScrollView {
                updateHeight(textView: textView, scrollView: scrollView)
            }
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                let event = NSApp.currentEvent
                if event?.modifierFlags.contains(.shift) == true {
                    textView.insertNewlineIgnoringFieldEditor(nil)
                    return true
                } else {
                    parent.onCommit()
                    return true
                }
            }
            return false
        }

        func updateHeight(textView: NSTextView, scrollView: NSScrollView) {
            guard let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer else { return }

            layoutManager.ensureLayout(for: textContainer)
            let contentHeight = layoutManager.usedRect(for: textContainer).height + textView.textContainerInset.height * 2
            let clampedHeight = min(max(contentHeight, parent.minHeight), parent.maxHeight)
            heightConstraint?.constant = clampedHeight
        }
    }
}

// MARK: - Toolbar Icon Button

private struct ToolbarIconButton: View {
    let icon: String
    let isActive: Bool
    let activeColor: Color
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(isActive ? activeColor : .white.opacity(0.4))
                .frame(width: 30, height: 30)
                .background(
                    Circle()
                        .fill(isActive ? activeColor.opacity(0.15) : Color.clear)
                )
                .animation(.easeInOut(duration: 0.15), value: isActive)
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

// MARK: - URL Mime Type Extension

private extension URL {
    var mimeType: String {
        if let type = UTType(filenameExtension: pathExtension) {
            return type.preferredMIMEType ?? "application/octet-stream"
        }
        return "application/octet-stream"
    }
}

#Preview {
    InputArea()
        .environmentObject(AppState())
}

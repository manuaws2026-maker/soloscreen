import SwiftUI
import UniformTypeIdentifiers

struct InputArea: View {
    @EnvironmentObject var appState: AppState
    @State private var messageText: String = ""
    @State private var editorHeight: CGFloat = 36
    @State private var showFilePicker: Bool = false
    @State private var pendingFileAttachment: Message.Attachment?

    private let bgColor = Color(hex: "0D1117")
    private let surfaceColor = Color(hex: "161B22")
    private let borderColor = Color(hex: "30363D")
    private let accentTeal = Color(hex: "22C55E")

    private let minEditorHeight: CGFloat = 36
    private let maxEditorHeight: CGFloat = 120

    /// Default prompt for a screenshot-only message in a blank chat (no
    /// template). Gives the LLM clear fallback instructions.
    fileprivate static let defaultScreenshotPrompt = """
    Please analyze the attached screenshot(s).
    - If it contains a task, problem, question, or error, solve it completely.
    - If it's code, explain or debug it as appropriate.
    - If anything important is ambiguous, ask a concise clarifying question before proceeding.
    Otherwise, describe what's shown and suggest the most useful next step.
    """

    /// Minimal prompt used when the active chat has a template — the template's
    /// system prompt already tells the LLM how to respond, so we only need to
    /// point it at the attachment without overriding that guidance.
    fileprivate static let templateScreenshotPrompt = "Please analyze the attached screenshot(s) and respond per your instructions."

    private var canSend: Bool {
        let hasText = !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasFile = pendingFileAttachment != nil
        let hasScreenshot = !appState.pendingScreenshots.isEmpty
        return (hasText || hasFile || hasScreenshot) && !appState.isStreaming
    }

    /// Whether extreme stealth is active (click-through mode).
    private var isStealth: Bool {
        appState.settings.extremeStealthEnabled
    }

    var body: some View {
        VStack(spacing: 0) {
            Divider()
                .overlay(borderColor)

            // Pending screenshots
            if !appState.pendingScreenshots.isEmpty {
                pendingScreenshotsBar
            }

            // (Live-listen UI has moved to the top-bar — no inline banner here.)

            // Pending file attachment chip
            if let file = pendingFileAttachment {
                HStack(spacing: 8) {
                    Image(systemName: "doc.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(accentTeal)
                    Text(file.fileName ?? "File")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                    Spacer()
                    Button {
                        pendingFileAttachment = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(accentTeal.opacity(0.08))
            }

            // Unified input container
            VStack(spacing: 0) {
                // Text editor
                ZStack(alignment: .leading) {
                    CompactTextEditor(
                        text: $messageText,
                        height: $editorHeight,
                        minHeight: minEditorHeight,
                        maxHeight: maxEditorHeight,
                        placeholder: appState.settings.extremeStealthEnabled ? "" : "Message SoloScreen...",
                        onCommit: sendIfPossible
                    )
                    .frame(height: editorHeight)

                    // Stealth focus hint — shown when in extreme stealth with empty input
                    if isStealth && messageText.isEmpty {
                        HStack(spacing: 6) {
                            Text("⌃⇧I")
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.green.opacity(0.5))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(.green.opacity(0.06))
                                )
                            Text("to focus input")
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.2))
                        }
                        .padding(.leading, 12)
                        .allowsHitTesting(false)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.top, 8)
                .padding(.bottom, 4)

                // Bottom row: action buttons + send
                HStack(spacing: 0) {
                    HStack(spacing: 2) {
                        actionButton("camera", active: false, color: accentTeal, tip: "Attach screenshot", shortcut: "⌃⇧S") {
                            appState.captureScreenshot()
                        }
                        actionButton(
                            appState.isRecordingMic ? "mic.fill" : "mic",
                            active: appState.isRecordingMic,
                            color: .red,
                            tip: appState.isRecordingMic
                                ? "Stop recording"
                                : "Dictate into the message box",
                            shortcut: "⌃⇧R"
                        ) {
                            appState.toggleMicRecording()
                        }
                        // (Listen Live lives in the top bar now — removed from here.)
                        // Hide attach in extreme stealth — file picker can't work in click-through mode.
                        if !isStealth {
                            actionButton("paperclip", active: false, color: accentTeal, tip: "Attach", shortcut: "⌃⇧A") {
                                showFilePicker = true
                            }
                        }
                    }

                    Spacer()

                    // Send / Stop button
                    VStack(spacing: 3) {
                        Button {
                            sendIfPossible()
                        } label: {
                            Image(systemName: appState.isStreaming ? "stop.fill" : "arrow.up")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(canSend || appState.isStreaming ? .white : .white.opacity(0.25))
                                .frame(width: 28, height: 28)
                                .background(
                                    Circle()
                                        .fill(canSend || appState.isStreaming ? accentTeal : accentTeal.opacity(0.15))
                                )
                        }
                        .buttonStyle(.plain)

                        if isStealth {
                            Text(appState.isStreaming ? "Esc" : "↵")
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.green.opacity(0.65))
                                .lineLimit(1)
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(bgColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(borderColor, lineWidth: 1)
                    )
            )
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .background(surfaceColor)
        .onChange(of: appState.showFilePicker) { _, show in
            if show {
                showFilePicker = true
                appState.showFilePicker = false
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .soloScreenInsertDictation)) { note in
            // Mic dictation finished — append the transcript to the composer
            // and focus it so the user can edit or press Enter.
            guard let text = note.userInfo?["text"] as? String else { return }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            if messageText.isEmpty {
                messageText = trimmed
            } else {
                messageText += " " + trimmed
            }
            NotificationCenter.default.post(name: .soloScreenFocusInput, object: nil)
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [
                .text, .sourceCode, .json, .xml, .yaml, .plainText, .pdf,
                .image, .png, .jpeg, .webP, .gif, .heic, .bmp, .tiff
            ],
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result)
        }
    }

    // MARK: - Action Button

    /// Button with optional keyboard shortcut hint shown in extreme stealth mode.
    private func actionButton(
        _ icon: String,
        active: Bool,
        color: Color,
        tip: String,
        shortcut: String?,
        action: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 3) {
            Button(action: action) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundStyle(active ? color : .white.opacity(0.35))
                    .frame(width: 28, height: 28)
                    .background(
                        Circle()
                            .fill(active ? color.opacity(0.15) : Color.clear)
                    )
            }
            .buttonStyle(.plain)
            .help(shortcut != nil ? "\(tip) (\(shortcut!))" : tip)

            if isStealth, let shortcut {
                Text(shortcut)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.green.opacity(0.65))
                    .lineLimit(1)
            }
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

    // MARK: - Actions

    private func sendIfPossible() {
        if appState.isStreaming {
            appState.cancelStreaming()
            return
        }

        let trimmed = messageText.trimmingCharacters(in: .whitespacesAndNewlines)

        // Build the message content — include file text if attached
        var messageContent = trimmed
        if let file = pendingFileAttachment, let fileText = file.textContent {
            let fileName = file.fileName ?? "File"
            let fileBlock = "[Attached file: \(fileName)]\n\(fileText)"
            messageContent = trimmed.isEmpty ? fileBlock : "\(trimmed)\n\n\(fileBlock)"
        }

        // Allow submitting with no text if at least one screenshot is attached.
        guard !messageContent.isEmpty || !appState.pendingScreenshots.isEmpty else { return }

        // If the user submits screenshots without any text, inject a default
        // analyze prompt so the LLM knows what to do with them.
        //   • Blank chat → verbose fallback instructions.
        //   • Templated chat → minimal nudge; the template's system prompt
        //     already defines the response format, don't override it.
        if messageContent.isEmpty && !appState.pendingScreenshots.isEmpty {
            let hasTemplate = appState.activeSession?.systemPrompt?.isEmpty == false
            messageContent = hasTemplate ? Self.templateScreenshotPrompt : Self.defaultScreenshotPrompt
        }

        var attachments = appState.pendingScreenshots.map { data in
            Message.Attachment(
                id: UUID(),
                type: .screenshot,
                data: data,
                fileName: "screenshot.png",
                mimeType: "image/png"
            )
        }
        if let file = pendingFileAttachment {
            attachments.append(file)
        }

        appState.sendMessage(messageContent, attachments: attachments)
        messageText = ""
        pendingFileAttachment = nil
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            guard url.startAccessingSecurityScopedResource() else { return }
            defer { url.stopAccessingSecurityScopedResource() }

            let mime = url.mimeType
            let isImage = mime.hasPrefix("image/")

            do {
                let data = try Data(contentsOf: url)

                if isImage {
                    // Route images into pendingScreenshots — that's the same
                    // path system-captured screenshots use, so LLM vision
                    // models pick them up automatically at send time.
                    if appState.pendingScreenshots.count >= 5 {
                        appState.pendingScreenshots.removeFirst()
                    }
                    appState.pendingScreenshots.append(data)
                } else {
                    let text = try FileProcessorService.extractText(from: url)
                    pendingFileAttachment = Message.Attachment(
                        id: UUID(),
                        type: .file,
                        data: data,
                        fileName: url.lastPathComponent,
                        mimeType: mime,
                        textContent: text
                    )
                }
            } catch {
                appState.setError("Failed to read file: \(error.localizedDescription)")
            }
        case .failure:
            break
        }
    }
}

// MARK: - Compact Text Editor (NSViewRepresentable)

/// A compact auto-growing text editor backed by NSTextView.
/// Reports its ideal height via a binding so SwiftUI can size it correctly.
private struct CompactTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var height: CGFloat
    let minHeight: CGFloat
    let maxHeight: CGFloat
    let placeholder: String
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
        textView.textContainerInset = NSSize(width: 4, height: 4)
        textView.insertionPointColor = NSColor(Color(hex: "22C55E"))

        applyPlaceholder(to: textView, text: placeholder)

        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder

        // Listen for ⌃⇧I focus-input hotkey.
        context.coordinator.focusObserver = NotificationCenter.default.addObserver(
            forName: .soloScreenFocusInput, object: nil, queue: .main
        ) { [weak textView] _ in
            guard let textView, let window = textView.window else { return }
            if window.firstResponder === textView {
                window.makeFirstResponder(nil)
            } else {
                // Click-through mode normally blocks the panel from becoming
                // key — so keyboard focus would bounce right back. Enable
                // `allowKeyTemporarily` AND KEEP it on until focus is
                // released, so the user can actually type continuously.
                (window as? KeyablePanel)?.allowKeyTemporarily = true
                window.makeKey()
                window.makeFirstResponder(textView)
                // NOTE: we intentionally do NOT reset `allowKeyTemporarily`
                // here. It stays true for the duration of the input session,
                // and gets reset when the text view resigns first responder.
            }
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
            DispatchQueue.main.async {
                context.coordinator.recalcHeight(textView: textView)
            }
        }
        applyPlaceholder(to: textView, text: placeholder)
    }

    private func applyPlaceholder(to textView: NSTextView, text: String) {
        let attributed = NSAttributedString(
            string: text,
            attributes: [
                .foregroundColor: NSColor.white.withAlphaComponent(0.28),
                .font: NSFont.systemFont(ofSize: 14),
            ]
        )
        textView.setValue(attributed, forKey: "placeholderAttributedString")
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        let parent: CompactTextEditor
        var focusObserver: Any?

        init(parent: CompactTextEditor) {
            self.parent = parent
        }

        deinit {
            if let focusObserver { NotificationCenter.default.removeObserver(focusObserver) }
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            recalcHeight(textView: textView)
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                if NSApp.currentEvent?.modifierFlags.contains(.shift) == true {
                    textView.insertNewlineIgnoringFieldEditor(nil)
                    return true
                } else {
                    parent.onCommit()
                    resignAndRestorePassthrough(textView: textView)
                    return true
                }
            }
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                // Escape pressed — give up focus and drop the key grant so
                // clicks pass through again in extreme stealth mode.
                resignAndRestorePassthrough(textView: textView)
                return true
            }
            return false
        }

        /// Blur the text view and flip `allowKeyTemporarily` back off so
        /// click-through behavior is restored after the user stops typing.
        private func resignAndRestorePassthrough(textView: NSTextView) {
            guard let window = textView.window else { return }
            window.makeFirstResponder(nil)
            (window as? KeyablePanel)?.allowKeyTemporarily = false
        }

        func recalcHeight(textView: NSTextView) {
            guard let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer else { return }

            layoutManager.ensureLayout(for: textContainer)
            let contentHeight = layoutManager.usedRect(for: textContainer).height
                + textView.textContainerInset.height * 2
            let clamped = min(max(contentHeight, parent.minHeight), parent.maxHeight)

            if abs(parent.height - clamped) > 1 {
                parent.height = clamped
            }
        }
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

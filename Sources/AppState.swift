import Combine
import Foundation
import SwiftUI

private extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let m = pow(10.0, Double(places))
        return (self * m).rounded() / m
    }
}

/// Central state manager for the entire SoloScreen application.
///
/// Owns all published state that drives the UI: sessions, projects, settings,
/// streaming status, recording state, and pending screenshots. All mutations
/// happen on the main actor so SwiftUI updates are safe.
@MainActor
final class AppState: ObservableObject {

    // MARK: - Core Data

    @Published var sessions: [Session] = []
    @Published var activeSessionId: UUID?
    @Published var projects: [Project] = []
    @Published var settings: UserSettings = UserSettings()

    // MARK: - UI State

    @Published var isStreaming: Bool = false
    /// Set when a complete (non-streamed) response is appended. The chat
    /// scroll view reads this to avoid auto-scrolling to the bottom of a
    /// huge pre-built answer — the user should read from the top.
    var skipNextAutoScroll: Bool = false
    @Published var showSettings: Bool = false
    @Published var settingsInitialTab: String?
    @Published var showProjects: Bool = false
    @Published var showOnboarding: Bool = false
    @Published var sidebarVisible: Bool = true
    @Published var showFilePicker: Bool = false
    @Published var showLanguagePicker: Bool = false

    // MARK: - Audio / Transcription

    @Published var isRecordingMic: Bool = false
    @Published var isDictating: Bool = false
    /// True while SoloScreen is live-transcribing *system audio* (speaker).
    /// Drives the top-bar live-listen bar graph + AI Help/Stop buttons.
    @Published var isLiveListening: Bool = false
    /// Rolling transcript built from Deepgram's live stream while
    /// `isLiveListening`. Kept separate from any chat session.
    @Published var liveTranscript: String = ""
    /// Recent audio RMS levels (0..1) for the top-bar bar graph.
    @Published var liveAudioLevels: [CGFloat] = Array(repeating: 0, count: 14)
    private var lastAudioLevelEmitAt: Date = .distantPast
    /// On-demand LLM answer triggered by the "AI Help" button.
    @Published var liveHelpAnswer: String = ""
    @Published var isLiveHelpStreaming: Bool = false
    @Published var showLiveHelpModal: Bool = false

    /// Multi-turn conversation shown in the Live Help modal.
    @Published var liveHelpMessages: [LiveHelpMessage] = []

    /// The diagram currently shown in the expansion overlay (if any).
    var lastDiagramSource: String?
    var lastDiagramImage: NSImage?
    @Published var showExpandedDiagram: Bool = false

    /// Ordered registry of diagrams the user has seen rendered.
    struct DiagramEntry: Equatable {
        let source: String
        var image: NSImage
    }
    @Published var diagramRegistry: [DiagramEntry] = []
    private static let maxDiagramShortcuts = 9

    func registerDiagram(source: String, image: NSImage) -> Int? {
        if let existing = diagramRegistry.firstIndex(where: { $0.source == source }) {
            diagramRegistry[existing].image = image
            return existing < Self.maxDiagramShortcuts ? (existing + 1) : nil
        }
        diagramRegistry.append(DiagramEntry(source: source, image: image))
        let idx = diagramRegistry.count - 1
        return idx < Self.maxDiagramShortcuts ? (idx + 1) : nil
    }

    func expandDiagram(number: Int) {
        let idx = number - 1
        guard diagramRegistry.indices.contains(idx) else {
            setError("No diagram #\(number) on screen.")
            return
        }
        if showExpandedDiagram, lastDiagramSource == diagramRegistry[idx].source {
            showExpandedDiagram = false
            return
        }
        lastDiagramSource = diagramRegistry[idx].source
        lastDiagramImage = diagramRegistry[idx].image
        showExpandedDiagram = true
    }

    struct LiveHelpMessage: Identifiable, Equatable {
        let id = UUID()
        let role: Role
        var content: String
        enum Role { case user, assistant }
    }

    // MARK: - User Templates

    @Published var userTemplates: [ChatTemplate] = []

    func addUserTemplate(_ template: ChatTemplate) {
        userTemplates.append(template)
        saveUserTemplates()
    }

    func deleteUserTemplate(_ id: UUID) {
        userTemplates.removeAll { $0.id == id }
        saveUserTemplates()
    }

    private func saveUserTemplates() {
        Task {
            do {
                let snapshot = userTemplates
                try await PersistenceService.shared.saveTemplates(snapshot)
            } catch {
                await MainActor.run {
                    setError("Failed to save templates: \(error.localizedDescription)")
                }
            }
        }
    }

    private func loadUserTemplates() {
        Task {
            let loaded = await PersistenceService.shared.loadTemplates()
            await MainActor.run {
                userTemplates = loaded
            }
        }
    }

    func updateUserTemplate(_ template: ChatTemplate) {
        if let idx = userTemplates.firstIndex(where: { $0.id == template.id }) {
            userTemplates[idx] = template
            saveUserTemplates()
        }
    }

    // MARK: - Screenshots

    @Published var pendingScreenshots: [Data] = []

    // MARK: - Error Handling

    @Published var errorMessage: String?
    @Published var errorLinkLabel: String?
    @Published var errorSettingsTab: String?
    @Published var errorSystemSettingsURL: String?

    // MARK: - Streaming Task

    var streamingTask: Task<Void, Never>?

    // MARK: - Dependencies

    private let llmRouter = LLMRouter()
    let audioService = AudioService()

    // MARK: - Key Status Cache

    var hasOpenAIKey: Bool = false
    var hasDeepgramKey: Bool = false

    // MARK: - Feature Model Selection

    /// Features that can use per-feature model overrides.
    enum AppFeature: String, CaseIterable, Identifiable {
        case liveHelp = "Live Help"
        case screenshot = "Screenshot Analysis"

        var id: String { rawValue }

        var description: String { rawValue }

        var requiresVision: Bool {
            switch self {
            case .screenshot: return true
            case .liveHelp: return false
            }
        }
    }

    /// Returns the fastest/cheapest sibling model for the given provider family.
    func fastSiblingModel(provider: String, current: String) -> String {
        switch provider.lowercased() {
        case "openai":    return "gpt-4o-mini"
        case "anthropic": return "claude-3-5-haiku-latest"
        case "google":    return "gemini-2.0-flash"
        default:          return current
        }
    }

    /// The model to use for a given feature. Checks user overrides first,
    /// then falls back to the fast sibling auto-pick.
    func effectiveModel(for feature: AppFeature) -> String {
        let override: String?
        switch feature {
        case .liveHelp:   override = settings.liveHelpModelOverride
        case .screenshot: override = settings.screenshotModelOverride
        }
        if let override, !override.isEmpty { return override }
        return fastSiblingModel(provider: settings.selectedProvider, current: settings.selectedModel)
    }

    // MARK: - Computed Properties

    /// The currently active chat session, if any.
    var activeSession: Session? {
        guard let id = activeSessionId else { return nil }
        return sessions.first { $0.id == id }
    }

    /// The provider that will actually be used for transcription right now.
    var effectiveTranscriptionProvider: String? {
        switch settings.transcriptionProvider.lowercased() {
        case "openai", "whisper":
            if hasOpenAIKey { return "openai" }
        case "deepgram":
            if hasDeepgramKey { return "deepgram" }
        default:
            break
        }
        if hasOpenAIKey { return "openai" }
        if hasDeepgramKey { return "deepgram" }
        return nil
    }

    func refreshKeyStatuses() async {
        hasOpenAIKey = !(await KeychainService.shared.loadOpenAIKey() ?? "").isEmpty
        hasDeepgramKey = !(await KeychainService.shared.loadDeepgramKey() ?? "").isEmpty
    }

    // MARK: - Initialization

    init() {
        Task { @MainActor in
            await loadPersistedState()
            if !settings.onboardingCompleted {
                showOnboarding = true
            }
            await refreshKeyStatuses()
            loadUserTemplates()
            // Enforce sane defaults on startup.
            settings.stealthEnabled = true
            settings.extremeStealthEnabled = false
            if settings.overlayOpacity < 0.25 { settings.overlayOpacity = 0.95 }
        }
    }

    private func loadPersistedState() async {
        let persistence = PersistenceService.shared
        let loadedSessions = await persistence.loadSessions()
        let loadedProjects = await persistence.loadProjects()
        let loadedSettings = await persistence.loadSettings()

        self.sessions = loadedSessions
        self.projects = loadedProjects
        self.settings = loadedSettings

        if !sessions.isEmpty, activeSessionId == nil {
            activeSessionId = sessions.sorted(by: { $0.updatedAt > $1.updatedAt }).first?.id
        }
    }

    // MARK: - Session Management

    func createSession(template: ChatTemplate? = nil) {
        var session = Session(model: settings.selectedModel)
        if let template {
            var prompt = template.systemPrompt
            if template.requiresLanguage, let lang = settings.preferredCodingLanguage {
                prompt = prompt.replacingOccurrences(of: "{{LANGUAGE}}", with: lang)
            }
            session.systemPrompt = prompt
            session.templateName = template.name
            session.templateIcon = template.icon
        }
        sessions.insert(session, at: 0)
        activeSessionId = session.id
        saveSessions()

        // Prompt for language on first coding/system-design chat if not set.
        if let tmpl = template,
           tmpl.requiresLanguage,
           settings.preferredCodingLanguage == nil {
            showLanguagePicker = true
        }
    }

    // MARK: - Opacity

    private static let opacityStep: Double = 0.05
    private static let opacityFloor: Double = 0.25

    func increaseOpacity() {
        settings.overlayOpacity = min(1.0, settings.overlayOpacity + Self.opacityStep).rounded(toPlaces: 2)
        saveSettings()
    }

    func decreaseOpacity() {
        settings.overlayOpacity = max(Self.opacityFloor, settings.overlayOpacity - Self.opacityStep).rounded(toPlaces: 2)
        saveSettings()
    }

    func clearCurrentChat() {
        guard let id = activeSessionId,
              let index = sessions.firstIndex(where: { $0.id == id })
        else { return }
        cancelStreaming()
        sessions[index].messages.removeAll()
        sessions[index].title = "New Chat"
        sessions[index].updatedAt = Date()
        pendingScreenshots.removeAll()
        diagramRegistry.removeAll()
        saveSessions()
    }

    func deleteSession(_ id: UUID) {
        sessions.removeAll { $0.id == id }
        if activeSessionId == id {
            activeSessionId = sessions.sorted(by: { $0.updatedAt > $1.updatedAt }).first?.id
        }
        saveSessions()
    }

    func renameSession(_ id: UUID, title: String) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[index].title = title
        sessions[index].updatedAt = Date()
        saveSessions()
    }

    // MARK: - Language Picker

    func applyLanguageChoice(_ language: String) {
        settings.preferredCodingLanguage = language
        showLanguagePicker = false
        saveSettings()
    }

    func dismissLanguagePicker() {
        showLanguagePicker = false
    }

    // MARK: - Send Message

    func sendMessage(_ text: String, attachments: [Message.Attachment] = []) {
        guard let sessionIndex = sessions.firstIndex(where: { $0.id == activeSessionId }) else {
            setError("No active session. Please create one first.")
            return
        }

        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty || !attachments.isEmpty else { return }

        let userMessage = Message(
            role: .user,
            content: trimmedText,
            attachments: attachments
        )
        sessions[sessionIndex].messages.append(userMessage)
        sessions[sessionIndex].updatedAt = Date()
        pendingScreenshots.removeAll()

        let sessionId = sessions[sessionIndex].id
        let provider = settings.selectedProvider
        let hasScreenshots = userMessage.attachments.contains { $0.type == .screenshot }
        let model: String = hasScreenshots
            ? effectiveModel(for: .screenshot)
            : sessions[sessionIndex].model
        let projectId = sessions[sessionIndex].projectId
        let isFirstExchange = sessions[sessionIndex].messages.filter({ $0.role == .user }).count == 1

        // Fast-serve path: any message in a System Design Help chat that
        // matches a pre-built answer gets served instantly.
        if sessions[sessionIndex].templateName == "System Design Help",
           let match = SystemDesignStore.shared.prebuiltDesign(for: trimmedText) {
            let body = "> 📚 *From SoloScreen's pre-built system design library — fast-served, no LLM round trip.*\n\n\(match.markdown)"
            let answer = Message(role: .assistant, content: body)
            skipNextAutoScroll = true
            sessions[sessionIndex].messages.append(answer)
            sessions[sessionIndex].updatedAt = Date()
            if isFirstExchange {
                sessions[sessionIndex].autoTitle()
            }
            saveSessions()
            return
        }

        cancelStreaming()

        var llmMessages = buildLLMMessages(from: sessions[sessionIndex].messages)

        let assistantPlaceholder = Message(role: .assistant, content: "")
        sessions[sessionIndex].messages.append(assistantPlaceholder)
        let assistantIndex = sessions[sessionIndex].messages.count - 1

        isStreaming = true

        streamingTask = Task { @MainActor [weak self] in
            guard let self else { return }

            do {
                if let projectId {
                    let contextText = await self.fetchProjectContext(query: trimmedText, projectId: projectId)
                    if !contextText.isEmpty {
                        let contextMessage = LLMMessage.text(
                            role: .system,
                            content: "Relevant project context:\n\n\(contextText)"
                        )
                        llmMessages.insert(contextMessage, at: 0)
                    }
                }

                guard let si = self.sessions.firstIndex(where: { $0.id == sessionId }) else { return }
                let sessionSystemPrompt = self.sessions[si].systemPrompt
                let defaultPrompt = "You are SoloScreen, a helpful and concise AI assistant. Respond clearly and directly."
                let options = LLMRequestOptions(
                    systemPrompt: sessionSystemPrompt ?? defaultPrompt
                )

                let useFreeTier = await self.shouldUseFreeTier(provider: provider)
                let stream: AsyncThrowingStream<LLMStreamDelta, Error>

                if useFreeTier {
                    stream = await FreeTierService.shared.stream(
                        messages: llmMessages,
                        model: model,
                        options: options
                    )
                } else {
                    let apiKey = try await self.resolveAPIKey(provider: provider)

                    guard let llmProvider = self.llmRouter.provider(for: provider) else {
                        self.setError("Provider '\(provider)' is not available.")
                        self.isStreaming = false
                        return
                    }

                    stream = llmProvider.stream(
                        messages: llmMessages,
                        model: model,
                        apiKey: apiKey,
                        options: options
                    )
                }

                for try await delta in stream {
                    try Task.checkCancellation()
                    if let content = delta.content {
                        guard let si = self.sessions.firstIndex(where: { $0.id == sessionId }) else { break }
                        self.sessions[si].messages[assistantIndex].content += content
                        self.sessions[si].updatedAt = Date()
                    }
                }

                if isFirstExchange {
                    guard let si = self.sessions.firstIndex(where: { $0.id == sessionId }) else { return }
                    self.sessions[si].autoTitle()
                }

                self.saveSessions()

            } catch is CancellationError {
                // Cancelled by user.
            } catch LLMError.cancelled {
                // LLM-level cancellation.
            } catch {
                self.setError(error.localizedDescription)
            }

            self.isStreaming = false
            self.streamingTask = nil
        }
    }

    func cancelStreaming() {
        streamingTask?.cancel()
        streamingTask = nil
        isStreaming = false
    }

    // MARK: - Free Tier

    private func shouldUseFreeTier(provider: String) async -> Bool {
        let key = await KeychainService.shared.loadKey(forProvider: provider)
        return key == nil || key?.isEmpty == true
    }

    // MARK: - Message Building

    private func buildLLMMessages(from messages: [Message]) -> [LLMMessage] {
        messages.compactMap { message in
            let role: LLMMessage.Role
            switch message.role {
            case .system:    role = .system
            case .user:      role = .user
            case .assistant: role = .assistant
            }

            let imageAttachments = message.attachments.filter { $0.type == .screenshot }

            if !imageAttachments.isEmpty && role == .user {
                let images = imageAttachments.map { ($0.data, $0.mimeType) }
                return LLMMessage.userWithImages(text: message.content, images: images)
            } else {
                return LLMMessage.text(role: role, content: message.content)
            }
        }
    }

    // MARK: - API Key Resolution

    private func resolveAPIKey(provider: String) async throws -> String {
        let key = await KeychainService.shared.loadKey(forProvider: provider)
        if let key, !key.isEmpty { return key }
        if settings.hasFreeTierRemaining { return "free-tier-placeholder" }
        throw LLMError.noAPIKey
    }

    // MARK: - Project Context (RAG)

    private func fetchProjectContext(query: String, projectId: UUID) async -> String {
        let results = await VectorStoreService.shared.search(
            query: query,
            projectId: projectId,
            topK: 3
        )
        if results.isEmpty { return "" }
        return results.map { $0.text }.joined(separator: "\n\n---\n\n")
    }

    // MARK: - Microphone Recording

    /// Toggle microphone recording (walkie-talkie style).
    /// Press once to start recording (mic turns red). Press again to stop.
    /// Transcription runs silently in the background — the mic goes back
    /// to idle immediately and the transcribed text appears in the input
    /// box when ready.
    func toggleMicRecording() {
        if isRecordingMic {
            isRecordingMic = false
            do {
                let audioData = try audioService.stopMicRecording()

                guard audioData.count > 1600 else { return }

                Task { @MainActor in
                    do {
                        guard let provider = effectiveTranscriptionProvider else {
                            setError("No transcription provider configured. Add a Deepgram or OpenAI key in Settings.", settingsTab: "Transcription")
                            return
                        }
                        let apiKey: String
                        switch provider {
                        case "openai", "whisper":
                            apiKey = await KeychainService.shared.loadOpenAIKey() ?? ""
                        default:
                            apiKey = await KeychainService.shared.loadDeepgramKey() ?? ""
                        }
                        let transcript = try await TranscriptionService.shared.transcribeAudio(
                            audioData,
                            provider: provider,
                            apiKey: apiKey
                        )

                        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            NotificationCenter.default.post(
                                name: .soloScreenInsertDictation,
                                object: nil,
                                userInfo: ["text": trimmed]
                            )
                        }
                    } catch {
                        setError("Transcription failed: \(error.localizedDescription)")
                    }
                }
            } catch {
                setError("Failed to stop recording: \(error.localizedDescription)")
            }
        } else {
            do {
                try audioService.startMicRecording()
                isRecordingMic = true
            } catch {
                setError("Microphone recording failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Live Transcription (Speaker Audio) / Live Listen

    func toggleTranscription() {
        if isLiveListening {
            stopLiveListening()
        } else {
            startLiveListening()
        }
    }

    private func startLiveListening() {
        Task { @MainActor in
            await refreshKeyStatuses()
            guard hasDeepgramKey else {
                setError("Live transcription requires a Deepgram API key. Add one in Settings.", settingsTab: "Transcription")
                return
            }
            doStartLiveListening()
        }
    }

    private func doStartLiveListening() {
        Task { @MainActor in
            do {
                let deepgramKey = await KeychainService.shared.loadDeepgramKey() ?? ""

                try await TranscriptionService.shared.startLiveTranscription(
                    apiKey: deepgramKey
                ) { [weak self] result in
                    Task { @MainActor in
                        guard let self else { return }
                        if result.isFinal {
                            self.liveTranscript += result.text + " "
                        }
                    }
                }

                try await audioService.startSystemAudioCapture { [weak self] data in
                    guard let self else { return }
                    // Send audio to Deepgram
                    Task {
                        try? await TranscriptionService.shared.sendAudioData(data)
                    }
                    // Update audio levels for the bar graph
                    let rms = data.withUnsafeBytes { raw -> Float in
                        guard let ptr = raw.bindMemory(to: Int16.self).baseAddress else { return 0 }
                        let count = data.count / 2
                        guard count > 0 else { return 0 }
                        var sum: Float = 0
                        for i in stride(from: 0, to: count, by: max(1, count / 32)) {
                            let s = Float(ptr[i]); sum += s * s
                        }
                        return sqrt(sum / Float(min(count, 32)))
                    }
                    let normalized = min(CGFloat(rms / 8000.0), 1.0)
                    Task { @MainActor in
                        let now = Date()
                        guard now.timeIntervalSince(self.lastAudioLevelEmitAt) > 0.05 else { return }
                        self.lastAudioLevelEmitAt = now
                        self.liveAudioLevels.removeFirst()
                        self.liveAudioLevels.append(normalized)
                    }
                }

                isLiveListening = true

            } catch {
                setError("Live listen failed: \(error.localizedDescription)")
            }
        }
    }

    private func stopLiveListening() {
        isLiveListening = false
        liveAudioLevels = Array(repeating: 0, count: 14)
        Task {
            await audioService.stopSystemAudioCapture()
            await TranscriptionService.shared.stopLiveTranscription()
        }
    }

    // MARK: - Live Help (AI Help button)

    func requestLiveHelp() {
        guard isLiveListening else {
            setError("Start Live Listening first.")
            return
        }
        let transcript = liveTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !transcript.isEmpty else {
            setError("No transcript yet — keep listening.")
            return
        }

        let recentChat = recentChatContextForLiveHelp()
        let userContent = "(analyze latest question from transcript)\n\nTranscript:\n\(transcript)\(recentChat.isEmpty ? "" : "\n\nRecent chat context:\n\(recentChat)")"

        liveHelpMessages = [
            LiveHelpMessage(role: .user, content: userContent)
        ]
        liveHelpAnswer = ""
        isLiveHelpStreaming = true
        showLiveHelpModal = true

        streamLiveHelpResponse()
    }

    func sendLiveHelpFollowup(_ text: String) {
        liveHelpMessages.append(LiveHelpMessage(role: .user, content: text))
        liveHelpMessages.append(LiveHelpMessage(role: .assistant, content: ""))
        isLiveHelpStreaming = true
        streamLiveHelpResponse()
    }

    private func streamLiveHelpResponse() {
        let model = effectiveModel(for: .liveHelp)
        let provider = settings.selectedProvider

        Task { @MainActor in
            do {
                let apiKey = try await resolveAPIKey(provider: provider)
                guard let llmProvider = llmRouter.provider(for: provider) else { return }

                var llmMessages: [LLMMessage] = []
                for msg in liveHelpMessages {
                    let role: LLMMessage.Role = msg.role == .user ? .user : .assistant
                    llmMessages.append(LLMMessage.text(role: role, content: msg.content))
                }

                let options = LLMRequestOptions(
                    systemPrompt: "You are SoloScreen's AI Help assistant. The user is in a live session and needs quick, accurate answers. Be concise and direct."
                )

                let stream = llmProvider.stream(
                    messages: llmMessages,
                    model: model,
                    apiKey: apiKey,
                    options: options
                )

                // Find or create the assistant message to stream into
                let assistantIdx: Int
                if let lastIdx = liveHelpMessages.indices.last,
                   liveHelpMessages[lastIdx].role == .assistant {
                    assistantIdx = lastIdx
                } else {
                    liveHelpMessages.append(LiveHelpMessage(role: .assistant, content: ""))
                    assistantIdx = liveHelpMessages.count - 1
                }

                for try await delta in stream {
                    if let content = delta.content {
                        liveHelpMessages[assistantIdx].content += content
                    }
                }
            } catch {
                setError("Live Help failed: \(error.localizedDescription)")
            }
            isLiveHelpStreaming = false
        }
    }

    func recentChatContextForLiveHelp() -> String {
        guard let session = activeSession else { return "" }
        let recent = session.messages.suffix(4)
        let lines = recent.map { msg -> String in
            let role = msg.role == .user ? "User" : "Assistant"
            return "\(role): \(msg.content)"
        }.joined(separator: "\n")
        return String(lines.suffix(2000))
    }

    func closeLiveHelpModal() {
        showLiveHelpModal = false
        liveHelpMessages.removeAll()
        liveHelpAnswer = ""
    }

    /// Toggle the expanded-diagram sheet. Fired by the `⌃⇧D` global shortcut.
    func toggleExpandedDiagram() {
        if showExpandedDiagram {
            showExpandedDiagram = false
            return
        }
        guard lastDiagramImage != nil, lastDiagramSource != nil else {
            setError("No diagram on screen to expand.")
            return
        }
        showExpandedDiagram = true
    }

    // MARK: - Screenshots

    func captureScreenshot() {
        Task { @MainActor in
            do {
                let imageData = try await ScreenCaptureService.shared.captureScreen()
                if pendingScreenshots.count >= 5 {
                    pendingScreenshots.removeFirst()
                }
                pendingScreenshots.append(imageData)
            } catch {
                setError("Screenshot failed: \(error.localizedDescription)")
            }
        }
    }

    func removeScreenshot(at index: Int) {
        guard pendingScreenshots.indices.contains(index) else { return }
        pendingScreenshots.remove(at: index)
    }

    // MARK: - Project Management

    func createProject(name: String) {
        let project = Project(name: name)
        projects.append(project)
        saveProjects()
    }

    func deleteProject(_ id: UUID) {
        projects.removeAll { $0.id == id }
        for i in sessions.indices where sessions[i].projectId == id {
            sessions[i].projectId = nil
        }
        saveProjects()
        saveSessions()
    }

    func linkProject(_ projectId: UUID, to sessionId: UUID) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionId }) else { return }
        sessions[index].projectId = projectId
        sessions[index].updatedAt = Date()
        saveSessions()
    }

    func addFileToProject(_ url: URL, projectId: UUID) {
        guard let projectIndex = projects.firstIndex(where: { $0.id == projectId }) else {
            setError("Project not found.")
            return
        }

        guard projects[projectIndex].canAddFile else {
            setError("Project has reached the maximum of \(Project.maxFiles) files.")
            return
        }

        Task { @MainActor in
            do {
                let fileData = try Data(contentsOf: url)
                let fileName = url.lastPathComponent
                let fileExtension = url.pathExtension.lowercased()

                guard ProjectFile.isSupportedExtension(fileExtension) else {
                    setError("Unsupported file type: .\(fileExtension)")
                    return
                }

                let fileSizeBytes = fileData.count
                guard fileSizeBytes <= Project.maxFileSizeMB * 1_024 * 1_024 else {
                    setError("File exceeds the \(Project.maxFileSizeMB)MB size limit.")
                    return
                }

                let textContent = try FileProcessorService.extractText(from: url)

                let projectFile = ProjectFile(
                    fileName: fileName,
                    mimeType: mimeType(for: fileExtension),
                    textContent: textContent,
                    sizeBytes: fileSizeBytes
                )

                let chunks = FileProcessorService.chunkText(textContent, chunkSize: 500, overlap: 50)
                try await VectorStoreService.shared.index(
                    chunks: chunks,
                    fileId: projectFile.id,
                    projectId: projectId
                )

                guard let pi = projects.firstIndex(where: { $0.id == projectId }) else { return }
                projects[pi].files.append(projectFile)
                projects[pi].updatedAt = Date()
                saveProjects()

            } catch {
                setError("Failed to add file: \(error.localizedDescription)")
            }
        }
    }

    private func mimeType(for ext: String) -> String {
        switch ext {
        case "txt":  return "text/plain"
        case "md":   return "text/markdown"
        case "rtf":  return "text/rtf"
        case "pdf":  return "application/pdf"
        case "doc":  return "application/msword"
        case "docx": return "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        default:     return "application/octet-stream"
        }
    }

    // MARK: - Persistence

    func saveAllState() {
        saveSessions()
        saveProjects()
        saveSettings()
    }

    func saveSessions() {
        Task.detached {
            do {
                let snapshot = await self.sessions
                try await PersistenceService.shared.saveSessions(snapshot)
            } catch {
                await self.setError("Failed to save sessions: \(error.localizedDescription)")
            }
        }
    }

    private func saveProjects() {
        Task.detached {
            do {
                let snapshot = await self.projects
                try await PersistenceService.shared.saveProjects(snapshot)
            } catch {
                await self.setError("Failed to save projects: \(error.localizedDescription)")
            }
        }
    }

    func saveSettings() {
        Task.detached {
            do {
                let snapshot = await self.settings
                try await PersistenceService.shared.saveSettings(snapshot)
            } catch {
                await self.setError("Failed to save settings: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Error Handling

    func setError(_ message: String, settingsTab: String? = nil, systemSettingsURL: String? = nil) {
        withAnimation(.easeIn(duration: 0.2)) {
            errorMessage = message
            errorSettingsTab = settingsTab
            errorSystemSettingsURL = systemSettingsURL
            errorLinkLabel = settingsTab != nil ? "Open Settings" : (systemSettingsURL != nil ? "Open System Settings" : nil)
        }
        // Auto-dismiss only if no link (informational errors).
        if settingsTab == nil && systemSettingsURL == nil {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                if errorMessage == message {
                    withAnimation(.easeOut(duration: 0.3)) {
                        errorMessage = nil
                        errorSettingsTab = nil
                        errorSystemSettingsURL = nil
                        errorLinkLabel = nil
                    }
                }
            }
        }
    }

    func openSettingsFromError() {
        if let tab = errorSettingsTab {
            settingsInitialTab = tab
            showSettings = true
        } else if let url = errorSystemSettingsURL, let nsURL = URL(string: url) {
            NSWorkspace.shared.open(nsURL)
        }
        withAnimation(.easeOut(duration: 0.25)) {
            errorMessage = nil
            errorSettingsTab = nil
            errorSystemSettingsURL = nil
            errorLinkLabel = nil
        }
    }
}

import Foundation
import SwiftUI

/// Central state manager for the entire SubtleAI application.
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
    @Published var showSettings: Bool = false
    @Published var showProjects: Bool = false
    @Published var showOnboarding: Bool = false

    // MARK: - Audio / Transcription

    @Published var isRecordingMic: Bool = false
    @Published var isTranscribing: Bool = false
    @Published var transcriptText: String = ""

    // MARK: - Screenshots

    @Published var pendingScreenshots: [Data] = []

    // MARK: - Error Handling

    @Published var errorMessage: String?

    // MARK: - Streaming Task

    var streamingTask: Task<Void, Never>?

    // MARK: - Dependencies

    private let llmRouter = LLMRouter()
    private let audioService = AudioService()

    // MARK: - Computed Properties

    /// The currently active chat session, if any.
    var activeSession: Session? {
        guard let id = activeSessionId else { return nil }
        return sessions.first { $0.id == id }
    }

    // MARK: - Initialization

    init() {
        Task { @MainActor in
            await loadPersistedState()
            if !settings.onboardingCompleted {
                showOnboarding = true
            }
        }
    }

    /// Load sessions, projects, and settings from PersistenceService.
    private func loadPersistedState() async {
        let persistence = PersistenceService.shared
        let loadedSessions = await persistence.loadSessions()
        let loadedProjects = await persistence.loadProjects()
        let loadedSettings = await persistence.loadSettings()

        self.sessions = loadedSessions
        self.projects = loadedProjects
        self.settings = loadedSettings

        // Restore the most recently updated session as active, if any exist.
        if !sessions.isEmpty, activeSessionId == nil {
            activeSessionId = sessions.sorted(by: { $0.updatedAt > $1.updatedAt }).first?.id
        }
    }

    // MARK: - Session Management

    /// Create a new chat session using the current model selection.
    func createSession() {
        let session = Session(
            model: settings.selectedModel
        )
        sessions.insert(session, at: 0)
        activeSessionId = session.id
        saveSessions()
    }

    /// Delete a session by its ID.
    func deleteSession(_ id: UUID) {
        sessions.removeAll { $0.id == id }
        if activeSessionId == id {
            activeSessionId = sessions.sorted(by: { $0.updatedAt > $1.updatedAt }).first?.id
        }
        saveSessions()
    }

    /// Rename a session by its ID.
    func renameSession(_ id: UUID, title: String) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[index].title = title
        sessions[index].updatedAt = Date()
        saveSessions()
    }

    // MARK: - Send Message

    /// The core method: send a user message and stream the LLM response.
    ///
    /// 1. Appends the user message to the active session.
    /// 2. Builds LLM messages from session history.
    /// 3. If a project is linked, queries VectorStoreService for relevant context.
    /// 4. Resolves the API key (or uses free tier).
    /// 5. Streams the response, appending deltas to an assistant message.
    /// 6. Auto-titles the session after the first exchange.
    func sendMessage(_ text: String, attachments: [Message.Attachment] = []) {
        guard let sessionIndex = sessions.firstIndex(where: { $0.id == activeSessionId }) else {
            setError("No active session. Please create one first.")
            return
        }

        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty || !attachments.isEmpty else { return }

        // Append user message.
        let userMessage = Message(
            role: .user,
            content: trimmedText,
            attachments: attachments
        )
        sessions[sessionIndex].messages.append(userMessage)
        sessions[sessionIndex].updatedAt = Date()

        // Include any pending screenshots as attachments on the user message.
        for screenshotData in pendingScreenshots {
            let attachment = Message.Attachment(
                type: .screenshot,
                data: screenshotData,
                mimeType: "image/png"
            )
            sessions[sessionIndex].messages[sessions[sessionIndex].messages.count - 1].attachments.append(attachment)
        }
        pendingScreenshots.removeAll()

        // Capture values for the async task.
        let sessionId = sessions[sessionIndex].id
        let provider = settings.selectedProvider
        let model = sessions[sessionIndex].model
        let projectId = sessions[sessionIndex].projectId
        let isFirstExchange = sessions[sessionIndex].messages.filter({ $0.role == .user }).count == 1

        // Cancel any existing stream.
        cancelStreaming()

        isStreaming = true

        streamingTask = Task { @MainActor [weak self] in
            guard let self else { return }

            do {
                // Build LLM messages from session history.
                guard let currentIndex = self.sessions.firstIndex(where: { $0.id == sessionId }) else { return }
                var llmMessages = self.buildLLMMessages(from: self.sessions[currentIndex].messages)

                // If a project is linked, search for relevant context and prepend as system message.
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

                // Resolve API key.
                let apiKey = try await self.resolveAPIKey(provider: provider)

                // Get the LLM provider.
                guard let llmProvider = self.llmRouter.provider(for: provider) else {
                    self.setError("Provider '\(provider)' is not available.")
                    self.isStreaming = false
                    return
                }

                // Create assistant message placeholder.
                let assistantMessage = Message(role: .assistant, content: "")
                guard let si = self.sessions.firstIndex(where: { $0.id == sessionId }) else { return }
                self.sessions[si].messages.append(assistantMessage)
                let assistantIndex = self.sessions[si].messages.count - 1

                // Stream the response.
                let options = LLMRequestOptions(
                    systemPrompt: "You are SubtleAI, a helpful and concise AI assistant. Respond clearly and directly."
                )
                let stream = llmProvider.stream(
                    messages: llmMessages,
                    model: model,
                    apiKey: apiKey,
                    options: options
                )

                for try await delta in stream {
                    try Task.checkCancellation()
                    if let content = delta.content {
                        guard let si = self.sessions.firstIndex(where: { $0.id == sessionId }) else { break }
                        self.sessions[si].messages[assistantIndex].content += content
                        self.sessions[si].updatedAt = Date()
                    }
                }

                // Auto-title after first exchange.
                if isFirstExchange {
                    guard let si = self.sessions.firstIndex(where: { $0.id == sessionId }) else { return }
                    self.sessions[si].autoTitle()
                }

                // Increment free tier usage if applicable.
                let currentKey = await KeychainService.shared.loadKey(forProvider: provider)
                if currentKey == nil || currentKey?.isEmpty == true {
                    self.settings.freeMessagesUsed += 1
                    self.saveSettings()
                }

                self.saveSessions()

            } catch is CancellationError {
                // Streaming was cancelled by the user.
            } catch LLMError.cancelled {
                // LLM-level cancellation — not an error.
            } catch {
                self.setError(error.localizedDescription)
            }

            self.isStreaming = false
            self.streamingTask = nil
        }
    }

    /// Cancel the current streaming task.
    func cancelStreaming() {
        streamingTask?.cancel()
        streamingTask = nil
        isStreaming = false
    }

    // MARK: - Message Building

    /// Convert the session's Message history into LLMMessage format for the API.
    private func buildLLMMessages(from messages: [Message]) -> [LLMMessage] {
        messages.compactMap { message in
            let role: LLMMessage.Role
            switch message.role {
            case .system:    role = .system
            case .user:      role = .user
            case .assistant: role = .assistant
            }

            // Check for image attachments on user messages.
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

    /// Resolve the API key for the given provider. Falls back to free tier if eligible.
    private func resolveAPIKey(provider: String) async throws -> String {
        let key = await KeychainService.shared.loadKey(forProvider: provider)

        if let key, !key.isEmpty {
            return key
        }

        // Free tier fallback.
        if settings.hasFreeTierRemaining {
            // In production, this would route through a backend proxy.
            // For now, return a placeholder that the backend would supply.
            return "free-tier-placeholder"
        }

        throw LLMError.noAPIKey
    }

    // MARK: - Project Context (RAG)

    /// Query VectorStoreService for relevant project context.
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

    /// Toggle microphone recording. When stopped, transcribe the audio and set transcriptText.
    func toggleMicRecording() {
        if isRecordingMic {
            // Stop recording and transcribe.
            isRecordingMic = false
            do {
                let audioData = try audioService.stopMicRecording()
                isTranscribing = true

                Task { @MainActor in
                    do {
                        let deepgramKey = await KeychainService.shared.loadDeepgramKey()
                        let transcript = try await TranscriptionService.shared.transcribeAudio(
                            audioData,
                            provider: settings.transcriptionProvider,
                            apiKey: deepgramKey ?? ""
                        )
                        transcriptText = transcript
                        isTranscribing = false
                    } catch {
                        isTranscribing = false
                        setError("Transcription failed: \(error.localizedDescription)")
                    }
                }
            } catch {
                setError("Failed to stop recording: \(error.localizedDescription)")
            }
        } else {
            // Start recording.
            do {
                try audioService.startMicRecording()
                isRecordingMic = true
            } catch {
                setError("Microphone recording failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Live Transcription (Speaker Audio)

    /// Toggle live transcription of system/speaker audio.
    func toggleTranscription() {
        if isTranscribing {
            isTranscribing = false
            Task {
                await TranscriptionService.shared.stopLiveTranscription()
            }
        } else {
            isTranscribing = true
            Task { @MainActor in
                do {
                    let deepgramKey = await KeychainService.shared.loadDeepgramKey()
                    try await TranscriptionService.shared.startLiveTranscription(
                        apiKey: deepgramKey ?? ""
                    ) { [weak self] result in
                        Task { @MainActor in
                            self?.transcriptText += result.text
                        }
                    }
                } catch {
                    isTranscribing = false
                    setError("Live transcription failed: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Screenshots

    /// Capture a screenshot and append it to pendingScreenshots (max 5).
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

    /// Remove a pending screenshot at the given index.
    func removeScreenshot(at index: Int) {
        guard pendingScreenshots.indices.contains(index) else { return }
        pendingScreenshots.remove(at: index)
    }

    // MARK: - Project Management

    /// Create a new project with the given name.
    func createProject(name: String) {
        let project = Project(name: name)
        projects.append(project)
        saveProjects()
    }

    /// Delete a project by its ID. Also unlinks it from any sessions.
    func deleteProject(_ id: UUID) {
        projects.removeAll { $0.id == id }

        // Unlink from any sessions that reference this project.
        for i in sessions.indices where sessions[i].projectId == id {
            sessions[i].projectId = nil
        }

        saveProjects()
        saveSessions()
    }

    /// Link a project to a session.
    func linkProject(_ projectId: UUID, to sessionId: UUID) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionId }) else { return }
        sessions[index].projectId = projectId
        sessions[index].updatedAt = Date()
        saveSessions()
    }

    /// Add a file to a project: extract text, chunk it, index in VectorStore.
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
                // Read file data.
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

                // Extract text content.
                let textContent = try FileProcessorService.extractText(from: url)

                // Create the project file record.
                let projectFile = ProjectFile(
                    fileName: fileName,
                    mimeType: mimeType(for: fileExtension),
                    textContent: textContent,
                    sizeBytes: fileSizeBytes
                )

                // Chunk the text and index in the vector store.
                let chunks = FileProcessorService.chunkText(textContent, chunkSize: 500, overlap: 50)
                try await VectorStoreService.shared.index(
                    chunks: chunks,
                    fileId: projectFile.id,
                    projectId: projectId
                )

                // Add file to the project.
                guard let pi = projects.firstIndex(where: { $0.id == projectId }) else { return }
                projects[pi].files.append(projectFile)
                projects[pi].updatedAt = Date()
                saveProjects()

            } catch {
                setError("Failed to add file: \(error.localizedDescription)")
            }
        }
    }

    /// Map file extension to MIME type.
    private func mimeType(for ext: String) -> String {
        switch ext {
        case "txt":           return "text/plain"
        case "md":            return "text/markdown"
        case "rtf":           return "text/rtf"
        case "pdf":           return "application/pdf"
        case "doc":           return "application/msword"
        case "docx":          return "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        default:              return "application/octet-stream"
        }
    }

    // MARK: - Persistence

    /// Persist all state to disk.
    func saveAllState() {
        saveSessions()
        saveProjects()
        saveSettings()
    }

    private func saveSessions() {
        Task.detached {
            do {
                let sessionsSnapshot = await self.sessions
                try await PersistenceService.shared.saveSessions(sessionsSnapshot)
            } catch {
                await self.setError("Failed to save sessions: \(error.localizedDescription)")
            }
        }
    }

    private func saveProjects() {
        Task.detached {
            do {
                let projectsSnapshot = await self.projects
                try await PersistenceService.shared.saveProjects(projectsSnapshot)
            } catch {
                await self.setError("Failed to save projects: \(error.localizedDescription)")
            }
        }
    }

    private func saveSettings() {
        Task.detached {
            do {
                let settingsSnapshot = await self.settings
                try await PersistenceService.shared.saveSettings(settingsSnapshot)
            } catch {
                await self.setError("Failed to save settings: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Error Handling

    /// Set an error message and auto-clear it after 5 seconds.
    func setError(_ message: String) {
        withAnimation(.easeIn(duration: 0.2)) {
            errorMessage = message
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            if errorMessage == message {
                withAnimation(.easeOut(duration: 0.3)) {
                    errorMessage = nil
                }
            }
        }
    }
}

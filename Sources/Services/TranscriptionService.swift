import Foundation

/// Provides speech-to-text transcription via Deepgram's API.
///
/// Supports two modes:
/// - **Batch**: Send a complete audio buffer and receive the full transcript.
/// - **Live streaming**: Open a persistent WebSocket connection to Deepgram
///   for real-time transcription with automatic reconnection.
actor TranscriptionService {

    // MARK: - Types

    /// Supported transcription providers.
    enum Provider: String, Sendable {
        case deepgram
        case whisperLocal  // Reserved for future local Whisper integration.
    }

    struct TranscriptionResult: Sendable {
        let text: String
        let isFinal: Bool
        let confidence: Float
    }

    // MARK: - Errors

    enum TranscriptionError: LocalizedError {
        case noAPIKey
        case unsupportedProvider(String)
        case networkError(underlying: Error)
        case invalidResponse
        case webSocketNotConnected
        case emptyAudioData

        var errorDescription: String? {
            switch self {
            case .noAPIKey:
                return "No API key provided for the transcription service."
            case .unsupportedProvider(let name):
                return "Transcription provider '\(name)' is not supported."
            case .networkError(let err):
                return "Transcription network error: \(err.localizedDescription)"
            case .invalidResponse:
                return "Received an invalid response from the transcription service."
            case .webSocketNotConnected:
                return "WebSocket is not connected to the transcription service."
            case .emptyAudioData:
                return "No audio data provided for transcription."
            }
        }
    }

    // MARK: - Singleton

    static let shared = TranscriptionService()

    // MARK: - State

    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var isLiveActive: Bool = false
    private var onTranscriptCallback: ((TranscriptionResult) -> Void)?
    private var reconnectAttempts: Int = 0
    private var liveAPIKey: String?

    private static let maxReconnectAttempts = 5
    private static let baseReconnectDelay: TimeInterval = 1.0
    private static let deepgramRESTEndpoint = "https://api.deepgram.com/v1/listen"
    private static let deepgramWSEndpoint = "wss://api.deepgram.com/v1/listen"

    // MARK: - Batch Transcription

    /// Transcribe a complete audio buffer using the specified provider.
    ///
    /// - Parameters:
    ///   - audioData: Raw audio data (16 kHz mono 16-bit PCM).
    ///   - provider: The transcription provider to use ("deepgram").
    ///   - apiKey: The API key for the provider.
    /// - Returns: The transcribed text.
    func transcribeAudio(_ audioData: Data, provider: String, apiKey: String) async throws -> String {
        guard !audioData.isEmpty else {
            throw TranscriptionError.emptyAudioData
        }
        guard !apiKey.isEmpty else {
            throw TranscriptionError.noAPIKey
        }

        switch provider.lowercased() {
        case "deepgram":
            return try await transcribeWithDeepgram(audioData, apiKey: apiKey)
        case "whisper", "whisper_local":
            throw TranscriptionError.unsupportedProvider("whisper_local (not yet implemented)")
        default:
            throw TranscriptionError.unsupportedProvider(provider)
        }
    }

    /// Send audio to Deepgram's REST API for batch transcription.
    private func transcribeWithDeepgram(_ audioData: Data, apiKey: String) async throws -> String {
        var urlComponents = URLComponents(string: Self.deepgramRESTEndpoint)
        urlComponents?.queryItems = [
            URLQueryItem(name: "model", value: "nova-2"),
            URLQueryItem(name: "language", value: "en"),
            URLQueryItem(name: "punctuate", value: "true"),
            URLQueryItem(name: "smart_format", value: "true")
        ]

        guard let url = urlComponents?.url else {
            throw TranscriptionError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Token \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("audio/l16;rate=16000;channels=1", forHTTPHeaderField: "Content-Type")
        request.httpBody = audioData

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw TranscriptionError.networkError(underlying: error)
        }

        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw TranscriptionError.invalidResponse
        }

        return parseDeepgramRESTResponse(data)
    }

    /// Parse the Deepgram REST API JSON response to extract transcript text.
    private func parseDeepgramRESTResponse(_ data: Data) -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [String: Any],
              let channels = results["channels"] as? [[String: Any]],
              let firstChannel = channels.first,
              let alternatives = firstChannel["alternatives"] as? [[String: Any]],
              let firstAlt = alternatives.first,
              let transcript = firstAlt["transcript"] as? String
        else {
            return ""
        }
        return transcript
    }

    // MARK: - Live Streaming Transcription

    /// Start a live WebSocket connection to Deepgram for real-time transcription.
    ///
    /// Audio buffers should be sent via `sendAudioData(_:)` after calling this method.
    /// Transcription results are delivered through the `onTranscript` callback.
    ///
    /// - Parameters:
    ///   - apiKey: The Deepgram API key.
    ///   - onTranscript: Callback invoked on each transcription result.
    func startLiveTranscription(apiKey: String, onTranscript: @escaping (TranscriptionResult) -> Void) async throws {
        guard !apiKey.isEmpty else {
            throw TranscriptionError.noAPIKey
        }

        // Clean up any existing connection.
        await stopLiveTranscription()

        liveAPIKey = apiKey
        onTranscriptCallback = onTranscript
        reconnectAttempts = 0

        try await connectWebSocket(apiKey: apiKey)
    }

    /// Stop the live transcription session and close the WebSocket.
    func stopLiveTranscription() async {
        isLiveActive = false

        // Send a close message to Deepgram to finalize any pending transcription.
        if let ws = webSocketTask {
            let closeMessage = "{\"type\": \"CloseStream\"}"
            try? await ws.send(.string(closeMessage))
            ws.cancel(with: .normalClosure, reason: nil)
        }

        webSocketTask = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil
        onTranscriptCallback = nil
        liveAPIKey = nil
        reconnectAttempts = 0
    }

    /// Send raw audio data to the live transcription WebSocket.
    ///
    /// - Parameter data: Raw 16 kHz mono 16-bit PCM audio data.
    func sendAudioData(_ data: Data) async throws {
        guard let ws = webSocketTask, isLiveActive else {
            throw TranscriptionError.webSocketNotConnected
        }
        try await ws.send(.data(data))
    }

    // MARK: - WebSocket Connection

    /// Establish the WebSocket connection to Deepgram.
    private func connectWebSocket(apiKey: String) async throws {
        var urlComponents = URLComponents(string: Self.deepgramWSEndpoint)
        urlComponents?.queryItems = [
            URLQueryItem(name: "model", value: "nova-2"),
            URLQueryItem(name: "language", value: "en"),
            URLQueryItem(name: "punctuate", value: "true"),
            URLQueryItem(name: "smart_format", value: "true"),
            URLQueryItem(name: "interim_results", value: "true"),
            URLQueryItem(name: "encoding", value: "linear16"),
            URLQueryItem(name: "sample_rate", value: "16000"),
            URLQueryItem(name: "channels", value: "1")
        ]

        guard let url = urlComponents?.url else {
            throw TranscriptionError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.setValue("Token \(apiKey)", forHTTPHeaderField: "Authorization")

        let session = URLSession(configuration: .default)
        let ws = session.webSocketTask(with: request)
        ws.resume()

        self.urlSession = session
        self.webSocketTask = ws
        self.isLiveActive = true

        // Start receiving messages in a background task.
        startReceivingMessages()
    }

    /// Continuously receive and process WebSocket messages.
    private func startReceivingMessages() {
        guard let ws = webSocketTask, isLiveActive else { return }

        Task { [weak self] in
            do {
                let message = try await ws.receive()
                await self?.handleWebSocketMessage(message)
                await self?.startReceivingMessages()
            } catch {
                await self?.handleWebSocketError(error)
            }
        }
    }

    /// Process a received WebSocket message from Deepgram.
    private func handleWebSocketMessage(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .string(let text):
            let result = parseDeepgramStreamResponse(text)
            if let result, !result.text.isEmpty {
                onTranscriptCallback?(result)
            }

        case .data(let data):
            // Deepgram typically sends JSON as text, but handle data just in case.
            if let text = String(data: data, encoding: .utf8) {
                let result = parseDeepgramStreamResponse(text)
                if let result, !result.text.isEmpty {
                    onTranscriptCallback?(result)
                }
            }

        @unknown default:
            break
        }
    }

    /// Parse a Deepgram streaming JSON response.
    private func parseDeepgramStreamResponse(_ jsonString: String) -> TranscriptionResult? {
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }

        // Check for error messages from Deepgram.
        if let type = json["type"] as? String, type == "Error" {
            #if DEBUG
            let errorMsg = json["description"] as? String ?? "Unknown error"
            print("[TranscriptionService] Deepgram error: \(errorMsg)")
            #endif
            return nil
        }

        guard let channel = json["channel"] as? [String: Any],
              let alternatives = channel["alternatives"] as? [[String: Any]],
              let firstAlt = alternatives.first,
              let transcript = firstAlt["transcript"] as? String
        else {
            return nil
        }

        let isFinal = json["is_final"] as? Bool ?? false
        let confidence = (firstAlt["confidence"] as? Double).map { Float($0) } ?? 0.0

        return TranscriptionResult(
            text: transcript,
            isFinal: isFinal,
            confidence: confidence
        )
    }

    // MARK: - Reconnection

    /// Handle WebSocket errors with automatic reconnection.
    private func handleWebSocketError(_ error: Error) async {
        guard isLiveActive else { return }

        #if DEBUG
        print("[TranscriptionService] WebSocket error: \(error.localizedDescription)")
        #endif

        webSocketTask?.cancel(with: .abnormalClosure, reason: nil)
        webSocketTask = nil

        guard reconnectAttempts < Self.maxReconnectAttempts,
              let apiKey = liveAPIKey
        else {
            // Exhausted reconnect attempts. Notify callback with empty result to signal failure.
            isLiveActive = false
            return
        }

        reconnectAttempts += 1

        // Exponential backoff: 1s, 2s, 4s, 8s, 16s.
        let delay = Self.baseReconnectDelay * pow(2.0, Double(reconnectAttempts - 1))

        #if DEBUG
        print("[TranscriptionService] Reconnecting in \(delay)s (attempt \(reconnectAttempts)/\(Self.maxReconnectAttempts))...")
        #endif

        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

        guard isLiveActive else { return }

        do {
            try await connectWebSocket(apiKey: apiKey)
        } catch {
            await handleWebSocketError(error)
        }
    }
}

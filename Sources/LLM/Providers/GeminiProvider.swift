import Foundation

/// Google Gemini API provider implementation.
/// Supports chat completions, streaming via SSE, and vision inputs.
struct GeminiProvider: LLMProvider, Sendable {
    let providerId = "google"
    let displayName = "Google"

    private static let baseURL = "https://generativelanguage.googleapis.com/v1beta/models"

    // MARK: - Vision Support

    func supportsVision(_ model: String) -> Bool {
        // All current Gemini models support vision.
        true
    }

    // MARK: - Complete (Non-Streaming)

    func complete(
        messages: [LLMMessage],
        model: String,
        apiKey: String,
        options: LLMRequestOptions
    ) async throws -> LLMResponse {
        let request = try buildURLRequest(
            messages: messages,
            model: model,
            apiKey: apiKey,
            options: options,
            stream: false
        )

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch is CancellationError {
            throw LLMError.cancelled
        } catch let urlError as URLError where urlError.code == .cancelled {
            throw LLMError.cancelled
        } catch {
            throw LLMError.networkError(underlying: error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.networkError(underlying: URLError(.badServerResponse))
        }

        try validateHTTPResponse(httpResponse, body: data)

        do {
            let decoded = try JSONDecoder().decode(GenerateContentResponse.self, from: data)
            guard let candidate = decoded.candidates?.first,
                  let parts = candidate.content?.parts else {
                throw LLMError.invalidResponse(
                    statusCode: httpResponse.statusCode,
                    body: "No candidates in response"
                )
            }

            let text = parts.compactMap { $0.text }.joined()

            return LLMResponse(
                content: text,
                model: model,
                finishReason: candidate.finishReason,
                usage: decoded.usageMetadata.map {
                    TokenUsage(
                        promptTokens: $0.promptTokenCount ?? 0,
                        completionTokens: $0.candidatesTokenCount ?? 0
                    )
                }
            )
        } catch let error as LLMError {
            throw error
        } catch {
            throw LLMError.decodingError(underlying: error)
        }
    }

    // MARK: - Stream (SSE)

    func stream(
        messages: [LLMMessage],
        model: String,
        apiKey: String,
        options: LLMRequestOptions
    ) -> AsyncThrowingStream<LLMStreamDelta, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = try buildURLRequest(
                        messages: messages,
                        model: model,
                        apiKey: apiKey,
                        options: options,
                        stream: true
                    )

                    let (bytes, response): (URLSession.AsyncBytes, URLResponse)
                    do {
                        (bytes, response) = try await URLSession.shared.bytes(for: request)
                    } catch is CancellationError {
                        continuation.finish(throwing: LLMError.cancelled)
                        return
                    } catch let urlError as URLError where urlError.code == .cancelled {
                        continuation.finish(throwing: LLMError.cancelled)
                        return
                    } catch {
                        continuation.finish(throwing: LLMError.networkError(underlying: error))
                        return
                    }

                    guard let httpResponse = response as? HTTPURLResponse else {
                        continuation.finish(throwing: LLMError.networkError(underlying: URLError(.badServerResponse)))
                        return
                    }

                    if httpResponse.statusCode != 200 {
                        var bodyData = Data()
                        for try await byte in bytes {
                            bodyData.append(byte)
                        }
                        do {
                            try validateHTTPResponse(httpResponse, body: bodyData)
                        } catch {
                            continuation.finish(throwing: error)
                            return
                        }
                    }

                    // Gemini streaming uses SSE with data: prefixed JSON chunks.
                    for try await line in bytes.lines {
                        try Task.checkCancellation()

                        guard line.hasPrefix("data: ") else { continue }
                        let payload = String(line.dropFirst(6))
                        guard let chunkData = payload.data(using: .utf8) else { continue }

                        do {
                            let chunk = try JSONDecoder().decode(GenerateContentResponse.self, from: chunkData)
                            if let candidate = chunk.candidates?.first,
                               let parts = candidate.content?.parts {
                                let text = parts.compactMap { $0.text }.joined()
                                if !text.isEmpty {
                                    continuation.yield(LLMStreamDelta(
                                        content: text,
                                        finishReason: candidate.finishReason
                                    ))
                                }
                            }
                        } catch {
                            // Skip malformed chunks.
                            continue
                        }
                    }

                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: LLMError.cancelled)
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    // MARK: - Request Building

    private func buildURLRequest(
        messages: [LLMMessage],
        model: String,
        apiKey: String,
        options: LLMRequestOptions,
        stream: Bool
    ) throws -> URLRequest {
        guard !apiKey.isEmpty else {
            throw LLMError.noAPIKey
        }

        // Build the URL: models/{model}:generateContent or :streamGenerateContent
        let action = stream ? "streamGenerateContent" : "generateContent"
        guard let encodedKey = apiKey.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            throw LLMError.noAPIKey
        }
        var urlString = "\(Self.baseURL)/\(model):\(action)?key=\(encodedKey)"
        if stream {
            urlString += "&alt=sse"
        }
        guard let url = URL(string: urlString) else {
            throw LLMError.invalidResponse(statusCode: 0, body: "Invalid model name for URL construction")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Separate system messages from conversation.
        var systemParts: [String] = []
        var contents: [GeminiContent] = []

        if let systemPrompt = options.systemPrompt, !systemPrompt.isEmpty {
            systemParts.append(systemPrompt)
        }

        for message in messages {
            if message.role == .system {
                let text = message.content.compactMap { part -> String? in
                    if case .text(let t) = part { return t }
                    return nil
                }.joined(separator: "\n")
                systemParts.append(text)
            } else {
                contents.append(convertMessage(message))
            }
        }

        let systemInstruction: GeminiContent?
        if !systemParts.isEmpty {
            systemInstruction = GeminiContent(
                role: nil,
                parts: [GeminiPart(text: systemParts.joined(separator: "\n\n"))]
            )
        } else {
            systemInstruction = nil
        }

        let generationConfig = GenerationConfig(
            temperature: options.temperature,
            maxOutputTokens: options.maxTokens
        )

        let body = GenerateContentRequest(
            contents: contents,
            systemInstruction: systemInstruction,
            generationConfig: generationConfig
        )

        request.httpBody = try JSONEncoder().encode(body)
        return request
    }

    /// Convert an LLMMessage to the Gemini API format.
    private func convertMessage(_ message: LLMMessage) -> GeminiContent {
        let role = message.role == .assistant ? "model" : "user"

        var parts: [GeminiPart] = []

        for contentPart in message.content {
            switch contentPart {
            case .text(let text):
                parts.append(GeminiPart(text: text))
            case .image(let data, let mimeType):
                parts.append(GeminiPart(
                    inlineData: InlineData(mimeType: mimeType, data: data.base64EncodedString())
                ))
            }
        }

        return GeminiContent(role: role, parts: parts)
    }

    // MARK: - Response Validation

    private func validateHTTPResponse(_ response: HTTPURLResponse, body: Data) throws {
        let statusCode = response.statusCode
        guard statusCode != 200 else { return }

        let bodyString = String(data: body, encoding: .utf8) ?? "<unreadable body>"

        switch statusCode {
        case 400:
            if bodyString.contains("API key not valid") || bodyString.contains("API_KEY_INVALID") {
                throw LLMError.invalidResponse(
                    statusCode: statusCode,
                    body: "Invalid API key. Please check your Google API key in Settings."
                )
            }
            if bodyString.contains("exceeds the maximum") || bodyString.contains("too long")
                || bodyString.contains("token limit") {
                throw LLMError.contextLengthExceeded
            }
            throw LLMError.invalidResponse(statusCode: statusCode, body: bodyString)
        case 403:
            throw LLMError.invalidResponse(
                statusCode: statusCode,
                body: "Invalid API key. Please check your Google API key in Settings."
            )
        case 429:
            let retryAfter = response.value(forHTTPHeaderField: "Retry-After")
                .flatMap { TimeInterval($0) }
            throw LLMError.rateLimited(retryAfter: retryAfter)
        default:
            throw LLMError.invalidResponse(statusCode: statusCode, body: bodyString)
        }
    }
}

// MARK: - Gemini API Request Types

private struct GenerateContentRequest: Encodable {
    let contents: [GeminiContent]
    let systemInstruction: GeminiContent?
    let generationConfig: GenerationConfig

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(contents, forKey: .contents)
        if let systemInstruction {
            try container.encode(systemInstruction, forKey: .systemInstruction)
        }
        try container.encode(generationConfig, forKey: .generationConfig)
    }

    enum CodingKeys: String, CodingKey {
        case contents, systemInstruction, generationConfig
    }
}

private struct GeminiContent: Encodable {
    let role: String?
    let parts: [GeminiPart]

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let role {
            try container.encode(role, forKey: .role)
        }
        try container.encode(parts, forKey: .parts)
    }

    enum CodingKeys: String, CodingKey {
        case role, parts
    }
}

private struct GeminiPart: Encodable {
    var text: String?
    var inlineData: InlineData?

    init(text: String) {
        self.text = text
    }

    init(inlineData: InlineData) {
        self.inlineData = inlineData
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let text {
            try container.encode(text, forKey: .text)
        }
        if let inlineData {
            try container.encode(inlineData, forKey: .inlineData)
        }
    }

    enum CodingKeys: String, CodingKey {
        case text, inlineData
    }
}

private struct InlineData: Encodable {
    let mimeType: String
    let data: String
}

private struct GenerationConfig: Encodable {
    let temperature: Double
    let maxOutputTokens: Int?

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(temperature, forKey: .temperature)
        if let maxOutputTokens {
            try container.encode(maxOutputTokens, forKey: .maxOutputTokens)
        }
    }

    enum CodingKeys: String, CodingKey {
        case temperature, maxOutputTokens
    }
}

// MARK: - Gemini API Response Types

private struct GenerateContentResponse: Decodable {
    let candidates: [Candidate]?
    let usageMetadata: UsageMetadata?

    enum CodingKeys: String, CodingKey {
        case candidates
        case usageMetadata = "usageMetadata"
    }
}

private struct Candidate: Decodable {
    let content: CandidateContent?
    let finishReason: String?
}

private struct CandidateContent: Decodable {
    let parts: [ResponsePart]?
    let role: String?
}

private struct ResponsePart: Decodable {
    let text: String?
}

private struct UsageMetadata: Decodable {
    let promptTokenCount: Int?
    let candidatesTokenCount: Int?
}

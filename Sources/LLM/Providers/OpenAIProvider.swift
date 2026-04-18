import Foundation

/// OpenAI API provider implementation.
/// Supports chat completions, streaming via SSE, and vision inputs.
struct OpenAIProvider: LLMProvider, Sendable {
    let providerId = "openai"
    let displayName = "OpenAI"

    private static let baseURL = URL(string: "https://api.openai.com/v1/chat/completions")!

    // MARK: - Vision Support

    /// Models that support image/vision inputs.
    func supportsVision(_ model: String) -> Bool {
        let lowered = model.lowercased()
        return lowered.contains("gpt-4o")
            || lowered.contains("gpt-4.1")
            || lowered.contains("gpt-5")
            || lowered.contains("o4")
    }

    // MARK: - Reasoning Model Detection

    /// Reasoning models (o-series and GPT-5.x) do not support `temperature`
    /// and use `max_completion_tokens` instead of `max_tokens`.
    private func isReasoningModel(_ model: String) -> Bool {
        let lowered = model.lowercased()
        return lowered.hasPrefix("o1")
            || lowered.hasPrefix("o3")
            || lowered.hasPrefix("o4")
            || lowered.contains("gpt-5")
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
            let decoded = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
            guard let firstChoice = decoded.choices.first else {
                throw LLMError.invalidResponse(
                    statusCode: httpResponse.statusCode,
                    body: "No choices in response"
                )
            }
            return LLMResponse(
                content: firstChoice.message.content ?? "",
                model: decoded.model,
                finishReason: firstChoice.finishReason,
                usage: decoded.usage.map {
                    TokenUsage(promptTokens: $0.promptTokens, completionTokens: $0.completionTokens)
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

                    // For streaming, error responses come as full body, not SSE.
                    // Status codes other than 200 mean we need to collect the body.
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

                    // Parse SSE line by line.
                    for try await line in bytes.lines {
                        try Task.checkCancellation()

                        // SSE lines starting with "data: "
                        guard line.hasPrefix("data: ") else { continue }

                        let payload = String(line.dropFirst(6))

                        // Stream termination signal.
                        if payload == "[DONE]" {
                            break
                        }

                        guard let chunkData = payload.data(using: .utf8) else { continue }
                        do {
                            let chunk = try JSONDecoder().decode(ChatCompletionChunk.self, from: chunkData)
                            if let delta = chunk.choices.first?.delta {
                                let streamDelta = LLMStreamDelta(
                                    content: delta.content,
                                    finishReason: chunk.choices.first?.finishReason
                                )
                                continuation.yield(streamDelta)
                            }
                        } catch {
                            // Skip malformed chunks rather than killing the stream.
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

        var request = URLRequest(url: Self.baseURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        // Build the messages array, prepending system prompt if provided.
        var apiMessages: [ChatRequestMessage] = []

        if let systemPrompt = options.systemPrompt, !systemPrompt.isEmpty {
            apiMessages.append(ChatRequestMessage(
                role: "system",
                content: .text(systemPrompt)
            ))
        }

        let hasVision = supportsVision(model)
        for message in messages {
            apiMessages.append(convertMessage(message, supportsVision: hasVision))
        }

        let reasoning = isReasoningModel(model)

        var body = ChatCompletionRequest(
            model: model,
            messages: apiMessages,
            // Reasoning models reject temperature — omit it.
            temperature: reasoning ? nil : options.temperature,
            // Reasoning models use max_completion_tokens, not max_tokens.
            maxTokens: reasoning ? nil : options.maxTokens,
            maxCompletionTokens: reasoning ? (options.maxTokens ?? 4096) : nil,
            stream: stream
        )

        // Include stream_options to get usage in streaming responses.
        if stream {
            body.streamOptions = StreamOptions(includeUsage: true)
        }

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        request.httpBody = try encoder.encode(body)

        return request
    }

    /// Convert an LLMMessage to the OpenAI API format.
    private func convertMessage(_ message: LLMMessage, supportsVision: Bool) -> ChatRequestMessage {
        let role = message.role.rawValue

        // If there is only text content (no images), use the simple string format.
        let textParts = message.content.compactMap { part -> String? in
            if case .text(let text) = part { return text }
            return nil
        }
        let imageParts = message.content.compactMap { part -> (Data, String)? in
            if case .image(let data, let mimeType) = part { return (data, mimeType) }
            return nil
        }

        // Simple text-only message.
        if imageParts.isEmpty {
            let combinedText = textParts.joined(separator: "\n")
            return ChatRequestMessage(role: role, content: .text(combinedText))
        }

        // Multi-part message with images (vision).
        var contentParts: [ChatContentPart] = []

        for (imageData, mimeType) in imageParts {
            if supportsVision {
                let base64 = imageData.base64EncodedString()
                let dataURL = "data:\(mimeType);base64,\(base64)"
                contentParts.append(.imageURL(ChatImageURL(url: dataURL)))
            }
            // If model doesn't support vision, silently skip image parts.
        }

        for text in textParts {
            contentParts.append(.text(text))
        }

        return ChatRequestMessage(role: role, content: .parts(contentParts))
    }

    // MARK: - Response Validation

    private func validateHTTPResponse(_ response: HTTPURLResponse, body: Data) throws {
        let statusCode = response.statusCode
        guard statusCode != 200 else { return }

        let bodyString = String(data: body, encoding: .utf8) ?? "<unreadable body>"

        switch statusCode {
        case 401:
            throw LLMError.invalidResponse(
                statusCode: statusCode,
                body: "Invalid API key. Please check your OpenAI API key in Settings."
            )
        case 429:
            let retryAfter = response.value(forHTTPHeaderField: "Retry-After")
                .flatMap { TimeInterval($0) }
            throw LLMError.rateLimited(retryAfter: retryAfter)
        case 400:
            // Check for context length errors.
            if bodyString.contains("context_length_exceeded")
                || bodyString.contains("maximum context length") {
                throw LLMError.contextLengthExceeded
            }
            throw LLMError.invalidResponse(statusCode: statusCode, body: bodyString)
        default:
            throw LLMError.invalidResponse(statusCode: statusCode, body: bodyString)
        }
    }
}

// MARK: - OpenAI API Request Types

/// Top-level chat completion request body.
/// Reasoning models (o-series, GPT-5.x) use `maxCompletionTokens` instead of
/// `maxTokens` and do not accept `temperature`.
private struct ChatCompletionRequest: Encodable {
    let model: String
    let messages: [ChatRequestMessage]
    let temperature: Double?
    let maxTokens: Int?
    let maxCompletionTokens: Int?
    let stream: Bool
    var streamOptions: StreamOptions?
}

private struct StreamOptions: Encodable {
    let includeUsage: Bool
}

/// A single message in the request.
private struct ChatRequestMessage: Encodable {
    let role: String
    let content: MessageContent

    enum MessageContent {
        case text(String)
        case parts([ChatContentPart])
    }

    enum CodingKeys: String, CodingKey {
        case role, content
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(role, forKey: .role)
        switch content {
        case .text(let text):
            try container.encode(text, forKey: .content)
        case .parts(let parts):
            try container.encode(parts, forKey: .content)
        }
    }
}

/// A content part within a multi-part message.
private enum ChatContentPart: Encodable {
    case text(String)
    case imageURL(ChatImageURL)

    enum CodingKeys: String, CodingKey {
        case type, text, imageUrl = "image_url"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let text):
            try container.encode("text", forKey: .type)
            try container.encode(text, forKey: .text)
        case .imageURL(let imageURL):
            try container.encode("image_url", forKey: .type)
            try container.encode(imageURL, forKey: .imageUrl)
        }
    }
}

private struct ChatImageURL: Encodable {
    let url: String
}

// MARK: - OpenAI API Response Types (Non-Streaming)

private struct ChatCompletionResponse: Decodable {
    let id: String
    let model: String
    let choices: [ChatChoice]
    let usage: ChatUsage?
}

private struct ChatChoice: Decodable {
    let index: Int
    let message: ChatChoiceMessage
    let finishReason: String?

    enum CodingKeys: String, CodingKey {
        case index, message
        case finishReason = "finish_reason"
    }
}

private struct ChatChoiceMessage: Decodable {
    let role: String?
    let content: String?
}

private struct ChatUsage: Decodable {
    let promptTokens: Int
    let completionTokens: Int

    enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
    }
}

// MARK: - OpenAI API Response Types (Streaming)

private struct ChatCompletionChunk: Decodable {
    let id: String?
    let choices: [ChunkChoice]

    struct ChunkChoice: Decodable {
        let delta: ChunkDelta?
        let finishReason: String?

        enum CodingKeys: String, CodingKey {
            case delta
            case finishReason = "finish_reason"
        }
    }

    struct ChunkDelta: Decodable {
        let role: String?
        let content: String?
    }
}

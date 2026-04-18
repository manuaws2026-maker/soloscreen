import Foundation

/// Anthropic Messages API provider implementation.
/// Supports chat completions, streaming via SSE, and vision inputs.
struct ClaudeProvider: LLMProvider, Sendable {
    let providerId = "anthropic"
    let displayName = "Claude"

    private static let baseURL = URL(string: "https://api.anthropic.com/v1/messages")!
    private static let apiVersion = "2023-06-01"

    // MARK: - Vision Support

    func supportsVision(_ model: String) -> Bool {
        // All current Claude models support vision.
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
            let decoded = try JSONDecoder().decode(MessagesResponse.self, from: data)
            let text = decoded.content
                .compactMap { block -> String? in
                    if case .text(let t) = block { return t }
                    return nil
                }
                .joined()

            return LLMResponse(
                content: text,
                model: decoded.model,
                finishReason: decoded.stopReason,
                usage: TokenUsage(
                    promptTokens: decoded.usage.inputTokens,
                    completionTokens: decoded.usage.outputTokens
                )
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

                    // Parse SSE events from Anthropic's streaming format.
                    for try await line in bytes.lines {
                        try Task.checkCancellation()

                        guard line.hasPrefix("data: ") else { continue }
                        let payload = String(line.dropFirst(6))
                        guard let chunkData = payload.data(using: .utf8) else { continue }

                        do {
                            let event = try JSONDecoder().decode(StreamEvent.self, from: chunkData)
                            switch event.type {
                            case "content_block_delta":
                                if let delta = event.delta, delta.type == "text_delta" {
                                    continuation.yield(LLMStreamDelta(
                                        content: delta.text,
                                        finishReason: nil
                                    ))
                                }
                            case "message_delta":
                                if let delta = event.delta {
                                    continuation.yield(LLMStreamDelta(
                                        content: nil,
                                        finishReason: delta.stopReason
                                    ))
                                }
                            case "message_stop":
                                break
                            default:
                                // message_start, content_block_start, content_block_stop, ping — skip.
                                break
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

        var request = URLRequest(url: Self.baseURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(Self.apiVersion, forHTTPHeaderField: "anthropic-version")

        // Separate system prompt from conversation messages.
        // Anthropic expects system as a top-level parameter, not in the messages array.
        var systemText: String?
        var apiMessages: [AnthropicMessage] = []

        if let systemPrompt = options.systemPrompt, !systemPrompt.isEmpty {
            systemText = systemPrompt
        }

        for message in messages {
            if message.role == .system {
                // Merge any system messages into the system parameter.
                let text = message.content.compactMap { part -> String? in
                    if case .text(let t) = part { return t }
                    return nil
                }.joined(separator: "\n")
                if systemText != nil {
                    systemText! += "\n\n" + text
                } else {
                    systemText = text
                }
            } else {
                apiMessages.append(convertMessage(message))
            }
        }

        let body = MessagesRequest(
            model: model,
            maxTokens: options.maxTokens ?? 4096,
            system: systemText,
            messages: apiMessages,
            // Anthropic only accepts temperature in 0.0...1.0.
            temperature: min(options.temperature, 1.0),
            stream: stream
        )

        request.httpBody = try JSONEncoder().encode(body)
        return request
    }

    /// Convert an LLMMessage to the Anthropic API format.
    private func convertMessage(_ message: LLMMessage) -> AnthropicMessage {
        let role = message.role == .assistant ? "assistant" : "user"

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
            let combined = textParts.joined(separator: "\n")
            return AnthropicMessage(
                role: role,
                content: .text(combined)
            )
        }

        // Multi-part message with images.
        var contentBlocks: [ContentBlock] = []

        for (imageData, mimeType) in imageParts {
            contentBlocks.append(.image(ImageSource(
                type: "base64",
                mediaType: mimeType,
                data: imageData.base64EncodedString()
            )))
        }

        for text in textParts {
            contentBlocks.append(.text(text))
        }

        return AnthropicMessage(role: role, content: .blocks(contentBlocks))
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
                body: "Invalid API key. Please check your Anthropic API key in Settings."
            )
        case 429:
            let retryAfter = response.value(forHTTPHeaderField: "Retry-After")
                .flatMap { TimeInterval($0) }
            throw LLMError.rateLimited(retryAfter: retryAfter)
        case 400:
            if bodyString.contains("context_length") || bodyString.contains("too long") {
                throw LLMError.contextLengthExceeded
            }
            throw LLMError.invalidResponse(statusCode: statusCode, body: bodyString)
        default:
            throw LLMError.invalidResponse(statusCode: statusCode, body: bodyString)
        }
    }
}

// MARK: - Anthropic API Request Types

private struct MessagesRequest: Encodable {
    let model: String
    let maxTokens: Int
    let system: String?
    let messages: [AnthropicMessage]
    let temperature: Double
    let stream: Bool

    enum CodingKeys: String, CodingKey {
        case model
        case maxTokens = "max_tokens"
        case system, messages, temperature, stream
    }
}

private struct AnthropicMessage: Encodable {
    let role: String
    let content: MessageContent

    enum MessageContent {
        case text(String)
        case blocks([ContentBlock])
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
        case .blocks(let blocks):
            try container.encode(blocks, forKey: .content)
        }
    }
}

private enum ContentBlock: Encodable {
    case text(String)
    case image(ImageSource)

    enum CodingKeys: String, CodingKey {
        case type, text, source
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let text):
            try container.encode("text", forKey: .type)
            try container.encode(text, forKey: .text)
        case .image(let source):
            try container.encode("image", forKey: .type)
            try container.encode(source, forKey: .source)
        }
    }
}

private struct ImageSource: Encodable {
    let type: String
    let mediaType: String
    let data: String

    enum CodingKeys: String, CodingKey {
        case type
        case mediaType = "media_type"
        case data
    }
}

// MARK: - Anthropic API Response Types (Non-Streaming)

private struct MessagesResponse: Decodable {
    let id: String
    let model: String
    let content: [ResponseContentBlock]
    let stopReason: String?
    let usage: ResponseUsage

    enum CodingKeys: String, CodingKey {
        case id, model, content
        case stopReason = "stop_reason"
        case usage
    }
}

private enum ResponseContentBlock: Decodable {
    case text(String)
    case other

    enum CodingKeys: String, CodingKey {
        case type, text
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        if type == "text" {
            let text = try container.decode(String.self, forKey: .text)
            self = .text(text)
        } else {
            self = .other
        }
    }
}

private struct ResponseUsage: Decodable {
    let inputTokens: Int
    let outputTokens: Int

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
    }
}

// MARK: - Anthropic API Streaming Types

private struct StreamEvent: Decodable {
    let type: String
    let delta: StreamDelta?
}

private struct StreamDelta: Decodable {
    let type: String?
    let text: String?
    let stopReason: String?

    enum CodingKeys: String, CodingKey {
        case type, text
        case stopReason = "stop_reason"
    }
}

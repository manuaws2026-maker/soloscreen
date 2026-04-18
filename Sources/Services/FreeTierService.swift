import Foundation

/// Backend proxy service for free-tier users.
///
/// When a user has no API key but has free messages remaining, requests are
/// routed through the SoloScreen backend. The backend holds its own API keys
/// and forwards requests to the appropriate provider.
///
/// The backend enforces per-device rate limits and returns usage information
/// so the client can display remaining free messages.
actor FreeTierService {

    // MARK: - Singleton

    static let shared = FreeTierService()

    private init() {}

    // MARK: - Configuration

    /// Backend proxy endpoint. Messages are POSTed here and streamed back.
    private static let proxyURL = URL(string: "https://api.soloscreen.app/v1/chat")!

    /// Device identifier for rate limiting (persisted across launches).
    private var deviceId: String {
        let key = "com.soloscreen.device-id"
        if let existing = UserDefaults.standard.string(forKey: key) {
            return existing
        }
        let newId = UUID().uuidString
        UserDefaults.standard.set(newId, forKey: key)
        return newId
    }

    // MARK: - Errors

    enum FreeTierError: LocalizedError {
        case quotaExhausted
        case backendUnavailable(String)

        var errorDescription: String? {
            switch self {
            case .quotaExhausted:
                return "Free tier limit reached. Please add your own API key in Settings to continue."
            case .backendUnavailable(let detail):
                return "Free tier service unavailable: \(detail)"
            }
        }
    }

    // MARK: - Non-Streaming

    func complete(
        messages: [LLMMessage],
        model: String,
        options: LLMRequestOptions
    ) async throws -> LLMResponse {
        let request = try buildRequest(messages: messages, model: model, options: options, stream: false)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch is CancellationError {
            throw LLMError.cancelled
        } catch {
            throw LLMError.networkError(underlying: error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.networkError(underlying: URLError(.badServerResponse))
        }

        try validateResponse(httpResponse, body: data)

        do {
            let decoded = try JSONDecoder().decode(ProxyResponse.self, from: data)
            return LLMResponse(
                content: decoded.content,
                model: decoded.model,
                finishReason: decoded.finishReason,
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

    // MARK: - Streaming

    func stream(
        messages: [LLMMessage],
        model: String,
        options: LLMRequestOptions
    ) -> AsyncThrowingStream<LLMStreamDelta, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = try self.buildRequest(messages: messages, model: model, options: options, stream: true)

                    let (bytes, response): (URLSession.AsyncBytes, URLResponse)
                    do {
                        (bytes, response) = try await URLSession.shared.bytes(for: request)
                    } catch is CancellationError {
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
                            try self.validateResponse(httpResponse, body: bodyData)
                        } catch {
                            continuation.finish(throwing: error)
                            return
                        }
                    }

                    // The proxy streams back SSE in the same format as OpenAI.
                    for try await line in bytes.lines {
                        try Task.checkCancellation()

                        guard line.hasPrefix("data: ") else { continue }
                        let payload = String(line.dropFirst(6))
                        if payload == "[DONE]" { break }

                        guard let chunkData = payload.data(using: .utf8) else { continue }
                        do {
                            let chunk = try JSONDecoder().decode(ProxyStreamChunk.self, from: chunkData)
                            continuation.yield(LLMStreamDelta(
                                content: chunk.content,
                                finishReason: chunk.finishReason
                            ))
                        } catch {
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

    private func buildRequest(
        messages: [LLMMessage],
        model: String,
        options: LLMRequestOptions,
        stream: Bool
    ) throws -> URLRequest {
        var request = URLRequest(url: Self.proxyURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(deviceId, forHTTPHeaderField: "X-Device-Id")

        // Convert messages to a JSON-serialisable format, preserving image data.
        let apiMessages = messages.map { msg -> ProxyMessage in
            var textParts: [String] = []
            var images: [ProxyImage] = []

            for part in msg.content {
                switch part {
                case .text(let t):
                    textParts.append(t)
                case .image(let data, let mimeType):
                    images.append(ProxyImage(
                        data: data.base64EncodedString(),
                        mimeType: mimeType
                    ))
                }
            }

            return ProxyMessage(
                role: msg.role.rawValue,
                content: textParts.joined(separator: "\n"),
                images: images.isEmpty ? nil : images
            )
        }

        let body = ProxyRequest(
            model: model,
            messages: apiMessages,
            systemPrompt: options.systemPrompt,
            temperature: options.temperature,
            maxTokens: options.maxTokens,
            stream: stream
        )

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        request.httpBody = try encoder.encode(body)
        return request
    }

    // MARK: - Response Validation

    private func validateResponse(_ response: HTTPURLResponse, body: Data) throws {
        let statusCode = response.statusCode
        guard statusCode != 200 else { return }

        let bodyString = String(data: body, encoding: .utf8) ?? "<unreadable body>"

        switch statusCode {
        case 402, 429:
            throw FreeTierError.quotaExhausted
        default:
            throw FreeTierError.backendUnavailable("HTTP \(statusCode): \(bodyString.prefix(200))")
        }
    }
}

// MARK: - Proxy API Types

private struct ProxyRequest: Encodable {
    let model: String
    let messages: [ProxyMessage]
    let systemPrompt: String?
    let temperature: Double
    let maxTokens: Int?
    let stream: Bool
}

private struct ProxyMessage: Encodable {
    let role: String
    let content: String
    let images: [ProxyImage]?
}

private struct ProxyImage: Encodable {
    let data: String
    let mimeType: String
}

private struct ProxyResponse: Decodable {
    let content: String
    let model: String
    let finishReason: String?
    let usage: ProxyUsage?

    enum CodingKeys: String, CodingKey {
        case content, model
        case finishReason = "finish_reason"
        case usage
    }
}

private struct ProxyUsage: Decodable {
    let promptTokens: Int
    let completionTokens: Int

    enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
    }
}

private struct ProxyStreamChunk: Decodable {
    let content: String?
    let finishReason: String?

    enum CodingKeys: String, CodingKey {
        case content
        case finishReason = "finish_reason"
    }
}

import Foundation

// MARK: - Request Types

/// A message in the LLM conversation.
struct LLMMessage: Sendable {
    let role: Role
    let content: [ContentPart]

    enum Role: String, Sendable {
        case system, user, assistant
    }

    enum ContentPart: Sendable {
        case text(String)
        case image(data: Data, mimeType: String)
    }

    /// Convenience: create a text-only message.
    static func text(role: Role, content: String) -> LLMMessage {
        LLMMessage(role: role, content: [.text(content)])
    }

    /// Convenience: create a user message with text and images.
    static func userWithImages(text: String, images: [(Data, String)]) -> LLMMessage {
        var parts: [ContentPart] = images.map { .image(data: $0.0, mimeType: $0.1) }
        parts.append(.text(text))
        return LLMMessage(role: .user, content: parts)
    }
}

/// Options for an LLM request.
struct LLMRequestOptions: Sendable {
    var temperature: Double
    var maxTokens: Int?
    var systemPrompt: String?

    init(temperature: Double = 0.7, maxTokens: Int? = nil, systemPrompt: String? = nil) {
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.systemPrompt = systemPrompt
    }
}

// MARK: - Response Types

/// A complete LLM response.
struct LLMResponse: Sendable {
    let content: String
    let model: String
    let finishReason: String?
    let usage: TokenUsage?
}

/// Token usage information.
struct TokenUsage: Sendable {
    let promptTokens: Int
    let completionTokens: Int
    var totalTokens: Int { promptTokens + completionTokens }
}

/// A streamed chunk from the LLM.
struct LLMStreamDelta: Sendable {
    let content: String?
    let finishReason: String?
}

// MARK: - Errors

enum LLMError: LocalizedError {
    case noAPIKey
    case invalidResponse(statusCode: Int, body: String)
    case networkError(underlying: Error)
    case decodingError(underlying: Error)
    case modelNotSupported(String)
    case rateLimited(retryAfter: TimeInterval?)
    case contextLengthExceeded
    case cancelled

    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "No API key configured. Please add your API key in Settings."
        case .invalidResponse(let code, let body):
            return "API error (HTTP \(code)): \(body.prefix(200))"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .decodingError(let error):
            return "Failed to parse response: \(error.localizedDescription)"
        case .modelNotSupported(let model):
            return "Model '\(model)' is not supported."
        case .rateLimited(let retry):
            if let retry { return "Rate limited. Retry after \(Int(retry))s." }
            return "Rate limited. Please wait and try again."
        case .contextLengthExceeded:
            return "Message too long for this model's context window."
        case .cancelled:
            return "Request was cancelled."
        }
    }
}

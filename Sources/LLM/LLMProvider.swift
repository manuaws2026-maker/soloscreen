import Foundation

/// Protocol that all LLM providers must implement.
/// Designed for extensibility: add new providers (Claude, Gemini) by conforming to this protocol.
protocol LLMProvider: Sendable {
    /// Unique identifier for the provider (e.g., "openai", "anthropic", "google").
    var providerId: String { get }

    /// Human-readable display name.
    var displayName: String { get }

    /// Send a completion request and return the full response.
    func complete(
        messages: [LLMMessage],
        model: String,
        apiKey: String,
        options: LLMRequestOptions
    ) async throws -> LLMResponse

    /// Stream a completion request, yielding deltas as they arrive.
    func stream(
        messages: [LLMMessage],
        model: String,
        apiKey: String,
        options: LLMRequestOptions
    ) -> AsyncThrowingStream<LLMStreamDelta, Error>

    /// Whether the given model supports vision (image) inputs.
    func supportsVision(_ model: String) -> Bool
}

// MARK: - LLM Router

/// Routes requests to the appropriate provider based on provider ID.
@MainActor
final class LLMRouter {
    private var providers: [String: any LLMProvider] = [:]

    init() {
        register(OpenAIProvider())
        register(ClaudeProvider())
        register(GeminiProvider())
    }

    func register(_ provider: any LLMProvider) {
        providers[provider.providerId] = provider
    }

    func provider(for id: String) -> (any LLMProvider)? {
        providers[id]
    }

    var availableProviders: [any LLMProvider] {
        Array(providers.values)
    }
}

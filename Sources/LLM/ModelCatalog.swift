import Foundation

/// Metadata about a specific AI model.
struct ModelInfo: Identifiable, Sendable, Equatable {
    let id: String
    let name: String
    let provider: String
    let description: String
    let strengths: [String]
    let weaknesses: [String]
    let supportsVision: Bool
    let contextWindow: Int
    let costTier: CostTier

    enum CostTier: String, Sendable, Equatable {
        case free, low, medium, high, premium

        var displayLabel: String {
            switch self {
            case .free: return "Free"
            case .low: return "$"
            case .medium: return "$$"
            case .high: return "$$$"
            case .premium: return "$$$$"
            }
        }
    }

    static func == (lhs: ModelInfo, rhs: ModelInfo) -> Bool { lhs.id == rhs.id }
}

/// Curated catalog of supported models with strengths/weaknesses.
enum ModelCatalog {
    // MARK: - OpenAI Models

    static let openai: [ModelInfo] = [
        ModelInfo(
            id: "gpt-4o",
            name: "GPT-4o",
            provider: "openai",
            description: "OpenAI's flagship multimodal model. Excellent at reasoning, coding, and vision tasks.",
            strengths: ["Strong reasoning", "Excellent code generation", "Fast responses", "Vision support", "Great instruction following"],
            weaknesses: ["Higher cost than mini models", "Can be verbose on simple tasks"],
            supportsVision: true,
            contextWindow: 128_000,
            costTier: .high
        ),
        ModelInfo(
            id: "gpt-4o-mini",
            name: "GPT-4o Mini",
            provider: "openai",
            description: "Fast, affordable model ideal for everyday tasks. Best balance of speed, cost, and capability.",
            strengths: ["Very fast", "Low cost", "Good for most tasks", "Vision support", "128K context"],
            weaknesses: ["Less capable at complex multi-step reasoning", "Weaker at nuanced code refactoring"],
            supportsVision: true,
            contextWindow: 128_000,
            costTier: .low
        ),
        ModelInfo(
            id: "gpt-4.1",
            name: "GPT-4.1",
            provider: "openai",
            description: "Latest GPT model optimized for coding and long-context tasks. 1M token context window.",
            strengths: ["Best coding performance", "1M token context", "Excellent instruction following", "Vision support"],
            weaknesses: ["Higher latency on complex prompts", "Premium pricing"],
            supportsVision: true,
            contextWindow: 1_000_000,
            costTier: .premium
        ),
        ModelInfo(
            id: "gpt-4.1-mini",
            name: "GPT-4.1 Mini",
            provider: "openai",
            description: "Compact version of GPT-4.1 with strong coding abilities at lower cost.",
            strengths: ["Good coding ability", "1M token context", "Fast", "Vision support", "Affordable"],
            weaknesses: ["Less capable than full 4.1 on complex tasks"],
            supportsVision: true,
            contextWindow: 1_000_000,
            costTier: .medium
        ),
        ModelInfo(
            id: "o4-mini",
            name: "o4-mini",
            provider: "openai",
            description: "Reasoning model that thinks step-by-step. Best for math, logic, and complex problem solving.",
            strengths: ["Superior reasoning", "Math and logic", "Step-by-step thinking", "Self-correction"],
            weaknesses: ["Slower (thinks before responding)", "Higher cost per token", "Not ideal for simple tasks"],
            supportsVision: true,
            contextWindow: 200_000,
            costTier: .high
        ),
    ]

    // MARK: - Anthropic Models (future)

    static let anthropic: [ModelInfo] = [
        ModelInfo(
            id: "claude-sonnet-4-20250514",
            name: "Claude Sonnet 4",
            provider: "anthropic",
            description: "Anthropic's balanced model. Excellent at writing, analysis, and careful reasoning.",
            strengths: ["Thoughtful responses", "Excellent writing quality", "Strong at analysis", "Good at following nuance"],
            weaknesses: ["Slower than GPT-4o-mini", "Higher cost"],
            supportsVision: true,
            contextWindow: 200_000,
            costTier: .high
        ),
        ModelInfo(
            id: "claude-haiku-4-20250414",
            name: "Claude Haiku 4",
            provider: "anthropic",
            description: "Fast and affordable Claude model for everyday tasks.",
            strengths: ["Very fast", "Low cost", "Good writing", "Vision support"],
            weaknesses: ["Less capable at complex reasoning", "Smaller context"],
            supportsVision: true,
            contextWindow: 200_000,
            costTier: .low
        ),
    ]

    // MARK: - Google Models (future)

    static let google: [ModelInfo] = [
        ModelInfo(
            id: "gemini-2.5-flash",
            name: "Gemini 2.5 Flash",
            provider: "google",
            description: "Google's fast multimodal model with thinking capabilities.",
            strengths: ["Very fast", "Strong multimodal", "Good reasoning", "Low cost"],
            weaknesses: ["Less consistent than GPT-4o on edge cases"],
            supportsVision: true,
            contextWindow: 1_000_000,
            costTier: .low
        ),
        ModelInfo(
            id: "gemini-2.5-pro",
            name: "Gemini 2.5 Pro",
            provider: "google",
            description: "Google's most capable model with advanced reasoning and 1M context.",
            strengths: ["Advanced reasoning", "1M context", "Strong at code", "Multimodal"],
            weaknesses: ["Higher latency", "Premium pricing"],
            supportsVision: true,
            contextWindow: 1_000_000,
            costTier: .premium
        ),
    ]

    // MARK: - All Models

    static let all: [ModelInfo] = openai + anthropic + google

    static func models(for provider: String) -> [ModelInfo] {
        all.filter { $0.provider == provider }
    }

    static func model(withId id: String) -> ModelInfo? {
        all.first { $0.id == id }
    }

    /// Recommended model for first-time users.
    static let defaultModel = "gpt-4o-mini"

    /// Model used for free tier messages (via backend).
    static let freeTierModel = "gpt-4o-mini"
}

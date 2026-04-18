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
            id: "gpt-5.4",
            name: "GPT-5.4",
            provider: "openai",
            description: "OpenAI's frontier model for complex reasoning, coding, and professional work.",
            strengths: ["Strongest reasoning", "Excellent code generation", "1M context", "Vision support"],
            weaknesses: ["Premium pricing", "Higher latency on complex prompts"],
            supportsVision: true,
            contextWindow: 1_050_000,
            costTier: .premium
        ),
        ModelInfo(
            id: "gpt-5.4-mini",
            name: "GPT-5.4 Mini",
            provider: "openai",
            description: "Fast, efficient GPT-5.4 variant for high-volume workloads. 400K context window.",
            strengths: ["Very fast", "Low cost", "400K context", "Vision support", "Strong coding"],
            weaknesses: ["Less capable than full 5.4 on complex tasks"],
            supportsVision: true,
            contextWindow: 400_000,
            costTier: .low
        ),
        ModelInfo(
            id: "gpt-4o",
            name: "GPT-4o",
            provider: "openai",
            description: "Previous-gen flagship model. Still excellent at reasoning, coding, and vision tasks.",
            strengths: ["Strong reasoning", "Fast responses", "Vision support", "Well-tested"],
            weaknesses: ["Surpassed by GPT-5.4", "128K context limit"],
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
            weaknesses: ["Less capable at complex multi-step reasoning"],
            supportsVision: true,
            contextWindow: 128_000,
            costTier: .low
        ),
        ModelInfo(
            id: "o4-mini",
            name: "o4-mini",
            provider: "openai",
            description: "Reasoning model that thinks step-by-step. Best for math, logic, and complex problem solving.",
            strengths: ["Superior reasoning", "Math and logic", "Step-by-step thinking", "Self-correction"],
            weaknesses: ["Slower (thinks before responding)", "Higher cost per token"],
            supportsVision: true,
            contextWindow: 200_000,
            costTier: .high
        ),
    ]

    // MARK: - Anthropic Models

    static let anthropic: [ModelInfo] = [
        ModelInfo(
            id: "claude-opus-4-6",
            name: "Claude Opus 4.6",
            provider: "anthropic",
            description: "Anthropic's most capable model. 1M context, agentic coding, advanced reasoning.",
            strengths: ["Strongest reasoning", "1M context", "Best coding", "Sustained agentic tasks"],
            weaknesses: ["Premium pricing", "Higher latency"],
            supportsVision: true,
            contextWindow: 1_000_000,
            costTier: .premium
        ),
        ModelInfo(
            id: "claude-sonnet-4-6",
            name: "Claude Sonnet 4.6",
            provider: "anthropic",
            description: "Balanced performance model. Excellent at writing, coding, and analysis with 1M context.",
            strengths: ["Excellent writing", "Strong coding", "1M context", "Good value"],
            weaknesses: ["Slower than Haiku"],
            supportsVision: true,
            contextWindow: 1_000_000,
            costTier: .high
        ),
        ModelInfo(
            id: "claude-haiku-4-5-20251001",
            name: "Claude Haiku 4.5",
            provider: "anthropic",
            description: "Fast and affordable Claude model for everyday tasks.",
            strengths: ["Very fast", "Low cost", "Good writing", "Vision support"],
            weaknesses: ["Less capable at complex reasoning"],
            supportsVision: true,
            contextWindow: 200_000,
            costTier: .low
        ),
    ]

    // MARK: - Google Models

    static let google: [ModelInfo] = [
        ModelInfo(
            id: "gemini-2.5-pro",
            name: "Gemini 2.5 Pro",
            provider: "google",
            description: "Google's flagship thinking model with advanced reasoning and 1M context.",
            strengths: ["Advanced reasoning", "1M context", "Strong at code", "Multimodal"],
            weaknesses: ["Higher latency", "Premium pricing"],
            supportsVision: true,
            contextWindow: 1_000_000,
            costTier: .premium
        ),
        ModelInfo(
            id: "gemini-2.5-flash",
            name: "Gemini 2.5 Flash",
            provider: "google",
            description: "Fast, budget-friendly model with built-in thinking capabilities.",
            strengths: ["Very fast", "Strong multimodal", "Good reasoning", "Low cost"],
            weaknesses: ["Less consistent on edge cases"],
            supportsVision: true,
            contextWindow: 1_000_000,
            costTier: .low
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

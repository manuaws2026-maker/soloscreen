import Foundation

/// Persisted user settings. API keys are stored in Keychain, NOT here.
struct UserSettings: Codable, Equatable {
    var selectedProvider: String
    var selectedModel: String
    var transcriptionProvider: String
    var freeMessagesUsed: Int
    var onboardingCompleted: Bool
    var stealthEnabled: Bool
    var extremeStealthEnabled: Bool
    var overlayOpacity: Double
    var fontSize: Double
    /// Preferred programming language. Prompted once on the first coding /
    /// system-design chat, then reused automatically. Nil = never asked.
    var preferredCodingLanguage: String?

    /// Per-feature model overrides. Nil = "Auto" (SoloScreen picks the cheapest
    /// fastest sibling from the same provider family). User can override each
    /// feature with a specific model.
    var liveHelpModelOverride: String?
    var screenshotModelOverride: String?

    static let freeMessageLimit = 10

    init(
        selectedProvider: String = "openai",
        selectedModel: String = "gpt-4o-mini",
        transcriptionProvider: String = "openai",
        freeMessagesUsed: Int = 0,
        onboardingCompleted: Bool = false,
        stealthEnabled: Bool = true,
        extremeStealthEnabled: Bool = false,
        overlayOpacity: Double = 0.95,
        fontSize: Double = 14.0,
        preferredCodingLanguage: String? = nil,
        liveHelpModelOverride: String? = nil,
        screenshotModelOverride: String? = nil
    ) {
        self.selectedProvider = selectedProvider
        self.selectedModel = selectedModel
        self.transcriptionProvider = transcriptionProvider
        self.freeMessagesUsed = freeMessagesUsed
        self.onboardingCompleted = onboardingCompleted
        self.stealthEnabled = stealthEnabled
        self.extremeStealthEnabled = extremeStealthEnabled
        self.overlayOpacity = overlayOpacity
        self.fontSize = fontSize
        self.preferredCodingLanguage = preferredCodingLanguage
        self.liveHelpModelOverride = liveHelpModelOverride
        self.screenshotModelOverride = screenshotModelOverride
    }

    var hasFreeTierRemaining: Bool { freeMessagesUsed < Self.freeMessageLimit }
    var freeMessagesRemaining: Int { max(0, Self.freeMessageLimit - freeMessagesUsed) }
}

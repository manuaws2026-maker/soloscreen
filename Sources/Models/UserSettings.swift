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

    static let freeMessageLimit = 10

    init(
        selectedProvider: String = "openai",
        selectedModel: String = "gpt-4o-mini",
        transcriptionProvider: String = "deepgram",
        freeMessagesUsed: Int = 0,
        onboardingCompleted: Bool = false,
        stealthEnabled: Bool = true,
        extremeStealthEnabled: Bool = false,
        overlayOpacity: Double = 1.0,
        fontSize: Double = 14.0
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
    }

    var hasFreeTierRemaining: Bool { freeMessagesUsed < Self.freeMessageLimit }
    var freeMessagesRemaining: Int { max(0, Self.freeMessageLimit - freeMessagesUsed) }
}

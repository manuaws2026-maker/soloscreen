import SwiftUI

/// Onboarding flow shown on first launch.
///
/// Three steps: Welcome, API Key setup, and Getting Started tips.
/// The user must complete onboarding before the main UI becomes accessible.
struct OnboardingView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var currentStep: Int = 0
    @State private var apiKey: String = ""
    @State private var isKeySaved: Bool = false

    private let accentTeal = Color(hex: "22C55E")
    private let bgColor = Color(hex: "0D1117")
    private let surfaceColor = Color(hex: "161B22")
    private let borderColor = Color(hex: "30363D")

    private let totalSteps = 3

    var body: some View {
        VStack(spacing: 0) {
            progressIndicator
                .padding(.top, 24)

            Spacer()

            Group {
                switch currentStep {
                case 0: welcomeStep
                case 1: apiKeyStep
                case 2: tipsStep
                default: EmptyView()
                }
            }
            .transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            ))

            Spacer()

            navigationButtons
                .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(bgColor)
    }

    // MARK: - Progress Indicator

    private var progressIndicator: some View {
        HStack(spacing: 8) {
            ForEach(0..<totalSteps, id: \.self) { step in
                Circle()
                    .fill(step == currentStep ? accentTeal : .white.opacity(0.2))
                    .frame(width: 8, height: 8)
                    .animation(.easeInOut(duration: 0.2), value: currentStep)
            }
        }
    }

    // MARK: - Welcome Step

    private var welcomeStep: some View {
        VStack(spacing: 20) {
            Group {
                if let url = Bundle.module.url(forResource: "BrainIcon", withExtension: "png"),
                   let nsImg = NSImage(contentsOf: url) {
                    Image(nsImage: nsImg)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 80, weight: .thin))
                        .foregroundStyle(accentTeal.opacity(0.7))
                }
            }
            .frame(width: 120, height: 120)

            Text("Welcome to SoloScreen")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.white.opacity(0.95))

            Text("Your invisible AI assistant.\nAlways there, never seen.")
                .font(.system(size: 15))
                .foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center)
                .lineSpacing(4)

            VStack(alignment: .leading, spacing: 12) {
                featureRow(icon: "eye.slash", text: "Invisible to screen share and recordings")
                featureRow(icon: "bolt.fill", text: "Multi-provider AI (OpenAI, Claude, Gemini)")
                featureRow(icon: "mic.fill", text: "Voice input and live transcription")
                featureRow(icon: "camera.fill", text: "Screenshot analysis with vision models")
                featureRow(icon: "folder.fill", text: "RAG with your own documents")
            }
            .padding(.top, 8)
        }
        .padding(.horizontal, 40)
    }

    private func featureRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(accentTeal)
                .frame(width: 24)

            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.7))
        }
    }

    // MARK: - API Key Step

    private var apiKeyStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "key.fill")
                .font(.system(size: 44, weight: .thin))
                .foregroundStyle(accentTeal.opacity(0.7))

            Text("Set Up Your API Key")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white.opacity(0.95))

            Text("SoloScreen uses your own API key.\nYour key is stored securely on your Mac.")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.5))
                .multilineTextAlignment(.center)
                .lineSpacing(3)

            VStack(spacing: 12) {
                HStack(spacing: 8) {
                    PasteableSecureField(placeholder: "Enter your OpenAI API key", text: $apiKey)
                        .frame(height: 20)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(surfaceColor)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(borderColor, lineWidth: 1)
                                )
                        )

                    if isKeySaved {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.system(size: 18))
                            .transition(.scale.combined(with: .opacity))
                    }
                }

                Button {
                    saveAPIKey()
                } label: {
                    Text("Save Key")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(apiKey.isEmpty ? accentTeal.opacity(0.3) : accentTeal)
                        )
                }
                .buttonStyle(.plain)
                .disabled(apiKey.isEmpty)
            }
            .frame(maxWidth: 340)

            Text("You can also skip this step and use 10 free messages first.")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.3))
        }
        .padding(.horizontal, 40)
    }

    // MARK: - Tips Step

    private var tipsStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "sparkles")
                .font(.system(size: 44, weight: .thin))
                .foregroundStyle(accentTeal.opacity(0.7))

            Text("You're All Set")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white.opacity(0.95))

            VStack(alignment: .leading, spacing: 14) {
                tipRow(keys: "Cmd+Shift+Space", tip: "Toggle SoloScreen visibility")
                tipRow(keys: "Cmd+Shift+S", tip: "Capture a screenshot")
                tipRow(keys: "Cmd+Shift+R", tip: "Record voice input")
                tipRow(keys: "Cmd+Shift+N", tip: "Start a new chat")
                tipRow(keys: "Cmd+Shift+M", tip: "Minimize to edge")
            }
            .padding(.top, 4)

            Text("SoloScreen is invisible to screen share.\nDrag the overlay to reposition it.")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.4))
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .padding(.top, 8)
        }
        .padding(.horizontal, 40)
    }

    private func tipRow(keys: String, tip: String) -> some View {
        HStack(spacing: 12) {
            Text(keys)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(accentTeal.opacity(0.8))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(accentTeal.opacity(0.08))
                )
                .frame(minWidth: 160, alignment: .leading)

            Text(tip)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.6))
        }
    }

    // MARK: - Navigation

    private var navigationButtons: some View {
        HStack(spacing: 16) {
            if currentStep > 0 {
                Button("Back") {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        currentStep -= 1
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.5))
                .font(.system(size: 14))
            }

            Spacer()

            if currentStep == 1 && !isKeySaved {
                Button("Skip") {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        currentStep += 1
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.4))
                .font(.system(size: 13))
            }

            Button {
                if currentStep < totalSteps - 1 {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        currentStep += 1
                    }
                } else {
                    completeOnboarding()
                }
            } label: {
                Text(currentStep < totalSteps - 1 ? "Next" : "Get Started")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(accentTeal, in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 40)
    }

    // MARK: - Actions

    private func saveAPIKey() {
        Task {
            do {
                try await KeychainService.shared.saveOpenAIKey(apiKey)
                withAnimation { isKeySaved = true }
            } catch {
                appState.setError("Failed to save API key: \(error.localizedDescription)")
            }
        }
    }

    private func completeOnboarding() {
        appState.settings.onboardingCompleted = true
        if appState.sessions.isEmpty {
            appState.createSession()
        }
        dismiss()
    }
}

#Preview {
    OnboardingView()
        .environmentObject(AppState())
        .frame(width: 520, height: 560)
}

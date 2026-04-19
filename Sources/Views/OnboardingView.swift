import SwiftUI

/// Onboarding flow: Welcome → Stealth Check → API Keys → Ready.
///
/// The sheet respects stealth (sharingType = .none is applied by
/// AppDelegate's global window observer). The user must verify at
/// least one AI provider key before proceeding.
struct OnboardingView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var currentStep: Int = 0

    // Provider keys
    @State private var openaiKey: String = ""
    @State private var anthropicKey: String = ""
    @State private var googleKey: String = ""
    @State private var deepgramKey: String = ""

    @State private var openaiStatus: KeyStatus = .empty
    @State private var anthropicStatus: KeyStatus = .empty
    @State private var googleStatus: KeyStatus = .empty
    @State private var deepgramStatus: KeyStatus = .empty

    @State private var expandedProvider: String?
    @State private var stealthConfirmed: Bool = false

    enum KeyStatus: Equatable {
        case empty, testing, valid, invalid(String)
    }

    private let accent = Color(hex: "22C55E")
    private let bg = Color(hex: "0D1117")
    private let surface = Color(hex: "161B22")
    private let border = Color(hex: "30363D")
    private let totalSteps = 4

    private var hasValidAIKey: Bool {
        openaiStatus == .valid || anthropicStatus == .valid || googleStatus == .valid
    }

    var body: some View {
        VStack(spacing: 0) {
            // Step indicator
            HStack(spacing: 0) {
                ForEach(0..<totalSteps, id: \.self) { step in
                    Rectangle()
                        .fill(step <= currentStep ? accent : .white.opacity(0.08))
                        .frame(height: 3)
                        .animation(.easeInOut(duration: 0.3), value: currentStep)
                }
            }

            // Step label
            HStack {
                Text(stepLabel)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.3))
                    .tracking(0.5)
                Spacer()
                Text("\(currentStep + 1) / \(totalSteps)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(accent)
            }
            .padding(.horizontal, 28)
            .padding(.top, 14)

            // Content
            Group {
                switch currentStep {
                case 0: welcomeStep
                case 1: stealthStep
                case 2: apiKeyStep
                case 3: readyStep
                default: EmptyView()
                }
            }
            .transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            ))
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Navigation
            navigationBar
                .padding(.bottom, 20)
        }
        .background(bg)
        .onAppear { loadExistingKeys() }
    }

    private var stepLabel: String {
        switch currentStep {
        case 0: return "WELCOME"
        case 1: return "STEALTH CHECK"
        case 2: return "API KEYS"
        case 3: return "READY"
        default: return ""
        }
    }

    // ---------------------------------------------------------------
    // MARK: - Step 1: Welcome
    // ---------------------------------------------------------------

    private var welcomeStep: some View {
        VStack(spacing: 0) {
            Spacer()

            Group {
                if let url = Bundle.module.url(forResource: "BrainIcon", withExtension: "png"),
                   let nsImg = NSImage(contentsOf: url) {
                    Image(nsImage: nsImg)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 64, weight: .thin))
                        .foregroundStyle(accent.opacity(0.7))
                }
            }
            .frame(width: 100, height: 100)
            .padding(.bottom, 20)

            Text("SoloScreen")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(.white)

            Text("Your invisible AI assistant")
                .font(.system(size: 15))
                .foregroundStyle(.white.opacity(0.45))
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 10) {
                featureRow(icon: "eye.slash.fill",
                           title: "100% Invisible",
                           desc: "Hidden from Zoom, Meet, Teams — all screen share and recordings. Proven stealth.")
                featureRow(icon: "bolt.fill",
                           title: "Multi-AI Provider",
                           desc: "Bring your own key for OpenAI, Claude, or Gemini. Switch models anytime.")
                featureRow(icon: "waveform",
                           title: "Live Listen",
                           desc: "Transcribes system audio in real-time. AI Help button analyzes the conversation instantly.")
                featureRow(icon: "camera.viewfinder",
                           title: "Screenshot Analysis",
                           desc: "Capture your screen and get AI analysis with vision models — no copy-paste needed.")
                featureRow(icon: "keyboard.fill",
                           title: "Keyboard-First",
                           desc: "Every action has a shortcut. Works in extreme stealth with click-through enabled.")
            }
            .padding(.horizontal, 28)
            .padding(.top, 24)

            Spacer()
        }
    }

    private func featureRow(icon: String, title: String, desc: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(accent)
                .frame(width: 28, height: 28)
                .background(Circle().fill(accent.opacity(0.1)))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                Text(desc)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.45))
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(1)
            }
        }
    }

    // ---------------------------------------------------------------
    // MARK: - Step 2: Stealth Check
    // ---------------------------------------------------------------

    private var stealthStep: some View {
        VStack(spacing: 0) {
            Spacer()

            Image(systemName: stealthConfirmed ? "checkmark.shield.fill" : "eye.slash.circle")
                .font(.system(size: 48, weight: .thin))
                .foregroundStyle(stealthConfirmed ? accent : accent.opacity(0.6))
                .padding(.bottom, 16)

            Text(stealthConfirmed ? "You're invisible." : "Let's prove it works")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white.opacity(0.95))

            Text("SoloScreen is hidden from screen share and recordings.\nVerify it yourself — takes 60 seconds.")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.45))
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .padding(.top, 6)
                .padding(.horizontal, 20)

            if !stealthConfirmed {
                VStack(alignment: .leading, spacing: 14) {
                    stealthInstruction(num: 1, text: "Start a meeting on this Mac\n(Zoom, Google Meet, Teams — any app)")
                    stealthInstruction(num: 2, text: "Share your entire screen in the meeting")
                    stealthInstruction(num: 3, text: "Join the same meeting from your phone\nand look at the shared screen")
                    stealthInstruction(num: 4, text: "Confirm this window is **not visible**\non your phone's view")
                }
                .padding(.horizontal, 36)
                .padding(.top, 24)

                Button {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        stealthConfirmed = true
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14))
                        Text("I've verified — I'm invisible")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: 280)
                    .padding(.vertical, 11)
                    .background(accent, in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .padding(.top, 20)
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "lock.shield.fill")
                        .foregroundStyle(accent)
                    Text("Screen capture cannot see SoloScreen")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.55))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(accent.opacity(0.08))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(accent.opacity(0.2), lineWidth: 1))
                )
                .padding(.top, 24)
            }

            Spacer()
        }
    }

    private func stealthInstruction(num: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(num)")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(accent)
                .frame(width: 22, height: 22)
                .background(Circle().fill(accent.opacity(0.12)))

            Text(.init(text))
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.65))
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // ---------------------------------------------------------------
    // MARK: - Step 3: API Keys
    // ---------------------------------------------------------------

    private var apiKeyStep: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                Text("Connect an AI Provider")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white.opacity(0.95))

                Text("Add at least one AI key. Stored in macOS Keychain — never leaves your Mac.")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.4))
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 16)
            .padding(.horizontal, 28)

            ScrollView {
                VStack(spacing: 8) {
                    providerCard(
                        name: "OpenAI", icon: "circle.hexagongrid",
                        key: $openaiKey, status: openaiStatus,
                        providerKey: "openai",
                        keyPrefix: "sk-",
                        url: "https://platform.openai.com/api-keys",
                        urlLabel: "platform.openai.com/api-keys",
                        instructions: [
                            "Sign in or create an account",
                            "Click **Create new secret key**",
                            "Copy the key (starts with `sk-`)",
                            "Add a payment method under **Billing**"
                        ],
                        onSave: { await saveAndTest(key: openaiKey, provider: "openai") }
                    )

                    providerCard(
                        name: "Anthropic (Claude)", icon: "sparkles",
                        key: $anthropicKey, status: anthropicStatus,
                        providerKey: "anthropic",
                        keyPrefix: "sk-ant-",
                        url: "https://console.anthropic.com/settings/keys",
                        urlLabel: "console.anthropic.com/settings/keys",
                        instructions: [
                            "Sign in or create an account",
                            "Click **Create Key** and copy it",
                            "Key starts with `sk-ant-`",
                            "Add credits under **Billing** → **Add funds**"
                        ],
                        onSave: { await saveAndTest(key: anthropicKey, provider: "anthropic") }
                    )

                    providerCard(
                        name: "Google (Gemini)", icon: "diamond",
                        key: $googleKey, status: googleStatus,
                        providerKey: "google",
                        keyPrefix: "AI",
                        url: "https://aistudio.google.com/apikey",
                        urlLabel: "aistudio.google.com/apikey",
                        instructions: [
                            "Sign in with your Google account",
                            "Click **Create API key**",
                            "Copy the key",
                            "Free tier included — no card needed"
                        ],
                        onSave: { await saveAndTest(key: googleKey, provider: "google") }
                    )

                    providerCard(
                        name: "Deepgram (Voice)", icon: "waveform",
                        key: $deepgramKey, status: deepgramStatus,
                        providerKey: "deepgram",
                        keyPrefix: "",
                        url: "https://console.deepgram.com",
                        urlLabel: "console.deepgram.com",
                        instructions: [
                            "Sign up or sign in",
                            "**API Keys** → **Create a New API Key**",
                            "Copy the key",
                            "$200 free credit — no card needed"
                        ],
                        onSave: { await saveAndTest(key: deepgramKey, provider: "deepgram") },
                        isOptional: true,
                        subtitle: "Only needed for Live Listen (system audio)"
                    )
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 12)
            }

            if !hasValidAIKey {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle")
                        .font(.system(size: 11))
                    Text("Verify at least one AI provider key to continue")
                        .font(.system(size: 11))
                }
                .foregroundStyle(.orange.opacity(0.75))
                .padding(.bottom, 8)
            }
        }
    }

    private func providerCard(
        name: String, icon: String,
        key: Binding<String>, status: KeyStatus,
        providerKey: String, keyPrefix: String,
        url: String, urlLabel: String,
        instructions: [String],
        onSave: @escaping () async -> Void,
        isOptional: Bool = false,
        subtitle: String? = nil
    ) -> some View {
        let isExpanded = expandedProvider == providerKey

        return VStack(alignment: .leading, spacing: 0) {
            // Header — whole area is tappable
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    expandedProvider = isExpanded ? nil : providerKey
                }
            } label: {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 6) {
                            Text(name)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.9))
                            if isOptional {
                                Text("Optional")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(.white.opacity(0.3))
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(RoundedRectangle(cornerRadius: 3).fill(.white.opacity(0.05)))
                            }
                        }
                        if let subtitle {
                            Text(subtitle)
                                .font(.system(size: 9))
                                .foregroundStyle(.white.opacity(0.3))
                        }
                    }

                    Spacer()
                    statusBadge(status)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white.opacity(0.3))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider().overlay(border)

                VStack(alignment: .leading, spacing: 10) {
                    // Opens browser. After 3s hides onboarding + main
                    // chat window so user can use the site. Clicking the
                    // floating dot or ⌃⇧Space brings everything back.
                    Button {
                        if let nsURL = URL(string: url) {
                            NSWorkspace.shared.open(nsURL)
                            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                                // Animate onboarding shrinking into the
                                // dot position, then hide everything.
                                if let w = NSApp.windows.first(where: { $0.title == "SoloScreen" && $0.level == .floating }) {
                                    Self.animateCollapseToCircle(window: w) {
                                        // Hide main chat panel after collapse
                                        NotificationCenter.default.post(
                                            name: .soloScreenHideForOnboarding,
                                            object: nil
                                        )
                                    }
                                } else {
                                    NotificationCenter.default.post(
                                        name: .soloScreenHideForOnboarding,
                                        object: nil
                                    )
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.right.square")
                                .font(.system(size: 10))
                            Text(urlLabel)
                                .font(.system(size: 11, weight: .medium))
                                .underline()
                        }
                        .foregroundStyle(accent)
                    }
                    .buttonStyle(.plain)

                    // Step-by-step
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(Array(instructions.enumerated()), id: \.offset) { i, text in
                            HStack(alignment: .top, spacing: 6) {
                                Text("\(i + 1).")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundStyle(accent.opacity(0.6))
                                    .frame(width: 14, alignment: .trailing)
                                Text(.init(text))
                                    .font(.system(size: 10))
                                    .foregroundStyle(.white.opacity(0.5))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }

                    // Key input
                    HStack(spacing: 6) {
                        PasteableSecureField(
                            placeholder: keyPrefix.isEmpty ? "Paste API key" : "Paste key (\(keyPrefix)…)",
                            text: key
                        )
                        .frame(height: 18)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(bg)
                                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(border, lineWidth: 1))
                        )

                        Button {
                            Task { await onSave() }
                        } label: {
                            Group {
                                if status == .testing {
                                    ProgressView().controlSize(.mini)
                                } else {
                                    Text("Save & Test")
                                        .font(.system(size: 10, weight: .semibold))
                                }
                            }
                            .foregroundStyle(.white)
                            .frame(width: 76, height: 32)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(key.wrappedValue.isEmpty ? accent.opacity(0.25) : accent)
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(key.wrappedValue.isEmpty || status == .testing)
                    }

                    if case .invalid(let msg) = status {
                        Text(msg)
                            .font(.system(size: 9))
                            .foregroundStyle(.red.opacity(0.75))
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(surface)
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(border, lineWidth: 1))
        )
    }

    private func statusBadge(_ status: KeyStatus) -> some View {
        Group {
            switch status {
            case .empty:
                EmptyView()
            case .testing:
                ProgressView().controlSize(.mini)
            case .valid:
                HStack(spacing: 3) {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 10))
                    Text("Verified").font(.system(size: 9, weight: .semibold))
                }
                .foregroundStyle(.green)
            case .invalid:
                HStack(spacing: 3) {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 10))
                    Text("Failed").font(.system(size: 9, weight: .semibold))
                }
                .foregroundStyle(.red.opacity(0.8))
            }
        }
    }

    // ---------------------------------------------------------------
    // MARK: - Step 4: Ready
    // ---------------------------------------------------------------

    private var readyStep: some View {
        VStack(spacing: 0) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 52))
                .foregroundStyle(accent)
                .padding(.bottom, 16)

            Text("You're all set")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.white.opacity(0.95))

            Text("SoloScreen is ready to use.\nIt stays invisible to screen share and recordings.")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.45))
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .padding(.top, 6)

            Spacer()
        }
    }

    // ---------------------------------------------------------------
    // MARK: - Navigation
    // ---------------------------------------------------------------

    private var navigationBar: some View {
        HStack(spacing: 16) {
            if currentStep > 0 {
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) { currentStep -= 1 }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left").font(.system(size: 10, weight: .bold))
                        Text("Back").font(.system(size: 13))
                    }
                    .foregroundStyle(.white.opacity(0.45))
                }
                .buttonStyle(.plain)
            }

            Spacer()

            // Skip for stealth step
            if currentStep == 1 && !stealthConfirmed {
                Button("Skip for now") {
                    withAnimation(.easeInOut(duration: 0.25)) { currentStep += 1 }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.3))
                .font(.system(size: 12))
            }

            Button {
                if currentStep < totalSteps - 1 {
                    withAnimation(.easeInOut(duration: 0.25)) { currentStep += 1 }
                } else {
                    completeOnboarding()
                }
            } label: {
                Text(currentStep < totalSteps - 1 ? "Continue" : "Get Started")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(canProceed ? accent : accent.opacity(0.25))
                    )
            }
            .buttonStyle(.plain)
            .disabled(!canProceed)
        }
        .padding(.horizontal, 28)
    }

    private var canProceed: Bool {
        switch currentStep {
        case 2: return hasValidAIKey
        default: return true
        }
    }

    // ---------------------------------------------------------------
    // MARK: - Key Logic
    // ---------------------------------------------------------------

    private func loadExistingKeys() {
        Task {
            let oai = await KeychainService.shared.loadOpenAIKey() ?? ""
            let ant = await KeychainService.shared.loadAnthropicKey() ?? ""
            let goo = await KeychainService.shared.loadGoogleKey() ?? ""
            let dg  = await KeychainService.shared.loadDeepgramKey() ?? ""
            await MainActor.run {
                if !oai.isEmpty { openaiKey = oai; openaiStatus = .valid }
                if !ant.isEmpty { anthropicKey = ant; anthropicStatus = .valid }
                if !goo.isEmpty { googleKey = goo; googleStatus = .valid }
                if !dg.isEmpty  { deepgramKey = dg; deepgramStatus = .valid }
            }
        }
    }

    private func saveAndTest(key: String, provider: String) async {
        guard !key.isEmpty else { return }
        await MainActor.run { setStatus(provider, .testing) }

        do {
            try await KeychainService.shared.saveKey(key, forProvider: provider)
            let ok = await testAPIKey(key: key, provider: provider)
            await MainActor.run {
                if ok {
                    setStatus(provider, .valid)
                    if provider != "deepgram" {
                        appState.settings.selectedProvider = provider
                    }
                    Task { await appState.refreshKeyStatuses() }
                } else {
                    setStatus(provider, .invalid("Invalid key — check it's correct and has billing enabled."))
                }
            }
        } catch {
            await MainActor.run {
                setStatus(provider, .invalid(error.localizedDescription))
            }
        }
    }

    private func setStatus(_ provider: String, _ status: KeyStatus) {
        switch provider {
        case "openai":    openaiStatus = status
        case "anthropic": anthropicStatus = status
        case "google":    googleStatus = status
        case "deepgram":  deepgramStatus = status
        default: break
        }
    }

    private func testAPIKey(key: String, provider: String) async -> Bool {
        do {
            switch provider {
            case "openai":
                var req = URLRequest(url: URL(string: "https://api.openai.com/v1/models")!)
                req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
                let (_, resp) = try await URLSession.shared.data(for: req)
                return (resp as? HTTPURLResponse)?.statusCode == 200

            case "anthropic":
                var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
                req.httpMethod = "POST"
                req.setValue(key, forHTTPHeaderField: "x-api-key")
                req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                let body: [String: Any] = [
                    "model": "claude-3-5-haiku-latest",
                    "max_tokens": 1,
                    "messages": [["role": "user", "content": "hi"]]
                ]
                req.httpBody = try JSONSerialization.data(withJSONObject: body)
                let (_, resp) = try await URLSession.shared.data(for: req)
                return (resp as? HTTPURLResponse)?.statusCode == 200

            case "google":
                let req = URLRequest(url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models?key=\(key)")!)
                let (_, resp) = try await URLSession.shared.data(for: req)
                return (resp as? HTTPURLResponse)?.statusCode == 200

            case "deepgram":
                var req = URLRequest(url: URL(string: "https://api.deepgram.com/v1/projects")!)
                req.setValue("Token \(key)", forHTTPHeaderField: "Authorization")
                let (_, resp) = try await URLSession.shared.data(for: req)
                return (resp as? HTTPURLResponse)?.statusCode == 200

            default: return false
            }
        } catch { return false }
    }

    /// Animate the window shrinking + fading toward the bottom-right
    /// corner (where the minimized dot lives), then hide it.
    private static func animateCollapseToCircle(window: NSWindow, completion: @escaping () -> Void) {
        let screen = window.screen ?? NSScreen.main ?? NSScreen.screens.first
        let screenFrame = screen?.visibleFrame ?? NSRect.zero
        // Target: 44×44 dot at bottom-right, matching StealthWindowManager's dot position.
        let dotSize: CGFloat = 44
        let targetFrame = NSRect(
            x: screenFrame.maxX - dotSize - 16,
            y: screenFrame.minY + 16,
            width: dotSize,
            height: dotSize
        )

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.4
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setFrame(targetFrame, display: true)
            window.animator().alphaValue = 0
        }, completionHandler: {
            window.level = .normal
            window.orderOut(nil)
            // Reset frame for when it reappears.
            window.setFrame(NSRect(x: 0, y: 0, width: 560, height: 640), display: false)
            window.alphaValue = 1.0
            window.center()
            completion()
        })
    }

    private func completeOnboarding() {
        appState.settings.onboardingCompleted = true
        appState.saveSettings()
        if appState.sessions.isEmpty {
            appState.createSession()
        }
        Task { await appState.refreshKeyStatuses() }
        // Close the onboarding — works for both .sheet and NSWindow.
        appState.showOnboarding = false
        dismiss()
    }
}

#Preview {
    OnboardingView()
        .environmentObject(AppState())
        .frame(width: 560, height: 640)
}

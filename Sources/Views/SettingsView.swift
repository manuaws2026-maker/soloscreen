import SwiftUI
import Security

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab: SettingsTab = .provider

    private let bgColor = Color(hex: "0D1117")
    private let surfaceColor = Color(hex: "161B22")
    private let borderColor = Color(hex: "30363D")
    private let accentTeal = Color(hex: "00BCD4")

    enum SettingsTab: String, CaseIterable {
        case provider = "AI Provider"
        case transcription = "Transcription"
        case appearance = "Appearance"
        case about = "About"

        var icon: String {
            switch self {
            case .provider: return "cpu"
            case .transcription: return "waveform"
            case .appearance: return "paintbrush"
            case .about: return "info.circle"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header

            Divider().overlay(borderColor)

            HStack(spacing: 0) {
                // Tab sidebar
                tabSidebar

                Divider().overlay(borderColor)

                // Content
                tabContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(bgColor)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Settings")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.white.opacity(0.4))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - Tab Sidebar

    private var tabSidebar: some View {
        VStack(spacing: 2) {
            ForEach(SettingsTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        selectedTab = tab
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 13))
                            .frame(width: 18)
                        Text(tab.rawValue)
                            .font(.system(size: 13))
                        Spacer()
                    }
                    .foregroundStyle(selectedTab == tab ? accentTeal : .white.opacity(0.6))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(selectedTab == tab ? accentTeal.opacity(0.1) : Color.clear)
                    )
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(8)
        .frame(width: 160)
        .background(surfaceColor)
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContent: some View {
        ScrollView {
            switch selectedTab {
            case .provider:
                ProviderSettingsTab()
            case .transcription:
                TranscriptionSettingsTab()
            case .appearance:
                AppearanceSettingsTab()
            case .about:
                AboutSettingsTab()
            }
        }
    }
}

// MARK: - Provider Settings Tab

private struct ProviderSettingsTab: View {
    @EnvironmentObject var appState: AppState
    @State private var apiKey: String = ""
    @State private var isKeySaved: Bool = false
    @State private var isTesting: Bool = false
    @State private var testResult: TestResult?

    private let accentTeal = Color(hex: "00BCD4")
    private let surfaceColor = Color(hex: "161B22")
    private let borderColor = Color(hex: "30363D")

    private let providers = ["OpenAI", "Claude", "Google"]

    enum TestResult {
        case success, failure(String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Provider picker
            settingsSection("Provider") {
                Picker("Provider", selection: $appState.settings.selectedProvider) {
                    ForEach(providers, id: \.self) { provider in
                        Text(provider).tag(provider)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                if appState.settings.selectedProvider != "OpenAI" {
                    HStack(spacing: 6) {
                        Image(systemName: "clock")
                            .font(.system(size: 11))
                        Text("\(appState.settings.selectedProvider) support coming soon")
                            .font(.system(size: 12))
                    }
                    .foregroundStyle(.yellow.opacity(0.7))
                    .padding(.top, 4)
                }
            }

            // Model picker
            settingsSection("Model") {
                let models = ModelCatalog.models(for: appState.settings.selectedProvider)
                VStack(spacing: 8) {
                    ForEach(models) { model in
                        modelCard(model, isSelected: appState.settings.selectedModel == model.id)
                    }
                }
            }

            // API key
            settingsSection("API Key") {
                HStack(spacing: 8) {
                    SecureField("Enter your API key", text: $apiKey)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(hex: "0D1117"))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .strokeBorder(borderColor, lineWidth: 1)
                                )
                        )

                    if isKeySaved {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.system(size: 16))
                            .transition(.scale.combined(with: .opacity))
                    }

                    Button("Save") {
                        saveAPIKey()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(accentTeal)
                    .disabled(apiKey.isEmpty)
                }

                // Test connection
                HStack(spacing: 8) {
                    Button {
                        testConnection()
                    } label: {
                        HStack(spacing: 4) {
                            if isTesting {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "bolt")
                                    .font(.system(size: 11))
                            }
                            Text("Test Connection")
                                .font(.system(size: 12))
                        }
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(surfaceColor)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .strokeBorder(borderColor, lineWidth: 1)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isTesting || !isKeySaved)

                    if let testResult {
                        switch testResult {
                        case .success:
                            Label("Connected", systemImage: "checkmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(.green)
                        case .failure(let message):
                            Label(message, systemImage: "xmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(.red)
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(20)
        .onAppear {
            loadSavedKey()
        }
    }

    private func modelCard(_ model: ModelInfo, isSelected: Bool) -> some View {
        Button {
            appState.settings.selectedModel = model.id
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(model.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.9))

                    Spacer()

                    Text(model.costTier.displayLabel)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(accentTeal)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(accentTeal.opacity(0.12)))

                    if model.supportsVision {
                        Image(systemName: "eye")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                }

                Text(model.description)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(2)

                HStack(spacing: 12) {
                    ForEach(model.strengths.prefix(2), id: \.self) { strength in
                        HStack(spacing: 3) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.green.opacity(0.7))
                            Text(strength)
                                .font(.system(size: 10))
                                .foregroundStyle(.white.opacity(0.45))
                        }
                    }

                    ForEach(model.weaknesses.prefix(1), id: \.self) { weakness in
                        HStack(spacing: 3) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 9))
                                .foregroundStyle(.yellow.opacity(0.7))
                            Text(weakness)
                                .font(.system(size: 10))
                                .foregroundStyle(.white.opacity(0.45))
                        }
                    }
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? accentTeal.opacity(0.08) : Color(hex: "0D1117"))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(isSelected ? accentTeal.opacity(0.4) : Color(hex: "30363D"), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func saveAPIKey() {
        let data = apiKey.data(using: .utf8)!
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "subtleai-\(appState.settings.selectedProvider.lowercased())-key",
            kSecValueData as String: data
        ]
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        withAnimation {
            isKeySaved = status == errSecSuccess
        }
    }

    private func loadSavedKey() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "subtleai-\(appState.settings.selectedProvider.lowercased())-key",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)
        isKeySaved = status == errSecSuccess
    }

    private func testConnection() {
        isTesting = true
        testResult = nil
        // Simulate connection test
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            isTesting = false
            testResult = isKeySaved ? .success : .failure("No API key saved")
        }
    }
}

// MARK: - Transcription Settings Tab

private struct TranscriptionSettingsTab: View {
    @EnvironmentObject var appState: AppState
    @State private var deepgramKey: String = ""
    @State private var isKeySaved: Bool = false

    private let accentTeal = Color(hex: "00BCD4")
    private let borderColor = Color(hex: "30363D")

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            settingsSection("Transcription Provider") {
                Picker("Provider", selection: $appState.settings.transcriptionProvider) {
                    Text("Deepgram").tag("Deepgram")
                    Text("Whisper (Local)").tag("Whisper")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            if appState.settings.transcriptionProvider == "Deepgram" {
                settingsSection("Deepgram API Key") {
                    HStack(spacing: 8) {
                        SecureField("Enter Deepgram API key", text: $deepgramKey)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(hex: "0D1117"))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .strokeBorder(borderColor, lineWidth: 1)
                                    )
                            )

                        if isKeySaved {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.system(size: 16))
                        }

                        Button("Save") {
                            saveDeepgramKey()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(accentTeal)
                        .disabled(deepgramKey.isEmpty)
                    }

                    Text("Get a free API key at deepgram.com")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.3))
                }
            } else {
                settingsSection("Whisper (Local)") {
                    HStack(spacing: 8) {
                        Image(systemName: "clock")
                            .font(.system(size: 13))
                            .foregroundStyle(.yellow.opacity(0.7))
                        Text("Local Whisper transcription is coming soon. It will run entirely on-device with no API key required.")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.yellow.opacity(0.05))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(.yellow.opacity(0.15), lineWidth: 1)
                            )
                    )
                }
            }
        }
        .padding(20)
        .onAppear {
            loadDeepgramKey()
        }
    }

    private func saveDeepgramKey() {
        let data = deepgramKey.data(using: .utf8)!
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "subtleai-deepgram-key",
            kSecValueData as String: data
        ]
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        withAnimation {
            isKeySaved = status == errSecSuccess
        }
    }

    private func loadDeepgramKey() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "subtleai-deepgram-key",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)
        isKeySaved = status == errSecSuccess
    }
}

// MARK: - Appearance Settings Tab

private struct AppearanceSettingsTab: View {
    @EnvironmentObject var appState: AppState

    private let accentTeal = Color(hex: "00BCD4")
    private let borderColor = Color(hex: "30363D")

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            settingsSection("Window Opacity") {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Opacity")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.6))
                        Spacer()
                        Text("\(Int(appState.settings.overlayOpacity * 100))%")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundStyle(accentTeal)
                    }

                    Slider(value: $appState.settings.overlayOpacity, in: 0.3...1.0, step: 0.05)
                        .tint(accentTeal)

                    Text("Lower opacity makes the window more transparent")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.3))
                }
            }

            settingsSection("Font Size") {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Size")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.6))
                        Spacer()
                        Text("\(Int(appState.settings.fontSize))pt")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundStyle(accentTeal)
                    }

                    Slider(value: $appState.settings.fontSize, in: 12...20, step: 1)
                        .tint(accentTeal)
                }
            }

            settingsSection("Stealth Mode") {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle(isOn: $appState.settings.stealthEnabled) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Stealth Mode")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.white.opacity(0.9))
                            Text("Hide from screen sharing and recordings")
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.4))
                        }
                    }
                    .toggleStyle(.switch)
                    .tint(accentTeal)

                    Divider().overlay(borderColor)

                    Toggle(isOn: $appState.settings.extremeStealthEnabled) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Extreme Stealth")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.white.opacity(0.9))
                            Text("Additionally hides from window lists, Cmd+Tab, and mission control. The app will only be accessible via its keyboard shortcut.")
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.4))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .toggleStyle(.switch)
                    .tint(accentTeal)
                    .disabled(!appState.settings.stealthEnabled)
                    .opacity(appState.settings.stealthEnabled ? 1.0 : 0.5)
                }
            }
        }
        .padding(20)
    }
}

// MARK: - About Settings Tab

private struct AboutSettingsTab: View {
    private let accentTeal = Color(hex: "00BCD4")
    private let surfaceColor = Color(hex: "161B22")
    private let borderColor = Color(hex: "30363D")

    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // App info
            settingsSection("") {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14)
                            .fill(accentTeal.opacity(0.15))
                            .frame(width: 56, height: 56)
                        Image(systemName: "eye.slash.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(accentTeal)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("SubtleAI")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.white.opacity(0.9))
                        Text("Version 1.0.0")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.4))
                        Text("Invisible AI Chat Assistant")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
            }

            // Free tier
            settingsSection("Free Tier") {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Free messages remaining")
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.7))
                        Text("\(appState.settings.freeMessagesRemaining) of \(UserSettings.freeMessageLimit) messages")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.4))
                    }

                    Spacer()

                    ZStack {
                        Circle()
                            .stroke(.white.opacity(0.1), lineWidth: 4)
                            .frame(width: 44, height: 44)
                        Circle()
                            .trim(from: 0, to: CGFloat(appState.settings.freeMessagesRemaining) / CGFloat(UserSettings.freeMessageLimit))
                            .stroke(accentTeal, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                            .frame(width: 44, height: 44)
                            .rotationEffect(.degrees(-90))
                        Text("\(appState.settings.freeMessagesRemaining)")
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundStyle(accentTeal)
                    }
                }
            }

            // Keyboard shortcuts
            settingsSection("Keyboard Shortcuts") {
                VStack(spacing: 8) {
                    shortcutRow(keys: "Cmd + Shift + Space", description: "Toggle window visibility")
                    shortcutRow(keys: "Cmd + N", description: "New chat")
                    shortcutRow(keys: "Cmd + Shift + S", description: "Capture screenshot")
                    shortcutRow(keys: "Cmd + Shift + M", description: "Toggle microphone")
                    shortcutRow(keys: "Cmd + Shift + T", description: "Toggle transcription")
                    shortcutRow(keys: "Cmd + ,", description: "Open settings")
                    shortcutRow(keys: "Enter", description: "Send message")
                    shortcutRow(keys: "Shift + Enter", description: "New line")
                }
            }
        }
        .padding(20)
    }

    private func shortcutRow(keys: String, description: String) -> some View {
        HStack {
            Text(keys)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(accentTeal.opacity(0.8))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(accentTeal.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .strokeBorder(accentTeal.opacity(0.2), lineWidth: 1)
                        )
                )

            Spacer()

            Text(description)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.5))
        }
    }
}

// MARK: - Shared Section Helper

private func settingsSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 10) {
        if !title.isEmpty {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.4))
                .textCase(.uppercase)
                .tracking(0.5)
        }
        content()
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppState())
        .frame(width: 560, height: 480)
}

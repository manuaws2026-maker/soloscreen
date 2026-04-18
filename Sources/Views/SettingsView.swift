import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab: SettingsTab = .provider

    private let bgColor = Color(hex: "0D1117")
    private let surfaceColor = Color(hex: "161B22")
    private let borderColor = Color(hex: "30363D")
    private let accentTeal = Color(hex: "22C55E")

    enum SettingsTab: String, CaseIterable {
        case provider = "AI Provider"
        case transcription = "Transcription"
        case templates = "Templates"
        case appearance = "Appearance"
        case about = "About"

        var icon: String {
            switch self {
            case .provider: return "cpu"
            case .transcription: return "waveform"
            case .templates: return "doc.text.below.ecg"
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
        .onAppear {
            applyInitialTabIfRequested()
        }
        .onChange(of: appState.settingsInitialTab) { _, _ in
            applyInitialTabIfRequested()
        }
    }

    private func applyInitialTabIfRequested() {
        if let raw = appState.settingsInitialTab,
           let tab = SettingsTab(rawValue: raw) {
            selectedTab = tab
            appState.settingsInitialTab = nil
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Settings")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
            Spacer()
            // Close button removed — macOS traffic-light red button on the
            // NSWindow titlebar handles dismissal via NSWindowDelegate.
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
        .frame(width: 180)
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
            case .templates:
                TemplatesSettingsTab()
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

    private let accentTeal = Color(hex: "22C55E")
    private let surfaceColor = Color(hex: "161B22")
    private let borderColor = Color(hex: "30363D")

    private let providers: [(id: String, label: String)] = [
        ("openai", "OpenAI"),
        ("anthropic", "Claude"),
        ("google", "Google"),
    ]

    enum TestResult {
        case success, failure(String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Provider picker
            settingsSection("Provider") {
                Picker("Provider", selection: $appState.settings.selectedProvider) {
                    ForEach(providers, id: \.id) { provider in
                        Text(provider.label).tag(provider.id)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .onChange(of: appState.settings.selectedProvider) { _, newProvider in
                    // Auto-select the first model for the new provider.
                    if let firstModel = ModelCatalog.models(for: newProvider).first {
                        appState.settings.selectedModel = firstModel.id
                    }
                    // Reload key state for the new provider.
                    loadSavedKey()
                    testResult = nil
                }

                Text(providerHint)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.35))
                    .padding(.top, 2)
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

            // Per-feature model overrides
            settingsSection("Feature Models") {
                VStack(spacing: 8) {
                    Text("Some features default to a faster, cheaper sibling of your selected model so they stay snappy. You can override each one below.")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.55))
                        .fixedSize(horizontal: false, vertical: true)

                    ForEach(AppState.AppFeature.allCases) { feature in
                        featureModelRow(feature: feature)
                    }
                }
            }

            // API key
            settingsSection("API Key") {
                HStack(spacing: 8) {
                    PasteableSecureField(placeholder: "Enter your API key", text: $apiKey)
                        .frame(height: 20)
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

    @ViewBuilder
    private func featureModelRow(feature: AppState.AppFeature) -> some View {
        let provider = appState.settings.selectedProvider
        // Only show models that actually support this feature — e.g.
        // Screenshot Analysis needs vision, so text-only models are hidden.
        let allModels = ModelCatalog.models(for: provider)
        let compatibleModels = feature.requiresVision
            ? allModels.filter { $0.supportsVision }
            : allModels
        let modelIds: [String] = compatibleModels.map(\.id)
        let modelNames: [String] = compatibleModels.map(\.name)
        let binding = Binding<String>(
            get: {
                switch feature {
                case .liveHelp:   return appState.settings.liveHelpModelOverride ?? "__auto__"
                case .screenshot: return appState.settings.screenshotModelOverride ?? "__auto__"
                }
            },
            set: { newValue in
                let override: String? = newValue == "__auto__" ? nil : newValue
                switch feature {
                case .liveHelp:   appState.settings.liveHelpModelOverride = override
                case .screenshot: appState.settings.screenshotModelOverride = override
                }
            }
        )
        let resolved = appState.effectiveModel(for: feature)

        return HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(feature.rawValue)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                Text(feature.description)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))
                    .fixedSize(horizontal: false, vertical: true)
                Text("Using: \(resolved)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(accentTeal.opacity(0.85))
            }

            Spacer()

            Picker(selection: binding, label: Text("")) {
                Text("Auto (cheapest fast sibling)").tag("__auto__")
                ForEach(modelIds.indices, id: \.self) { i in
                    Text(modelNames[i]).tag(modelIds[i])
                }
            }
            .labelsHidden()
            .frame(width: 200)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(hex: "161B22"))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(borderColor, lineWidth: 1))
        )
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
        Task {
            do {
                try await KeychainService.shared.saveKey(apiKey, forProvider: appState.settings.selectedProvider)
                await MainActor.run {
                    withAnimation { isKeySaved = true }
                }
            } catch {
                await MainActor.run {
                    withAnimation { isKeySaved = false }
                }
            }
        }
    }

    private func loadSavedKey() {
        Task {
            let key = await KeychainService.shared.loadKey(forProvider: appState.settings.selectedProvider)
            await MainActor.run {
                isKeySaved = key != nil && !(key?.isEmpty ?? true)
            }
        }
    }

    private var providerHint: String {
        switch appState.settings.selectedProvider {
        case "openai":    return "Get a key at platform.openai.com"
        case "anthropic": return "Get a key at console.anthropic.com"
        case "google":    return "Get a key at aistudio.google.com"
        default:          return ""
        }
    }

    private func testConnection() {
        guard isKeySaved else {
            testResult = .failure("No API key saved")
            return
        }
        isTesting = true
        testResult = nil

        Task {
            do {
                let key = await KeychainService.shared.loadKey(forProvider: appState.settings.selectedProvider)
                guard let key, !key.isEmpty else {
                    await MainActor.run {
                        isTesting = false
                        testResult = .failure("No API key saved")
                    }
                    return
                }

                let testMessages = [LLMMessage.text(role: .user, content: "Hi")]
                let options = LLMRequestOptions(maxTokens: 5)
                let provider = appState.settings.selectedProvider

                // Use the LLM router to send a minimal request.
                let router = LLMRouter()
                guard let llmProvider = router.provider(for: provider) else {
                    await MainActor.run {
                        isTesting = false
                        testResult = .failure("Provider not found")
                    }
                    return
                }

                _ = try await llmProvider.complete(
                    messages: testMessages,
                    model: appState.settings.selectedModel,
                    apiKey: key,
                    options: options
                )

                await MainActor.run {
                    isTesting = false
                    testResult = .success
                }
            } catch {
                await MainActor.run {
                    isTesting = false
                    let message = error.localizedDescription
                    testResult = .failure(String(message.prefix(80)))
                }
            }
        }
    }
}

// MARK: - Transcription Settings Tab

private struct TranscriptionSettingsTab: View {
    @EnvironmentObject var appState: AppState
    @State private var deepgramKey: String = ""
    @State private var pendingActivation: String?  // provider id awaiting confirmation

    private let accentTeal = Color(hex: "22C55E")
    private let borderColor = Color(hex: "30363D")
    private let surfaceColor = Color(hex: "161B22")

    private var hasDeepgramKey: Bool { appState.hasDeepgramKey }
    private var hasOpenAIKey: Bool { appState.hasOpenAIKey }

    private var activeProvider: String {
        appState.settings.transcriptionProvider.lowercased() == "deepgram" ? "deepgram" : "openai"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Deepgram card
            providerCard(
                id: "deepgram",
                name: "Deepgram",
                icon: "waveform",
                description: "Live streaming + batch transcription. Uses your Deepgram API key.",
                configured: hasDeepgramKey,
                configureHint: "Paste a Deepgram API key below."
            )

            // Deepgram key entry (only when Deepgram card is active-or-being-configured)
            settingsSection("Deepgram API Key") {
                HStack(spacing: 8) {
                    PasteableSecureField(placeholder: "Enter Deepgram API key", text: $deepgramKey)
                        .frame(height: 20)
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

                    if hasDeepgramKey {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.system(size: 16))
                    }

                    Button("Save") { saveDeepgramKey() }
                        .buttonStyle(.borderedProminent)
                        .tint(accentTeal)
                        .disabled(deepgramKey.isEmpty)
                }

                Text("Get a free API key at deepgram.com — required for live transcription of system audio.")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.3))
            }

            // OpenAI Whisper card
            providerCard(
                id: "openai",
                name: "OpenAI Whisper",
                icon: "brain.head.profile",
                description: "Batch transcription via whisper-1. Reuses your OpenAI chat key.",
                configured: hasOpenAIKey,
                configureHint: "Add an OpenAI key in the API Keys tab."
            )

            Text("Note: live transcription of system audio requires Deepgram. OpenAI Whisper supports mic-recording transcription only.")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.35))
                .padding(.top, 4)

            Spacer()
        }
        .padding(20)
        .onAppear {
            Task { await appState.refreshKeyStatuses() }
        }
        .alert(
            "Switch transcription provider?",
            isPresented: Binding(
                get: { pendingActivation != nil },
                set: { if !$0 { pendingActivation = nil } }
            ),
            presenting: pendingActivation
        ) { newProvider in
            Button("Cancel", role: .cancel) { pendingActivation = nil }
            Button(activationButtonLabel(for: newProvider)) {
                appState.settings.transcriptionProvider = newProvider
                pendingActivation = nil
            }
        } message: { newProvider in
            Text("\(displayName(for: activeProvider)) will be deactivated and \(displayName(for: newProvider)) activated. You can switch back anytime.")
        }
    }

    // MARK: - Card

    @ViewBuilder
    private func providerCard(
        id: String,
        name: String,
        icon: String,
        description: String,
        configured: Bool,
        configureHint: String
    ) -> some View {
        let isActive = (activeProvider == id)

        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(isActive ? accentTeal : .white.opacity(0.5))
                .frame(width: 28, height: 28)
                .background(
                    Circle().fill((isActive ? accentTeal : Color.white).opacity(0.08))
                )

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.95))
                    if isActive {
                        Text("ACTIVE")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .tracking(0.5)
                            .foregroundStyle(.black)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(accentTeal))
                    }
                }

                Text(description)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)

                // Status row + hint, stacked so the hint wraps on its own line.
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(configured ? Color.green : Color.yellow.opacity(0.85))
                            .frame(width: 6, height: 6)
                        Text(configured ? "Configured" : "No API key")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(configured ? 0.6 : 0.75))
                    }
                    if !configured {
                        Text(configureHint)
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.4))
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.leading, 12)
                    }
                }
                .padding(.top, 2)
            }

            Spacer()

            if !isActive && configured {
                Button {
                    requestActivate(id)
                } label: {
                    Text("Activate")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(accentTeal)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(accentTeal.opacity(0.12))
                                .overlay(Capsule().strokeBorder(accentTeal.opacity(0.4), lineWidth: 1))
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(surfaceColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(isActive ? accentTeal.opacity(0.45) : borderColor, lineWidth: 1)
                )
        )
    }

    // MARK: - Activation flow

    private func requestActivate(_ id: String) {
        // If nothing meaningful is active yet (or same), just activate silently.
        let current = activeProvider
        let currentHasKey = (current == "deepgram" && hasDeepgramKey) || (current == "openai" && hasOpenAIKey)
        if !currentHasKey || current == id {
            appState.settings.transcriptionProvider = id
        } else {
            // Ask for confirmation when swapping away from an active, configured provider.
            pendingActivation = id
        }
    }

    private func displayName(for id: String) -> String {
        id == "deepgram" ? "Deepgram" : "OpenAI Whisper"
    }

    private func activationButtonLabel(for id: String) -> String {
        "Use \(displayName(for: id))"
    }

    // MARK: - Keychain I/O

    private func saveDeepgramKey() {
        Task {
            try? await KeychainService.shared.saveDeepgramKey(deepgramKey)
            await appState.refreshKeyStatuses()
        }
    }
}

// MARK: - Templates Settings Tab

private struct TemplatesSettingsTab: View {
    @EnvironmentObject var appState: AppState
    @State private var editingTemplate: ChatTemplate?
    @State private var viewingTemplate: ChatTemplate?
    @State private var isCreatingNew: Bool = false

    private let accentTeal = Color(hex: "22C55E")
    private let borderColor = Color(hex: "30363D")
    private let surfaceColor = Color(hex: "161B22")

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Use templates to guide how the AI responds in a new chat. Built-in templates are read-only; you can duplicate one by creating a new template with the same prompt.")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)

                Spacer()

                Button {
                    isCreatingNew = true
                } label: {
                    Label("New Template", systemImage: "plus")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(accentTeal)
            }

            // Default coding language — applied automatically to coding /
            // system-design chats. Shown once as a picker on the first such
            // chat; from then on lives here.
            HStack(spacing: 10) {
                Image(systemName: "keyboard")
                    .font(.system(size: 13))
                    .foregroundStyle(accentTeal)
                Text("Default coding language")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))

                Spacer()

                Picker("", selection: Binding(
                    get: { appState.settings.preferredCodingLanguage ?? "—" },
                    set: { newValue in
                        appState.settings.preferredCodingLanguage = (newValue == "—") ? nil : newValue
                    }
                )) {
                    Text("Not set").tag("—")
                    ForEach(LanguagePickerModal.choices, id: \.self) { lang in
                        Text(lang).tag(lang)
                    }
                }
                .labelsHidden()
                .frame(width: 160)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(surfaceColor)
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(borderColor, lineWidth: 1))
            )

            sectionHeader("Built-in")
            VStack(spacing: 8) {
                ForEach(ChatTemplate.builtIns) { tpl in
                    templateRow(tpl)
                }
            }

            if !appState.userTemplates.isEmpty {
                sectionHeader("My Templates")
                VStack(spacing: 8) {
                    ForEach(appState.userTemplates) { tpl in
                        templateRow(tpl)
                    }
                }
            }

            Spacer(minLength: 20)
        }
        .padding(20)
        .sheet(item: $editingTemplate) { tpl in
            TemplateEditorSheet(template: tpl, mode: .edit)
                .environmentObject(appState)
        }
        .sheet(item: $viewingTemplate) { tpl in
            TemplateEditorSheet(template: tpl, mode: .view)
                .environmentObject(appState)
        }
        .sheet(isPresented: $isCreatingNew) {
            TemplateEditorSheet(
                template: ChatTemplate(
                    name: "",
                    description: "",
                    icon: "sparkles",
                    systemPrompt: ""
                ),
                mode: .create
            )
            .environmentObject(appState)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .bold))
            .tracking(0.5)
            .foregroundStyle(.white.opacity(0.35))
    }

    private func templateRow(_ tpl: ChatTemplate) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: tpl.icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(accentTeal)
                .frame(width: 28, height: 28)
                .background(Circle().fill(accentTeal.opacity(0.12)))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(tpl.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.95))
                    if tpl.isBuiltIn {
                        Text("BUILT-IN")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .tracking(0.5)
                            .foregroundStyle(.white.opacity(0.5))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(.white.opacity(0.08)))
                    }
                }
                Text(tpl.description)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            if tpl.isBuiltIn {
                Button("View") { viewingTemplate = tpl }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            } else {
                HStack(spacing: 6) {
                    Button("Edit") { editingTemplate = tpl }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    Button(role: .destructive) {
                        appState.deleteUserTemplate(tpl.id)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(surfaceColor)
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(borderColor, lineWidth: 1))
        )
    }
}

// MARK: - Template Editor Sheet

private struct TemplateEditorSheet: View {
    enum Mode { case create, edit, view }

    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State var template: ChatTemplate
    let mode: Mode

    private let accentTeal = Color(hex: "22C55E")
    private let borderColor = Color(hex: "30363D")
    private let surfaceColor = Color(hex: "161B22")

    private static let iconChoices: [String] = [
        "sparkles", "chevron.left.forwardslash.chevron.right", "folder.fill",
        "ant.fill", "square.stack.3d.up.fill", "pencil.and.list.clipboard",
        "book.fill", "magnifyingglass", "brain.head.profile", "terminal.fill",
        "doc.text.fill", "paintbrush.fill", "lightbulb.fill", "bubble.left.fill",
        "checkmark.seal.fill", "megaphone.fill"
    ]

    private var isReadOnly: Bool { mode == .view }
    private var canSave: Bool {
        !template.name.trimmingCharacters(in: .whitespaces).isEmpty &&
        !template.systemPrompt.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(headerTitle)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.95))
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

            // Name
            VStack(alignment: .leading, spacing: 4) {
                fieldLabel("Name")
                TextField("e.g. Code Review Buddy", text: $template.name)
                    .textFieldStyle(.plain)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(surfaceColor).overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(borderColor, lineWidth: 1)))
                    .disabled(isReadOnly)
            }

            // Description
            VStack(alignment: .leading, spacing: 4) {
                fieldLabel("Description (shown in the picker)")
                TextField("One short line", text: $template.description)
                    .textFieldStyle(.plain)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(surfaceColor).overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(borderColor, lineWidth: 1)))
                    .disabled(isReadOnly)
            }

            // Icon
            VStack(alignment: .leading, spacing: 6) {
                fieldLabel("Icon")
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(34), spacing: 6), count: 8), spacing: 6) {
                    ForEach(Self.iconChoices, id: \.self) { sym in
                        Button {
                            guard !isReadOnly else { return }
                            template.icon = sym
                        } label: {
                            Image(systemName: sym)
                                .font(.system(size: 14))
                                .foregroundStyle(template.icon == sym ? accentTeal : .white.opacity(0.5))
                                .frame(width: 30, height: 30)
                                .background(
                                    RoundedRectangle(cornerRadius: 7)
                                        .fill(template.icon == sym ? accentTeal.opacity(0.15) : surfaceColor)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 7)
                                                .strokeBorder(template.icon == sym ? accentTeal.opacity(0.5) : borderColor, lineWidth: 1)
                                        )
                                )
                        }
                        .buttonStyle(.plain)
                        .disabled(isReadOnly)
                    }
                }
            }

            // System prompt
            VStack(alignment: .leading, spacing: 4) {
                fieldLabel("System prompt — the instructions the AI receives")
                TextEditor(text: $template.systemPrompt)
                    .font(.system(size: 12, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    // Use a FIXED height (not min-height) so content
                    // scrolls within the box instead of expanding it.
                    .frame(height: 240)
                    .background(RoundedRectangle(cornerRadius: 8).fill(surfaceColor).overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(borderColor, lineWidth: 1)))
                    .disabled(isReadOnly)
            }

            HStack {
                Spacer()
                if !isReadOnly {
                    Button("Cancel") { dismiss() }
                        .buttonStyle(.bordered)
                    Button(mode == .create ? "Create" : "Save") {
                        switch mode {
                        case .create:
                            appState.addUserTemplate(template)
                        case .edit:
                            appState.updateUserTemplate(template)
                        case .view:
                            break
                        }
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(accentTeal)
                    .disabled(!canSave)
                } else {
                    Button("Close") { dismiss() }
                        .buttonStyle(.borderedProminent)
                        .tint(accentTeal)
                }
            }
        }
        .padding(20)
        .frame(minWidth: 540, minHeight: 520)
    }

    private var headerTitle: String {
        switch mode {
        case .create: return "New Template"
        case .edit:   return "Edit Template"
        case .view:   return template.name
        }
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white.opacity(0.55))
    }
}

// MARK: - Appearance Settings Tab

private struct AppearanceSettingsTab: View {
    @EnvironmentObject var appState: AppState

    private let accentTeal = Color(hex: "22C55E")
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
                            Text("Invisible to screen sharing and screen recordings. The app is also hidden from Cmd+Tab, the Dock, and Mission Control.")
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.4))
                                .fixedSize(horizontal: false, vertical: true)
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
                            Text("Completely undetectable to proctoring sites. Clicks and scrolls pass through to the browser beneath — the browser never sees you lose focus, switch tabs, or move the cursor away, even while you type into SoloScreen.\n\nDon't take our word for it — open [webbrowsertools.com/test-always-active](https://webbrowsertools.com/test-always-active), press Start, and use SoloScreen's shortcuts. Every counter stays at 0.")
                                .tint(accentTeal)
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
    private let accentTeal = Color(hex: "22C55E")
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
                        Text("SoloScreen")
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

            // (Free tier section removed — free-message limit no longer applied.)

            // Keyboard shortcuts
            settingsSection("Keyboard Shortcuts") {
                VStack(spacing: 8) {
                    shortcutRow(keys: "Ctrl + Shift + Space", description: "Show / Hide window")
                    shortcutRow(keys: "Ctrl + Shift + N", description: "New chat")
                    shortcutRow(keys: "Ctrl + Shift + E", description: "Toggle extreme stealth")
                    shortcutRow(keys: "Ctrl + Shift + I", description: "Focus input")
                    shortcutRow(keys: "Ctrl + Shift + M", description: "Minimize / Restore")
                    shortcutRow(keys: "Ctrl + Shift + S", description: "Capture screenshot")
                    shortcutRow(keys: "Ctrl + Shift + R", description: "Toggle mic recording")
                    shortcutRow(keys: "Ctrl + Shift + T", description: "Live transcription")
                    shortcutRow(keys: "Ctrl + Shift + A", description: "Attach file")
                    shortcutRow(keys: "Ctrl + Shift + ↑/↓", description: "Scroll chat")
                    shortcutRow(keys: "Escape", description: "Stop streaming")
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

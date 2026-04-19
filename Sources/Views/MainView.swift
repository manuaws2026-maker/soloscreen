import SwiftUI

struct MainView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared

    // MARK: - Theme Constants
    private let bgColor = Color(hex: "0D1117")
    private let surfaceColor = Color(hex: "161B22")
    private let borderColor = Color(hex: "30363D")
    private let accentTeal = Color(hex: "22C55E")

    /// Below this width the sidebar flips from inline layout to a slide-in
    /// overlay drawer so the chat content keeps breathing room.
    private let narrowThreshold: CGFloat = 560

    /// Border color/width reflects stealth state:
    ///  - Stealth OFF → red (window is visible to screen share!)
    ///  - Extreme stealth ON → green (click-through)
    ///  - Normal stealth ON → subtle white
    private var borderGradient: LinearGradient {
        if !appState.settings.stealthEnabled {
            // Solid, vivid red all the way around — safety warning.
            return LinearGradient(
                colors: [.red, .red],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
        if appState.settings.extremeStealthEnabled {
            return LinearGradient(
                colors: [.green.opacity(0.5), .green.opacity(0.25)],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
        return LinearGradient(
            colors: [.white.opacity(0.08), .white.opacity(0.04)],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private var borderWidth: CGFloat {
        if !appState.settings.stealthEnabled { return 3.5 }
        if appState.settings.extremeStealthEnabled { return 1.5 }
        return 0.5
    }

    var body: some View {
        GeometryReader { geo in
            let isNarrow = geo.size.width < narrowThreshold
            let overlayOpen = isNarrow && appState.sidebarVisible

            // Auto-collapse sidebar in narrow width — handles both first
            // launch (onAppear) and live resize (onChange). Without this,
            // starting in a narrow window or shrinking a wide one would
            // pop the sidebar open as a drawer unintentionally.
            Color.clear
                .frame(width: 0, height: 0)
                .onAppear {
                    if isNarrow && appState.sidebarVisible {
                        appState.sidebarVisible = false
                    }
                }
                .onChange(of: isNarrow) { _, nowNarrow in
                    if nowNarrow && appState.sidebarVisible {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            appState.sidebarVisible = false
                        }
                    }
                }

            VStack(spacing: 0) {
                // Full-width top bar — sits above both sidebar and chat.
                ChatTopBar()
                    .environmentObject(appState)

                Rectangle()
                    .fill(borderColor)
                    .frame(height: 1)

                // Stealth-off warning banner: tells the user the window is
                // visible to screen capture right now, with a one-click link
                // to the Appearance tab where stealth is toggled.
                if !appState.settings.stealthEnabled {
                    VisibleBanner()
                        .padding(.top, 8)
                        .transition(.opacity)
                }

                // Extreme-stealth banner: tells the user the mode is on +
                // how to toggle it, without taking up top-bar space.
                if appState.settings.extremeStealthEnabled {
                    StealthBanner()
                        .padding(.top, 8)
                        .transition(.opacity)
                }

                // Content row below the top bar.
                ZStack(alignment: .topLeading) {
                    HStack(spacing: 0) {
                        if !isNarrow && appState.sidebarVisible {
                            SidebarView()
                                .frame(width: 260)
                                .transition(.move(edge: .leading).combined(with: .opacity))

                            Rectangle()
                                .fill(borderColor)
                                .frame(width: 1)
                        }

                        VStack(spacing: 0) {
                            detailContent
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .animation(.easeInOut(duration: 0.2), value: appState.sidebarVisible)

                    // Narrow-mode drawer: dimmed backdrop + slide-in sidebar
                    // (stays below the top bar).
                    if overlayOpen {
                        Color.black.opacity(0.35)
                            .ignoresSafeArea()
                            .contentShape(Rectangle())
                            .onTapGesture {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    appState.sidebarVisible = false
                                }
                            }
                            .transition(.opacity)
                            .zIndex(50)

                        SidebarView(onSessionSelected: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                appState.sidebarVisible = false
                            }
                        })
                        .frame(width: min(320, geo.size.width * 0.85))
                        .frame(maxHeight: .infinity)
                        .shadow(color: .black.opacity(0.35), radius: 10, x: 2, y: 0)
                        .transition(.move(edge: .leading))
                        .zIndex(51)
                    }

                    if let errorMessage = appState.errorMessage {
                        ErrorBannerView(
                            message: errorMessage,
                            linkLabel: appState.errorLinkLabel,
                            onOpenSettings: {
                                withAnimation(.easeOut(duration: 0.15)) {
                                    appState.openSettingsFromError()
                                }
                            },
                            onDismiss: {
                                withAnimation(.easeOut(duration: 0.25)) {
                                    appState.errorMessage = nil
                                    appState.errorSettingsTab = nil
                                    appState.errorSystemSettingsURL = nil
                                }
                            }
                        )
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .frame(maxWidth: .infinity)
                        .zIndex(100)
                    }

                    if appState.showLiveHelpModal {
                        LiveHelpModal()
                            .environmentObject(appState)
                            .transition(.opacity.combined(with: .scale(scale: 0.96)))
                            .zIndex(150)
                    }

                    if appState.showLanguagePicker {
                        LanguagePickerModal()
                            .environmentObject(appState)
                            .transition(.opacity.combined(with: .scale(scale: 0.96)))
                            .zIndex(160)
                    }

                    // Paywall — shown after 3 free prompts.
                    if subscriptionManager.showPaywall {
                        PaywallView()
                            .transition(.opacity.combined(with: .scale(scale: 0.96)))
                            .zIndex(200)
                    }

                    // (Diagram expansion now opens in a dedicated NSWindow
                    // managed by AppDelegate — see showDiagramWindow — so the
                    // whole stealth / sharingType treatment applies and it
                    // can be closed even when the main panel is hidden.)
                }
                .animation(.easeInOut(duration: 0.2), value: overlayOpen)
            }
        }
        .frame(minWidth: 500, minHeight: 400)
        .background(bgColor)
        .overlay(
            RoundedRectangle(cornerRadius: appState.settings.stealthEnabled ? 12 : 0)
                .strokeBorder(borderGradient, lineWidth: borderWidth)
                .animation(.easeInOut(duration: 0.3), value: appState.settings.extremeStealthEnabled)
                .animation(.easeInOut(duration: 0.3), value: appState.settings.stealthEnabled)
                .allowsHitTesting(false)   // border must never swallow clicks
        )
        .preferredColorScheme(.dark)
        // Settings is managed as a separate floating window centered on the
        // screen (see `AppDelegate.showSettingsWindow`) — not as a sheet off
        // the right-edge panel, which would anchor far right.
        .sheet(isPresented: $appState.showProjects) {
            ProjectsView()
                .environmentObject(appState)
                .frame(minWidth: 520, minHeight: 440)
        }
        // Onboarding is managed as a centered NSWindow by AppDelegate
        // (not a sheet, which would anchor to the right-edge panel).
    }

    // MARK: - Detail Content

    @ViewBuilder
    private var detailContent: some View {
        if appState.activeSession != nil {
            ChatView()
        } else {
            emptyState
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()

            Group {
                if let url = Bundle.module.url(forResource: "BrainIcon", withExtension: "png"),
                   let nsImg = NSImage(contentsOf: url) {
                    Image(nsImage: nsImg)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    Image(systemName: "brain.head.profile")
                        .foregroundStyle(accentTeal.opacity(0.5))
                }
            }
            .frame(width: 96, height: 96)

            Text("SoloScreen")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))

            Text("Select a conversation or start a new one")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.55))

            Button {
                appState.createSession()
            } label: {
                Label("New Chat", systemImage: "plus.circle.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(accentTeal, in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .padding(.top, 8)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(bgColor)
    }
}

// MARK: - Error Banner

private struct ErrorBannerView: View {
    let message: String
    let linkLabel: String?
    let onOpenSettings: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.white)
                .font(.system(size: 14))
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 6) {
                Text(message)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)

                if let linkLabel {
                    Button(action: onOpenSettings) {
                        HStack(spacing: 4) {
                            Image(systemName: "gearshape.fill")
                                .font(.system(size: 11, weight: .semibold))
                            Text(linkLabel)
                                .font(.system(size: 12, weight: .semibold))
                                .underline()
                        }
                        .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer(minLength: 8)

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            // Solid fills (no .opacity) so the banner reads as fully opaque
            // even when the host window is slightly translucent.
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(red: 0.70, green: 0.11, blue: 0.11))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color(red: 0.90, green: 0.20, blue: 0.20), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.35), radius: 8, y: 2)
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }
}

// MARK: - Stealth-Off Warning Banner

/// Shown directly beneath the top bar when stealth is OFF. The window is
/// visible to screen sharing / recording in this mode, so the banner makes
/// that state impossible to miss and one click takes the user straight to
/// the Appearance tab where the stealth toggle lives.
private struct VisibleBanner: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Button {
            appState.settingsInitialTab = "Appearance"
            appState.showSettings = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "eye.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.white)

                Text("Stealth is OFF — this window IS visible to screen share and recordings.")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 8)

                HStack(spacing: 4) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 10, weight: .semibold))
                    Text("Turn on")
                        .font(.system(size: 10, weight: .semibold))
                        .underline()
                }
                .foregroundStyle(.white)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                // Solid red — the window's overlayOpacity clamps it, but this
                // should still read urgently.
                LinearGradient(
                    colors: [Color(red: 0.75, green: 0.12, blue: 0.12), Color(red: 0.62, green: 0.08, blue: 0.08)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .overlay(
                Rectangle()
                    .frame(height: 1)
                    .foregroundStyle(Color(red: 0.90, green: 0.25, blue: 0.25)),
                alignment: .bottom
            )
        }
        .buttonStyle(.plain)
        .help("Stealth is off — click to open Settings and turn it back on.")
    }
}

// MARK: - Extreme Stealth Banner

/// Shown directly beneath the top bar while extreme stealth is active.
/// Reassures the user the mode is on and how to toggle back.
private struct StealthBanner: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "eye.slash.fill")
                .font(.system(size: 11))
                .foregroundStyle(.green.opacity(0.85))

            Text("Extreme Stealth is ON.")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.green.opacity(0.85))
                .lineLimit(1)

            Spacer(minLength: 8)

            Text("Press")
                .font(.system(size: 10))
                .foregroundStyle(.green.opacity(0.65))

            Text("⌃⇧E")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(.green.opacity(0.85))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.green.opacity(0.14))
                        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.green.opacity(0.35), lineWidth: 1))
                )

            Text("to exit")
                .font(.system(size: 10))
                .foregroundStyle(.green.opacity(0.65))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [.green.opacity(0.10), .green.opacity(0.04)],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundStyle(.green.opacity(0.25)),
            alignment: .bottom
        )
    }
}

// MARK: - Hex Color Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: UInt64
        switch hex.count {
        case 6:
            (r, g, b) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default:
            (r, g, b) = (0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: 1
        )
    }
}

#Preview {
    MainView()
        .environmentObject(AppState())
}

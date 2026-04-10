import SwiftUI

struct MainView: View {
    @EnvironmentObject var appState: AppState

    // MARK: - Theme Constants
    private let bgColor = Color(hex: "0D1117")
    private let surfaceColor = Color(hex: "161B22")
    private let borderColor = Color(hex: "30363D")
    private let accentTeal = Color(hex: "00BCD4")

    var body: some View {
        ZStack(alignment: .top) {
            NavigationSplitView {
                SidebarView()
                    .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
            } detail: {
                detailContent
            }
            .navigationSplitViewStyle(.balanced)

            // Error banner
            if let errorMessage = appState.errorMessage {
                ErrorBannerView(message: errorMessage) {
                    withAnimation(.easeOut(duration: 0.25)) {
                        appState.errorMessage = nil
                    }
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(100)
            }
        }
        .frame(minWidth: 700, minHeight: 500)
        .background(bgColor)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $appState.showSettings) {
            SettingsView()
                .environmentObject(appState)
                .frame(minWidth: 560, minHeight: 480)
        }
        .sheet(isPresented: $appState.showProjects) {
            ProjectsView()
                .environmentObject(appState)
                .frame(minWidth: 520, minHeight: 440)
        }
        .sheet(isPresented: $appState.showOnboarding) {
            OnboardingView()
                .environmentObject(appState)
                .frame(width: 520, height: 560)
                .interactiveDismissDisabled()
        }
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

            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 56, weight: .thin))
                .foregroundStyle(accentTeal.opacity(0.5))

            Text("SubtleAI")
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
        .background(Color(hex: "0D1117"))
    }
}

// MARK: - Error Banner

private struct ErrorBannerView: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
                .font(.system(size: 14))

            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(2)

            Spacer()

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.red.opacity(0.2))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.red.opacity(0.4), lineWidth: 1)
                )
        )
        .padding(.horizontal, 20)
        .padding(.top, 8)
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

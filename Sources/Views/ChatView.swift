import SwiftUI

struct ChatView: View {
    @EnvironmentObject var appState: AppState
    @State private var scrollProxy: ScrollViewProxy?
    @Namespace private var bottomAnchor

    private let bgColor = Color(hex: "0D1117")
    private let surfaceColor = Color(hex: "161B22")
    private let borderColor = Color(hex: "30363D")
    private let accentTeal = Color(hex: "00BCD4")

    var body: some View {
        VStack(spacing: 0) {
            // Top bar
            topBar

            Divider()
                .overlay(borderColor)

            // Messages area
            if let session = appState.activeSession {
                if session.messages.filter({ $0.role != .system }).isEmpty {
                    emptyConversation
                } else {
                    messageScrollView(session: session)
                }
            }

            // Input area
            InputArea()
        }
        .background(bgColor)
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            if let session = appState.activeSession {
                // Model label
                HStack(spacing: 6) {
                    Image(systemName: "cpu")
                        .font(.system(size: 11))
                        .foregroundStyle(accentTeal.opacity(0.7))

                    Text(session.model)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(surfaceColor)
                        .overlay(Capsule().strokeBorder(borderColor, lineWidth: 1))
                )
            }

            Spacer()

            // Free tier indicator
            if appState.settings.hasFreeTierRemaining {
                HStack(spacing: 4) {
                    Image(systemName: "gift")
                        .font(.system(size: 11))

                    Text("\(appState.settings.freeMessagesRemaining) free messages left")
                        .font(.system(size: 11))
                }
                .foregroundStyle(accentTeal.opacity(0.7))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(accentTeal.opacity(0.08))
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - Empty Conversation

    private var emptyConversation: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "sparkles")
                .font(.system(size: 44, weight: .thin))
                .foregroundStyle(accentTeal.opacity(0.5))

            VStack(spacing: 8) {
                Text("Start a conversation")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))

                Text("Ask anything. SubtleAI stays invisible to screen share.")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.45))
            }

            // Suggestion chips
            VStack(spacing: 10) {
                suggestionRow(icon: "doc.text", text: "Summarize this document for me")
                suggestionRow(icon: "chevron.left.forwardslash.chevron.right", text: "Explain this code snippet")
                suggestionRow(icon: "lightbulb", text: "Help me brainstorm ideas")
                suggestionRow(icon: "text.magnifyingglass", text: "Review my writing")
            }
            .padding(.top, 8)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func suggestionRow(icon: String, text: String) -> some View {
        Button {
            appState.sendMessage(text, attachments: [])
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundStyle(accentTeal.opacity(0.7))
                    .frame(width: 20)

                Text(text)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.7))

                Spacer()

                Image(systemName: "arrow.right")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.2))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: 380)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(surfaceColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(borderColor, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Message Scroll View

    private func messageScrollView(session: Session) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(session.messages.filter { $0.role != .system }) { message in
                        MessageBubble(message: message)
                            .id(message.id)
                    }

                    // Streaming indicator
                    if appState.isStreaming {
                        streamingIndicator
                    }

                    // Bottom anchor for scrolling
                    Color.clear
                        .frame(height: 1)
                        .id("bottom")
                }
                .padding(.vertical, 12)
            }
            .onAppear {
                scrollProxy = proxy
                scrollToBottom(proxy: proxy, animated: false)
            }
            .onChange(of: session.messages.count) { _, _ in
                scrollToBottom(proxy: proxy, animated: true)
            }
            .onChange(of: appState.isStreaming) { _, _ in
                scrollToBottom(proxy: proxy, animated: true)
            }
            .onChange(of: session.messages.last?.content) { _, _ in
                scrollToBottom(proxy: proxy, animated: false)
            }
        }
    }

    // MARK: - Streaming Indicator

    private var streamingIndicator: some View {
        HStack(spacing: 0) {
            HStack(spacing: 12) {
                PulsingDotsView()

                Button {
                    appState.cancelStreaming()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "stop.circle.fill")
                            .font(.system(size: 12))
                        Text("Stop")
                            .font(.system(size: 12))
                    }
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(.white.opacity(0.06))
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Spacer()
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Helpers

    private func scrollToBottom(proxy: ScrollViewProxy, animated: Bool) {
        if animated {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        } else {
            proxy.scrollTo("bottom", anchor: .bottom)
        }
    }
}

// MARK: - Pulsing Dots

struct PulsingDotsView: View {
    @State private var animating = false

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(Color(hex: "00BCD4").opacity(0.7))
                    .frame(width: 6, height: 6)
                    .scaleEffect(animating ? 1.0 : 0.5)
                    .opacity(animating ? 1.0 : 0.3)
                    .animation(
                        .easeInOut(duration: 0.6)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.2),
                        value: animating
                    )
            }
        }
        .onAppear {
            animating = true
        }
    }
}

#Preview {
    ChatView()
        .environmentObject(AppState())
}

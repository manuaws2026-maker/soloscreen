import SwiftUI
import StoreKit

/// Full-screen paywall modal shown after 3 free prompts.
/// Presents the $10/month subscription with feature highlights.
struct PaywallView: View {
    @ObservedObject var subscriptionManager = SubscriptionManager.shared
    @State private var isPurchasing = false
    @State private var isRestoring = false
    @State private var errorMessage: String?

    private let accent = Color(hex: "22C55E")
    private let bg = Color(hex: "0D1117")
    private let surface = Color(hex: "161B22")
    private let border = Color(hex: "30363D")

    var body: some View {
        ZStack {
            Color.black.opacity(0.7)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                VStack(spacing: 12) {
                    Group {
                        if let url = Bundle.module.url(forResource: "BrainIcon", withExtension: "png"),
                           let nsImg = NSImage(contentsOf: url) {
                            Image(nsImage: nsImg)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                        } else {
                            Image(systemName: "brain.head.profile")
                                .font(.system(size: 40, weight: .thin))
                                .foregroundStyle(accent)
                        }
                    }
                    .frame(width: 56, height: 56)

                    Text("Upgrade to SoloScreen Pro")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)

                    Text("You've used your 3 free prompts")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.45))
                }
                .padding(.top, 28)

                // Features
                VStack(alignment: .leading, spacing: 10) {
                    proFeature(icon: "infinity", text: "Unlimited AI prompts")
                    proFeature(icon: "eye.slash.fill", text: "Stealth mode — invisible to screen share")
                    proFeature(icon: "bolt.fill", text: "OpenAI, Claude, and Gemini support")
                    proFeature(icon: "waveform", text: "Live Listen with real-time transcription")
                    proFeature(icon: "camera.viewfinder", text: "Screenshot analysis with vision AI")
                    proFeature(icon: "doc.on.doc", text: "RAG with your own documents")
                }
                .padding(.horizontal, 32)
                .padding(.top, 24)

                Spacer()

                // Price
                VStack(spacing: 6) {
                    if let product = subscriptionManager.proProduct {
                        Text(product.displayPrice)
                            .font(.system(size: 32, weight: .bold))
                            .foregroundStyle(.white)
                        Text("per month")
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.45))
                    } else {
                        Text("$9.99")
                            .font(.system(size: 32, weight: .bold))
                            .foregroundStyle(.white)
                        Text("per month")
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.45))
                    }
                }
                .padding(.top, 16)

                // Subscribe button
                Button {
                    purchase()
                } label: {
                    HStack(spacing: 8) {
                        if isPurchasing {
                            ProgressView().controlSize(.small).tint(.white)
                        }
                        Text(isPurchasing ? "Processing…" : "Subscribe Now")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(accent)
                    )
                }
                .buttonStyle(.plain)
                .disabled(isPurchasing)
                .padding(.horizontal, 32)
                .padding(.top, 20)

                // Restore + error
                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 11))
                        .foregroundStyle(.red.opacity(0.8))
                        .padding(.top, 8)
                }

                Button {
                    restore()
                } label: {
                    Text(isRestoring ? "Restoring…" : "Restore Purchase")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.4))
                        .underline()
                }
                .buttonStyle(.plain)
                .disabled(isRestoring)
                .padding(.top, 10)

                // Legal
                HStack(spacing: 16) {
                    Text("Terms of Service")
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.2))
                    Text("Privacy Policy")
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.2))
                }
                .padding(.top, 12)
                .padding(.bottom, 20)
            }
            .frame(maxWidth: 420, maxHeight: 540)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(bg)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(border, lineWidth: 1)
                    )
            )
            .shadow(color: .black.opacity(0.5), radius: 20, y: 8)
        }
    }

    private func proFeature(icon: String, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(accent)
                .frame(width: 18, height: 18)
                .background(Circle().fill(accent.opacity(0.12)))

            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.75))
        }
    }

    private func purchase() {
        isPurchasing = true
        errorMessage = nil
        Task {
            let success = await subscriptionManager.purchase()
            isPurchasing = false
            if !success && !subscriptionManager.isSubscribed {
                errorMessage = "Purchase was not completed. Try again."
            }
        }
    }

    private func restore() {
        isRestoring = true
        errorMessage = nil
        Task {
            await subscriptionManager.restore()
            isRestoring = false
            if !subscriptionManager.isSubscribed {
                errorMessage = "No active subscription found."
            }
        }
    }
}

#Preview {
    PaywallView()
        .frame(width: 500, height: 600)
        .background(Color.black)
}

import StoreKit
import SwiftUI

/// Manages the $10/month SoloScreen Pro subscription via StoreKit 2.
///
/// After freePromptLimit free prompts, users must subscribe to continue using
/// the app. The subscription is verified locally using StoreKit's built-in
/// transaction verification and persisted across launches.
@MainActor
final class SubscriptionManager: ObservableObject {

    static let shared = SubscriptionManager()

    // MARK: - Product IDs

    /// The product ID configured in App Store Connect.
    static let proMonthlyID = "com.soloscreen.pro.monthly"

    // MARK: - State

    /// The current subscription product (loaded from StoreKit).
    @Published var proProduct: Product?

    /// Whether the user has an active subscription.
    @Published var isSubscribed: Bool = false

    /// Number of free prompts used (persisted in UserDefaults).
    @Published var freePromptsUsed: Int = 0

    /// Whether the paywall should be shown.
    @Published var showPaywall: Bool = false

    static let freePromptLimit = 10000

    var freePromptsRemaining: Int {
        max(0, Self.freePromptLimit - freePromptsUsed)
    }

    var needsSubscription: Bool {
        !isSubscribed && freePromptsUsed >= Self.freePromptLimit
    }

    // MARK: - Persistence Keys

    private let freePromptsKey = "soloscreen.freePromptsUsed"

    // MARK: - Init

    private init() {
        freePromptsUsed = UserDefaults.standard.integer(forKey: freePromptsKey)
        Task {
            await loadProducts()
            await updateSubscriptionStatus()
            listenForTransactionUpdates()
        }
    }

    // MARK: - Products

    /// Load the subscription product from StoreKit.
    func loadProducts() async {
        do {
            let products = try await Product.products(for: [Self.proMonthlyID])
            proProduct = products.first
        } catch {
            #if DEBUG
            print("[SubscriptionManager] Failed to load products: \(error)")
            #endif
        }
    }

    // MARK: - Purchase

    /// Initiate a purchase of the monthly subscription.
    func purchase() async -> Bool {
        guard let product = proProduct else {
            // If products haven't loaded (e.g., sandbox/dev), grant access.
            #if DEBUG
            print("[SubscriptionManager] No product loaded — granting dev access.")
            isSubscribed = true
            showPaywall = false
            return true
            #else
            return false
            #endif
        }

        do {
            let result = try await product.purchase()

            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await transaction.finish()
                isSubscribed = true
                showPaywall = false
                return true

            case .userCancelled:
                return false

            case .pending:
                // Ask-to-buy or other pending state.
                return false

            @unknown default:
                return false
            }
        } catch {
            #if DEBUG
            print("[SubscriptionManager] Purchase failed: \(error)")
            #endif
            return false
        }
    }

    /// Restore previous purchases.
    func restore() async {
        try? await AppStore.sync()
        await updateSubscriptionStatus()
    }

    // MARK: - Prompt Tracking

    /// Called after each successful LLM response. Increments the counter
    /// and shows the paywall if the free limit is reached.
    func recordPrompt() {
        guard !isSubscribed else { return }
        freePromptsUsed += 1
        UserDefaults.standard.set(freePromptsUsed, forKey: freePromptsKey)

        if freePromptsUsed >= Self.freePromptLimit {
            showPaywall = true
        }
    }

    // MARK: - Subscription Status

    /// Check current entitlement status from StoreKit.
    func updateSubscriptionStatus() async {
        // Check for any verified transaction for our product.
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result {
                if transaction.productID == Self.proMonthlyID {
                    isSubscribed = true
                    return
                }
            }
        }
        isSubscribed = false
    }

    // MARK: - Transaction Listener

    /// Listen for real-time transaction updates (renewals, cancellations, etc.).
    private func listenForTransactionUpdates() {
        Task.detached {
            for await result in Transaction.updates {
                if case .verified(let transaction) = result {
                    await transaction.finish()
                    await MainActor.run {
                        if transaction.productID == Self.proMonthlyID {
                            self.isSubscribed = !transaction.revocationDate.hasValue
                        }
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw StoreError.verificationFailed
        case .verified(let item):
            return item
        }
    }

    enum StoreError: Error {
        case verificationFailed
    }
}

// Convenience for optional date checking
private extension Optional where Wrapped == Date {
    var hasValue: Bool { self != nil }
}

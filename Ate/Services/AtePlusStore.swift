import Foundation
import StoreKit
import Combine

/// StoreKit 2 purchase state for Ate Plus. Product identifiers must match App Store Connect.
/// Prices are always rendered from Product.displayPrice; never store price literals in the app.
@MainActor
final class AtePlusStore: ObservableObject {
    enum ProductID {
        static let monthly = "com.melusik.ate.plus.monthly"
        static let annual = "com.melusik.ate.plus.annual"
        static let lifetime = "com.melusik.ate.plus.lifetime"
        static let all: Set<String> = [monthly, annual, lifetime]
    }

    @Published private(set) var products: [Product] = []
    @Published private(set) var hasPlusAccess = false
    @Published private(set) var hasLifetimeAccess = false
    @Published private(set) var isLoading = false
    @Published private(set) var isPurchasing = false
    @Published private(set) var message: String?

    private var updatesTask: Task<Void, Never>?

    init() {
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                await self?.handle(update)
                await self?.refreshEntitlements()
            }
        }
        Task {
            await loadProducts()
            await refreshEntitlements()
        }
    }

    deinit {
        updatesTask?.cancel()
    }

    func loadProducts() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            products = try await Product.products(for: ProductID.all)
                .sorted { order($0.id) < order($1.id) }
            if products.isEmpty {
                message = "Ate Plus products aren't available yet. Please try again later."
            } else {
                message = nil
            }
        } catch {
            message = "Couldn't load purchases. Check your connection and try again."
        }
    }

    func refreshEntitlements() async {
        var activeIDs = Set<String>()
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  transaction.revocationDate == nil,
                  ProductID.all.contains(transaction.productID) else { continue }
            activeIDs.insert(transaction.productID)
        }
        hasLifetimeAccess = activeIDs.contains(ProductID.lifetime)
        hasPlusAccess = !activeIDs.isEmpty
    }

    func purchase(_ product: Product) async {
        guard !isPurchasing else { return }
        isPurchasing = true
        message = nil
        defer { isPurchasing = false }

        do {
            switch try await product.purchase() {
            case .success(let result):
                await handle(result)
                await refreshEntitlements()
                if hasPlusAccess { message = "Ate Plus is active on this Apple Account." }
            case .pending:
                message = "Your purchase is pending approval."
            case .userCancelled:
                break
            @unknown default:
                message = "The purchase result wasn't recognised. Please try again."
            }
        } catch {
            message = "Purchase couldn't be completed. Please try again."
        }
    }

    func restorePurchases() async {
        message = nil
        do {
            try await StoreKit.AppStore.sync()
            await refreshEntitlements()
            message = hasPlusAccess
                ? "Purchases restored."
                : "No active Ate Plus purchase was found for this Apple Account."
        } catch {
            message = "Couldn't restore purchases. Please try again."
        }
    }

    private func handle(_ result: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = result else {
            message = "Apple couldn't verify this transaction. No access was granted."
            return
        }
        await transaction.finish()
    }

    private func order(_ id: String) -> Int {
        switch id {
        case ProductID.monthly: return 0
        case ProductID.annual: return 1
        case ProductID.lifetime: return 2
        default: return 3
        }
    }
}

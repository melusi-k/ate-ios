import SwiftUI
import StoreKit

struct AtePlusPaywallView: View {
    @StateObject private var purchases = AtePlusStore()

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Ate Plus", systemImage: "sparkles")
                        .font(.title2.weight(.semibold))
                    Text(purchases.hasPlusAccess
                         ? "Ate Plus is active for your Apple Account."
                         : "Choose a plan to support Ate and unlock future Plus features.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                    if purchases.hasLifetimeAccess {
                        Label("Lifetime access", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                    }
                }
                .padding(.vertical, 6)
            }

            Section("Choose your plan") {
                if purchases.isLoading && purchases.products.isEmpty {
                    HStack { ProgressView(); Text("Loading plans…").foregroundStyle(.secondary) }
                } else if purchases.products.isEmpty {
                    Text("Plans aren't available right now. You can try again.")
                        .foregroundStyle(.secondary)
                    Button("Try again") { Task { await purchases.loadProducts() } }
                } else {
                    ForEach(purchases.products, id: \.id) { product in
                        Button {
                            Task { await purchases.purchase(product) }
                        } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(planName(product.id)).font(.body.weight(.medium))
                                    Text(planDescription(product.id))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 8)
                                Text(product.displayPrice).font(.body.weight(.semibold))
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(purchases.isPurchasing || purchases.hasPlusAccess)
                        .accessibilityIdentifier("atePlus.purchase.\(product.id)")
                    }
                }
                if purchases.isPurchasing {
                    HStack { ProgressView(); Text("Processing purchase…").foregroundStyle(.secondary) }
                }
            } footer: {
                Text("Prices and currency are provided by the App Store for your storefront. Subscriptions renew automatically until cancelled in your Apple Account settings.")
            }

            Section {
                Button("Restore purchases") { Task { await purchases.restorePurchases() } }
                    .disabled(purchases.isPurchasing)
                    .accessibilityIdentifier("atePlus.restore")
                if let message = purchases.message {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("atePlus.status")
                }
            }

            Section("Legal") {
                Link("Terms of Use", destination: URL(string: "https://melusi-k.github.io/ate-legal/terms.html")!)
                Link("Privacy Policy", destination: URL(string: "https://melusi-k.github.io/ate-legal/privacy.html")!)
            }
        }
        .navigationTitle("Ate Plus")
        .navigationBarTitleDisplayMode(.inline)
        .task { await purchases.refreshEntitlements() }
    }

    private func planName(_ id: String) -> String {
        switch id {
        case AtePlusStore.ProductID.monthly: return "Monthly"
        case AtePlusStore.ProductID.annual: return "Annual"
        case AtePlusStore.ProductID.lifetime: return "Lifetime"
        default: return "Ate Plus"
        }
    }

    private func planDescription(_ id: String) -> String {
        switch id {
        case AtePlusStore.ProductID.monthly: return "Billed monthly; cancel any time"
        case AtePlusStore.ProductID.annual: return "Billed yearly; renews annually"
        case AtePlusStore.ProductID.lifetime: return "One-time purchase"
        default: return ""
        }
    }
}

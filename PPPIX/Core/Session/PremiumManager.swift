import Foundation
import SwiftUI
import StoreKit

/// Gerencia o estado de assinatura Premium via StoreKit 2.
/// Verifica automaticamente entitlements ao inicializar e após cada compra.
@MainActor
final class PremiumManager: ObservableObject {

    static let shared = PremiumManager()
    private init() {
        Task { await refreshPurchaseStatus() }
        listenForTransactions()
    }

    // MARK: - Product IDs
    static let monthlyID = "tech.pppix.app.premium.monthly"
    static let yearlyID  = "tech.pppix.app.premium.yearly"

    // MARK: - Preços de fallback (mostrados antes de carregar da App Store)
    static let monthlyPrice   = "R$ 19,90"
    static let yearlyPrice    = "R$ 159,90"
    static let yearlyDiscount = "33% OFF"
    static let yearlyPerMonth = "R$ 13,32/mês"

    // MARK: - Estado publicado
    @Published var isPremium: Bool = false
    @Published var monthlyProduct: Product? = nil
    @Published var yearlyProduct:  Product? = nil
    @Published var isPurchasing = false
    @Published var purchaseError: String? = nil

    private var transactionListener: Task<Void, Never>? = nil

    // MARK: - Limites Free
    static let freeContactLimit = 1
    static let freeVehicleLimit = 1
    static let freeAppLimit     = 1

    // MARK: - Verificações de limite
    func canAddContact(currentCount: Int) -> Bool { isPremium || currentCount < Self.freeContactLimit }
    func canAddVehicle(currentCount: Int) -> Bool { isPremium || currentCount < Self.freeVehicleLimit }
    func canAddApp() -> Bool { isPremium }
    var canUseWhatsApp: Bool { isPremium }

    // MARK: - Carregar produtos da App Store

    func loadProducts() async {
        do {
            let products = try await Product.products(for: [Self.monthlyID, Self.yearlyID])
            for p in products {
                if p.id == Self.monthlyID { monthlyProduct = p }
                if p.id == Self.yearlyID  { yearlyProduct  = p }
            }
        } catch {
            print("[PremiumManager] Erro ao carregar produtos: \(error)")
        }
    }

    // MARK: - Comprar

    func purchase(_ product: Product) async {
        isPurchasing = true
        purchaseError = nil
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await transaction.finish()
                await refreshPurchaseStatus()
            case .userCancelled:
                break
            case .pending:
                purchaseError = "Compra pendente de aprovação."
            @unknown default:
                break
            }
        } catch {
            purchaseError = "Erro ao processar compra. Tente novamente."
            print("[PremiumManager] Erro na compra: \(error)")
        }
        isPurchasing = false
    }

    // MARK: - Restaurar compras

    func restorePurchases() async {
        isPurchasing = true
        do {
            try await AppStore.sync()
            await refreshPurchaseStatus()
        } catch {
            purchaseError = "Erro ao restaurar compras."
        }
        isPurchasing = false
    }

    // MARK: - Verificar entitlements

    func refreshPurchaseStatus() async {
        var active = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.productType == .autoRenewable,
               (transaction.productID == Self.monthlyID || transaction.productID == Self.yearlyID),
               transaction.revocationDate == nil {
                active = true
            }
        }
        isPremium = active
    }

    // MARK: - Ouvir transações em tempo real

    private func listenForTransactions() {
        transactionListener = Task.detached(priority: .background) {
            for await result in Transaction.updates {
                if case .verified(let transaction) = result {
                    await transaction.finish()
                    await self.refreshPurchaseStatus()
                }
            }
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified: throw StoreError.failedVerification
        case .verified(let value): return value
        }
    }
}

enum StoreError: Error { case failedVerification }

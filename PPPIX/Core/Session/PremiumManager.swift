import Foundation
import SwiftUI

/// Gerencia o estado de assinatura do usuário (Free vs Premium).
///
/// Por enquanto usa UserDefaults local — quando o In-App Purchase
/// for configurado na Apple, este manager será atualizado para
/// verificar a receipt/entitlement via StoreKit 2.
@MainActor
final class PremiumManager: ObservableObject {

    static let shared = PremiumManager()
    private init() {}

    private let key = "pppix_is_premium"

    /// true se o usuário tem plano Premium ativo.
    @Published var isPremium: Bool = false {
        didSet { UserDefaults.standard.set(isPremium, forKey: key) }
    }

    // MARK: - Limites do plano Free

    static let freeContactLimit = 1
    static let freeVehicleLimit = 1
    static let freeAppLimit     = 1

    // MARK: - Preços (usados no paywall)

    static let monthlyPrice = "R$ 19,90"
    static let yearlyPrice  = "R$ 159,90"
    static let yearlyDiscount = "33% OFF"

    // MARK: - Verificações de limite

    func canAddContact(currentCount: Int) -> Bool {
        isPremium || currentCount < Self.freeContactLimit
    }

    func canAddVehicle(currentCount: Int) -> Bool {
        isPremium || currentCount < Self.freeVehicleLimit
    }

    func canAddApp() -> Bool {
        isPremium
    }

    var canUseWhatsApp: Bool { isPremium }

    // MARK: - Ativa/desativa premium (temporário até StoreKit)

    func activate() {
        isPremium = true
    }

    func deactivate() {
        isPremium = false
    }
}

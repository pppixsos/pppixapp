import FamilyControls
import ManagedSettings
import DeviceActivity
import SwiftUI

/// Equivalente ao AccessibilityService + AppMonitorService do Android.
/// Usa Screen Time API (FamilyControls + ManagedSettings) para bloquear apps financeiros.
@MainActor
final class ScreenTimeManager: ObservableObject {

    static let shared = ScreenTimeManager()
    private init() {}

    private let store = ManagedSettingsStore()
    @Published var isAuthorized: Bool = false

    // MARK: - Apps financeiros padrão (bundle IDs)
    // Equivalente à lista hardcoded do Android

    static let defaultFinancialApps: Set<String> = [
        "com.nu.production",           // Nubank
        "br.com.itau",                 // Itaú
        "br.com.bancodobrasil.bancodobrasil", // Banco do Brasil
        "com.santander.app",           // Santander
        "com.c6bank.app",              // C6 Bank
        "com.mercadopago.wallet",      // Mercado Pago
        "br.com.bradesco",             // Bradesco
        "br.com.caixa",                // Caixa
        "br.com.inter",                // Inter
        "com.picpay",                  // PicPay
        "br.com.original.bank",        // Original
        "com.pagbank.app",             // PagBank
    ]

    // MARK: - Authorization

    func requestAuthorization() async {
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            isAuthorized = true
        } catch {
            isAuthorized = false
            print("[PPPIX] Screen Time auth failed: \(error)")
        }
    }

    var authorizationStatus: AuthorizationStatus {
        AuthorizationCenter.shared.authorizationStatus
    }

    // MARK: - Block / Unblock

    /// Bloqueia os apps selecionados usando Screen Time.
    /// Chamado quando o usuário confirma a lista de apps.
    func blockApps(_ selection: FamilyActivitySelection) {
        store.application.blockedApplications = selection.applicationTokens
        store.webContent.blockedByFilter = nil

        // Salva os bundle IDs para referência
        SessionManager.shared.isMonitorActive = true
    }

    /// Remove todos os bloqueios (ex: ao deslogar)
    func unblockAll() {
        store.clearAllSettings()
        SessionManager.shared.isMonitorActive = false
    }

    /// Desbloqueia temporariamente um app específico
    /// Chamado após senha correta na LockScreenView
    func temporarilyUnblock(token: ApplicationToken) {
        var current = store.application.blockedApplications ?? []
        current.remove(token)
        store.application.blockedApplications = current

        // Re-bloqueia após 30 segundos
        Task {
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            current.insert(token)
            store.application.blockedApplications = current
        }
    }
}

// MARK: - DeviceActivityMonitor Extension
// Este código fica na extensão PPPIXActivityMonitor (target separado)

/*
 No target PPPIXActivityMonitor, criar:

 import DeviceActivity

 class PPPIXActivityMonitor: DeviceActivityMonitor {
     override func intervalDidStart(for activity: DeviceActivityName) {
         super.intervalDidStart(for: activity)
     }

     override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
         super.eventDidReachThreshold(event, activity: activity)
         // O iOS mostrará automaticamente o bloqueio via ManagedSettings
         // A tela customizada é definida no ShieldConfiguration extension
     }
 }
*/

// MARK: - Shield Configuration Extension
// Este código fica na extensão PPPIXBlockExtension (target separado)

/*
 No target PPPIXBlockExtension, criar ShieldConfigurationDataSource:

 import ManagedSettings
 import ManagedSettingsUI

 class ShieldConfigurationExtension: ShieldConfigurationDataSource {
     override func configuration(shielding application: Application) -> ShieldConfiguration {
         return ShieldConfiguration(
             backgroundBlurStyle: .dark,
             backgroundColor: UIColor(red: 0.05, green: 0.05, blue: 0.1, alpha: 1),
             icon: UIImage(named: "AppIcon"),
             title: ShieldConfiguration.Label(
                 text: "App Bloqueado pelo PPPIX",
                 color: .white
             ),
             subtitle: ShieldConfiguration.Label(
                 text: "Abra o PPPIX e digite sua senha",
                 color: UIColor(white: 0.7, alpha: 1)
             ),
             primaryButtonLabel: ShieldConfiguration.Label(
                 text: "Abrir PPPIX",
                 color: .white
             ),
             primaryButtonBackgroundColor: UIColor(red: 0.2, green: 0.4, blue: 1.0, alpha: 1)
         )
     }
 }
*/

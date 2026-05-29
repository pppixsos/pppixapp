import ManagedSettingsUI
import ManagedSettings
import UIKit
import UserNotifications
import FamilyControls

class ShieldConfigurationExtension: ShieldConfigurationDataSource {

    private let store = ManagedSettingsStore(named: ManagedSettingsStore.Name("pppix"))
    private let sharedDefaults = UserDefaults(suiteName: "group.tech.pppix.app")

    override func configuration(shielding application: Application) -> ShieldConfiguration {
        saveAppInfo(application)
        return pppixShield()
    }

    override func configuration(shielding application: Application,
                                in category: ActivityCategory) -> ShieldConfiguration {
        saveAppInfo(application)
        return pppixShield()
    }

    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        return pppixShield()
    }

    override func configuration(shielding webDomain: WebDomain,
                                in category: ActivityCategory) -> ShieldConfiguration {
        return pppixShield()
    }

    private func saveAppInfo(_ application: Application) {
        // Salva bundle ID
        if let bundleId = application.bundleIdentifier {
            sharedDefaults?.set(bundleId, forKey: "pppix_target_bundle_id")
        }

        // Salva token via FamilyActivitySelection (mais confiável que encode direto)
        var singleSelection = FamilyActivitySelection()
        if let token = application.token { singleSelection.applicationTokens = [token] }
        if let data = try? JSONEncoder().encode(singleSelection) {
            sharedDefaults?.set(data, forKey: "pppix_single_unlock_selection")
        }

        sharedDefaults?.synchronize()
    }

    private func pppixShield() -> ShieldConfiguration {
        let houseIcon = UIImage(systemName: "house.fill",
                                withConfiguration: UIImage.SymbolConfiguration(pointSize: 44, weight: .medium))
        return ShieldConfiguration(
            backgroundBlurStyle: .systemUltraThinMaterialDark,
            backgroundColor: UIColor(red: 0.04, green: 0.04, blue: 0.07, alpha: 0.97),
            icon: houseIcon,
            title: ShieldConfiguration.Label(
                text: "🔒 Você está fora de casa!",
                color: .white
            ),
            subtitle: ShieldConfiguration.Label(
                text: "Clique em Desbloquear e abra a notificação exibida",
                color: UIColor(white: 0.55, alpha: 1.0)
            ),
            primaryButtonLabel: ShieldConfiguration.Label(
                text: "Desbloquear",
                color: .white
            ),
            primaryButtonBackgroundColor: UIColor(red: 0.2, green: 0.4, blue: 1.0, alpha: 1.0)
        )
    }
}

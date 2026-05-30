import ManagedSettingsUI
import ManagedSettings
import UIKit
import FamilyControls

class ShieldConfigurationExtension: ShieldConfigurationDataSource {

    private let store = ManagedSettingsStore(named: .init("pppix"))
    private let sharedDefaults = UserDefaults(suiteName: "group.tech.pppix.app")

    override func configuration(shielding application: Application) -> ShieldConfiguration {
        // CAMADA 1 DE REBLOCK: verifica se o unlock expirou
        // Chamado toda vez que o usuário toca no app bloqueado
        checkAndReblockIfExpired(application: application)
        return pppixShield()
    }

    override func configuration(shielding application: Application,
                                in category: ActivityCategory) -> ShieldConfiguration {
        checkAndReblockIfExpired(application: application)
        return pppixShield()
    }

    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        return pppixShield()
    }

    override func configuration(shielding webDomain: WebDomain,
                                in category: ActivityCategory) -> ShieldConfiguration {
        return pppixShield()
    }

    // Verifica se o período de unlock expirou e reaplica o shield se necessário
    private func checkAndReblockIfExpired(application: Application) {
        let unlockUntil = sharedDefaults?.double(forKey: "pppix_unlocked_until") ?? 0
        let now = Date().timeIntervalSince1970

        // Se nunca foi desbloqueado OU se o unlock expirou → garantir shield aplicado
        if unlockUntil == 0 || now > unlockUntil {
            reapplyFullShield()
            if unlockUntil > 0 {
                sharedDefaults?.removeObject(forKey: "pppix_unlocked_until")
                sharedDefaults?.synchronize()
            }
        }
    }

    private func reapplyFullShield() {
        guard let data = sharedDefaults?.data(forKey: "pppix_activity_selection"),
              let selection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data)
        else { return }

        store.shield.applications = selection.applicationTokens.isEmpty ? nil : selection.applicationTokens
        store.shield.applicationCategories = selection.categoryTokens.isEmpty ? nil : .specific(selection.categoryTokens)
        store.shield.webDomains = selection.webDomainTokens.isEmpty ? nil : selection.webDomainTokens
    }

    private func pppixShield() -> ShieldConfiguration {
        // Ícone azul (mesma cor do botão)
        let lockIcon = UIImage(systemName: "lock.fill",
                               withConfiguration: UIImage.SymbolConfiguration(pointSize: 44, weight: .medium))?
            .withTintColor(UIColor(red: 0.2, green: 0.4, blue: 1.0, alpha: 1.0), renderingMode: .alwaysOriginal)
        return ShieldConfiguration(
            backgroundBlurStyle: .systemUltraThinMaterialDark,
            backgroundColor: UIColor(red: 0.04, green: 0.04, blue: 0.07, alpha: 0.97),
            icon: lockIcon,
            title: ShieldConfiguration.Label(text: "🔒 Você está fora de casa!", color: .white),
            subtitle: ShieldConfiguration.Label(
                text: "Clique em Desbloquear e abra a notificação exibida",
                color: UIColor(white: 0.55, alpha: 1.0)
            ),
            primaryButtonLabel: ShieldConfiguration.Label(text: "Desbloquear", color: .white),
            primaryButtonBackgroundColor: UIColor(red: 0.2, green: 0.4, blue: 1.0, alpha: 1.0)
        )
    }
}

import ManagedSettingsUI
import ManagedSettings
import UIKit

// Esta extensão é chamada pelo iOS quando um app bloqueado é aberto
// Ela retorna a tela que aparece em cima do app bloqueado
class ShieldConfigurationExtension: ShieldConfigurationDataSource {

    override func configuration(shielding application: Application) -> ShieldConfiguration {
        return pppixShield()
    }

    override func configuration(shielding application: Application, in domain: WebDomain) -> ShieldConfiguration {
        return pppixShield()
    }

    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        return pppixShield()
    }

    override func configuration(shielding category: ActivityCategory) -> ShieldConfiguration {
        return pppixShield()
    }

    private func pppixShield() -> ShieldConfiguration {
        ShieldConfiguration(
            backgroundBlurStyle: .systemUltraThinMaterialDark,
            backgroundColor: UIColor(red: 0.04, green: 0.04, blue: 0.07, alpha: 0.97),
            icon: UIImage(named: "AppIcon"),
            title: ShieldConfiguration.Label(
                text: "App Protegido pelo PPPIX",
                color: .white
            ),
            subtitle: ShieldConfiguration.Label(
                text: "Digite sua senha para abrir",
                color: UIColor(white: 0.65, alpha: 1.0)
            ),
            primaryButtonLabel: ShieldConfiguration.Label(
                text: "Digitar Senha",
                color: .white
            ),
            primaryButtonBackgroundColor: UIColor(red: 0.2, green: 0.4, blue: 1.0, alpha: 1.0)
        )
    }
}

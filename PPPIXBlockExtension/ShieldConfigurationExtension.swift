import ManagedSettingsUI
import UIKit

class ShieldConfigurationExtension: ShieldConfigurationDataSource {

    override func configuration(shielding application: Application) -> ShieldConfiguration {
        let name = application.localizedDisplayName ?? "App"
        return ShieldConfiguration(
            backgroundBlurStyle: .dark,
            backgroundColor: UIColor(red: 0.02, green: 0.02, blue: 0.06, alpha: 1.0),
            icon: UIImage(systemName: "lock.fill"),
            title: ShieldConfiguration.Label(
                text: "\(name) está bloqueado",
                color: .white
            ),
            subtitle: ShieldConfiguration.Label(
                text: "Digite sua senha no PPPIX para abrir",
                color: UIColor(white: 0.5, alpha: 1.0)
            ),
            primaryButtonLabel: ShieldConfiguration.Label(
                text: "Digitar Senha",
                color: .white
            ),
            primaryButtonBackgroundColor: UIColor(red: 0.2, green: 0.4, blue: 1.0, alpha: 1.0)
        )
    }

    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        return ShieldConfiguration(
            backgroundBlurStyle: .dark,
            title: ShieldConfiguration.Label(text: "Site Bloqueado", color: .white),
            subtitle: ShieldConfiguration.Label(
                text: "Digite sua senha no PPPIX para abrir",
                color: UIColor(white: 0.5, alpha: 1.0)
            ),
            primaryButtonLabel: ShieldConfiguration.Label(text: "Digitar Senha", color: .white),
            primaryButtonBackgroundColor: UIColor(red: 0.2, green: 0.4, blue: 1.0, alpha: 1.0)
        )
    }
}

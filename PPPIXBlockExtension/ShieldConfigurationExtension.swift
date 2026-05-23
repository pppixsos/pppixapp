import ManagedSettingsUI
import UIKit

/// Target: PPPIXBlockExtension
/// Bundle ID: tech.pppix.app.block
///
/// Adicionar no Xcode:
///   File → New → Target → Shield Configuration Extension
///   Product Name: PPPIXBlockExtension
///
/// Capabilities do target:
///   - Family Controls

class ShieldConfigurationExtension: ShieldConfigurationDataSource {

    override func configuration(shielding application: Application) -> ShieldConfiguration {
        return ShieldConfiguration(
            backgroundBlurStyle: .dark,
            backgroundColor: UIColor(red: 0.04, green: 0.04, blue: 0.08, alpha: 1.0),
            icon: UIImage(named: "AppIcon"),
            title: ShieldConfiguration.Label(
                text: "App Bloqueado pelo PPPIX",
                color: .white
            ),
            subtitle: ShieldConfiguration.Label(
                text: "Abra o PPPIX e use a tela de senhas para desbloquear",
                color: UIColor(white: 0.6, alpha: 1.0)
            ),
            primaryButtonLabel: ShieldConfiguration.Label(
                text: "Abrir PPPIX",
                color: .white
            ),
            primaryButtonBackgroundColor: UIColor(
                red: 0.2, green: 0.4, blue: 1.0, alpha: 1.0
            )
        )
    }

    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        return ShieldConfiguration(
            backgroundBlurStyle: .dark,
            title: ShieldConfiguration.Label(text: "Site Bloqueado", color: .white),
            subtitle: ShieldConfiguration.Label(
                text: "Abra o PPPIX para desbloquear",
                color: UIColor(white: 0.6, alpha: 1.0)
            ),
            primaryButtonLabel: ShieldConfiguration.Label(text: "Abrir PPPIX", color: .white),
            primaryButtonBackgroundColor: UIColor(red: 0.2, green: 0.4, blue: 1.0, alpha: 1.0)
        )
    }
}

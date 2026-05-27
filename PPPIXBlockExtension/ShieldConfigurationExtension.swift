import ManagedSettingsUI
import UIKit

class ShieldConfigurationExtension: ShieldConfigurationDataSource {

    override func configuration(shielding application: Application) -> ShieldConfiguration {
        let name = application.localizedDisplayName ?? "App"
        return ShieldConfiguration(
            backgroundBlurStyle: .dark,
            backgroundColor: UIColor(red: 0.02, green: 0.02, blue: 0.06, alpha: 1.0),
            icon: nil,  // Remove ampulheta
            title: ShieldConfiguration.Label(
                text: "Você está fora de casa!",
                color: .white
            ),
            subtitle: ShieldConfiguration.Label(
                text: "\(name) está protegido. Entre com sua senha abaixo para continuar.",
                color: UIColor(white: 0.65, alpha: 1.0)
            ),
            primaryButtonLabel: ShieldConfiguration.Label(
                text: "Desbloquear",
                color: .white
            ),
            primaryButtonBackgroundColor: UIColor(red: 0.2, green: 0.4, blue: 1.0, alpha: 1.0)
        )
    }

    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        return ShieldConfiguration(
            backgroundBlurStyle: .dark,
            backgroundColor: UIColor(red: 0.02, green: 0.02, blue: 0.06, alpha: 1.0),
            icon: nil,
            title: ShieldConfiguration.Label(
                text: "Você está fora de casa!",
                color: .white
            ),
            subtitle: ShieldConfiguration.Label(
                text: "Este site está protegido. Entre com sua senha abaixo para continuar.",
                color: UIColor(white: 0.65, alpha: 1.0)
            ),
            primaryButtonLabel: ShieldConfiguration.Label(
                text: "Desbloquear",
                color: .white
            ),
            primaryButtonBackgroundColor: UIColor(red: 0.2, green: 0.4, blue: 1.0, alpha: 1.0)
        )
    }
}

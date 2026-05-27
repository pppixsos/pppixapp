import ManagedSettingsUI
import UIKit

class ShieldConfigurationExtension: ShieldConfigurationDataSource {

    override func configuration(shielding application: ApplicationToken) -> ShieldConfiguration {
        return shieldConfig()
    }

    override func configuration(shielding webDomain: WebDomainToken) -> ShieldConfiguration {
        return shieldConfig()
    }

    override func configuration(shielding category: ActivityCategoryToken) -> ShieldConfiguration {
        return shieldConfig()
    }

    private func shieldConfig() -> ShieldConfiguration {
        return ShieldConfiguration(
            backgroundBlurStyle: .dark,
            backgroundColor: UIColor(red: 0.04, green: 0.04, blue: 0.08, alpha: 1.0),
            title: ShieldConfiguration.Label(
                text: "App Bloqueado pelo PPPIX",
                color: .white
            ),
            subtitle: ShieldConfiguration.Label(
                text: "Toque em Desbloquear para abrir o PPPIX",
                color: UIColor(white: 0.6, alpha: 1.0)
            ),
            primaryButtonLabel: ShieldConfiguration.Label(
                text: "Desbloquear",
                color: .white
            ),
            primaryButtonBackgroundColor: UIColor(
                red: 0.2, green: 0.4, blue: 1.0, alpha: 1.0
            )
        )
    }
}

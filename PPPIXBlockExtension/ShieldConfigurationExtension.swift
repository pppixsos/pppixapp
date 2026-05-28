import ManagedSettingsUI
import ManagedSettings
import UIKit

class ShieldConfigurationExtension: ShieldConfigurationDataSource {

    // Store com mesmo nome — CRÍTICO para o iOS conectar a extensão ao store correto
    private let store = ManagedSettingsStore(named: ManagedSettingsStore.Name("pppix"))

    override func configuration(shielding application: Application) -> ShieldConfiguration {
        return pppixShield()
    }

    override func configuration(shielding application: Application,
                                in category: ActivityCategory) -> ShieldConfiguration {
        return pppixShield()
    }

    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        return pppixShield()
    }

    override func configuration(shielding webDomain: WebDomain,
                                in category: ActivityCategory) -> ShieldConfiguration {
        return pppixShield()
    }

    private func pppixShield() -> ShieldConfiguration {
        ShieldConfiguration(
            backgroundBlurStyle: .systemUltraThinMaterialDark,
            backgroundColor: UIColor(red: 0.04, green: 0.04, blue: 0.07, alpha: 0.97),
            icon: nil, // nil evita crash — extensão não acessa bundle do app principal
            title: ShieldConfiguration.Label(
                text: "🔐 App Protegido",
                color: .white
            ),
            subtitle: ShieldConfiguration.Label(
                text: "Digite sua senha para continuar",
                color: UIColor(white: 0.6, alpha: 1.0)
            ),
            primaryButtonLabel: ShieldConfiguration.Label(
                text: "Digitar Senha",
                color: .white
            ),
            primaryButtonBackgroundColor: UIColor(red: 0.2, green: 0.4, blue: 1.0, alpha: 1.0)
        )
    }
}

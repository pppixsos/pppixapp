import ManagedSettingsUI
import ManagedSettings
import UIKit
import UserNotifications

class ShieldConfigurationExtension: ShieldConfigurationDataSource {

    private let store = ManagedSettingsStore(named: ManagedSettingsStore.Name("pppix"))
    private let sharedDefaults = UserDefaults(suiteName: "group.tech.pppix.app")

    override func configuration(shielding application: Application) -> ShieldConfiguration {
        // Envia notificação quando shield aparece — usuário toca pra abrir PPPIX
        sendUnlockNotification()
        return pppixShield()
    }

    override func configuration(shielding application: Application,
                                in category: ActivityCategory) -> ShieldConfiguration {
        sendUnlockNotification()
        return pppixShield()
    }

    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        sendUnlockNotification()
        return pppixShield()
    }

    override func configuration(shielding webDomain: WebDomain,
                                in category: ActivityCategory) -> ShieldConfiguration {
        sendUnlockNotification()
        return pppixShield()
    }

    private func sendUnlockNotification() {
        // Sinaliza para o app principal
        sharedDefaults?.set(true, forKey: "pppix_show_password_screen")
        sharedDefaults?.set(Date().timeIntervalSince1970, forKey: "pppix_password_request_time")
        sharedDefaults?.synchronize()

        // Envia notificação para o usuário abrir o PPPIX
        let content = UNMutableNotificationContent()
        content.title = "🔐 App Protegido"
        content.body = "Toque aqui para digitar sua senha"
        content.sound = .none
        content.userInfo = ["action": "unlock"]
        content.categoryIdentifier = "PPPIX_UNLOCK"

        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: ["pppix_unlock"])

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.5, repeats: false)
        let request = UNNotificationRequest(
            identifier: "pppix_unlock",
            content: content,
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(request)
    }

    private func pppixShield() -> ShieldConfiguration {
        ShieldConfiguration(
            backgroundBlurStyle: .systemUltraThinMaterialDark,
            backgroundColor: UIColor(red: 0.04, green: 0.04, blue: 0.07, alpha: 0.97),
            icon: nil,
            title: ShieldConfiguration.Label(
                text: "🔐 App Protegido",
                color: .white
            ),
            subtitle: ShieldConfiguration.Label(
                text: "Toque na notificação do PPPIX para digitar a senha",
                color: UIColor(white: 0.55, alpha: 1.0)
            ),
            primaryButtonLabel: ShieldConfiguration.Label(
                text: "Digitar Senha →",
                color: .white
            ),
            primaryButtonBackgroundColor: UIColor(red: 0.2, green: 0.4, blue: 1.0, alpha: 1.0)
        )
    }
}

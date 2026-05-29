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
        sharedDefaults?.set(true, forKey: "pppix_show_password_screen")
        sharedDefaults?.set(Date().timeIntervalSince1970, forKey: "pppix_password_request_time")
        sharedDefaults?.synchronize()

        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["pppix_unlock_1", "pppix_unlock_2", "pppix_unlock_3"])

        // Envia 3 notificações espaçadas — a primeira aparece quando o shield fecha ao tocar o botão
        // iOS suprime notificações enquanto o shield está visível, então as próximas servem de fallback
        for i in 1...3 {
            let content = UNMutableNotificationContent()
            content.title = "🔐 App Protegido"
            content.body = "Toque aqui para digitar sua senha"
            content.sound = UNNotificationSound.default
            content.userInfo = ["action": "unlock"]
            content.categoryIdentifier = "PPPIX_UNLOCK"

            let trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: Double(i) * 1.0,
                repeats: false
            )
            let request = UNNotificationRequest(
                identifier: "pppix_unlock_\(i)",
                content: content,
                trigger: trigger
            )
            center.add(request)
        }
    }

    private func pppixShield() -> ShieldConfiguration {
        ShieldConfiguration(
            backgroundBlurStyle: .systemUltraThinMaterialDark,
            backgroundColor: UIColor(red: 0.04, green: 0.04, blue: 0.07, alpha: 0.97),
            icon: nil,
            title: ShieldConfiguration.Label(
                text: "🔒 Você está fora de casa!",
                color: .white
            ),
            subtitle: ShieldConfiguration.Label(
                text: "Desbloqueie o app clicando na notificação exibida...",
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

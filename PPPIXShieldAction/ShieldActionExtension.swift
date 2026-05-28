import ManagedSettings
import Foundation
import UserNotifications

class ShieldActionExtension: ShieldActionDelegate {

    private let sharedDefaults = UserDefaults(suiteName: "group.tech.pppix.app")

    override func handle(action: ShieldAction,
                         for application: ApplicationToken,
                         completionHandler: @escaping (ShieldActionResponse) -> Void) {
        sendUnlockNotification()
        completionHandler(.close)
    }

    override func handle(action: ShieldAction,
                         for webDomain: WebDomainToken,
                         completionHandler: @escaping (ShieldActionResponse) -> Void) {
        sendUnlockNotification()
        completionHandler(.close)
    }

    override func handle(action: ShieldAction,
                         for category: ActivityCategoryToken,
                         completionHandler: @escaping (ShieldActionResponse) -> Void) {
        sendUnlockNotification()
        completionHandler(.close)
    }

    private func sendUnlockNotification() {
        // Sinaliza via UserDefaults para o app principal
        sharedDefaults?.set(true, forKey: "pppix_show_password_screen")
        sharedDefaults?.set(Date().timeIntervalSince1970, forKey: "pppix_password_request_time")
        sharedDefaults?.synchronize()

        // Envia notificação local imediata — usuário toca e o PPPIX abre
        let content = UNMutableNotificationContent()
        content.title = "🔐 App Protegido"
        content.body = "Toque aqui para digitar sua senha e abrir o app"
        content.sound = .default
        content.userInfo = ["action": "unlock"]

        // URL scheme no categoryIdentifier para abrir diretamente
        if let url = URL(string: "pppix://unlock") {
            content.userInfo["url"] = url.absoluteString
        }

        // Disparo imediato (0.1 segundos)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        let request = UNNotificationRequest(
            identifier: "pppix_unlock_\(Date().timeIntervalSince1970)",
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("[PPPIX Shield] Erro notificação: \(error)")
            }
        }
    }
}

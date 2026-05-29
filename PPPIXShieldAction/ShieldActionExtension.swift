import ManagedSettings
import Foundation
import UserNotifications

class ShieldActionExtension: ShieldActionDelegate {

    private let sharedDefaults = UserDefaults(suiteName: "group.tech.pppix.app")

    override func handle(action: ShieldAction,
                         for application: ApplicationToken,
                         completionHandler: @escaping (ShieldActionResponse) -> Void) {
        triggerPasswordScreen()
        completionHandler(.close)
    }

    override func handle(action: ShieldAction,
                         for webDomain: WebDomainToken,
                         completionHandler: @escaping (ShieldActionResponse) -> Void) {
        triggerPasswordScreen()
        completionHandler(.close)
    }

    override func handle(action: ShieldAction,
                         for category: ActivityCategoryToken,
                         completionHandler: @escaping (ShieldActionResponse) -> Void) {
        triggerPasswordScreen()
        completionHandler(.close)
    }

    private func triggerPasswordScreen() {
        // Debounce: só registrar nova requisição se a última foi há mais de 3 segundos
        let lastRequest = sharedDefaults?.double(forKey: "pppix_password_request_time") ?? 0
        let timeSinceLast = Date().timeIntervalSince1970 - lastRequest
        guard timeSinceLast > 3 else { return }

        sharedDefaults?.set(true, forKey: "pppix_show_password_screen")
        sharedDefaults?.set(Date().timeIntervalSince1970, forKey: "pppix_password_request_time")
        sharedDefaults?.synchronize()

        // Notificação genérica
        let content = UNMutableNotificationContent()
        content.title = "Acesso protegido"
        content.body = "Desbloqueie o uso fora de casa do seu aplicativo..."
        content.sound = UNNotificationSound.default
        content.userInfo = ["action": "unlock"]
        content.categoryIdentifier = "PPPIX_UNLOCK"

        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: ["pppix_unlock"])

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        let request = UNNotificationRequest(
            identifier: "pppix_unlock",
            content: content,
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(request)
    }
}

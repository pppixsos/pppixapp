import ManagedSettings
import Foundation
import UserNotifications

class ShieldActionExtension: ShieldActionDelegate {

    private let store = ManagedSettingsStore(named: ManagedSettingsStore.Name("pppix"))
    private let sharedDefaults = UserDefaults(suiteName: "group.tech.pppix.app")

    override func handle(action: ShieldAction,
                         for application: ApplicationToken,
                         completionHandler: @escaping (ShieldActionResponse) -> Void) {
        openPPPIX()
        completionHandler(.close)
    }

    override func handle(action: ShieldAction,
                         for webDomain: WebDomainToken,
                         completionHandler: @escaping (ShieldActionResponse) -> Void) {
        openPPPIX()
        completionHandler(.close)
    }

    override func handle(action: ShieldAction,
                         for category: ActivityCategoryToken,
                         completionHandler: @escaping (ShieldActionResponse) -> Void) {
        openPPPIX()
        completionHandler(.close)
    }

    private func openPPPIX() {
        // Sinaliza para o app principal via UserDefaults
        sharedDefaults?.set(true, forKey: "pppix_show_password_screen")
        sharedDefaults?.set(Date().timeIntervalSince1970, forKey: "pppix_password_request_time")
        sharedDefaults?.synchronize()

        // Envia notificação para abrir o PPPIX — aparece assim que o shield fecha
        let content = UNMutableNotificationContent()
        content.title = "🔐 PPPIX"
        content.body = "Toque para digitar sua senha"
        content.sound = UNNotificationSound.default
        content.userInfo = ["action": "unlock"]
        content.categoryIdentifier = "PPPIX_UNLOCK"

        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: ["pppix_unlock"])

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.3, repeats: false)
        let request = UNNotificationRequest(
            identifier: "pppix_unlock",
            content: content,
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(request)
    }
}

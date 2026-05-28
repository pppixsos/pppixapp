import ManagedSettings
import Foundation
import UserNotifications

class ShieldActionExtension: ShieldActionDelegate {

    private let store = ManagedSettingsStore(named: ManagedSettingsStore.Name("pppix"))

    private let sharedDefaults = UserDefaults(suiteName: "group.tech.pppix.app")

    override func handle(action: ShieldAction,
                         for application: ApplicationToken,
                         completionHandler: @escaping (ShieldActionResponse) -> Void) {
        // Salvar bundle ID do app bloqueado para abrir após senha
        if let bundleId = application.bundleIdentifier {
            sharedDefaults?.set(bundleId, forKey: "pppix_target_bundle_id")
            sharedDefaults?.synchronize()
        }
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

    private func sendUnlockNotification(bundleId: String = "") {
        sharedDefaults?.set(true, forKey: "pppix_show_password_screen")
        sharedDefaults?.set(Date().timeIntervalSince1970, forKey: "pppix_password_request_time")
        if !bundleId.isEmpty {
            sharedDefaults?.set(bundleId, forKey: "pppix_target_bundle_id")
        }
        sharedDefaults?.synchronize()

        let center = UNUserNotificationCenter.current()

        // Registrar categoria com botão que abre o app (foreground)
        let unlockAction = UNNotificationAction(
            identifier: "UNLOCK_ACTION",
            title: "🔑 Digitar Senha",
            options: [.foreground]
        )
        let category = UNNotificationCategory(
            identifier: "PPPIX_UNLOCK",
            actions: [unlockAction],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([category])

        let content = UNMutableNotificationContent()
        content.title = "🔐 App Protegido pelo PPPIX"
        content.body = "Toque para digitar sua senha e abrir o app"
        content.sound = .default
        content.userInfo = ["action": "unlock"]
        content.categoryIdentifier = "PPPIX_UNLOCK"

        // Remover notificações antigas pendentes
        center.removePendingNotificationRequests(withIdentifiers: ["pppix_unlock"])

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.5, repeats: false)
        let request = UNNotificationRequest(
            identifier: "pppix_unlock",
            content: content,
            trigger: trigger
        )

        center.add(request)
    }
}

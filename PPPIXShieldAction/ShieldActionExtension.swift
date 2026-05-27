import ManagedSettings
import Foundation
import UserNotifications

class ShieldActionExtension: ShieldActionDelegate {

    private let sharedDefaults = UserDefaults(suiteName: "group.tech.pppix.app")

    override func handle(action: ShieldAction, for application: ApplicationToken, completionHandler: @escaping (ShieldActionResponse) -> Void) {
        if case .primaryButtonPressed = action { requestUnlock() }
        completionHandler(.defer)
    }

    override func handle(action: ShieldAction, for webDomain: WebDomainToken, completionHandler: @escaping (ShieldActionResponse) -> Void) {
        if case .primaryButtonPressed = action { requestUnlock() }
        completionHandler(.defer)
    }

    override func handle(action: ShieldAction, for category: ActivityCategoryToken, completionHandler: @escaping (ShieldActionResponse) -> Void) {
        if case .primaryButtonPressed = action { requestUnlock() }
        completionHandler(.defer)
    }

    private func requestUnlock() {
        sharedDefaults?.set(true, forKey: "pppix_unlock_requested")
        sharedDefaults?.set(Date().timeIntervalSince1970, forKey: "pppix_unlock_timestamp")
        sharedDefaults?.synchronize()

        let content = UNMutableNotificationContent()
        content.title = "PPPIX"
        content.body = "Toque para desbloquear"
        content.sound = .default
        content.userInfo = ["action": "unlock"]

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        let request = UNNotificationRequest(
            identifier: "pppix_unlock_\(Date().timeIntervalSince1970)",
            content: content,
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(request)
    }
}

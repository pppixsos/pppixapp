import ManagedSettings
import Foundation
import UserNotifications

class ShieldActionExtension: ShieldActionDelegate {

    private let sharedDefaults = UserDefaults(suiteName: "group.tech.pppix.app")

    override func handle(action: ShieldAction, for application: Application, completionHandler: @escaping (ShieldActionResponse) -> Void) {
        if case .primaryButtonPressed = action {
            requestUnlock()
        }
        completionHandler(.defer)
    }

    override func handle(action: ShieldAction, for webDomain: WebDomain, completionHandler: @escaping (ShieldActionResponse) -> Void) {
        if case .primaryButtonPressed = action {
            requestUnlock()
        }
        completionHandler(.defer)
    }

    private func requestUnlock() {
        // Sinaliza via UserDefaults (funciona se app está em background ativo)
        sharedDefaults?.set(true, forKey: "pppix_unlock_requested")
        sharedDefaults?.set(Date().timeIntervalSince1970, forKey: "pppix_unlock_timestamp")
        sharedDefaults?.synchronize()

        // Envia notificação local para abrir o app (funciona sempre)
        let content = UNMutableNotificationContent()
        content.title = "PPPIX"
        content.body = "Toque para desbloquear"
        content.sound = .default
        content.userInfo = ["action": "unlock"]

        // URL scheme via categoria de notificação
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        let request = UNNotificationRequest(
            identifier: "pppix_unlock_\(Date().timeIntervalSince1970)",
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request)
    }
}

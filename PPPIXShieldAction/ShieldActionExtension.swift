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

        let content = UNMutableNotificationContent()
        content.title = "Acesso protegido"
        content.body = "Toque aqui para digitar a senha"
        content.sound = UNNotificationSound.default
        content.userInfo = ["action": "unlock"]
        content.categoryIdentifier = "PPPIX_UNLOCK"

        // FIX DELAY: .timeSensitive + relevanceScore = 1.0 + trigger nil
        // Isso bypassa o Apple Intelligence classifier que causa 10s de delay
        // trigger nil = entrega IMEDIATA segundo a documentação Apple
        // 0.001s trigger paradoxalmente é MAIS lento que nil
        content.interruptionLevel = .timeSensitive
        content.relevanceScore = 1.0

        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: ["pppix_unlock"])

        // trigger = nil → entrega instantânea (sem passar pelo Intelligence classifier)
        let request = UNNotificationRequest(
            identifier: "pppix_unlock",
            content: content,
            trigger: nil   // nil = imediato, sem delay de AI
        )
        UNUserNotificationCenter.current().add(request)
    }
}

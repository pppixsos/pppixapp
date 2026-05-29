import ManagedSettings
import Foundation
import UserNotifications

class ShieldActionExtension: ShieldActionDelegate {

    private let sharedDefaults = UserDefaults(suiteName: "group.tech.pppix.app")

    override func handle(action: ShieldAction,
                         for application: ApplicationToken,
                         completionHandler: @escaping (ShieldActionResponse) -> Void) {
        guard case .primaryButtonPressed = action else { completionHandler(.close); return }
        handleUnlock(token: application)
        completionHandler(.close)
    }

    override func handle(action: ShieldAction,
                         for webDomain: WebDomainToken,
                         completionHandler: @escaping (ShieldActionResponse) -> Void) {
        guard case .primaryButtonPressed = action else { completionHandler(.close); return }
        handleUnlock(token: nil)
        completionHandler(.close)
    }

    override func handle(action: ShieldAction,
                         for category: ActivityCategoryToken,
                         completionHandler: @escaping (ShieldActionResponse) -> Void) {
        guard case .primaryButtonPressed = action else { completionHandler(.close); return }
        handleUnlock(token: nil)
        completionHandler(.close)
    }

    private func handleUnlock(token: ApplicationToken?) {
        // NÃO remove o shield aqui — shield só é removido após senha correta no PPPIX

        // Salva o token para unlock individual posterior
        if let t = token, let data = try? JSONEncoder().encode(t) {
            sharedDefaults?.set(data, forKey: "pppix_single_app_token_data")
        }

        // FIX DEBOUNCE: limpa o timestamp para permitir nova solicitação imediata
        // O debounce só bloqueia se a MESMA solicitação chegou em menos de 2s
        let last = sharedDefaults?.double(forKey: "pppix_password_request_time") ?? 0
        let sinceLastRequest = Date().timeIntervalSince1970 - last
        guard sinceLastRequest > 2 else { return }

        sharedDefaults?.set(true, forKey: "pppix_show_password_screen")
        sharedDefaults?.set(Date().timeIntervalSince1970, forKey: "pppix_password_request_time")
        sharedDefaults?.synchronize()

        sendUnlockNotification()
    }

    private func sendUnlockNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Acesso protegido"
        content.body = "Toque aqui para digitar a senha"
        content.sound = .default
        content.userInfo = ["action": "unlock"]
        content.categoryIdentifier = "PPPIX_UNLOCK"
        content.interruptionLevel = .timeSensitive
        content.relevanceScore = 1.0

        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: ["pppix_unlock"])

        let request = UNNotificationRequest(
            identifier: "pppix_unlock",
            content: content,
            trigger: nil  // imediato
        )
        UNUserNotificationCenter.current().add(request)
    }
}

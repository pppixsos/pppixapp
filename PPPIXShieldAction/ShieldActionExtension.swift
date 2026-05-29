import ManagedSettings
import Foundation
import UserNotifications

class ShieldActionExtension: ShieldActionDelegate {

    private let sharedDefaults = UserDefaults(suiteName: "group.tech.pppix.app")

    // REGRA FUNDAMENTAL: NÃO desbloqueia aqui.
    // O shield só é removido DEPOIS que o usuário digita a senha correta no PPPIX.
    // Aqui só: salva o token, sinaliza que precisa de senha, envia notificação.

    override func handle(action: ShieldAction,
                         for application: ApplicationToken,
                         completionHandler: @escaping (ShieldActionResponse) -> Void) {
        guard case .primaryButtonPressed = action else { completionHandler(.close); return }

        let last = sharedDefaults?.double(forKey: "pppix_password_request_time") ?? 0
        guard Date().timeIntervalSince1970 - last > 3 else { completionHandler(.close); return }

        // Salva o token do app que foi tocado — usado pelo ScreenTimeManager para unlock individual
        if let tokenData = try? JSONEncoder().encode(application) {
            sharedDefaults?.set(tokenData, forKey: "pppix_single_app_token_data")
        }

        // Sinaliza que precisa de senha
        sharedDefaults?.set(true, forKey: "pppix_show_password_screen")
        sharedDefaults?.set(Date().timeIntervalSince1970, forKey: "pppix_password_request_time")
        sharedDefaults?.synchronize()

        // Envia notificação para abrir PPPIX
        sendUnlockNotification()

        // .close fecha o shield e mostra o app bloqueado por baixo (ainda bloqueado)
        // O usuário vai ver a notificação e tocar nela para abrir o PPPIX e digitar senha
        completionHandler(.close)
    }

    override func handle(action: ShieldAction,
                         for webDomain: WebDomainToken,
                         completionHandler: @escaping (ShieldActionResponse) -> Void) {
        guard case .primaryButtonPressed = action else { completionHandler(.close); return }
        let last = sharedDefaults?.double(forKey: "pppix_password_request_time") ?? 0
        guard Date().timeIntervalSince1970 - last > 3 else { completionHandler(.close); return }
        sharedDefaults?.set(true, forKey: "pppix_show_password_screen")
        sharedDefaults?.set(Date().timeIntervalSince1970, forKey: "pppix_password_request_time")
        sharedDefaults?.synchronize()
        sendUnlockNotification()
        completionHandler(.close)
    }

    override func handle(action: ShieldAction,
                         for category: ActivityCategoryToken,
                         completionHandler: @escaping (ShieldActionResponse) -> Void) {
        guard case .primaryButtonPressed = action else { completionHandler(.close); return }
        let last = sharedDefaults?.double(forKey: "pppix_password_request_time") ?? 0
        guard Date().timeIntervalSince1970 - last > 3 else { completionHandler(.close); return }
        sharedDefaults?.set(true, forKey: "pppix_show_password_screen")
        sharedDefaults?.set(Date().timeIntervalSince1970, forKey: "pppix_password_request_time")
        sharedDefaults?.synchronize()
        sendUnlockNotification()
        completionHandler(.close)
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

        let request = UNNotificationRequest(identifier: "pppix_unlock", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

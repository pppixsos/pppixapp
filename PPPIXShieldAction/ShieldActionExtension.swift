import ManagedSettings
import Foundation
import UserNotifications

class ShieldActionExtension: ShieldActionDelegate {

    private let store = ManagedSettingsStore(named: .init("pppix"))
    private let sharedDefaults = UserDefaults(suiteName: "group.tech.pppix.app")

    // MARK: - Handle shield button tap

    override func handle(action: ShieldAction,
                         for application: ApplicationToken,
                         completionHandler: @escaping (ShieldActionResponse) -> Void) {
        switch action {
        case .primaryButtonPressed:
            // Debounce: ignora cliques repetidos em 3s
            let last = sharedDefaults?.double(forKey: "pppix_password_request_time") ?? 0
            guard Date().timeIntervalSince1970 - last > 3 else {
                completionHandler(.close)
                return
            }

            // FIX UNLOCK INDIVIDUAL:
            // A extensão já TEM o ApplicationToken correto aqui — não precisa de UserDefaults.
            // Remove APENAS esse token do store diretamente.
            var current = store.shield.applications ?? []
            current.remove(application)
            store.shield.applications = current.isEmpty ? nil : current

            // Salva o token para o reblock posterior (60s)
            if let tokenData = try? JSONEncoder().encode(application) {
                sharedDefaults?.set(tokenData, forKey: "pppix_single_app_token_data")
            }

            // Salva timestamp do unlock para reblock
            let unlockUntil = Date().timeIntervalSince1970 + 60
            sharedDefaults?.set(unlockUntil, forKey: "pppix_unlocked_until")

            // Agenda notificação de reblock após 60s (3 camadas de segurança)
            scheduleReblock(after: 60)

            // Sinaliza para o app abrir tela de senha
            sharedDefaults?.set(true, forKey: "pppix_show_password_screen")
            sharedDefaults?.set(Date().timeIntervalSince1970, forKey: "pppix_password_request_time")
            sharedDefaults?.synchronize()

            // Notificação para o usuário abrir o PPPIX
            sendUnlockNotification()

            completionHandler(.close)

        default:
            completionHandler(.close)
        }
    }

    override func handle(action: ShieldAction,
                         for webDomain: WebDomainToken,
                         completionHandler: @escaping (ShieldActionResponse) -> Void) {
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
        let last = sharedDefaults?.double(forKey: "pppix_password_request_time") ?? 0
        guard Date().timeIntervalSince1970 - last > 3 else { completionHandler(.close); return }
        sharedDefaults?.set(true, forKey: "pppix_show_password_screen")
        sharedDefaults?.set(Date().timeIntervalSince1970, forKey: "pppix_password_request_time")
        sharedDefaults?.synchronize()
        sendUnlockNotification()
        completionHandler(.close)
    }

    // MARK: - Notificação para abrir PPPIX

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

        // trigger nil = entrega imediata, bypassa Apple Intelligence classifier
        let request = UNNotificationRequest(identifier: "pppix_unlock", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Reblock agendado (camada 2 de segurança)
    // Camada 1: ShieldConfigurationExtension verifica timestamp ao ser chamado
    // Camada 2: notificação silenciosa agendada aqui reaplica o shield
    // Camada 3: foreground check no ScreenTimeManager

    private func scheduleReblock(after seconds: TimeInterval) {
        let content = UNMutableNotificationContent()
        content.userInfo = ["action": "reblock"]
        content.interruptionLevel = .passive  // silenciosa

        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: ["pppix_reblock"])

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
        let request = UNNotificationRequest(identifier: "pppix_reblock", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }
}

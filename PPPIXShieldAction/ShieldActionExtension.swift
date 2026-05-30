import ManagedSettings
import Foundation
import UserNotifications

class ShieldActionExtension: ShieldActionDelegate {

    // Store com mesmo nome que o app principal — compartilha configurações (iOS 16+)
    private let store = ManagedSettingsStore(named: .init("pppix"))
    private let sharedDefaults = UserDefaults(suiteName: "group.tech.pppix.app")

    override func handle(action: ShieldAction,
                         for application: ApplicationToken,
                         completionHandler: @escaping (ShieldActionResponse) -> Void) {
        guard case .primaryButtonPressed = action else { completionHandler(.close); return }

        let last = sharedDefaults?.double(forKey: "pppix_password_request_time") ?? 0
        guard Date().timeIntervalSince1970 - last > 2 else { completionHandler(.close); return }

        // SOLUÇÃO DEFINITIVA UNLOCK INDIVIDUAL:
        // NÃO remove o shield aqui — apenas sinaliza e envia notificação.
        // O unlock real (remover só esse token) é feito no ScreenTimeManager
        // APÓS a senha ser digitada. O token é passado via UserDefaults como Data
        // usando o mesmo processo, mas aqui também fazemos o unlock direto
        // para garantir que funcione mesmo se o app principal não abrir a tempo.
        //
        // ABORDAGEM: guardar o token E fazer uma cópia do set atual sem ele
        // para que o ScreenTimeManager possa restaurar exatamente esse estado.

        // Salva o bundle ID para identificar o app na tela de desbloqueio
        // ApplicationToken não tem bundleIdentifier exposto — salvamos o set atual sem esse token
        let currentApps = store.shield.applications ?? []
        var remaining = currentApps
        remaining.remove(application)

        // Salva: conjunto restante (para restaurar após unlock), e token (para reblock)
        if let currentData = try? JSONEncoder().encode(currentApps) {
            sharedDefaults?.set(currentData, forKey: "pppix_shield_apps_before_unlock")
        }
        if let tokenData = try? JSONEncoder().encode(application) {
            sharedDefaults?.set(tokenData, forKey: "pppix_single_app_token_data")
        }

        sharedDefaults?.set(true, forKey: "pppix_show_password_screen")
        sharedDefaults?.set(Date().timeIntervalSince1970, forKey: "pppix_password_request_time")
        sharedDefaults?.synchronize()

        sendUnlockNotification()
        completionHandler(.close)
    }

    override func handle(action: ShieldAction,
                         for webDomain: WebDomainToken,
                         completionHandler: @escaping (ShieldActionResponse) -> Void) {
        guard case .primaryButtonPressed = action else { completionHandler(.close); return }
        let last = sharedDefaults?.double(forKey: "pppix_password_request_time") ?? 0
        guard Date().timeIntervalSince1970 - last > 2 else { completionHandler(.close); return }
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
        guard Date().timeIntervalSince1970 - last > 2 else { completionHandler(.close); return }
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

        // Delay de 2s para garantir que o banco minimizou antes da notificação aparecer
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false)
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: ["pppix_unlock"])
        let request = UNNotificationRequest(identifier: "pppix_unlock", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }
}

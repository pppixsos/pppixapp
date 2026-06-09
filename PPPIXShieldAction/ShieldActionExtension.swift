import ManagedSettings
import Foundation
import UserNotifications
import DeviceActivity

class ShieldActionExtension: ShieldActionDelegate {

    private let store = ManagedSettingsStore(named: .init("pppix"))
    private let sharedDefaults = UserDefaults(suiteName: "group.tech.pppix.app")

    override func handle(action: ShieldAction,
                         for application: ApplicationToken,
                         completionHandler: @escaping (ShieldActionResponse) -> Void) {
        guard case .primaryButtonPressed = action else { completionHandler(.close); return }

        let last = sharedDefaults?.double(forKey: "pppix_password_request_time") ?? 0
        guard Date().timeIntervalSince1970 - last > 2 else { completionHandler(.close); return }

        // Salvar estado para unlock
        if let currentData = try? JSONEncoder().encode(store.shield.applications ?? []) {
            sharedDefaults?.set(currentData, forKey: "pppix_shield_apps_before_unlock")
        }
        if let tokenData = try? JSONEncoder().encode(application) {
            sharedDefaults?.set(tokenData, forKey: "pppix_single_app_token_data")
        }

        sharedDefaults?.set(true, forKey: "pppix_show_password_screen")
        sharedDefaults?.set(Date().timeIntervalSince1970, forKey: "pppix_password_request_time")
        sharedDefaults?.synchronize()

        // Fechar o app bancário
        completionHandler(.close)

        // Agendar relock via DeviceActivity (funciona com app fechado)
        scheduleRelock(afterSeconds: 30)

        // Enviar notificação de unlock com delay curto
        // O delay garante que o app bancário já foi fechado antes do banner aparecer
        sendUnlockNotification()
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
        completionHandler(.close)
        scheduleRelock(afterSeconds: 30)
        sendUnlockNotification()
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
        completionHandler(.close)
        scheduleRelock(afterSeconds: 30)
        sendUnlockNotification()
    }

    // MARK: - Relock via DeviceActivity
    private func scheduleRelock(afterSeconds seconds: Double) {
        let reblockDate = Date().addingTimeInterval(seconds)
        sharedDefaults?.set(reblockDate.timeIntervalSince1970, forKey: "pppix_relock_scheduled_at")
        sharedDefaults?.synchronize()

        let center = DeviceActivityCenter()
        center.stopMonitoring([.init("pppix.relock")])

        var startComps = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second], from: Date())
        var endComps = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second], from: reblockDate)

        // Garantir diferença mínima
        if startComps.second == endComps.second && startComps.minute == endComps.minute {
            endComps.second = ((endComps.second ?? 0) + 5) % 60
        }

        let schedule = DeviceActivitySchedule(
            intervalStart: startComps,
            intervalEnd: endComps,
            repeats: false
        )
        try? center.startMonitoring(.init("pppix.relock"), during: schedule)
    }

    // MARK: - Notificação de unlock
    // Aparece como banner na tela inicial após fechar o app bancário
    private func sendUnlockNotification() {
        let content = UNMutableNotificationContent()
        content.title = "🔐 Acesso protegido"
        content.body = "Toque para digitar a senha do PPPIX"
        content.sound = UNNotificationSound.default
        content.userInfo = ["action": "unlock"]
        content.categoryIdentifier = "PPPIX_UNLOCK"
        content.interruptionLevel = .timeSensitive
        content.relevanceScore = 1.0

        // 1.5s de delay — tempo para o app bancário fechar e a home aparecer
        // Banner aparece na home screen normalmente
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: ["pppix_unlock"])
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1.5, repeats: false)
        let request = UNNotificationRequest(identifier: "pppix_unlock", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }
}

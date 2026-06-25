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

        // Tentar salvar o bundle ID do app — funciona dentro da extensão
        // (Application.bundleIdentifier é acessível no contexto do shield)
        let app = Application(token: application)
        if let bundleId = app.bundleIdentifier {
            sharedDefaults?.set(bundleId, forKey: "pppix_target_bundle_id")
            print("[ShieldAction] bundle ID salvo: \(bundleId)")
        }

        sharedDefaults?.set(true, forKey: "pppix_show_password_screen")
        sharedDefaults?.set(Date().timeIntervalSince1970, forKey: "pppix_password_request_time")
        sharedDefaults?.synchronize()

        // .close fecha o app bloqueado e vai para a Home.
        // O PPPIX abre via notificação, o usuário digita a senha,
        // e o ArrowUnlockView minimiza o PPPIX — o iOS então
        // mostra o app desbloqueado na Home para o usuário abrir.
        // .defer não funcionou pois o iOS não retorna automaticamente
        // ao app pausado quando o PPPIX minimiza.
        completionHandler(.defer)

        // Agendar relock
        scheduleRelock(afterSeconds: 30)

        // Notificação de unlock
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
        completionHandler(.defer)
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
        completionHandler(.defer)
        scheduleRelock(afterSeconds: 30)
        sendUnlockNotification()
    }

    // MARK: - Relock via DeviceActivity
    // IMPORTANTE: DeviceActivitySchedule só tem granularidade de MINUTO.
    // Componentes de "second" são ignorados pelo sistema — usar segundos
    // faz o schedule nunca disparar (intervalStart == intervalEnd no mesmo minuto).
    // Por isso arredondamos para o próximo minuto cheio + 1 minuto de folga.
    private func scheduleRelock(afterSeconds seconds: Double) {
        let now = Date()
        let reblockDate = now.addingTimeInterval(max(seconds, 60))
        sharedDefaults?.set(reblockDate.timeIntervalSince1970, forKey: "pppix_relock_scheduled_at")
        sharedDefaults?.synchronize()

        let center = DeviceActivityCenter()
        // Nome único por timestamp — evita que o segundo unlock cancele
        // o DeviceActivity do primeiro app desbloqueado
        let activityName = DeviceActivityName("pppix.relock.\(Int(reblockDate.timeIntervalSince1970))")

        var cal = Calendar.current
        cal.timeZone = TimeZone.current

        var startComps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: now)
        startComps.second = 0

        let endDate = cal.date(byAdding: .minute, value: 1, to: reblockDate) ?? reblockDate
        var endComps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: endDate)
        endComps.second = 0

        let schedule = DeviceActivitySchedule(
            intervalStart: startComps,
            intervalEnd: endComps,
            repeats: false
        )
        try? center.startMonitoring(activityName, during: schedule)
    }

    // MARK: - Notificação de unlock
    // Abre o PPPIX assim que possível após o app bloqueado fechar.
    // Delay mínimo de 0.3s para garantir que o app bloqueado já fechou.
    // O banner aparece com ação única — tocar abre o PPPIX direto na senha.
    private func sendUnlockNotification() {
        let content = UNMutableNotificationContent()
        content.title = "🔐 Digite sua senha PPPIX"
        content.body = "Toque aqui para continuar"
        content.sound = UNNotificationSound.default
        content.userInfo = ["action": "unlock"]
        content.categoryIdentifier = "PPPIX_UNLOCK"
        content.interruptionLevel = .timeSensitive
        content.relevanceScore = 1.0

        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: ["pppix_unlock"])
        UNUserNotificationCenter.current()
            .removeDeliveredNotifications(withIdentifiers: ["pppix_unlock"])

        // 0.3s — tempo mínimo para o app bloqueado fechar
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.3, repeats: false)
        let request = UNNotificationRequest(identifier: "pppix_unlock", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }
}

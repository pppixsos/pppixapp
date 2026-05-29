import SwiftUI
import FirebaseCore
import FirebaseMessaging
import UserNotifications

@main
struct PPPIXApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
        }
    }
}

class AppDelegate: NSObject, UIApplicationDelegate {

    static var pendingUnlockScreen = false
    static var skipNextAuthReset = false

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        setupNotificationCategories()
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound, .badge, .timeSensitive]) { granted, _ in
            if granted {
                DispatchQueue.main.async {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }
        }

        Task { @MainActor in
            #if !targetEnvironment(simulator)
            ScreenTimeManager.shared.checkAuthorization()
            #endif
        }

        // Firebase — configurar ANTES de registerForRemoteNotifications
        if Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil {
            FirebaseApp.configure()
            Messaging.messaging().delegate = self
            // Desativa o swizzling manual — usamos delegate próprio
            Messaging.messaging().isAutoInitEnabled = true
        }

        BackgroundTaskManager.shared.registerTasks()
        return true
    }

    private func setupNotificationCategories() {
        let unlockAction = UNNotificationAction(
            identifier: "UNLOCK_ACTION",
            title: "🔑 Digitar Senha",
            options: [.foreground]
        )
        let category = UNNotificationCategory(
            identifier: "PPPIX_UNLOCK",
            actions: [unlockAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        // Passa o token APNS para o Firebase — crítico para FCM funcionar no iOS
        Messaging.messaging().apnsToken = deviceToken
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {}

    // Handler de mensagens FCM em background/killed (data-only messages)
    // Chamado pelo iOS quando chega push com content-available:1
    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {

        // Passa para o Firebase processar primeiro
        Messaging.messaging().appDidReceiveMessage(userInfo)

        let payload = Self.extractPayload(userInfo)
        let action = payload["action"] as? String ?? ""

        // Notificação de alerta de emergência vinda do backend
        if action != "unlock" && action != "reblock" {
            if processEmergencyAlert(payload: payload) {
                completionHandler(.newData)
                return
            }
        }

        completionHandler(.noData)
    }

    func application(_ app: UIApplication, open url: URL,
                     options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        if url.scheme == "pppix" && url.host == "unlock" { triggerUnlockScreen() }
        return true
    }

    func triggerUnlockScreen() {
        AppDelegate.pendingUnlockScreen = true
        let d = UserDefaults(suiteName: "group.tech.pppix.app")
        d?.set(true, forKey: "pppix_show_password_screen")
        d?.set(Date().timeIntervalSince1970, forKey: "pppix_password_request_time")
        d?.synchronize()
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .pppixForceOpenUnlockScreen, object: nil)
        }
    }

    // Processa alerta de emergência — retorna true se era um alerta
    @discardableResult
    private func processEmergencyAlert(payload: [String: Any]) -> Bool {
        let alertType   = str(payload["alert_type"])
        let senderEmail = str(payload["sender_email"])
        let myEmail     = SessionManager.shared.userEmail

        guard !alertType.isEmpty,
              !senderEmail.isEmpty,
              senderEmail.lowercased() != myEmail.lowercased() else { return false }

        let isEmergency = alertType.contains("emergency") || alertType.contains("alert")
                       || alertType == "wrong_password"
        guard isEmergency else { return false }

        let alertId = intVal(payload["alert_id"])

        // Mostra notificação local visível (garante entrega mesmo se app está morto)
        let senderName = senderEmail.components(separatedBy: "@").first ?? senderEmail
        let content = UNMutableNotificationContent()
        content.title = "🚨 Alerta de Emergência"
        content.body  = "\(senderName) pode estar em perigo! Toque para ver detalhes."
        content.sound = .defaultCritical
        content.userInfo = [
            "alert_id":    String(alertId),
            "alert_type":  alertType,
            "sender_email": senderEmail
        ]
        content.interruptionLevel = .critical

        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "pppix_alert_\(alertId)", content: content, trigger: nil)
        )

        // Notifica o RootView se o app estiver ativo
        EmergencyAudioService.shared.playSiren()
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .incomingEmergencyAlert,
                object: nil,
                userInfo: ["alert_id": alertId]
            )
        }
        return true
    }

    private func str(_ val: Any?) -> String {
        (val as? String) ?? (val as? NSString).map(String.init) ?? ""
    }

    private func intVal(_ val: Any?) -> Int {
        (val as? Int) ?? (val as? String).flatMap(Int.init) ?? (val as? NSString).flatMap { Int($0 as String) } ?? 0
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {

    // App em FOREGROUND — notificação chegou
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        Messaging.messaging().appDidReceiveMessage(notification.request.content.userInfo)
        let payload = Self.extractPayload(notification.request.content.userInfo)
        let action  = payload["action"] as? String ?? ""

        switch action {
        case "unlock":
            // Abre a tela imediatamente sem esperar o usuário tocar
            triggerUnlockScreen()
            completionHandler([.banner, .sound])
        case "reblock":
            Task { @MainActor in
                #if !targetEnvironment(simulator)
                ScreenTimeManager.shared.syncCheckAndReblock()
                #endif
            }
            completionHandler([])
        default:
            processEmergencyAlert(payload: payload)
            completionHandler([.banner, .sound, .badge])
        }
    }

    // Usuário TOCOU na notificação
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        Messaging.messaging().appDidReceiveMessage(response.notification.request.content.userInfo)
        let payload = Self.extractPayload(response.notification.request.content.userInfo)
        let action  = payload["action"] as? String ?? ""

        switch action {
        case "reblock":
            Task { @MainActor in
                #if !targetEnvironment(simulator)
                ScreenTimeManager.shared.syncCheckAndReblock()
                #endif
            }
        case "unlock":
            triggerUnlockScreen()
        default:
            if response.actionIdentifier == "UNLOCK_ACTION" {
                triggerUnlockScreen()
            } else {
                // Toque em notificação de alerta de emergência
                let alertId = intVal(payload["alert_id"])
                if alertId > 0 {
                    EmergencyAudioService.shared.playSiren()
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(
                            name: .incomingEmergencyAlert,
                            object: nil,
                            userInfo: ["alert_id": alertId]
                        )
                    }
                }
            }
        }
        completionHandler()
    }

    // Extrai payload FCM independente do formato
    static func extractPayload(_ userInfo: [AnyHashable: Any]) -> [String: Any] {
        var result = [String: Any]()
        for (k, v) in userInfo { if let key = k as? String { result[key] = v } }
        // Android FCM envia dados em "data"
        for src in [userInfo["data"] as? [AnyHashable: Any],
                    userInfo["data"] as? [String: Any] as? [AnyHashable: Any]] {
            if let d = src { for (k, v) in d { if let key = k as? String { result[key] = v } } }
        }
        return result
    }

    private func intVal(_ val: Any?) -> Int {
        (val as? Int) ?? (val as? String).flatMap(Int.init) ?? (val as? NSString).flatMap { Int($0 as String) } ?? 0
    }
}

extension AppDelegate: MessagingDelegate {
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let token = fcmToken else { return }
        SessionManager.shared.fcmToken = token
        if SessionManager.shared.isLoggedIn {
            Task { try? await APIClient.shared.registerFcmDevice(token: token, platform: "ios") }
        }
    }
}

extension Notification.Name {
    static let openAlertDetail            = Notification.Name("pppix.openAlertDetail")
    static let incomingEmergencyAlert     = Notification.Name("pppix.incomingEmergencyAlert")
    static let sessionExpired             = Notification.Name("pppix.sessionExpired")
    static let openUnlockScreen           = Notification.Name("pppix.openUnlockScreen")
    static let pppixForceOpenUnlockScreen = Notification.Name("pppix.forceOpenUnlockScreen")
}

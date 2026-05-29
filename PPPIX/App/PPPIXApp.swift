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

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Notificações PRIMEIRO — crítico para cold start rápido
        UNUserNotificationCenter.current().delegate = self
        setupNotificationCategories()
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge, .timeSensitive]) { _, _ in }

        // Screen Time
        Task { @MainActor in
            #if !targetEnvironment(simulator)
            ScreenTimeManager.shared.checkAuthorization()
            #endif
        }

        // Firebase em background para não atrasar launch
        Task.detached(priority: .background) {
            if Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil {
                await MainActor.run {
                    FirebaseApp.configure()
                    Messaging.messaging().delegate = self
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }
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
        let unlockCategory = UNNotificationCategory(
            identifier: "PPPIX_UNLOCK",
            actions: [unlockAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        UNUserNotificationCenter.current().setNotificationCategories([unlockCategory])
    }

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {}

    func application(_ app: UIApplication,
                     open url: URL,
                     options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        if url.scheme == "pppix" && url.host == "unlock" {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .pppixForceOpenUnlockScreen, object: nil)
            }
        }
        return true
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let userInfo = extractPayload(notification.request.content.userInfo)
        let action = userInfo["action"] as? String ?? ""

        switch action {
        case "unlock":
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .pppixForceOpenUnlockScreen, object: nil)
            }
            completionHandler([.banner, .sound])

        case "reblock":
            Task { @MainActor in
                #if !targetEnvironment(simulator)
                ScreenTimeManager.shared.syncCheckAndReblock()
                #endif
            }
            completionHandler([])

        default:
            handleIncomingAlert(userInfo: userInfo)
            completionHandler([.banner, .sound, .badge])
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = extractPayload(response.notification.request.content.userInfo)
        let action = userInfo["action"] as? String ?? ""

        if action == "reblock" {
            Task { @MainActor in
                #if !targetEnvironment(simulator)
                ScreenTimeManager.shared.syncCheckAndReblock()
                #endif
            }
            completionHandler()
            return
        }

        if action == "unlock" || response.actionIdentifier == "UNLOCK_ACTION" {
            AppDelegate.pendingUnlockScreen = true
            let defaults = UserDefaults(suiteName: "group.tech.pppix.app")
            defaults?.set(true, forKey: "pppix_show_password_screen")
            defaults?.set(Date().timeIntervalSince1970, forKey: "pppix_password_request_time")
            defaults?.synchronize()
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .pppixForceOpenUnlockScreen, object: nil)
            }
            completionHandler()
            return
        }

        // Alerta de emergência — abre tela
        let alertType = userInfo["alert_type"] as? String ?? ""
        if alertType.contains("emergency") || alertType.contains("alert") || alertType == "wrong_password" {
            let alertId = (userInfo["alert_id"] as? String).flatMap(Int.init)
                       ?? userInfo["alert_id"] as? Int
                       ?? 0
            if alertId > 0 {
                EmergencyAudioService.shared.playSiren()
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .incomingEmergencyAlert, object: nil, userInfo: ["alert_id": alertId])
                }
            }
        }

        if let alertIdStr = userInfo["alert_id"] as? String, let alertId = Int(alertIdStr) {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .openAlertDetail, object: nil, userInfo: ["alert_id": alertId])
            }
        }

        completionHandler()
    }

    // FIX ALERTAS: FCM às vezes envolve o payload em "data" ou "aps"
    // Extrai os campos do nível correto
    private func extractPayload(_ userInfo: [AnyHashable: Any]) -> [String: Any] {
        var result = [String: Any]()

        // Copia campos do nível raiz
        for (key, value) in userInfo {
            if let k = key as? String {
                result[k] = value
            }
        }

        // Se há um dict "data" aninhado, sobrescreve com seus campos
        if let data = userInfo["data"] as? [String: Any] {
            for (k, v) in data { result[k] = v }
        }
        // Também tenta "gcm.notification"
        if let notif = userInfo["gcm.notification"] as? [String: Any] {
            for (k, v) in notif { result[k] = v }
        }

        return result
    }

    private func handleIncomingAlert(userInfo: [String: Any]) {
        let alertType = userInfo["alert_type"] as? String ?? ""
        let senderEmail = userInfo["sender_email"] as? String ?? ""
        let myEmail = SessionManager.shared.userEmail
        guard !senderEmail.isEmpty, senderEmail.lowercased() != myEmail.lowercased() else { return }

        let isEmergency = alertType.contains("emergency") || alertType.contains("alert") || alertType == "wrong_password"
        guard isEmergency else { return }

        let alertId = (userInfo["alert_id"] as? String).flatMap(Int.init)
                   ?? userInfo["alert_id"] as? Int
                   ?? 0

        EmergencyAudioService.shared.playSiren()
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .incomingEmergencyAlert, object: nil, userInfo: ["alert_id": alertId])
        }
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

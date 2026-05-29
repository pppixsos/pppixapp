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

    // Flag para abertura instantânea ao cold start via notificação
    static var pendingUnlockScreen = false

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {

        // Inicializar Screen Time ao abrir o app (fix para rebloquear automaticamente)
        Task { @MainActor in
            ScreenTimeManager.shared.checkAuthorization()
        }

        setupNotificationCategories()

        if let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
           let _ = NSDictionary(contentsOfFile: path) {
            FirebaseApp.configure()
            Messaging.messaging().delegate = self
            application.registerForRemoteNotifications()
        }

        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
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
            postUnlockNotification()
        }
        return true
    }

    private func postUnlockNotification() {
        // Sem delay — abre instantaneamente
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: Notification.Name("pppix.forceOpenUnlockScreen"),
                object: nil
            )
        }
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {

    // Notificação chega com app em FOREGROUND
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let userInfo = notification.request.content.userInfo

        if let action = userInfo["action"] as? String, action == "unlock" {
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: Notification.Name("pppix.forceOpenUnlockScreen"),
                    object: nil
                )
            }
            completionHandler([.banner, .sound])
            return
        }

        handleIncomingAlert(userInfo: userInfo)
        completionHandler([.banner, .sound, .badge])
    }

    // Usuário TOCA na notificação
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo

        if let action = userInfo["action"] as? String, action == "unlock" {
            // Setar flag ESTÁTICO — lido imediatamente pelo RootView mesmo em cold start
            AppDelegate.pendingUnlockScreen = true
            // Setar UserDefaults como backup
            let defaults = UserDefaults(suiteName: "group.tech.pppix.app")
            defaults?.set(true, forKey: "pppix_show_password_screen")
            defaults?.set(Date().timeIntervalSince1970, forKey: "pppix_password_request_time")
            defaults?.synchronize()
            // Postar notificação para caso app esteja em background (já ativo)
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: Notification.Name("pppix.forceOpenUnlockScreen"),
                    object: nil
                )
            }
            completionHandler()
            return
        }

        if response.actionIdentifier == "UNLOCK_ACTION" {
            AppDelegate.pendingUnlockScreen = true
            let defaults = UserDefaults(suiteName: "group.tech.pppix.app")
            defaults?.set(true, forKey: "pppix_show_password_screen")
            defaults?.set(Date().timeIntervalSince1970, forKey: "pppix_password_request_time")
            defaults?.synchronize()
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: Notification.Name("pppix.forceOpenUnlockScreen"),
                    object: nil
                )
            }
            completionHandler()
            return
        }

        if let alertIdStr = userInfo["alert_id"] as? String,
           let alertId = Int(alertIdStr) {
            NotificationCenter.default.post(
                name: .openAlertDetail,
                object: nil,
                userInfo: ["alert_id": alertId]
            )
        }
        completionHandler()
    }

    private func handleIncomingAlert(userInfo: [AnyHashable: Any]) {
        let alertType = userInfo["alert_type"] as? String ?? ""
        let senderEmail = userInfo["sender_email"] as? String ?? ""
        let myEmail = SessionManager.shared.userEmail
        guard !senderEmail.isEmpty, senderEmail.lowercased() != myEmail.lowercased() else { return }
        let isEmergency = alertType.contains("emergency") || alertType.contains("alert") || alertType == "wrong_password"
        if isEmergency {
            let alertId = (userInfo["alert_id"] as? String).flatMap(Int.init) ?? 0
            EmergencyAudioService.shared.playSiren()
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
    static let openAlertDetail        = Notification.Name("pppix.openAlertDetail")
    static let incomingEmergencyAlert = Notification.Name("pppix.incomingEmergencyAlert")
    static let sessionExpired         = Notification.Name("pppix.sessionExpired")
    static let openUnlockScreen       = Notification.Name("pppix.openUnlockScreen")
}

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

        // FIX COLD START: configurar notificações ANTES de qualquer outra coisa
        // para que didReceive seja chamado imediatamente
        UNUserNotificationCenter.current().delegate = self
        setupNotificationCategories()

        // Screen Time — só inicializa se NÃO é cold start via notificação de reblock
        // Evita bloquear o launch thread com operações pesadas
        let isReblockLaunch = launchOptions?[.remoteNotification] != nil
        if !isReblockLaunch {
            Task { @MainActor in
                #if !targetEnvironment(simulator)
                ScreenTimeManager.shared.checkAuthorization()
                #endif
            }
        }

        // Firebase — inicializa de forma lazy para não atrasar o cold start
        Task.detached(priority: .background) {
            if let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
               let _ = NSDictionary(contentsOfFile: path) {
                await MainActor.run {
                    FirebaseApp.configure()
                    Messaging.messaging().delegate = self
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }
        }

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge, .timeSensitive]) { _, _ in }
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

    // Notificação chega com app em FOREGROUND
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let userInfo = notification.request.content.userInfo
        let action = userInfo["action"] as? String ?? ""

        switch action {
        case "unlock":
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .pppixForceOpenUnlockScreen, object: nil)
            }
            completionHandler([.banner, .sound])
        case "reblock":
            // Notificação silenciosa de reblock — reaplica shield
            Task { @MainActor in
                #if !targetEnvironment(simulator)
                ScreenTimeManager.shared.syncCheckAndReblock()
                #endif
            }
            completionHandler([])  // silenciosa
        default:
            handleIncomingAlert(userInfo: userInfo)
            completionHandler([.banner, .sound, .badge])
        }
    }

    // Usuário TOCA na notificação (background ou killed)
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        let action = userInfo["action"] as? String ?? ""

        if action == "reblock" {
            // Reblock silencioso — não abre UI
            Task { @MainActor in
                #if !targetEnvironment(simulator)
                ScreenTimeManager.shared.syncCheckAndReblock()
                #endif
            }
            completionHandler()
            return
        }

        if action == "unlock" || response.actionIdentifier == "UNLOCK_ACTION" {
            // FIX COLD START: setar flag ANTES do SwiftUI montar qualquer view
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
    static let pppixForceOpenUnlockScreen = Notification.Name("pppix.forceOpenUnlockScreen")
}

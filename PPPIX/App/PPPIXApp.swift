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

// MARK: - AppDelegate

class AppDelegate: NSObject, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Firebase
        FirebaseApp.configure()

        // Push notifications
        UNUserNotificationCenter.current().delegate = self
        Messaging.messaging().delegate = self

        // Registra para push remoto (necessário para APNs / FCM)
        application.registerForRemoteNotifications()

        // Background tasks
        BackgroundTaskManager.shared.registerTasks()

        return true
    }

    // APNs token → repassa ao Firebase
    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("[PPPIX] APNs registration failed: \(error.localizedDescription)")
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension AppDelegate: UNUserNotificationCenterDelegate {

    // Mostra notificação mesmo com app em foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let userInfo = notification.request.content.userInfo
        handleIncomingAlert(userInfo: userInfo)
        completionHandler([.banner, .sound, .badge])
    }

    // Usuário tocou na notificação
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
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

        // Ignora alertas enviados por mim mesmo
        guard !senderEmail.lowercased().isEmpty,
              senderEmail.lowercased() != myEmail.lowercased() else { return }

        let isEmergency = alertType == "emergency_password"
            || alertType == "wrong_password"
            || alertType.contains("emergency")
            || alertType.contains("alert")

        if isEmergency {
            let alertId = (userInfo["alert_id"] as? String).flatMap(Int.init) ?? 0
            EmergencyAudioService.shared.playSiren()
            NotificationCenter.default.post(
                name: .incomingEmergencyAlert,
                object: nil,
                userInfo: ["alert_id": alertId]
            )
        }
    }
}

// MARK: - MessagingDelegate (FCM)

extension AppDelegate: MessagingDelegate {

    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let token = fcmToken else { return }
        SessionManager.shared.fcmToken = token
        // Registra no backend se já estiver logado
        if SessionManager.shared.isLoggedIn {
            Task {
                try? await APIClient.shared.registerFcmDevice(token: token, platform: "ios")
            }
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let openAlertDetail       = Notification.Name("pppix.openAlertDetail")
    static let incomingEmergencyAlert = Notification.Name("pppix.incomingEmergencyAlert")
    static let sessionExpired         = Notification.Name("pppix.sessionExpired")
}

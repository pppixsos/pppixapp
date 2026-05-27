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

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {

        if let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
           let _ = NSDictionary(contentsOfFile: path) {
            FirebaseApp.configure()
            UNUserNotificationCenter.current().delegate = self
            Messaging.messaging().delegate = self
            application.registerForRemoteNotifications()
        }

        BackgroundTaskManager.shared.registerTasks()
        return true
    }

    // MARK: - URL Scheme: pppix://unlock
    func application(_ app: UIApplication, open url: URL,
                     options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        if url.scheme == "pppix" && url.host == "unlock" {
            // Notifica RootView para abrir a tela de senha
            NotificationCenter.default.post(name: .openUnlockScreen, object: nil)
            return true
        }
        return false
    }

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("[PPPIX] APNs registration failed: \(error.localizedDescription)")
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let userInfo = notification.request.content.userInfo
        handleIncomingAlert(userInfo: userInfo)
        completionHandler([.banner, .sound, .badge])
    }

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

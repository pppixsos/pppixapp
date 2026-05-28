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

        // Registrar categoria de notificação com action de desbloqueio
        setupNotificationCategories()

        if let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
           let _ = NSDictionary(contentsOfFile: path) {
            FirebaseApp.configure()
            Messaging.messaging().delegate = self
            application.registerForRemoteNotifications()
        }

        UNUserNotificationCenter.current().delegate = self

        // Solicitar permissão de notificações
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            print("[PPPIX] Notificações: \(granted ? "autorizado" : "negado")")
        }

        BackgroundTaskManager.shared.registerTasks()
        return true
    }

    private func setupNotificationCategories() {
        // Action que abre o PPPIX — aparece como botão na notificação
        let unlockAction = UNNotificationAction(
            identifier: "UNLOCK_ACTION",
            title: "🔑 Digitar Senha",
            options: [.foreground] // .foreground abre o app ao tocar
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
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("[PPPIX] APNs registration failed: \(error.localizedDescription)")
    }

    // URL Scheme: pppix://unlock
    func application(_ app: UIApplication,
                     open url: URL,
                     options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        if url.scheme == "pppix" && url.host == "unlock" {
            NotificationCenter.default.post(name: .openUnlockScreen, object: nil)
        }
        return true
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {

    // Chamado quando notificação chega com app em FOREGROUND
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let userInfo = notification.request.content.userInfo

        if let action = userInfo["action"] as? String, action == "unlock" {
            // App em foreground — abrir tela de senha diretamente
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .openUnlockScreen, object: nil)
            }
            // Mostrar banner TAMBÉM para o usuário saber que precisa interagir
            completionHandler([.banner, .sound])
            return
        }

        handleIncomingAlert(userInfo: userInfo)
        completionHandler([.banner, .sound, .badge])
    }

    // Chamado quando usuário TOCA na notificação
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo

        // Toque no banner ou no botão "Digitar Senha"
        if let action = userInfo["action"] as? String, action == "unlock" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                NotificationCenter.default.post(name: .openUnlockScreen, object: nil)
            }
            completionHandler()
            return
        }

        // Botão de ação "UNLOCK_ACTION"
        if response.actionIdentifier == "UNLOCK_ACTION" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                NotificationCenter.default.post(name: .openUnlockScreen, object: nil)
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

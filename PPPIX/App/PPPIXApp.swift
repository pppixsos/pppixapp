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
    // Impede que o próximo ciclo background→active mostre tela de senha
    // Usado quando o usuário abre o app desbloqueado a partir do PPPIX
    static var skipNextAuthReset = false

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        setupNotificationCategories()
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound, .badge, .timeSensitive]) { _, _ in }

        Task { @MainActor in
            #if !targetEnvironment(simulator)
            ScreenTimeManager.shared.checkAuthorization()
            #endif
        }

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
        Messaging.messaging().apnsToken = deviceToken
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {}

    // FIX ALERTAS: handler para mensagens FCM data-only (content-available: 1)
    // Sem isso, mensagens do Android NÃO acordam o app iOS em background
    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        let payload = Self.extractPayload(userInfo)
        let alertType = (payload["alert_type"] as? String)
                     ?? (payload["alert_type"] as? NSString).map(String.init)
                     ?? ""
        let senderEmail = (payload["sender_email"] as? String)
                       ?? (payload["sender_email"] as? NSString).map(String.init)
                       ?? ""
        let myEmail = SessionManager.shared.userEmail

        guard !alertType.isEmpty,
              !senderEmail.isEmpty,
              senderEmail.lowercased() != myEmail.lowercased() else {
            completionHandler(.noData)
            return
        }

        let isEmergency = alertType.contains("emergency") || alertType.contains("alert") || alertType == "wrong_password"
        guard isEmergency else { completionHandler(.noData); return }

        let alertId = (payload["alert_id"] as? String).flatMap(Int.init)
                   ?? (payload["alert_id"] as? NSString).flatMap { Int($0 as String) }
                   ?? payload["alert_id"] as? Int
                   ?? 0

        // Toca sirene e abre tela de emergência
        EmergencyAudioService.shared.playSiren()
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .incomingEmergencyAlert,
                object: nil,
                userInfo: ["alert_id": alertId]
            )
        }

        // Dispara notificação local visível para o usuário (caso esteja com tela apagada)
        let content = UNMutableNotificationContent()
        content.title = "🚨 Alerta de Emergência"
        content.body = senderEmail.isEmpty ? "Um contato precisa de ajuda!" : "\(senderEmail.components(separatedBy: "@").first ?? senderEmail) pode estar em perigo!"
        content.sound = .defaultCritical
        content.userInfo = ["alert_id": String(alertId), "alert_type": alertType, "sender_email": senderEmail]
        content.interruptionLevel = .critical

        let request = UNNotificationRequest(
            identifier: "pppix_emergency_\(alertId)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
        completionHandler(.newData)
    }

    func application(_ app: UIApplication, open url: URL,
                     options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        if url.scheme == "pppix" && url.host == "unlock" {
            triggerUnlockScreen()
        }
        return true
    }

    func triggerUnlockScreen() {
        AppDelegate.pendingUnlockScreen = true
        let defaults = UserDefaults(suiteName: "group.tech.pppix.app")
        defaults?.set(true, forKey: "pppix_show_password_screen")
        defaults?.set(Date().timeIntervalSince1970, forKey: "pppix_password_request_time")
        defaults?.synchronize()
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .pppixForceOpenUnlockScreen, object: nil)
        }
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let userInfo = Self.extractPayload(notification.request.content.userInfo)
        let action = userInfo["action"] as? String ?? ""

        switch action {
        case "unlock":
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
            // Notificação de alerta de emergência em foreground
            let alertType = (userInfo["alert_type"] as? String) ?? ""
            if alertType.contains("emergency") || alertType.contains("alert") {
                handleIncomingAlert(userInfo: userInfo)
            }
            completionHandler([.banner, .sound, .badge])
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = Self.extractPayload(response.notification.request.content.userInfo)
        let action = userInfo["action"] as? String ?? ""

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
                let alertType = (userInfo["alert_type"] as? String) ?? ""
                if alertType.contains("emergency") || alertType.contains("alert") {
                    handleIncomingAlert(userInfo: userInfo)
                } else if let idStr = userInfo["alert_id"] as? String, let id = Int(idStr) {
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(name: .openAlertDetail, object: nil, userInfo: ["alert_id": id])
                    }
                }
            }
        }
        completionHandler()
    }

    // Extrai payload FCM independente do formato (flat ou aninhado em "data")
    static func extractPayload(_ userInfo: [AnyHashable: Any]) -> [String: Any] {
        var result = [String: Any]()
        for (key, value) in userInfo {
            if let k = key as? String { result[k] = value }
        }
        // Android FCM envia dados dentro de "data"
        if let data = userInfo["data"] as? [AnyHashable: Any] {
            for (key, value) in data { if let k = key as? String { result[k] = value } }
        }
        if let data = userInfo["data"] as? [String: Any] {
            for (k, v) in data { result[k] = v }
        }
        return result
    }

    private func handleIncomingAlert(userInfo: [String: Any]) {
        let alertType    = (userInfo["alert_type"] as? String) ?? (userInfo["alert_type"] as? NSString).map(String.init) ?? ""
        let senderEmail  = (userInfo["sender_email"] as? String) ?? (userInfo["sender_email"] as? NSString).map(String.init) ?? ""
        let myEmail      = SessionManager.shared.userEmail
        guard !senderEmail.isEmpty, senderEmail.lowercased() != myEmail.lowercased() else { return }
        let isEmergency  = alertType.contains("emergency") || alertType.contains("alert") || alertType == "wrong_password"
        guard isEmergency else { return }
        let alertId = (userInfo["alert_id"] as? String).flatMap(Int.init)
                   ?? (userInfo["alert_id"] as? NSString).flatMap { Int($0 as String) }
                   ?? userInfo["alert_id"] as? Int ?? 0
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

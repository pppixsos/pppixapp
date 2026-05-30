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

    // IDs de alertas já exibidos — persistido em UserDefaults para não repetir após restart
    private static let processedKey = "pppix_processed_alert_ids"
    private static var _processedCache: Set<Int>? = nil

    private static var processedAlertIds: Set<Int> {
        get {
            if let cached = _processedCache { return cached }
            let arr = UserDefaults.standard.array(forKey: processedKey) as? [Int] ?? []
            let s = Set(arr)
            _processedCache = s
            return s
        }
        set {
            _processedCache = newValue
            // Guarda apenas os últimos 100 IDs para não crescer demais
            let limited = Array(newValue.sorted().suffix(100))
            UserDefaults.standard.set(limited, forKey: processedKey)
            UserDefaults.standard.synchronize()
        }
    }

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        setupNotificationCategories()

        if Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil {
            FirebaseApp.configure()
            Messaging.messaging().delegate = self
        }

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

        // Esquenta o GPS logo que o app abre (igual FusedLocationClient do Android)
        LocationService.shared.warmUp()

        BackgroundTaskManager.shared.registerTasks()

        // Quando usuário fizer login, tentar registrar FCM token se disponível
        NotificationCenter.default.addObserver(
            forName: .pppixUserDidLogin, object: nil, queue: .main) { _ in
            if let token = SessionManager.shared.fcmToken {
                Task { @MainActor in
                    do {
                        try await APIClient.shared.registerFcmDevice(token: token, platform: "ios")
                        AlertDiagnosticLog.shared.log("FCM re-registrado após login")
                    } catch {
                        AlertDiagnosticLog.shared.log("FCM re-registro ERRO: \(error)")
                    }
                }
            } else {
                // Forçar refresh do token FCM
                Messaging.messaging().deleteToken { error in
                    if let error = error {
                        AlertDiagnosticLog.shared.log("FCM deleteToken erro: \(error.localizedDescription)")
                    } else {
                        Messaging.messaging().token { token, error in
                            if let token = token {
                                Task { @MainActor in
                                    AlertDiagnosticLog.shared.log("FCM token forçado: \(token.prefix(20))...")
                                    try? await APIClient.shared.registerFcmDevice(token: token, platform: "ios")
                                }
                            }
                        }
                    }
                }
            }
        }

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
        let tokenStr = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task { @MainActor in AlertDiagnosticLog.shared.log("APNS token OK: \(tokenStr.prefix(20))...") }
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("[PPPIX] APNS register failed: \(error)")
        Task { @MainActor in AlertDiagnosticLog.shared.log("APNS FALHOU: \(error.localizedDescription)") }
        Task { @MainActor in AlertDiagnosticLog.shared.log("[PPPIX] APNS register failed: \(error)") }
    }

    // Chamado para push data-only (silent) — throttled pelo iOS, usar apenas como fallback
    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {

        Messaging.messaging().appDidReceiveMessage(userInfo)

        let payload = Self.extractPayload(userInfo)
        let action = str(payload["action"])

        print("[PPPIX] didReceiveRemoteNotification — action='\(action)' keys=\(Array(payload.keys).sorted())")
        Task { @MainActor in AlertDiagnosticLog.shared.log("[PPPIX] didReceiveRemoteNotification — action='\(action)' keys=\(Array(payload.keys).sorted())") }

        if action == "unlock" {
            triggerUnlockScreen()
            completionHandler(.newData)
        } else if action == "reblock" {
            Task { @MainActor in
                #if !targetEnvironment(simulator)
                ScreenTimeManager.shared.syncCheckAndReblock()
                #endif
            }
            completionHandler(.newData)
        } else {
            // Pode ser alerta de emergência — processar
            if handleEmergencyPayload(payload) {
                completionHandler(.newData)
            } else {
                completionHandler(.noData)
            }
        }
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

    // MARK: - Emergency alert handling

    /// Processa payload de alerta de emergência.
    /// Retorna true se o payload continha um alerta de emergência.
    @discardableResult
    func handleEmergencyPayload(_ payload: [String: Any]) -> Bool {
        let alertType   = str(payload["alert_type"])
        let senderEmail = str(payload["sender_email"])
        let myEmail     = SessionManager.shared.userEmail

        print("[PPPIX] handleEmergencyPayload — type='\(alertType)' sender='\(senderEmail)' me='\(myEmail)'")
        Task { @MainActor in AlertDiagnosticLog.shared.log("RECEBER(FCM): tipo=\(alertType) de=\(senderEmail)") }
        Task { @MainActor in AlertDiagnosticLog.shared.log("[PPPIX] handleEmergencyPayload — type='\(alertType)' sender='\(senderEmail)' me='\(myEmail)'") }

        // Filtra alertas enviados por mim mesmo (igual Android)
        // Só filtra se myEmail está disponível (pode estar vazio em background)
        if !myEmail.isEmpty && !senderEmail.isEmpty &&
           senderEmail.lowercased() == myEmail.lowercased() {
            print("[PPPIX] handleEmergencyPayload — ignorado: é meu próprio alerta")
            Task { @MainActor in AlertDiagnosticLog.shared.log("RECEBER(FCM): IGNORADO - meu próprio alerta") }
            Task { @MainActor in AlertDiagnosticLog.shared.log("[PPPIX] handleEmergencyPayload — ignorado: é meu próprio alerta") }
            return false
        }

        // Deve ter alert_type com conteúdo de emergência (igual Android)
        guard !alertType.isEmpty else { return false }

        let isEmergency = alertType == "emergency_password"
                       || alertType == "wrong_password"
                       || alertType.lowercased().contains("emergency")
                       || alertType.lowercased().contains("alert")
        guard isEmergency else { return false }

        let alertId    = intVal(payload["alert_id"] ?? payload["id"])
        let rawSenderName = str(payload["sender_name"])
        let senderName = rawSenderName.isEmpty ? (senderEmail.components(separatedBy: "@").first ?? "Contato") : rawSenderName

        // Deduplicar: não processar o mesmo alerta duas vezes
        if alertId > 0 {
            guard !AppDelegate.processedAlertIds.contains(alertId) else {
                print("[PPPIX] handleEmergencyPayload — ignorado: alerta \(alertId) já processado")
                Task { @MainActor in AlertDiagnosticLog.shared.log("[PPPIX] handleEmergencyPayload — ignorado: alerta \(alertId) já processado") }
                return false
            }
            AppDelegate.processedAlertIds.insert(alertId)
            // Limita o set a 50 entradas para não crescer indefinidamente
            if AppDelegate.processedAlertIds.count > 50 {
                AppDelegate.processedAlertIds.removeFirst()
            }
        }

        print("[PPPIX] handleEmergencyPayload PROCESSANDO — id=\(alertId) sender=\(senderEmail)")
        Task { @MainActor in AlertDiagnosticLog.shared.log("RECEBER(FCM): PROCESSANDO id=\(alertId) de=\(senderEmail)") }
        Task { @MainActor in AlertDiagnosticLog.shared.log("[PPPIX] handleEmergencyPayload PROCESSANDO — id=\(alertId) sender=\(senderEmail)") }

        let appState = UIApplication.shared.applicationState

        // Sempre criar notificação local com som (toca em QUALQUER estado)
        // A notificação local garante: banner + sirene mesmo se o push FCM não tiver notification
        let notifContent = UNMutableNotificationContent()
        notifContent.title = "🚨 Alerta de Emergência"
        notifContent.body  = "\(senderName) pode estar em perigo! Toque para ver detalhes."
        notifContent.interruptionLevel = .critical
        notifContent.userInfo = [
            "alert_id":     alertId > 0 ? String(alertId) : "0",
            "alert_type":   alertType,
            "sender_email": senderEmail
        ]
        // Som .caf para notificação (único formato aceito pelo iOS para notif sound)
        if Bundle.main.url(forResource: "sirene", withExtension: "caf") != nil {
            notifContent.sound = UNNotificationSound(named: UNNotificationSoundName("sirene.caf"))
        } else {
            notifContent.sound = .defaultCritical
        }
        let identifier = alertId > 0 ? "pppix_alert_\(alertId)" : "pppix_alert_\(Int(Date().timeIntervalSince1970))"

        // Em FOREGROUND: mostrar notificação E tocar sirene via AVAudioPlayer (mais longa)
        // Em BACKGROUND/MORTO: a notificação com UNNotificationSound toca automaticamente
        if appState == .active {
            // App aberto: notificação + sirene AVAudioPlayer ao mesmo tempo
            UNUserNotificationCenter.current().add(
                UNNotificationRequest(identifier: identifier, content: notifContent, trigger: nil)
            )
            EmergencyAudioService.shared.playSiren()
        } else {
            // App em background/morto: só notificação (UNNotificationSound cuida do som)
            UNUserNotificationCenter.current().add(
                UNNotificationRequest(identifier: identifier, content: notifContent, trigger: nil)
            )
        }

        // Notificar a UI para abrir a tela de alerta
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
        (val as? Int) ?? (val as? String).flatMap(Int.init) ?? (val as? NSNumber).map { $0.intValue } ?? 0
    }
}

extension String {
    func ifEmpty(_ fallback: String) -> String { isEmpty ? fallback : self }
}

extension AppDelegate: @preconcurrency UNUserNotificationCenterDelegate {

    // App em FOREGROUND — notificação chegou antes do usuário ver
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        Messaging.messaging().appDidReceiveMessage(notification.request.content.userInfo)
        let payload = Self.extractPayload(notification.request.content.userInfo)
        let action  = str(payload["action"])

        print("[PPPIX] willPresent — action='\(action)' identifier=\(notification.request.identifier)")
        Task { @MainActor in AlertDiagnosticLog.shared.log("[PPPIX] willPresent — action='\(action)' identifier=\(notification.request.identifier)") }

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
            // Notificação de emergência chegou com app em FOREGROUND
            // Processar o payload E mostrar o banner com som
            let wasProcessed = handleEmergencyPayload(payload)
            if wasProcessed {
                // handleEmergencyPayload já criou notificação local — não mostrar a FCM original
                // para evitar duplicata de banner
                completionHandler([])
            } else {
                completionHandler([.banner, .sound, .badge])
            }
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
        let action  = str(payload["action"])

        print("[PPPIX] didReceive (tap) — action='\(action)' identifier=\(response.notification.request.identifier)")
        Task { @MainActor in AlertDiagnosticLog.shared.log("[PPPIX] didReceive (tap) — action='\(action)' identifier=\(response.notification.request.identifier)") }

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
                let alertId = intVal(payload["alert_id"] ?? payload["id"])
                let alertType = str(payload["alert_type"])

                print("[PPPIX] didReceive tap emergência — id=\(alertId) type=\(alertType)")
                Task { @MainActor in AlertDiagnosticLog.shared.log("[PPPIX] didReceive tap emergência — id=\(alertId) type=\(alertType)") }

                if alertId > 0 || alertType.lowercased().contains("emergency") {
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

    // Extrai payload FCM independente do formato (notification+data ou data puro)
    static func extractPayload(_ userInfo: [AnyHashable: Any]) -> [String: Any] {
        var result = [String: Any]()

        // Copia tudo que tem chave String
        for (k, v) in userInfo {
            if let key = k as? String { result[key] = v }
        }

        // Desembala campo "data" — pode ser Dict, JSON string, ou ausente
        if let data = userInfo["data"] as? [AnyHashable: Any] {
            for (k, v) in data { if let key = k as? String { result[key] = v } }
        } else if let data = userInfo["data"] as? [String: Any] {
            for (k, v) in data { result[k] = v }
        } else if let dataStr = userInfo["data"] as? String,
                  let dataBytes = dataStr.data(using: .utf8),
                  let dataDict = try? JSONSerialization.jsonObject(with: dataBytes) as? [String: Any] {
            for (k, v) in dataDict { result[k] = v }
        }

        print("[PPPIX] extractPayload — chaves: \(result.keys.sorted().joined(separator: ", "))")
        Task { @MainActor in AlertDiagnosticLog.shared.log("[PPPIX] extractPayload — chaves: \(result.keys.sorted().joined(separator: ", "))") }
        return result
    }

}

extension AppDelegate: @preconcurrency MessagingDelegate {
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let token = fcmToken else { return }
        print("[PPPIX] FCM token atualizado: \(token.prefix(20))...")
        Task { @MainActor in AlertDiagnosticLog.shared.log("[PPPIX] FCM token atualizado: \(token.prefix(20))...") }
        SessionManager.shared.fcmToken = token
        if SessionManager.shared.isLoggedIn {
            Task { @MainActor in
                do {
                    try await APIClient.shared.registerFcmDevice(token: token, platform: "ios")
                    AlertDiagnosticLog.shared.log("FCM iOS registrado com sucesso")
                } catch {
                    AlertDiagnosticLog.shared.log("FCM iOS registro ERRO: \(error)")
                }
            }
        } else {
            Task { @MainActor in AlertDiagnosticLog.shared.log("FCM token recebido mas não logado — guardado para depois") }
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

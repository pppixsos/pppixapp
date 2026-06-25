import SwiftUI
import FirebaseCore
import FirebaseMessaging
import UserNotifications
import GoogleSignIn

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
    static var pendingAlertId: Int? = nil

    // Deduplicação unificada via AlertDeduplicator (UserDefaults persistente)

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        setupNotificationCategories()

        // Configuracao do Firebase 100% programatica — NAO depende do
        // GoogleService-Info.plist estar presente no bundle do .ipa
        // (que se mostrou nao-confiavel via xcodegen/CI). Valores
        // copiados diretamente do projeto Firebase pppix-bf8ff.
        if FirebaseApp.app() == nil {
            let options = FirebaseOptions(
                googleAppID: "1:496555012887:ios:c85e1ce4122cedab54bd52",
                gcmSenderID: "496555012887"
            )
            options.apiKey = "AIzaSyBvK9bH3oWHpJmCKrIuJ0163jXPWp--JMA"
            options.projectID = "pppix-bf8ff"
            options.bundleID = "tech.pppix.app"
            options.storageBucket = "pppix-bf8ff.firebasestorage.app"
            FirebaseApp.configure(options: options)
        }
        Messaging.messaging().delegate = self
        Task { @MainActor in AlertDiagnosticLog.shared.log("[FCM] FirebaseApp.configure() OK (programatico), delegate setado") }

        // Tenta buscar o token FCM IMEDIATAMENTE no boot, em paralelo
        // ao fluxo via APNS callback. Antes, so' tentavamos dentro de
        // didRegisterForRemoteNotificationsWithDeviceToken — se aquele
        // callback demorasse/falhasse, nunca havia uma segunda via.
        Self.fetchFCMTokenWithRetry(attempt: 1)

        // Registrar para remote notifications IMEDIATAMENTE (sem aguardar permissão)
        // Firebase precisa do APNS token antes de gerar FCM token
        UIApplication.shared.registerForRemoteNotifications()

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
            // FamilyControls/ScreenTime só existe em iPhone — não chamar no iPad
            // para evitar crash durante revisão da Apple em iPad
            if UIDevice.current.userInterfaceIdiom == .phone {
                ScreenTimeManager.shared.checkAuthorization()
            }
            #endif
        }

        // Inicializa o GPS logo que o app abre
        LocationService.shared.warmUp()

        // Retoma o rastreamento em tempo real se o app foi relançado pelo
        // sistema enquanto um alerta de emergência ainda estava ativo.
        Task { @MainActor in
            LiveLocationTracker.shared.resumeIfNeeded()
        }

        BackgroundTaskManager.shared.registerTasks()
        // Ouvir pedido de verificação de alertas vindo do background task
        NotificationCenter.default.addObserver(
            forName: .pppixCheckAlertsInBackground,
            object: nil,
            queue: .main
        ) { _ in
            Task { await BackgroundTaskManager.shared.checkAndNotifyAlerts() }
        }

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
        // Categoria de desbloqueio
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

        // Categoria de emergência — botões grandes no banner
        let mapsAction = UNNotificationAction(
            identifier: "EMERGENCY_MAPS",
            title: "🗺️ Ver Localização",
            options: [.foreground]
        )
        let callAction = UNNotificationAction(
            identifier: "EMERGENCY_CALL",
            title: "📞 Ligar 190 — Polícia",
            options: [.foreground, .destructive]
        )
        let detailsAction = UNNotificationAction(
            identifier: "EMERGENCY_DETAILS",
            title: "🚨 Ver Detalhes",
            options: [.foreground]
        )
        let emergencyCategory = UNNotificationCategory(
            identifier: "PPPIX_EMERGENCY",
            actions: [detailsAction, mapsAction, callAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )

        UNUserNotificationCenter.current().setNotificationCategories([unlockCategory, emergencyCategory])
    }

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
        let tokenStr = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task { @MainActor in AlertDiagnosticLog.shared.log("APNS token OK: \(tokenStr.prefix(20))...") }
        // IMPORTANTE: NAO registrar o token APNS bruto (hex) no backend.
        // O backend usa Firebase Admin SDK (messaging.send), que so aceita
        // tokens FCM (formato "xxxx:APA91b..."), e REJEITA tokens APNS
        // brutos com "not a valid FCM registration token". Registrar o
        // token APNS aqui sobrescrevia o token FCM correto, fazendo TODOS
        // os pushes falharem silenciosamente. O token FCM real e' obtido
        // e registrado em fetchFCMTokenWithRetry() logo abaixo.

        // Tentar gerar FCM token com retry (Firebase precisa processar o APNS token)
        Self.fetchFCMTokenWithRetry(attempt: 1)
    }

    static func fetchFCMTokenWithRetry(attempt: Int) {
        let delays = [1.0, 3.0, 5.0, 10.0, 20.0]
        let delay = attempt <= delays.count ? delays[attempt - 1] : 30.0
        Task { @MainActor in AlertDiagnosticLog.shared.log("[FCM] Agendando solicitacao de token, tentativa \(attempt), delay=\(delay)s") }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            Task { @MainActor in AlertDiagnosticLog.shared.log("[FCM] Chamando Messaging.messaging().token (tentativa \(attempt))") }
            Messaging.messaging().token { token, error in
                Task { @MainActor in AlertDiagnosticLog.shared.log("[FCM] Callback do token recebido (tentativa \(attempt)) - token=\(token != nil), error=\(error?.localizedDescription ?? "nil")") }
                if let token = token, !token.isEmpty {
                    Task { @MainActor in
                        AlertDiagnosticLog.shared.log("FCM token gerado (tentativa \(attempt)): \(token.prefix(20))...")
                        SessionManager.shared.fcmToken = token
                        if SessionManager.shared.isLoggedIn {
                            do {
                                try await APIClient.shared.registerFcmDevice(token: token, platform: "ios")
                                AlertDiagnosticLog.shared.log("FCM registrado no backend ✅")
                            } catch {
                                AlertDiagnosticLog.shared.log("FCM registro erro: \(error)")
                            }
                        }
                    }
                } else {
                    Task { @MainActor in AlertDiagnosticLog.shared.log("FCM tentativa \(attempt) falhou: \(error?.localizedDescription ?? "sem token"). Tentando novamente...") }
                    if attempt < 6 {
                        fetchFCMTokenWithRetry(attempt: attempt + 1)
                    }
                }
            }
        }
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
            #if !targetEnvironment(simulator)
            if UIDevice.current.userInterfaceIdiom == .phone {
                ScreenTimeManager.shared.forceReblock()
            }
            #endif
            completionHandler(.newData)
        } else {
            // Alerta de emergência — processar e guardar ID para abrir tela ao foreground
            let alertId = intVal(payload["alert_id"] ?? payload["id"])
            if alertId > 0 {
                AppDelegate.pendingAlertId = alertId
            }
            Task { @MainActor in
                _ = self.handleEmergencyPayload(payload)
            }
            completionHandler(.newData)
        }
    }

    func application(_ app: UIApplication, open url: URL,
                     options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        // Google Sign In handler
        if GIDSignIn.sharedInstance.handle(url) { return true }
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

    /// Cria notificação local de emergência diretamente (chamado pelo polling)
    @MainActor func createEmergencyNotification(alertId: Int, alertType: String, senderEmail: String, senderName: String) {
        let displayName = senderName.isEmpty ? (senderEmail.components(separatedBy: "@").first ?? "Contato") : senderName
        let content = UNMutableNotificationContent()
        content.title = "🚨 Alerta de Emergência"
        content.body = "\(displayName) pode estar em perigo! Toque para ver detalhes."
        content.interruptionLevel = .critical
        content.categoryIdentifier = "PPPIX_EMERGENCY"
        content.userInfo = [
            "alert_id": String(alertId),
            "alert_type": alertType,
            "sender_email": senderEmail,
            "sender_name": senderName
        ]
        if Bundle.main.url(forResource: "sirene", withExtension: "caf") != nil {
            content.sound = UNNotificationSound(named: UNNotificationSoundName(rawValue: "sirene.caf"))
            AlertDiagnosticLog.shared.log("NOTIF: criando com sirene.caf id=\(alertId)")
        } else if Bundle.main.url(forResource: "sirene", withExtension: "mp3") != nil {
            content.sound = UNNotificationSound(named: UNNotificationSoundName(rawValue: "sirene.mp3"))
            AlertDiagnosticLog.shared.log("NOTIF: criando com sirene.mp3 id=\(alertId)")
        } else {
            content.sound = .default
            AlertDiagnosticLog.shared.log("NOTIF: criando com som padrão id=\(alertId)")
        }
        let identifier = "pppix_alert_\(alertId)"
        // Trigger de 1s garante que iOS processa corretamente em qualquer estado do app
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        ) { error in
            if let error = error {
                Task { @MainActor in AlertDiagnosticLog.shared.log("NOTIF: erro ao adicionar: \(error)") }
            } else {
                Task { @MainActor in AlertDiagnosticLog.shared.log("NOTIF: adicionada com sucesso id=\(alertId)") }
            }
        }
        // Tocar sirene via AVAudioPlayer se app estiver ativo
        if UIApplication.shared.applicationState == .active {
            EmergencyAudioService.shared.playSiren()
        }
        // Notificar UI
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .incomingEmergencyAlert, object: nil, userInfo: ["alert_id": alertId])
        }
    }

    /// Processa payload de alerta de emergência.
    /// Retorna true se o payload continha um alerta de emergência.
    @discardableResult
    @MainActor func handleEmergencyPayload(_ payload: [String: Any], createLocalNotification: Bool = true) -> Bool {
        let alertType   = str(payload["alert_type"])
        let senderEmail = str(payload["sender_email"])
        let myEmail     = SessionManager.shared.userEmail

        print("[PPPIX] handleEmergencyPayload — type='\(alertType)' sender='\(senderEmail)' me='\(myEmail)'")
        Task { @MainActor in AlertDiagnosticLog.shared.log("RECEBER(FCM): tipo=\(alertType) de=\(senderEmail)") }
        Task { @MainActor in AlertDiagnosticLog.shared.log("[PPPIX] handleEmergencyPayload — type='\(alertType)' sender='\(senderEmail)' me='\(myEmail)'") }

        // Filtra alertas enviados por mim mesmo
        // Só filtra se myEmail está disponível (pode estar vazio em background)
        if !myEmail.isEmpty && !senderEmail.isEmpty &&
           senderEmail.lowercased() == myEmail.lowercased() {
            print("[PPPIX] handleEmergencyPayload — ignorado: é meu próprio alerta")
            Task { @MainActor in AlertDiagnosticLog.shared.log("RECEBER(FCM): IGNORADO - meu próprio alerta") }
            Task { @MainActor in AlertDiagnosticLog.shared.log("[PPPIX] handleEmergencyPayload — ignorado: é meu próprio alerta") }
            return false
        }

        // Deve ter alert_type com conteúdo de emergência
        guard !alertType.isEmpty else {
            AlertDiagnosticLog.shared.log("NOTIF: alertType vazio — ignorado")
            return false
        }

        let isEmergency = alertType == "emergency_password"
                       || alertType == "wrong_password"
                       || alertType.lowercased().contains("emergency")
                       || alertType.lowercased().contains("alert")
        guard isEmergency else {
            AlertDiagnosticLog.shared.log("NOTIF: alertType='\(alertType)' não é emergência — ignorado")
            return false
        }

        let alertId    = intVal(payload["alert_id"] ?? payload["id"])
        let rawSenderName = str(payload["sender_name"])
        let senderName = rawSenderName.isEmpty ? (senderEmail.components(separatedBy: "@").first ?? "Contato") : rawSenderName

        // Deduplicar: não processar o mesmo alerta duas vezes
        if alertId > 0 {
            guard !AlertDeduplicator.shared.contains(alertId) else {
                AlertDiagnosticLog.shared.log("NOTIF: id=\(alertId) já no Deduplicator — ignorado")
                return false
            }
            AlertDeduplicator.shared.markShown(alertId)
            AlertDiagnosticLog.shared.log("NOTIF: id=\(alertId) marcado no Deduplicator")
            // Limita o set a 50 entradas para não crescer indefinidamente
        }

        print("[PPPIX] handleEmergencyPayload PROCESSANDO — id=\(alertId) sender=\(senderEmail)")
        Task { @MainActor in AlertDiagnosticLog.shared.log("RECEBER(FCM): PROCESSANDO id=\(alertId) de=\(senderEmail)") }
        Task { @MainActor in AlertDiagnosticLog.shared.log("[PPPIX] handleEmergencyPayload PROCESSANDO — id=\(alertId) sender=\(senderEmail)") }

        let appState = UIApplication.shared.applicationState

        // Criar notificação local com som apenas quando necessário
        // (quando não há push FCM para mostrar o banner automaticamente)
        let notifContent = UNMutableNotificationContent()
        let displayName = senderName.isEmpty ? senderEmail : senderName
        notifContent.title = "🚨 Alerta de Emergência"
        notifContent.body  = "\(displayName) pode estar em perigo! Toque para ver detalhes."
        notifContent.interruptionLevel = .critical
        notifContent.categoryIdentifier = "PPPIX_EMERGENCY"
        notifContent.userInfo = [
            "alert_id":     alertId > 0 ? String(alertId) : "0",
            "alert_type":   alertType,
            "sender_email": senderEmail,
            "sender_name":  senderName
        ]
        // Som da notificação — sirene.caf se disponível, senão som padrão alto
        // O sirene.caf é gerado pelo sign.yml via afconvert do sirene.mp3
        if let cafURL = Bundle.main.url(forResource: "sirene", withExtension: "caf") {
            _ = cafURL // arquivo existe
            notifContent.sound = UNNotificationSound(named: UNNotificationSoundName(rawValue: "sirene.caf"))
            Task { @MainActor in AlertDiagnosticLog.shared.log("Notif: usando sirene.caf") }
        } else if Bundle.main.url(forResource: "sirene", withExtension: "mp3") != nil {
            notifContent.sound = UNNotificationSound(named: UNNotificationSoundName(rawValue: "sirene.mp3"))
            Task { @MainActor in AlertDiagnosticLog.shared.log("Notif: usando sirene.mp3 (sem caf)") }
        } else {
            notifContent.sound = UNNotificationSound.default
            Task { @MainActor in AlertDiagnosticLog.shared.log("Notif: usando som padrão (sem sirene)") }
        }
        let identifier = alertId > 0 ? "pppix_alert_\(alertId)" : "pppix_alert_\(Int(Date().timeIntervalSince1970))"

        if createLocalNotification {
            if appState == .active {
                // App ATIVO em foreground:
                // 1. Tocar sirene IMEDIATAMENTE (AVAudioPlayer funciona em foreground)
                EmergencyAudioService.shared.playSiren()
                // 2. Notificação com trigger 5s para aparecer no notification center
                //    (no foreground, banners com trigger muito curto são suprimidos pelo iOS)
                notifContent.interruptionLevel = .critical
                UNUserNotificationCenter.current().add(
                    UNNotificationRequest(
                        identifier: identifier,
                        content: notifContent,
                        trigger: UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
                    )
                )
                // 3. A tela fullscreen é aberta pelo incomingEmergencyAlert (abaixo)
            } else {
                // Background ou fechado: notificação crítica imediata
                notifContent.interruptionLevel = .critical
                UNUserNotificationCenter.current().add(
                    UNNotificationRequest(
                        identifier: identifier,
                        content: notifContent,
                        trigger: UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
                    )
                )
            }
        } else {
            // Veio via push FCM
            if appState == .active {
                EmergencyAudioService.shared.playSiren()
            }
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

        let identifier = notification.request.identifier

        switch action {
        case "unlock":
            // App está em foreground — abrir tela de senha diretamente sem banner
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [notification.request.identifier])
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["pppix_unlock"])
            // Pequeno delay para garantir que a UI está pronta
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.triggerUnlockScreen()
            }
            completionHandler([])
        case "reblock":
            // Reblock notificação — aplicar shield imediatamente
            #if !targetEnvironment(simulator)
            if UIDevice.current.userInterfaceIdiom == .phone {
                ScreenTimeManager.shared.forceReblock()
            }
            #endif
            completionHandler([])
        default:
            // Notificação de emergência — sempre mostrar banner + som + badge
            if identifier.hasPrefix("pppix_alert_") {
                EmergencyAudioService.shared.playSiren()
                completionHandler([.banner, .sound, .badge])
                return
            }
            // Push FCM de emergência — processar payload E mostrar banner
            handleEmergencyPayload(payload, createLocalNotification: false)
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
        let action  = str(payload["action"])

        print("[PPPIX] didReceive (tap) — action='\(action)' identifier=\(response.notification.request.identifier)")
        Task { @MainActor in AlertDiagnosticLog.shared.log("[PPPIX] didReceive (tap) — action='\(action)' identifier=\(response.notification.request.identifier)") }

        switch action {
        case "reblock":
            #if !targetEnvironment(simulator)
            if UIDevice.current.userInterfaceIdiom == .phone {
                ScreenTimeManager.shared.forceReblock()
            }
            #endif
        case "unlock":
            // Remover notificação de unlock imediatamente ao tocar
            UNUserNotificationCenter.current().removeDeliveredNotifications(
                withIdentifiers: [response.notification.request.identifier, "pppix_unlock"]
            )
            UNUserNotificationCenter.current().removePendingNotificationRequests(
                withIdentifiers: ["pppix_unlock"]
            )
            triggerUnlockScreen()
        default:
            // Ações dos botões do banner de emergência
            if response.actionIdentifier == "EMERGENCY_MAPS" {
                let payload = Self.extractPayload(response.notification.request.content.userInfo)
                let lat = str(payload["latitude"] ?? "")
                let lng = str(payload["longitude"] ?? "")
                if !lat.isEmpty, !lng.isEmpty,
                   let url = URL(string: "https://www.google.com/maps/search/?api=1&query=\(lat),\(lng)") {
                    DispatchQueue.main.async { UIApplication.shared.open(url) }
                }
            } else if response.actionIdentifier == "EMERGENCY_CALL" {
                if let url = URL(string: "tel://190") {
                    DispatchQueue.main.async { UIApplication.shared.open(url) }
                }
            } else if response.actionIdentifier == "EMERGENCY_DETAILS" {
                let payload = Self.extractPayload(response.notification.request.content.userInfo)
                let alertId = intVal(payload["alert_id"] ?? payload["id"])
                EmergencyAudioService.shared.playSiren()
                DispatchQueue.main.async {
                    NotificationCenter.default.post(
                        name: .incomingEmergencyAlert,
                        object: nil,
                        userInfo: ["alert_id": alertId]
                    )
                }
            } else if response.actionIdentifier == "UNLOCK_ACTION" {
                triggerUnlockScreen()
            } else {
                // Toque em notificação de alerta de emergência
                let alertId = intVal(payload["alert_id"] ?? payload["id"])
                let alertType = str(payload["alert_type"])

                print("[PPPIX] didReceive tap emergência — id=\(alertId) type=\(alertType)")
                Task { @MainActor in AlertDiagnosticLog.shared.log("[PPPIX] didReceive tap emergência — id=\(alertId) type=\(alertType)") }

                if alertId > 0 || alertType.lowercased().contains("emergency") {
                    EmergencyAudioService.shared.playSiren()
                    if alertId > 0 {
                        AppDelegate.pendingAlertId = alertId
                    }
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
    static let pppixUserDidLogin          = Notification.Name("pppix.userDidLogin")
}

import SwiftUI
import AudioToolbox
import MapKit
import UserNotifications
import CoreLocation

extension Int: @retroactive Identifiable {
    public var id: Int { self }
}

// MARK: - Auth State
@MainActor
class PPPIXAuthState: ObservableObject {
    static let instance = PPPIXAuthState()
    private init() {}
    @Published var isAuthenticated = false

    static var hasAppPassword: Bool {
        get {
            if UserDefaults.standard.object(forKey: "pppix_app_password_enabled") == nil { return true }
            return UserDefaults.standard.bool(forKey: "pppix_app_password_enabled")
        }
        set { UserDefaults.standard.set(newValue, forKey: "pppix_app_password_enabled") }
    }
}

// MARK: - RootView
struct RootView: View {
    @StateObject private var session = SessionManager.shared
    @StateObject private var auth    = PPPIXAuthState.instance
    @Environment(\.scenePhase) private var scenePhase

    @State private var showAlertDetail: Int?  = nil
    @State private var emergencyAlert: Alert? = nil
    @State private var alertPollTimer: Timer? = nil

    // Inicializa com true se há notificação pendente (cold start instantâneo)
    @State private var showUnlockScreen: Bool = {
        if AppDelegate.pendingUnlockScreen {
            AppDelegate.pendingUnlockScreen = false
            return true
        }
        if let d = UserDefaults(suiteName: "group.tech.pppix.app"),
           d.bool(forKey: "pppix_show_password_screen") {
            let t = d.double(forKey: "pppix_password_request_time")
            let age = Date().timeIntervalSince1970 - t
            d.removeObject(forKey: "pppix_show_password_screen")
            d.removeObject(forKey: "pppix_password_request_time")
            d.synchronize()
            if t > 0, age >= 0, age < 120 { return true }
        }
        return false
    }()

    private let sharedDefaults = UserDefaults(suiteName: "group.tech.pppix.app")

    var body: some View {
        Group {
            if !session.isLoggedIn {
                LoginView()
            } else {
                HomeView()
            }
        }
        .sheet(item: $showAlertDetail) { id in AlertDetailView(alertId: id) }
        .fullScreenCover(isPresented: $showUnlockScreen) {
            UnlockPasswordView(isPresented: $showUnlockScreen, onPPPIXAccess: {
                showUnlockScreen = false
                auth.isAuthenticated = true
            })
        }
        .fullScreenCover(item: $emergencyAlert) { alert in
            EmergencyAlertView(alert: alert, onDismiss: { emergencyAlert = nil })
        }
        .onAppear {
            #if !targetEnvironment(simulator)
            ScreenTimeManager.shared.checkAuthorization()
            #endif
            // Verificar se há alerta pendente (app aberto via tap na notificação)
            if let pendingId = AppDelegate.pendingAlertId {
                AppDelegate.pendingAlertId = nil
                Task { @MainActor in
                    if let a = try? await APIClient.shared.getAlert(id: pendingId) {
                        EmergencyAudioService.shared.playSiren()
                        emergencyAlert = a
                    }
                }
            }
        }
        .onChange(of: scenePhase) { phase in
            switch phase {
            case .background:
                stopAlertPolling()
                BackgroundTaskManager.shared.appDidEnterBackground()
                if AppDelegate.skipNextAuthReset {
                    AppDelegate.skipNextAuthReset = false
                } else {
                    auth.isAuthenticated = false
                }
                #if !targetEnvironment(simulator)
                ScreenTimeManager.shared.reblockOnBackground()
                #endif
            case .active:
                // Remover notificação de unlock ao ativar o app
                UNUserNotificationCenter.current().removeDeliveredNotifications(
                    withIdentifiers: ["pppix_unlock"]
                )
                checkPasswordFlag()
                // Verificar alerta pendente ao voltar ao foreground
                if let pendingId = AppDelegate.pendingAlertId {
                    AppDelegate.pendingAlertId = nil
                    Task { @MainActor in
                        if let a = try? await APIClient.shared.getAlert(id: pendingId) {
                            EmergencyAudioService.shared.playSiren()
                            emergencyAlert = a
                        }
                    }
                }
                pollAlertsOnce()
                startAlertPolling()
            default: break
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .pppixForceOpenUnlockScreen)) { _ in
            guard !showUnlockScreen else { return }
            showUnlockScreen = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .openAlertDetail)) { notif in
            guard let id = notif.userInfo?["alert_id"] as? Int else { return }
            showAlertDetail = id
        }
        .onReceive(NotificationCenter.default.publisher(for: .incomingEmergencyAlert)) { notif in
            let id = notif.userInfo?["alert_id"] as? Int ?? 0
            AlertDiagnosticLog.shared.log("RECEBER(push): notificação chegou id=\(id)")
            // Se já foi mostrado localmente, ignorar
            if id > 0 && AlertDeduplicator.shared.shownIds.contains(id) {
                AlertDiagnosticLog.shared.log("RECEBER(push): id=\(id) já exibido — ignorado")
                return
            }
            Task { @MainActor in
                if id > 0, let a = try? await APIClient.shared.getAlert(id: id) {
                    AlertDiagnosticLog.shared.log("RECEBER(push): carregado id=\(a.id) de=\(a.sender_email)")
                    markShown(a.id)
                    try? await APIClient.shared.markAlertRead(id: a.id)
                    emergencyAlert = a
                } else {
                    AlertDiagnosticLog.shared.log("RECEBER(push): getAlert falhou id=\(id), buscando recentes...")
                    if let alerts = try? await APIClient.shared.getReceivedAlerts() {
                        processAlerts(alerts, source: "push-fallback")
                    } else if id > 0 {
                        showAlertDetail = id
                    }
                }
            }
        }
    }

    /// Busca alertas recebidos e exibe se houver algum não lido.
    /// Equivalente ao onMessageReceived do Android: processa alertas recentes.
    private func markShown(_ id: Int) {
        AlertDeduplicator.shared.markShown(id)
    }

    private func processAlerts(_ alerts: [Alert], source: String) {
        let myEmail   = SessionManager.shared.userEmail
        let shown     = AlertDeduplicator.shared.shownIds
        // Só mostrar alertas dos últimos 10 minutos para evitar alertas antigos
        let cutoff    = Date().addingTimeInterval(-10 * 60)
        let iso       = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        AlertDiagnosticLog.shared.log("RECEBER(\(source)): \(alerts.count) alertas, \(shown.count) já vistos")
        let candidate = alerts.first(where: {
            let s = $0.status.lowercased()
            let isMine = !myEmail.isEmpty && $0.sender_email.lowercased() == myEmail.lowercased()
            // Verificar se o alerta é recente (últimos 10 minutos)
            let alertDate = iso.date(from: $0.created_at) ?? Date.distantPast
            let isRecent  = alertDate > cutoff
            if !isRecent && !shown.contains($0.id) {
                AlertDeduplicator.shared.markShown($0.id) // marcar antigos como vistos
            }
            return !isMine && s != "cancelled" && s != "cancel" && !shown.contains($0.id) && isRecent
        })
        guard let a = candidate else {
            AlertDiagnosticLog.shared.log("RECEBER(\(source)): nenhum alerta novo")
            return
        }
        AlertDiagnosticLog.shared.log("RECEBER(\(source)): NOVO id=\(a.id) de=\(a.sender_email) status=\(a.status)")
        // Marcar IMEDIATAMENTE antes de qualquer Task para garantir deduplicação
        AlertDeduplicator.shared.markShown(a.id)
        // Criar notificação local DIRETAMENTE (sem Task — já estamos no MainActor)
        let alertId  = a.id
        let dispName = a.sender_name.isEmpty
            ? (a.sender_email.components(separatedBy: "@").first ?? "Contato")
            : a.sender_name
        AlertDiagnosticLog.shared.log("NOTIF: criando id=\(alertId) nome=\(dispName)")
        let nc = UNMutableNotificationContent()
        nc.title = "🚨 Alerta de Emergência"
        nc.body  = "\(dispName) pode estar em perigo! Toque para ver detalhes."
        nc.interruptionLevel = .timeSensitive
        nc.userInfo = [
            "alert_id": String(alertId),
            "alert_type": a.alert_type,
            "sender_email": a.sender_email,
            "sender_name": a.sender_name,
            "latitude": a.latitude ?? "",
            "longitude": a.longitude ?? ""
        ]
        nc.categoryIdentifier = "PPPIX_EMERGENCY"
        nc.interruptionLevel = .critical
        if Bundle.main.url(forResource: "sirene", withExtension: "caf") != nil {
            nc.sound = UNNotificationSound(named: UNNotificationSoundName(rawValue: "sirene.caf"))
            AlertDiagnosticLog.shared.log("NOTIF: som=sirene.caf")
        } else {
            nc.sound = UNNotificationSound(named: UNNotificationSoundName(rawValue: "sirene.mp3"))
            AlertDiagnosticLog.shared.log("NOTIF: som=sirene.mp3")
        }
        // Trigger 0.1s — aparece mesmo com app em foreground
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        let req = UNNotificationRequest(identifier: "pppix_alert_\(alertId)", content: nc, trigger: trigger)
        UNUserNotificationCenter.current().add(req) { error in
            if let error = error {
                AlertDiagnosticLog.shared.log("NOTIF: ERRO \(error)")
            } else {
                AlertDiagnosticLog.shared.log("NOTIF: agendada ✅ id=\(alertId)")
            }
        }
        EmergencyAudioService.shared.playSiren()
        // Vibração de emergência — padrão longo repetido
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        }
        Task { @MainActor in
            try? await APIClient.shared.markAlertRead(id: a.id)
            AlertDiagnosticLog.shared.log("RECEBER: markAlertRead id=\(a.id)")
        }
        emergencyAlert = a
    }

    private func pollAlertsOnce() {
        guard SessionManager.shared.isLoggedIn else { return }
        Task { @MainActor in
            AlertDiagnosticLog.shared.log("RECEBER: buscando alertas...")
            guard let alerts = try? await APIClient.shared.getReceivedAlerts() else {
                AlertDiagnosticLog.shared.log("RECEBER ERRO: falhou ao buscar")
                return
            }
            processAlerts(alerts, source: "poll")
        }
    }

    private func startAlertPolling() {
        guard SessionManager.shared.isLoggedIn else { return }
        guard alertPollTimer == nil else { return } // já está rodando
        alertPollTimer = Timer.scheduledTimer(withTimeInterval: 8, repeats: true) { _ in
            Task { @MainActor in
                guard SessionManager.shared.isLoggedIn else { return }
                guard let alerts = try? await APIClient.shared.getReceivedAlerts() else { return }
                self.processAlerts(alerts, source: "timer")
            }
        }
    }

    private func stopAlertPolling() {
        alertPollTimer?.invalidate()
        alertPollTimer = nil
    }

    private func checkPasswordFlag() {
        guard let d = sharedDefaults,
              d.bool(forKey: "pppix_show_password_screen"),
              !showUnlockScreen else { return }
        let t = d.double(forKey: "pppix_password_request_time")
        let age = Date().timeIntervalSince1970 - t
        d.removeObject(forKey: "pppix_show_password_screen")
        d.removeObject(forKey: "pppix_password_request_time")
        d.synchronize()
        guard t > 0, age >= 0, age < 120 else { return }
        showUnlockScreen = true
    }
}

// MARK: - Tela de Emergência Fullscreen (igual Android)
struct EmergencyAlertView: View {
    let alert: Alert
    let onDismiss: () -> Void
    @State private var isCancelling = false
    @State private var cancelled = false

    private var isSender: Bool {
        alert.sender_email.lowercased() == SessionManager.shared.userEmail.lowercased()
    }

    private var displayName: String {
        alert.sender_name.isEmpty ? alert.sender_email : alert.sender_name
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 0) {

                    // Sirene
                    Text("🚨")
                        .font(.system(size: 72))
                        .padding(.top, 48)
                        .padding(.bottom, 8)

                    // Título
                    Text("Senha de Emergência")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(Color(hex: "#FF3333"))
                        .multilineTextAlignment(.center)

                    // Nome do remetente
                    Text("De: \(displayName)")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(Color(hex: "#FFCC00"))
                        .padding(.top, 6)

                    // Mensagem
                    Text(alert.message)
                        .font(.system(size: 15))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .padding(.top, 10)
                        .padding(.bottom, 20)

                    // Mapa nativo
                    if alert.has_location, let latStr = alert.latitude, let lngStr = alert.longitude,
                       let lat = Double(latStr), let lng = Double(lngStr) {
                        VStack(spacing: 0) {
                            MapPreviewView(latitude: lat, longitude: lng)
                                .frame(height: 200)
                                .cornerRadius(12)
                            HStack {
                                Text("📍 \(latStr), \(lngStr)")
                                    .font(.caption)
                                    .foregroundColor(Color(white: 0.5))
                                Spacer()
                                if let url = alert.googleMapsURL {
                                    Link(destination: url) {
                                        Text("Abrir Maps →")
                                            .font(.caption.bold())
                                            .foregroundColor(Color(hex: "#44AAFF"))
                                    }
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color(hex: "#1A1A1A"))
                        }
                        .cornerRadius(12)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                    }

                    // Veículo
                    if !alert.vehicleText.isEmpty {
                        HStack(spacing: 10) {
                            Text("🚗")
                                .font(.system(size: 18))
                            Text(alert.vehicleText)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(Color(hex: "#FFCC00"))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(14)
                        .background(Color(hex: "#1A1A1A"))
                        .cornerRadius(10)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                    }

                    VStack(spacing: 12) {
                        // Ver no Google Maps
                        if let url = alert.googleMapsURL {
                            Button {
                                UIApplication.shared.open(url)
                            } label: {
                                HStack(spacing: 8) {
                                    Text("🗺️")
                                    Text("ABRIR NO GOOGLE MAPS")
                                        .font(.system(size: 15, weight: .bold))
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(Color(hex: "#1A4DCC"))
                                .cornerRadius(10)
                            }
                        }

                        // Ligar 190
                        Button {
                            if let url = URL(string: "tel://190") { UIApplication.shared.open(url) }
                        } label: {
                            HStack(spacing: 8) {
                                Text("📞")
                                Text("LIGAR PARA 190 — POLÍCIA")
                                    .font(.system(size: 15, weight: .bold))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color(hex: "#CC0000"))
                            .cornerRadius(10)
                        }

                        // Parar sirene
                        Button {
                            EmergencyAudioService.shared.stopSiren()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "speaker.slash.fill")
                                Text("Parar Sirene")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            .foregroundColor(Color(white: 0.6))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color(hex: "#222222"))
                            .cornerRadius(10)
                        }

                        // Cancelar alerta (se for o remetente)
                        if isSender && !cancelled {
                            Button {
                                Task {
                                    isCancelling = true
                                    try? await APIClient.shared.patchAlertStatus(id: alert.id, status: "cancelled")
                                    isCancelling = false
                                    cancelled = true
                                    EmergencyAudioService.shared.stopSiren()
                                    onDismiss()
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    if isCancelling { ProgressView().tint(.white) }
                                    else {
                                        Image(systemName: "checkmark.circle.fill")
                                        Text("Estou Bem — Cancelar Alerta")
                                            .font(.system(size: 14, weight: .semibold))
                                    }
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color(hex: "#006600"))
                                .cornerRadius(10)
                            }
                            .disabled(isCancelling)
                        }

                        // Fechar
                        Button {
                            EmergencyAudioService.shared.stopSiren()
                            onDismiss()
                        } label: {
                            Text("FECHAR")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(Color(white: 0.5))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color(hex: "#1A1A1A"))
                                .cornerRadius(10)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 40)
                }
            }
        }
    }
}

// MARK: - Login do PPPIX (senha 2)
struct PPPIXLoginView: View {
    let onAuthenticated: () -> Void
    @State private var password = ""
    @State private var errorMsg = ""
    @State private var isLoading = false
    @FocusState private var isFocused: Bool

    var body: some View {
        ZStack {
            Color(hex: "#0A0A12").ignoresSafeArea()
            VStack(spacing: 0) {
                Spacer()
                VStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(LinearGradient(colors: [Color(hex: "#3366FF").opacity(0.2), Color(hex: "#6633FF").opacity(0.1)], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 88, height: 88)
                        Image(systemName: "lock.fill").font(.system(size: 36))
                            .foregroundStyle(LinearGradient(colors: [Color(hex: "#3366FF"), Color(hex: "#6633FF")], startPoint: .top, endPoint: .bottom))
                    }
                    Text("PPPIX").font(.title.bold()).foregroundColor(.white)
                    Text("Digite sua senha para continuar").font(.subheadline).foregroundColor(Color(white: 0.45))
                }
                .padding(.bottom, 40)

                VStack(spacing: 8) {
                    SecureField("Senha", text: $password)
                        .font(.system(size: 17)).foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20).frame(height: 54)
                        .background(Color(white: 0.07)).cornerRadius(14)
                        .overlay(RoundedRectangle(cornerRadius: 14)
                            .stroke(errorMsg.isEmpty ? Color(white: 0.12) : Color(hex: "#FF4444"), lineWidth: 1))
                        .focused($isFocused)
                    if !errorMsg.isEmpty {
                        Text(errorMsg).font(.caption).foregroundColor(Color(hex: "#FF4444"))
                    }
                }
                .padding(.horizontal, 28)

                Spacer().frame(height: 24)

                Button { verify() } label: {
                    ZStack {
                        if isLoading { ProgressView().tint(.white) }
                        else { Text("Entrar").font(.system(size: 16, weight: .semibold)).foregroundColor(.white) }
                    }
                    .frame(maxWidth: .infinity).frame(height: 54)
                    .background(LinearGradient(colors: [Color(hex: "#3366FF"), Color(hex: "#6633FF")], startPoint: .leading, endPoint: .trailing))
                    .cornerRadius(14)
                }
                .disabled(isLoading || password.isEmpty)
                .padding(.horizontal, 28)
                Spacer()
            }
        }
        .onAppear { isFocused = true }
    }

    private func verify() {
        guard !password.isEmpty, !isLoading else { return }
        isLoading = true; errorMsg = ""
        Task {
            do {
                let r = try await APIClient.shared.verifyPassword(
                    body: VerifyPasswordRequest(password: password, latitude: nil, longitude: nil))
                await MainActor.run {
                    isLoading = false
                    if r.action == "open_pppix" || r.action == "open_ppix" {
                        onAuthenticated()
                    } else {
                        errorMsg = "Senha incorreta"; password = ""
                    }
                }
            } catch {
                await MainActor.run { isLoading = false; errorMsg = "Senha incorreta"; password = "" }
            }
        }
    }
}

// MARK: - Tela de desbloqueio de app protegido
struct UnlockPasswordView: View {
    @Binding var isPresented: Bool
    let onPPPIXAccess: () -> Void

    @State private var password     = ""
    @State private var errorMsg     = ""
    @State private var isLoading    = false
    @State private var showArrow    = false
    @State private var unlockedApp  = ""
    @FocusState private var focused: Bool

    private let sharedDefaults = UserDefaults(suiteName: "group.tech.pppix.app")

    var body: some View {
        ZStack {
            Color(hex: "#0A0A12").ignoresSafeArea()
            VStack(spacing: 0) {
                VStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(LinearGradient(colors: [Color(hex: "#3366FF").opacity(0.2), Color(hex: "#6633FF").opacity(0.1)], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 88, height: 88)
                        Image(systemName: "lock.shield.fill").font(.system(size: 40))
                            .foregroundStyle(LinearGradient(colors: [Color(hex: "#3366FF"), Color(hex: "#6633FF")], startPoint: .top, endPoint: .bottom))
                    }
                    Text("App Protegido").font(.title2.bold()).foregroundColor(.white)
                    Text("Digite sua senha para continuar").font(.subheadline).foregroundColor(Color(white: 0.45))
                }
                .padding(.top, 64).padding(.bottom, 40)

                VStack(spacing: 8) {
                    SecureField("Senha", text: $password)
                        .font(.system(size: 17)).foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20).frame(height: 54)
                        .background(Color(white: 0.07)).cornerRadius(14)
                        .overlay(RoundedRectangle(cornerRadius: 14)
                            .stroke(errorMsg.isEmpty ? Color(white: 0.12) : Color(hex: "#FF4444"), lineWidth: 1))
                        .focused($focused)
                    if !errorMsg.isEmpty {
                        Text(errorMsg).font(.caption).foregroundColor(Color(hex: "#FF4444"))
                    }
                }
                .padding(.horizontal, 28)

                Spacer().frame(height: 24)

                Button { verify() } label: {
                    ZStack {
                        if isLoading { ProgressView().tint(.white) }
                        else { Text("Confirmar").font(.system(size: 16, weight: .semibold)).foregroundColor(.white) }
                    }
                    .frame(maxWidth: .infinity).frame(height: 54)
                    .background(LinearGradient(colors: [Color(hex: "#3366FF"), Color(hex: "#6633FF")], startPoint: .leading, endPoint: .trailing))
                    .cornerRadius(14)
                }
                .disabled(isLoading || password.isEmpty)
                .padding(.horizontal, 28)

                Spacer().frame(height: 12)
                Button("Cancelar") { isPresented = false }
                    .font(.subheadline).foregroundColor(Color(white: 0.35)).padding(.bottom, 40)
                Spacer()
            }
        }
        .onAppear { focused = true }
        .fullScreenCover(isPresented: $showArrow, onDismiss: { isPresented = false }) {
            ArrowUnlockView(appName: unlockedApp, isPresented: $showArrow)
        }
    }

    private func verify() {
        guard !password.isEmpty, !isLoading else { return }
        isLoading = true; errorMsg = ""
        Task { @MainActor in
            do {
                // Verifica senha SEM localização primeiro (rápido)
                // Localização só é buscada se a ação for open_bank_alert (senha 3)
                let r = try await APIClient.shared.verifyPassword(
                    body: VerifyPasswordRequest(password: password, latitude: nil, longitude: nil))

                if r.action == "open_bank_alert" {
                    // Senha 3: unlock imediato, localização em background
                    isLoading = false
                    handleResponse(r, coord: nil)
                    // Busca localização após unlock (não bloqueia UI)
                    let location = await LocationService.shared.getCurrentLocation()
                    sendEmergencyAlert(coord: location)
                } else {
                    isLoading = false
                    handleResponse(r, coord: nil)
                }
            } catch {
                isLoading = false; errorMsg = "Senha incorreta"; password = ""
            }
        }
    }

    private func handleResponse(_ r: VerifyPasswordResponse, coord: CLLocationCoordinate2D?) {
        let bundleId = sharedDefaults?.string(forKey: "pppix_target_bundle_id") ?? ""
        let appName  = appDisplayName(for: bundleId)

        // Limpa o debounce para permitir próxima solicitação do mesmo app
        sharedDefaults?.removeObject(forKey: "pppix_password_request_time")
        sharedDefaults?.synchronize()

        switch r.action {
        case "open_pppix", "open_ppix":
            isPresented = false
            onPPPIXAccess()

        case "open_bank":
            #if !targetEnvironment(simulator)
            ScreenTimeManager.shared.unlockSingleApp(reblockAfterSeconds: 30)
            #endif
            unlockedApp = appName
            showArrow = true

        case "open_bank_alert":
            #if !targetEnvironment(simulator)
            ScreenTimeManager.shared.unlockSingleApp(reblockAfterSeconds: 30)
            #endif
            unlockedApp = appName
            showArrow = true

        default:
            errorMsg = "Senha incorreta"
            password = ""
        }
    }

    private func sendEmergencyAlert(coord: CLLocationCoordinate2D?) {
        let myEmail  = SessionManager.shared.userEmail
        let userName = SessionManager.shared.userName
        let latStr   = coord.map { String(format: "%.6f", $0.latitude) }
        let lonStr   = coord.map { String(format: "%.6f", $0.longitude) }

        AlertDiagnosticLog.shared.log("ENVIAR: início user=\(myEmail) lat=\(latStr ?? "nil")")

        guard !myEmail.isEmpty else {
            AlertDiagnosticLog.shared.log("ENVIAR ABORTADO: userEmail vazio — não logado?")
            return
        }

        Task { @MainActor in
            do {
                let connections  = try await APIClient.shared.getAcceptedConnections()
                let recipientIds = connections.map { $0.userId(myEmail: myEmail) }.filter { $0 > 0 }
                AlertDiagnosticLog.shared.log("ENVIAR: \(connections.count) conexões, ids=\(recipientIds)")

                let vehicles = (try? await APIClient.shared.getVehicles()) ?? []
                let vehicle  = vehicles.first(where: { $0.is_active }) ?? vehicles.first
                let vPayload = vehicle.map {
                    VehicleInfoPayload(model: $0.model, license_plate: $0.license_plate,
                                       color: $0.color, year: $0.year)
                }

                let body = SendAlertRequest(
                    alert_type: "emergency_password",
                    priority:   "critical",
                    title:      "🚨 Senha de Emergência",
                    message:    "\(userName) utilizou a senha de emergência e pode estar em perigo!",
                    latitude:   latStr,
                    longitude:  lonStr,
                    metadata:   AlertMetadata(
                        timestamp:    String(Int(Date().timeIntervalSince1970 * 1000)),
                        vehicle_info: vPayload
                    ),
                    recipient_ids: recipientIds
                )

                let result = try await APIClient.shared.sendAlert(body: body)
                AlertDiagnosticLog.shared.log("ENVIAR SUCESSO: id=\(result.id)")
            } catch APIError.forbidden(let msg) {
                AlertDiagnosticLog.shared.log("ENVIAR ERRO 403: \(msg)")
                return
            } catch {
                AlertDiagnosticLog.shared.log("ENVIAR ERRO: \(error)")
                // Retry sem recipientes específicos — backend filtra por conexões do usuário
                do {
                    let body = SendAlertRequest(
                        alert_type: "emergency_password",
                        priority:   "critical",
                        title:      "🚨 Senha de Emergência",
                        message:    "\(userName) utilizou a senha de emergência e pode estar em perigo!",
                        latitude:   latStr,
                        longitude:  lonStr,
                        metadata:   AlertMetadata(
                            timestamp: String(Int(Date().timeIntervalSince1970 * 1000)),
                            vehicle_info: nil
                        ),
                        recipient_ids: []
                    )
                    let result = try await APIClient.shared.sendAlert(body: body)
                    print("[PPPIX] sendEmergencyAlert RETRY OK — id: \(result.id)")
                } catch {
                    print("[PPPIX] sendEmergencyAlert RETRY TAMBÉM FALHOU: \(error)")
                }
            }
        }
    }

    private func appDisplayName(for bundleId: String) -> String {
        [
            "com.santander.app": "Santander", "com.santander.SantanderBrasil": "Santander",
            "com.nubank.app": "Nubank", "com.itau.iphone": "Itaú",
            "com.bradesco.app": "Bradesco", "com.bb.bolsodigital": "Banco do Brasil",
            "com.caixa.app": "Caixa", "com.inter.Inter": "Inter",
            "com.c6bank.ios": "C6 Bank", "com.picpay.ios": "PicPay",
            "com.mercadopago.ios": "Mercado Pago", "net.whatsapp.WhatsApp": "WhatsApp",
            "com.burbn.instagram": "Instagram", "com.facebook.Facebook": "Facebook",
            "com.zhiliaoapp.musically": "TikTok",
        ][bundleId] ?? "App"
    }
}

// MARK: - Tela pós-desbloqueio
struct ArrowUnlockView: View {
    let appName: String
    @Binding var isPresented: Bool

    var body: some View {
        ZStack {
            Color(hex: "#0A0A12").ignoresSafeArea()
            VStack(spacing: 0) {
                Spacer()
                VStack(spacing: 24) {
                    ZStack {
                        Circle()
                            .fill(Color(hex: "#44FF88").opacity(0.12))
                            .frame(width: 100, height: 100)
                        Image(systemName: "checkmark.shield.fill")
                            .font(.system(size: 52))
                            .foregroundColor(Color(hex: "#44FF88"))
                    }

                    VStack(spacing: 10) {
                        Text("\(appName) Desbloqueado!")
                            .font(.title2.bold())
                            .foregroundColor(.white)
                        Text("Toque no ícone do \(appName) na tela inicial para abri-lo.")
                            .font(.subheadline)
                            .foregroundColor(Color(white: 0.45))
                            .multilineTextAlignment(.center)
                            .lineSpacing(4)
                            .padding(.horizontal, 32)
                    }
                }
                Spacer()
            }
        }
        .onAppear {
            // Minimiza o PPPIX automaticamente após 1.5s mostrando a tela de desbloqueado
            AppDelegate.skipNextAuthReset = true
            #if !targetEnvironment(simulator)
            ScreenTimeManager.shared.isOpeningBankApp = true
            #endif
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                isPresented = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    UIControl().sendAction(#selector(URLSessionTask.suspend),
                                          to: UIApplication.shared, for: nil)
                }
            }
        }
    }


}

extension Notification.Name {
    static let sendEmergencyAlert = Notification.Name("pppix_send_emergency_alert")
}

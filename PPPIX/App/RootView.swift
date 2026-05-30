import SwiftUI
import CoreLocation

extension Int: @retroactive Identifiable {
    public var id: Int { self }
}

// MARK: - Auth State
@MainActor
class PPPIXAuthState: ObservableObject {
    static let shared = PPPIXAuthState()
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
    @StateObject private var auth    = PPPIXAuthState.shared
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
            } else if !auth.isAuthenticated && PPPIXAuthState.hasAppPassword {
                PPPIXLoginView(onAuthenticated: { auth.isAuthenticated = true })
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
        }
        .onChange(of: scenePhase) { phase in
            switch phase {
            case .background:
                stopAlertPolling()
                // FIX "ABRIR APP": se o usuário abriu o app desbloqueado a partir daqui,
                // não reseta a autenticação no próximo ciclo
                if AppDelegate.skipNextAuthReset {
                    AppDelegate.skipNextAuthReset = false
                } else {
                    auth.isAuthenticated = false
                }
                #if !targetEnvironment(simulator)
                ScreenTimeManager.shared.reblockOnBackground()
                #endif
            case .active:
                checkPasswordFlag()
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
            AlertDiagnosticLog.shared.log("RECEBER(push): notificação recebida id=\(id)")
            Task { @MainActor in
                if id > 0, let a = try? await APIClient.shared.getAlert(id: id) {
                    AlertDiagnosticLog.shared.log("RECEBER(push): alerta carregado id=\(a.id) de=\(a.sender_email) status=\(a.status)")
                    try? await APIClient.shared.markAlertRead(id: a.id)
                    emergencyAlert = a
                } else {
                    AlertDiagnosticLog.shared.log("RECEBER(push): getAlert falhou para id=\(id), buscando recentes...")
                    if let alerts = try? await APIClient.shared.getReceivedAlerts(),
                       let latest = alerts.first {
                        AlertDiagnosticLog.shared.log("RECEBER(push): usando alerta mais recente id=\(latest.id)")
                        try? await APIClient.shared.markAlertRead(id: latest.id)
                        emergencyAlert = latest
                    } else if id > 0 {
                        showAlertDetail = id
                    }
                }
            }
        }
    }

    /// Busca alertas recebidos e exibe se houver algum não lido.
    /// Equivalente ao onMessageReceived do Android: processa alertas recentes.
    private func pollAlertsOnce() {
        guard SessionManager.shared.isLoggedIn else { return }
        Task { @MainActor in
            AlertDiagnosticLog.shared.log("RECEBER: buscando alertas...")
            guard let alerts = try? await APIClient.shared.getReceivedAlerts() else {
                AlertDiagnosticLog.shared.log("RECEBER ERRO: falhou ao buscar alertas")
                return
            }
            AlertDiagnosticLog.shared.log("RECEBER: \(alerts.count) alertas encontrados")
            let myEmail = SessionManager.shared.userEmail
            for a in alerts {
                AlertDiagnosticLog.shared.log("  alerta id=\(a.id) tipo=\(a.alert_type) status=\(a.status) de=\(a.sender_email)")
            }
            let unread = alerts.first(where: {
                let s = $0.status.lowercased()
                let isMine = !myEmail.isEmpty && $0.sender_email.lowercased() == myEmail.lowercased()
                return !isMine && s != "cancelled" && s != "read" && s != "cancel"
            })
            guard let a = unread, emergencyAlert?.id != a.id else {
                if unread == nil { AlertDiagnosticLog.shared.log("RECEBER: nenhum alerta não lido") }
                return
            }
            AlertDiagnosticLog.shared.log("RECEBER: exibindo alerta id=\(a.id) de=\(a.sender_email)")
            try? await APIClient.shared.markAlertRead(id: a.id)
            AlertDiagnosticLog.shared.log("RECEBER: marcado como lido id=\(a.id)")
            emergencyAlert = a
        }
    }

    private func startAlertPolling() {
        guard SessionManager.shared.isLoggedIn else { return }
        stopAlertPolling()
        alertPollTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
            Task { @MainActor in
                guard SessionManager.shared.isLoggedIn else { return }
                guard let alerts = try? await APIClient.shared.getReceivedAlerts() else { return }
                let myEmail = SessionManager.shared.userEmail
                let unread = alerts.first(where: {
                    let s = $0.status.lowercased()
                    let isMine = !myEmail.isEmpty && $0.sender_email.lowercased() == myEmail.lowercased()
                    return !isMine && s != "cancelled" && s != "read" && s != "cancel"
                })
                guard let a = unread, self.emergencyAlert?.id != a.id else { return }
                AlertDiagnosticLog.shared.log("RECEBER(timer): novo alerta id=\(a.id) de=\(a.sender_email)")
                try? await APIClient.shared.markAlertRead(id: a.id)
                self.emergencyAlert = a
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

// MARK: - Tela de Emergência Fullscreen
struct EmergencyAlertView: View {
    let alert: Alert
    let onDismiss: () -> Void
    @State private var isCancelling = false
    @State private var cancelled = false

    private var isSender: Bool {
        alert.sender_email.lowercased() == SessionManager.shared.userEmail.lowercased()
    }

    var body: some View {
        ZStack {
            Color(hex: "#0A0005").ignoresSafeArea()
            ScrollView {
                VStack(spacing: 20) {
                    // Header
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 64))
                            .foregroundColor(Color(hex: "#FF2222"))
                        Text("🚨 ALERTA DE EMERGÊNCIA")
                            .font(.title2.bold()).foregroundColor(.white)
                            .multilineTextAlignment(.center)
                        Text(alert.message)
                            .font(.subheadline).foregroundColor(Color(white: 0.7))
                            .multilineTextAlignment(.center).padding(.horizontal, 8)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 28)
                    .background(Color(hex: "#330000")).cornerRadius(16)

                    infoCard(icon: "person.fill", color: Color(hex: "#3366FF"),
                             label: "Pessoa", value: alert.sender_name)

                    if alert.has_location, let url = alert.googleMapsURL {
                        Link(destination: url) {
                            HStack(spacing: 12) {
                                Image(systemName: "location.fill")
                                    .font(.system(size: 20)).foregroundColor(.white).frame(width: 36)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Localização GPS").font(.caption).foregroundColor(Color(white: 0.5))
                                    Text("Ver no Google Maps ↗")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(Color(hex: "#44AAFF"))
                                }
                                Spacer()
                            }
                            .padding(14).background(Color(hex: "#141422")).cornerRadius(14)
                        }
                    } else {
                        infoCard(icon: "location.slash.fill", color: Color(hex: "#FF6600"),
                                 label: "Localização", value: "Não disponível")
                    }

                    if !alert.vehicleText.isEmpty {
                        infoCard(icon: "car.fill", color: Color(hex: "#FF6600"),
                                 label: "Veículo", value: alert.vehicleText)
                    }

                    infoCard(icon: "clock.fill", color: Color(hex: "#9966FF"),
                             label: "Horário", value: alert.formattedDate)

                    // Botão 190
                    Button {
                        if let url = URL(string: "tel://190") { UIApplication.shared.open(url) }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "phone.fill").font(.system(size: 18, weight: .bold))
                            Text("LIGAR 190 — POLÍCIA").font(.system(size: 16, weight: .bold))
                        }
                        .foregroundColor(.white).frame(maxWidth: .infinity).padding(.vertical, 18)
                        .background(Color(hex: "#CC0000")).cornerRadius(14)
                    }

                    if isSender && !cancelled {
                        PPPIXButton(title: "Estou Bem — Cancelar Alerta", isLoading: isCancelling) {
                            Task {
                                isCancelling = true
                                try? await APIClient.shared.patchAlertStatus(id: alert.id, status: "cancelled")
                                isCancelling = false; cancelled = true; onDismiss()
                            }
                        }
                    } else {
                        Button("Fechar") { onDismiss() }
                            .font(.subheadline).foregroundColor(Color(white: 0.4)).padding(.bottom, 8)
                    }
                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 20).padding(.top, 40)
            }
        }
    }

    private func infoCard(icon: String, color: Color, label: String, value: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.system(size: 18)).foregroundColor(color).frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.caption).foregroundColor(Color(white: 0.5))
                Text(value).font(.system(size: 14, weight: .medium)).foregroundColor(.white)
            }
            Spacer()
        }
        .padding(14).background(Color(hex: "#141422")).cornerRadius(14)
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
            ScreenTimeManager.shared.unlockSingleApp(reblockAfterSeconds: 20)
            #endif
            unlockedApp = appName
            showArrow = true

        case "open_bank_alert":
            // FIX SENHA 3: mesmo unlock individual que senha 1
            // O alerta é disparado separadamente em verify() após buscar localização
            #if !targetEnvironment(simulator)
            ScreenTimeManager.shared.unlockSingleApp(reblockAfterSeconds: 20)
            #endif
            unlockedApp = appName
            showArrow = true

        default:
            errorMsg = "Senha incorreta"
            password = ""
        }
    }

    private func sendEmergencyAlert(coord: CLLocationCoordinate2D?) {
        // Captura valores AGORA no MainActor antes de entrar na Task assíncrona
        let myEmail  = SessionManager.shared.userEmail
        let userName = SessionManager.shared.userName
        let latStr   = coord.map { String(format: "%.6f", $0.latitude) }
        let lonStr   = coord.map { String(format: "%.6f", $0.longitude) }
        print("[PPPIX] sendEmergencyAlert inicio — user: \(myEmail), lat: \(latStr ?? "nil")")

        guard !myEmail.isEmpty else {
            print("[PPPIX] sendEmergencyAlert ABORTADO — userEmail vazio, usuário não logado?")
            return
        }

        Task { @MainActor in
            do {
                let connections  = try await APIClient.shared.getAcceptedConnections()
                let recipientIds = connections.map { $0.userId(myEmail: myEmail) }.filter { $0 > 0 }
                print("[PPPIX] sendEmergencyAlert — \(connections.count) conexões")
                for c in connections {
                    print("[PPPIX]   conexão: from=\(c.from_user_email) to=\(c.to_user_email) userId=\(c.userId(myEmail: myEmail))")
                }
                print("[PPPIX] recipient_ids: \(recipientIds)")

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
                print("[PPPIX] sendEmergencyAlert ENVIADO com sucesso — id: \(result.id)")
            } catch {
                print("[PPPIX] sendEmergencyAlert ERRO na primeira tentativa: \(error)")
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

// MARK: - Tela de seta
// MARK: - Tela pós-desbloqueio (substitui ArrowUnlockView)
struct ArrowUnlockView: View {
    let appName: String
    @Binding var isPresented: Bool

    var body: some View {
        ZStack {
            Color(hex: "#0A0A12").ignoresSafeArea()
            VStack(spacing: 0) {
                Spacer()
                VStack(spacing: 24) {
                    // Ícone de sucesso
                    ZStack {
                        Circle()
                            .fill(Color(hex: "#44FF88").opacity(0.12))
                            .frame(width: 100, height: 100)
                        Image(systemName: "checkmark.shield.fill")
                            .font(.system(size: 52))
                            .foregroundColor(Color(hex: "#44FF88"))
                    }

                    VStack(spacing: 10) {
                        Text("\(appName) Desbloqueado")
                            .font(.title2.bold())
                            .foregroundColor(.white)
                        Text("Você pode usar o \(appName) normalmente.\nEle ficará disponível por 10 segundos após você minimizar este app.")
                            .font(.subheadline)
                            .foregroundColor(Color(white: 0.45))
                            .multilineTextAlignment(.center)
                            .lineSpacing(4)
                            .padding(.horizontal, 32)
                    }

                    // Botão principal — minimiza o PPPIX e abre o app
                    Button {
                        openUnlockedApp()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "arrow.up.forward.app.fill")
                                .font(.system(size: 18, weight: .bold))
                            Text("Abrir \(appName)")
                                .font(.system(size: 16, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(LinearGradient(
                            colors: [Color(hex: "#3366FF"), Color(hex: "#6633FF")],
                            startPoint: .leading, endPoint: .trailing))
                        .cornerRadius(14)
                    }
                    .padding(.horizontal, 28)

                    Button { isPresented = false } label: {
                        Text("Fechar")
                            .font(.subheadline)
                            .foregroundColor(Color(white: 0.35))
                    }
                }
                Spacer()
            }
        }
    }

    private func openUnlockedApp() {
        let bundleId = UserDefaults(suiteName: "group.tech.pppix.app")?.string(forKey: "pppix_target_bundle_id") ?? ""
        let schemes: [String: String] = [
            "com.santander.app":             "santander://",
            "com.santander.SantanderBrasil": "santander://",
            "com.nubank.app":                "nubank://",
            "com.itau.iphone":               "itauaplicativo://",
            "com.bradesco.app":              "bradesco://",
            "com.bb.bolsodigital":           "bbdigi://",
            "com.caixa.app":                 "caixatemapp://",
            "com.inter.Inter":               "interapp://",
            "com.c6bank.ios":                "c6bank://",
            "com.picpay.ios":                "picpay://",
            "com.mercadopago.ios":           "mercadopago://",
            "net.whatsapp.WhatsApp":         "whatsapp://",
            "com.burbn.instagram":           "instagram://",
            "com.facebook.Facebook":         "fb://",
            "com.zhiliaoapp.musically":      "tiktok://",
        ]

        guard let scheme = schemes[bundleId], let url = URL(string: scheme) else {
            // App sem URL scheme — só fecha a tela
            isPresented = false
            return
        }

        // FIX: sinaliza para NÃO pedir senha quando o PPPIX voltar ao foreground
        AppDelegate.skipNextAuthReset = true

        // Sinaliza que estamos indo para background PROPOSITALMENTE (abrindo o banco)
        // Isso evita que reblockOnBackground() aplique shield prematuramente
        #if !targetEnvironment(simulator)
        ScreenTimeManager.shared.isOpeningBankApp = true
        #endif

        // Fecha TODOS os covers de uma vez antes de abrir o outro app
        isPresented = false

        // Abre o app com delay mínimo para o dismiss animar
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
    }
}

extension Notification.Name {
    static let sendEmergencyAlert = Notification.Name("pppix_send_emergency_alert")
}

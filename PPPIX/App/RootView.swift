import SwiftUI

extension Int: @retroactive Identifiable {
    public var id: Int { self }
}

// MARK: - Auth State
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

struct RootView: View {
    @StateObject private var session = SessionManager.shared
    @StateObject private var auth = PPPIXAuthState.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var showAlertDetail: Int? = nil
    @State private var emergencyAlert: Alert? = nil  // tela de emergência fullscreen

    @State private var showUnlockScreen: Bool = {
        if AppDelegate.pendingUnlockScreen {
            AppDelegate.pendingUnlockScreen = false
            return true
        }
        let defaults = UserDefaults(suiteName: "group.tech.pppix.app")
        if let defaults = defaults, defaults.bool(forKey: "pppix_show_password_screen") {
            let requestTime = defaults.double(forKey: "pppix_password_request_time")
            let age = Date().timeIntervalSince1970 - requestTime
            if requestTime > 0, age >= 0, age < 120 {
                defaults.removeObject(forKey: "pppix_show_password_screen")
                defaults.removeObject(forKey: "pppix_password_request_time")
                defaults.synchronize()
                return true
            }
            defaults.removeObject(forKey: "pppix_show_password_screen")
            defaults.removeObject(forKey: "pppix_password_request_time")
            defaults.synchronize()
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
        .sheet(item: $showAlertDetail) { alertId in
            AlertDetailView(alertId: alertId)
        }
        .fullScreenCover(isPresented: $showUnlockScreen) {
            UnlockPasswordView(
                isPresented: $showUnlockScreen,
                onPPPIXAccess: {
                    showUnlockScreen = false
                    auth.isAuthenticated = true
                }
            )
        }
        // Tela de emergência fullscreen ao receber alerta de outro dispositivo
        .fullScreenCover(item: $emergencyAlert) { alert in
            EmergencyAlertView(alert: alert, onDismiss: { emergencyAlert = nil })
        }
        .onAppear {
            #if !targetEnvironment(simulator)
            ScreenTimeManager.shared.checkAuthorization()
            #endif
        }
        // FIX REBLOCK: quando app vai para background, rebloqueia se unlock expirou
        .onChange(of: scenePhase) { phase in
            switch phase {
            case .background:
                auth.isAuthenticated = false
                #if !targetEnvironment(simulator)
                ScreenTimeManager.shared.reblockOnBackground()
                #endif
            case .active:
                checkPasswordFlag()
                #if !targetEnvironment(simulator)
                ScreenTimeManager.shared.syncCheckAndReblock()
                #endif
            default: break
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("pppix.forceOpenUnlockScreen"))) { _ in
            guard !showUnlockScreen else { return }
            showUnlockScreen = true
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("pppix.openAlertDetail"))) { notif in
            if let alertId = notif.userInfo?["alert_id"] as? Int {
                showAlertDetail = alertId
            }
        }
        // FIX ALERTA: escuta o evento e chama a API
        .onReceive(NotificationCenter.default.publisher(for: .sendEmergencyAlert)) { notif in
            let alertId = notif.userInfo?["alert_id"] as? Int
            if let id = alertId {
                Task { showAlertDetail = id }
            }
        }
        // Recebe alerta de emergência de outro dispositivo — abre tela fullscreen
        .onReceive(NotificationCenter.default.publisher(for: .incomingEmergencyAlert)) { notif in
            if let alertId = notif.userInfo?["alert_id"] as? Int {
                Task {
                    EmergencyAudioService.shared.playSiren()
                    if let a = try? await APIClient.shared.getAlert(id: alertId) {
                        await MainActor.run { emergencyAlert = a }
                    } else {
                        await MainActor.run { showAlertDetail = alertId }
                    }
                }
            }
        }
    }

    private func checkPasswordFlag() {
        guard let defaults = sharedDefaults else { return }
        guard defaults.bool(forKey: "pppix_show_password_screen") else { return }
        guard !showUnlockScreen else {
            defaults.removeObject(forKey: "pppix_show_password_screen")
            defaults.synchronize()
            return
        }
        let requestTime = defaults.double(forKey: "pppix_password_request_time")
        let age = Date().timeIntervalSince1970 - requestTime
        guard requestTime > 0, age >= 0, age < 120 else {
            defaults.removeObject(forKey: "pppix_show_password_screen")
            defaults.removeObject(forKey: "pppix_password_request_time")
            defaults.synchronize()
            return
        }
        defaults.removeObject(forKey: "pppix_show_password_screen")
        defaults.removeObject(forKey: "pppix_password_request_time")
        defaults.synchronize()
        showUnlockScreen = true
    }
}

// MARK: - Tela de Emergência Fullscreen
struct EmergencyAlertView: View {
    let alert: Alert
    let onDismiss: () -> Void
    @State private var isCancelling = false
    @State private var cancelled = false

    private var isSender: Bool { alert.sender_email.lowercased() == SessionManager.shared.userEmail.lowercased() }

    var body: some View {
        ZStack {
            Color(hex: "#0A0005").ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {

                    // Header pulsante
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 64))
                            .foregroundColor(Color(hex: "#FF2222"))

                        Text("🚨 ALERTA DE EMERGÊNCIA")
                            .font(.title2.bold())
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)

                        Text(alert.message)
                            .font(.subheadline)
                            .foregroundColor(Color(white: 0.7))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 8)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
                    .background(Color(hex: "#330000"))
                    .cornerRadius(16)

                    // Nome da pessoa
                    infoCard(icon: "person.fill", color: Color(hex: "#3366FF"),
                             label: "Pessoa", value: alert.sender_name)

                    // Localização
                    if alert.has_location, let mapsURL = alert.googleMapsURL {
                        Link(destination: mapsURL) {
                            HStack(spacing: 12) {
                                Image(systemName: "location.fill")
                                    .font(.system(size: 20))
                                    .foregroundColor(.white)
                                    .frame(width: 36)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Localização GPS")
                                        .font(.caption)
                                        .foregroundColor(Color(white: 0.5))
                                    Text("Ver no Google Maps ↗")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(Color(hex: "#44AAFF"))
                                }
                                Spacer()
                            }
                            .padding(14)
                            .background(Color(hex: "#141422"))
                            .cornerRadius(14)
                        }
                    } else {
                        infoCard(icon: "location.slash.fill", color: Color(hex: "#FF6600"),
                                 label: "Localização", value: "Não disponível")
                    }

                    // Veículo
                    if !alert.vehicleText.isEmpty {
                        infoCard(icon: "car.fill", color: Color(hex: "#FF6600"),
                                 label: "Veículo", value: alert.vehicleText)
                    }

                    // Data/hora
                    infoCard(icon: "clock.fill", color: Color(hex: "#9966FF"),
                             label: "Horário", value: alert.formattedDate)

                    // Botão 190 vermelho
                    Button {
                        if let url = URL(string: "tel://190") {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "phone.fill")
                                .font(.system(size: 18, weight: .bold))
                            Text("LIGAR 190 — POLÍCIA")
                                .font(.system(size: 16, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(Color(hex: "#CC0000"))
                        .cornerRadius(14)
                    }

                    // Estou bem / fechar (se for o remetente)
                    if isSender && !cancelled {
                        PPPIXButton(title: "Estou Bem — Cancelar Alerta", isLoading: isCancelling) {
                            Task {
                                isCancelling = true
                                try? await APIClient.shared.patchAlertStatus(id: alert.id, status: "cancelled")
                                isCancelling = false
                                cancelled = true
                                onDismiss()
                            }
                        }
                    } else {
                        Button("Fechar") { onDismiss() }
                            .font(.subheadline)
                            .foregroundColor(Color(white: 0.4))
                            .padding(.bottom, 8)
                    }

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 20)
                .padding(.top, 40)
            }
        }
    }

    private func infoCard(icon: String, color: Color, label: String, value: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(color)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.caption).foregroundColor(Color(white: 0.5))
                Text(value).font(.system(size: 14, weight: .medium)).foregroundColor(.white)
            }
            Spacer()
        }
        .padding(14)
        .background(Color(hex: "#141422"))
        .cornerRadius(14)
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
                        Image(systemName: "lock.fill")
                            .font(.system(size: 36))
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
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(errorMsg.isEmpty ? Color(white: 0.12) : Color(hex: "#FF4444"), lineWidth: 1))
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
                let response = try await APIClient.shared.verifyPassword(body: VerifyPasswordRequest(password: password, latitude: nil, longitude: nil))
                await MainActor.run {
                    isLoading = false
                    if response.action == "open_pppix" || response.action == "open_ppix" {
                        onAuthenticated()
                    } else {
                        errorMsg = "Senha incorreta"
                        password = ""
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

    @State private var password = ""
    @State private var errorMsg = ""
    @State private var isLoading = false
    @State private var showArrow = false
    @State private var unlockedAppName = ""
    @FocusState private var isFocused: Bool

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
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 40))
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
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(errorMsg.isEmpty ? Color(white: 0.12) : Color(hex: "#FF4444"), lineWidth: 1))
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
        .onAppear { isFocused = true }
        .fullScreenCover(isPresented: $showArrow, onDismiss: { isPresented = false }) {
            ArrowUnlockView(appName: unlockedAppName, isPresented: $showArrow)
        }
    }

    private func verify() {
        guard !password.isEmpty, !isLoading else { return }
        isLoading = true; errorMsg = ""
        Task {
            do {
                let coord = await LocationService.shared.getCurrentLocation()
                let response = try await APIClient.shared.verifyPassword(body: VerifyPasswordRequest(password: password, latitude: coord?.latitude, longitude: coord?.longitude))
                await MainActor.run {
                    isLoading = false
                    handleResponse(response, coord: coord)
                }
            } catch {
                await MainActor.run { isLoading = false; errorMsg = "Senha incorreta"; password = "" }
            }
        }
    }

    private func handleResponse(_ response: VerifyPasswordResponse, coord: CLLocationCoordinate2D?) {
        let bundleId = sharedDefaults?.string(forKey: "pppix_target_bundle_id") ?? ""
        let appName = appDisplayName(for: bundleId)

        switch response.action {
        case "open_pppix", "open_ppix":
            isPresented = false
            onPPPIXAccess()

        case "open_bank":
            // Senha correta — desbloqueia o app agora e agenda reblock em 10s
            #if !targetEnvironment(simulator)
            ScreenTimeManager.shared.unlockSingleApp(reblockAfterSeconds: 10)
            #endif
            unlockedAppName = appName
            showArrow = true

        case "open_bank_alert":
            // Senha de emergência — desbloqueia + envia alerta silencioso
            #if !targetEnvironment(simulator)
            ScreenTimeManager.shared.unlockSingleApp(reblockAfterSeconds: 10)
            #endif
            unlockedAppName = appName
            showArrow = true
            sendEmergencyAlert(coord: coord)

        default:
            errorMsg = "Senha incorreta"
            password = ""
        }
    }

    // FIX ALERTA: envia alerta diretamente aqui, com localização
    private func sendEmergencyAlert(coord: CLLocationCoordinate2D?) {
        let myEmail = SessionManager.shared.userEmail
        let userName = SessionManager.shared.userName
        Task {
            do {
                let connections = (try? await APIClient.shared.getAcceptedConnections()) ?? []
                let recipientIds = connections.map { $0.userId(myEmail: myEmail) }.filter { $0 > 0 }
                let vehicles = (try? await APIClient.shared.getVehicles()) ?? []
                let vehicle = vehicles.first(where: { $0.is_active }) ?? vehicles.first
                let vehiclePayload = vehicle.map {
                    VehicleInfoPayload(model: $0.model, license_plate: $0.license_plate, color: $0.color, year: $0.year)
                }
                let body = SendAlertRequest(
                    alert_type: "emergency_password",
                    priority: "critical",
                    title: "🚨 Senha de Emergência",
                    message: "\(userName) utilizou a senha de emergência e pode estar em perigo!",
                    latitude: coord.map { String(format: "%.6f", $0.latitude) },
                    longitude: coord.map { String(format: "%.6f", $0.longitude) },
                    metadata: AlertMetadata(
                        timestamp: String(Int(Date().timeIntervalSince1970 * 1000)),
                        vehicle_info: vehiclePayload
                    ),
                    recipient_ids: recipientIds
                )
                _ = try await APIClient.shared.sendAlert(body: body)
            } catch {}
        }
    }

    private func appDisplayName(for bundleId: String) -> String {
        let names: [String: String] = [
            "com.santander.app": "Santander", "com.santander.SantanderBrasil": "Santander",
            "com.nubank.app": "Nubank", "com.itau.iphone": "Itaú",
            "com.bradesco.app": "Bradesco", "com.bb.bolsodigital": "Banco do Brasil",
            "com.caixa.app": "Caixa", "com.inter.Inter": "Inter",
            "com.c6bank.ios": "C6 Bank", "com.picpay.ios": "PicPay",
            "com.mercadopago.ios": "Mercado Pago", "net.whatsapp.WhatsApp": "WhatsApp",
            "com.burbn.instagram": "Instagram", "com.facebook.Facebook": "Facebook",
            "com.zhiliaoapp.musically": "TikTok",
        ]
        return names[bundleId] ?? "App"
    }
}

// MARK: - Tela de seta
struct ArrowUnlockView: View {
    let appName: String
    @Binding var isPresented: Bool

    var body: some View {
        ZStack {
            Color(hex: "#0A0A12").ignoresSafeArea()
            VStack(spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Image(systemName: "arrow.up.left")
                            .font(.system(size: 60, weight: .bold))
                            .foregroundStyle(LinearGradient(colors: [Color(hex: "#3366FF"), Color(hex: "#6633FF")], startPoint: .topLeading, endPoint: .bottomTrailing))
                        Text("Toque aqui para\nabrir o \(appName)")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(Color(white: 0.5))
                            .lineSpacing(3)
                    }
                    .padding(.top, 56).padding(.leading, 28)
                    Spacer()
                }
                Spacer()
                VStack(spacing: 20) {
                    ZStack {
                        Circle().fill(Color(hex: "#44FF88").opacity(0.12)).frame(width: 88, height: 88)
                        Image(systemName: "checkmark.shield.fill").font(.system(size: 44)).foregroundColor(Color(hex: "#44FF88"))
                    }
                    VStack(spacing: 10) {
                        Text("\(appName) Desbloqueado").font(.title2.bold()).foregroundColor(.white)
                        Text("Agora você pode usá-lo normalmente.\nEle está minimizado no canto superior esquerdo.")
                            .font(.subheadline).foregroundColor(Color(white: 0.45))
                            .multilineTextAlignment(.center).lineSpacing(4).padding(.horizontal, 32)
                    }
                }
                Spacer()
                Button { isPresented = false } label: {
                    Text("Fechar").font(.system(size: 16, weight: .medium)).foregroundColor(Color(white: 0.35))
                        .frame(maxWidth: .infinity).frame(height: 48)
                }
                .padding(.horizontal, 28).padding(.bottom, 40)
            }
        }
    }
}

import CoreLocation

extension Notification.Name {
    static let sendEmergencyAlert = Notification.Name("pppix_send_emergency_alert")
}

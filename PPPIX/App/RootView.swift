import SwiftUI

extension Int: @retroactive Identifiable {
    public var id: Int { self }
}

// MARK: - Auth State
class PPPIXAuthState: ObservableObject {
    static let shared = PPPIXAuthState()
    private init() {}
    @Published var isAuthenticated = false

    // Senha 2: padrão TRUE — se o usuário tem as senhas salvas, sempre pede
    static var hasAppPassword: Bool {
        get {
            // Padrão: true (pede senha ao abrir)
            if UserDefaults.standard.object(forKey: "pppix_app_password_enabled") == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: "pppix_app_password_enabled")
        }
        set { UserDefaults.standard.set(newValue, forKey: "pppix_app_password_enabled") }
    }
}

struct RootView: View {
    @StateObject private var session = SessionManager.shared
    @StateObject private var auth = PPPIXAuthState.shared
    @State private var showAlertDetail: Int? = nil
    @State private var showUnlockScreen = false

    private let sharedDefaults = UserDefaults(suiteName: "group.tech.pppix.app")

    var body: some View {
        Group {
            if !session.isLoggedIn {
                LoginView()
            } else if !auth.isAuthenticated && PPPIXAuthState.hasAppPassword {
                PPPIXLoginView(onAuthenticated: {
                    auth.isAuthenticated = true
                })
            } else {
                HomeView()
            }
        }
        .onAppear {
            // Resetar flag após primeira aparição
            AppDelegate.pendingUnlockScreen = false
        }
        .sheet(item: $showAlertDetail) { alertId in
            AlertDetailView(alertId: alertId)
        }
        // Tela de unlock — contém a tela de seta internamente (sem flash)
        .fullScreenCover(isPresented: $showUnlockScreen) {
            UnlockPasswordView(
                isPresented: $showUnlockScreen,
                onPPPIXAccess: {
                    showUnlockScreen = false
                    auth.isAuthenticated = true
                }
            )
        }
        .onAppear {
            // Inicializar Screen Time ao abrir o app
            #if !targetEnvironment(simulator)
            ScreenTimeManager.shared.checkAuthorization()
            #endif
            // Verificar flag do UserDefaults sem delay (backup para background)
            checkPasswordFlag()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("pppix.forceOpenUnlockScreen"))) { _ in
            openUnlockScreen()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("pppix.openAlertDetail"))) { notif in
            if let alertId = notif.userInfo?["alert_id"] as? Int {
                showAlertDetail = alertId
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
            auth.isAuthenticated = false
            #if !targetEnvironment(simulator)
            ScreenTimeManager.shared.reblockOnBackground()
            #endif
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            // Verificar flag imediatamente — SEM delay
            checkPasswordFlag()
            #if !targetEnvironment(simulator)
            ScreenTimeManager.shared.syncCheckAndReblock()
            #endif
        }
    }

    private func openUnlockScreen() {
        guard !showUnlockScreen else { return }
        showUnlockScreen = true
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
        openUnlockScreen()
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
                            .fill(LinearGradient(
                                colors: [Color(hex: "#3366FF").opacity(0.2), Color(hex: "#6633FF").opacity(0.1)],
                                startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 88, height: 88)
                        Image(systemName: "lock.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(LinearGradient(
                                colors: [Color(hex: "#3366FF"), Color(hex: "#6633FF")],
                                startPoint: .top, endPoint: .bottom))
                    }
                    Text("PPPIX").font(.title.bold()).foregroundColor(.white)
                    Text("Digite sua senha para continuar")
                        .font(.subheadline).foregroundColor(Color(white: 0.45))
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
                let response = try await APIClient.shared.verifyPassword(
                    body: VerifyPasswordRequest(password: password, latitude: nil, longitude: nil))
                await MainActor.run {
                    isLoading = false
                    if response.action == "open_pppix" {
                        onAuthenticated()
                    } else {
                        // DEBUG: mostrar qual ação retornou para diagnóstico
                        errorMsg = "Senha incorreta (cod: \(response.action))"
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
    @State private var showArrow = false      // tela de seta — dentro desta view (sem flash)
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
                            .fill(LinearGradient(
                                colors: [Color(hex: "#3366FF").opacity(0.2), Color(hex: "#6633FF").opacity(0.1)],
                                startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 88, height: 88)
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(LinearGradient(
                                colors: [Color(hex: "#3366FF"), Color(hex: "#6633FF")],
                                startPoint: .top, endPoint: .bottom))
                    }
                    Text("App Protegido").font(.title2.bold()).foregroundColor(.white)
                    Text("Digite sua senha para continuar")
                        .font(.subheadline).foregroundColor(Color(white: 0.45))
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
        // Tela de seta abre POR CIMA desta view — sem flash da HomeView
        .fullScreenCover(isPresented: $showArrow, onDismiss: {
            isPresented = false  // fecha unlock view depois que seta é fechada
        }) {
            ArrowUnlockView(appName: unlockedAppName, isPresented: $showArrow)
        }
    }

    private func verify() {
        guard !password.isEmpty, !isLoading else { return }
        isLoading = true; errorMsg = ""
        Task {
            do {
                let response = try await APIClient.shared.verifyPassword(
                    body: VerifyPasswordRequest(password: password, latitude: nil, longitude: nil))
                await MainActor.run {
                    isLoading = false
                    handleResponse(response)
                }
            } catch {
                await MainActor.run { isLoading = false; errorMsg = "Senha incorreta"; password = "" }
            }
        }
    }

    private func handleResponse(_ response: VerifyPasswordResponse) {
        let bundleId = sharedDefaults?.string(forKey: "pppix_target_bundle_id") ?? ""
        let appName = appDisplayName(for: bundleId)

        switch response.action {
        case "open_pppix":
            // Senha 2 → acessa o PPPIX
            isPresented = false
            onPPPIXAccess()

        case "open_bank":
            // Senha 1 → desbloqueia app + tela de seta (sem redirecionar via URL)
            #if !targetEnvironment(simulator)
            ScreenTimeManager.shared.unlockSingleApp(seconds: 60)
            #endif
            unlockedAppName = appName
            showArrow = true   // abre tela de seta POR CIMA, sem fechar esta view primeiro

        case "open_bank_alert":
            // Senha 3 → desbloqueia + alerta silencioso + tela de seta
            #if !targetEnvironment(simulator)
            ScreenTimeManager.shared.unlockSingleApp(seconds: 60)
            #endif
            NotificationCenter.default.post(name: .sendEmergencyAlert, object: nil)
            unlockedAppName = appName
            showArrow = true

        default:
            errorMsg = "Senha incorreta"
            password = ""
        }
    }

    private func appDisplayName(for bundleId: String) -> String {
        let names: [String: String] = [
            "com.santander.app":             "Santander",
            "com.santander.SantanderBrasil": "Santander",
            "com.nubank.app":                "Nubank",
            "com.itau.iphone":               "Itaú",
            "com.bradesco.app":              "Bradesco",
            "com.bb.bolsodigital":           "Banco do Brasil",
            "com.caixa.app":                 "Caixa",
            "com.inter.Inter":               "Inter",
            "com.c6bank.ios":                "C6 Bank",
            "com.picpay.ios":                "PicPay",
            "com.mercadopago.ios":           "Mercado Pago",
            "net.whatsapp.WhatsApp":         "WhatsApp",
            "com.burbn.instagram":           "Instagram",
            "com.facebook.Facebook":         "Facebook",
            "com.zhiliaoapp.musically":      "TikTok",
        ]
        return names[bundleId] ?? "App"
    }
}

// MARK: - Tela de seta (app minimizado no canto superior esquerdo)
struct ArrowUnlockView: View {
    let appName: String
    @Binding var isPresented: Bool

    var body: some View {
        ZStack {
            Color(hex: "#0A0A12").ignoresSafeArea()
            VStack(spacing: 0) {

                // Seta apontando para o ◄ botão nativo do iOS (canto sup. esq.)
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Image(systemName: "arrow.up.left")
                            .font(.system(size: 60, weight: .bold))
                            .foregroundStyle(LinearGradient(
                                colors: [Color(hex: "#3366FF"), Color(hex: "#6633FF")],
                                startPoint: .topLeading, endPoint: .bottomTrailing))

                        Text("Toque aqui para\nabrir o \(appName)")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(Color(white: 0.5))
                            .lineSpacing(3)
                    }
                    .padding(.top, 56)
                    .padding(.leading, 28)
                    Spacer()
                }

                Spacer()

                // Conteúdo central
                VStack(spacing: 20) {
                    ZStack {
                        Circle()
                            .fill(Color(hex: "#44FF88").opacity(0.12))
                            .frame(width: 88, height: 88)
                        Image(systemName: "checkmark.shield.fill")
                            .font(.system(size: 44))
                            .foregroundColor(Color(hex: "#44FF88"))
                    }

                    VStack(spacing: 10) {
                        Text("\(appName) Desbloqueado")
                            .font(.title2.bold())
                            .foregroundColor(.white)

                        Text("Agora você pode usá-lo normalmente.\nEle está minimizado no canto superior esquerdo.")
                            .font(.subheadline)
                            .foregroundColor(Color(white: 0.45))
                            .multilineTextAlignment(.center)
                            .lineSpacing(4)
                            .padding(.horizontal, 32)
                    }
                }

                Spacer()

                Button {
                    isPresented = false
                } label: {
                    Text("Fechar")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(Color(white: 0.35))
                        .frame(maxWidth: .infinity).frame(height: 48)
                }
                .padding(.horizontal, 28).padding(.bottom, 40)
            }
        }
    }
}

extension Notification.Name {
    static let sendEmergencyAlert = Notification.Name("pppix_send_emergency_alert")
}

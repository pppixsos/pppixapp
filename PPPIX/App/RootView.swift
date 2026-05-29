import SwiftUI

extension Int: @retroactive Identifiable {
    public var id: Int { self }
}

// MARK: - Estado de autenticação do PPPIX (em memória)
class PPPIXAuthState: ObservableObject {
    static let shared = PPPIXAuthState()
    private init() {}
    @Published var isAuthenticated = false
    @Published var showUnlockFlow = false // veio de notificação de app bloqueado
}

struct RootView: View {

    @StateObject private var session = SessionManager.shared
    @StateObject private var auth = PPPIXAuthState.shared
    @State private var showAlertDetail: Int? = nil
    @State private var showUnlockScreen = false    // tela de senha do app bloqueado
    @State private var showPPPIXLogin = false      // senha 2 para entrar no PPPIX
    @State private var showArrowScreen = false     // após desbloquear
    @State private var unlockedAppName = ""

    private let sharedDefaults = UserDefaults(suiteName: "group.tech.pppix.app")

    var body: some View {
        Group {
            if !session.isLoggedIn {
                LoginView()
            } else if !auth.isAuthenticated {
                // PPPIX sempre pede senha 2 ao abrir
                PPPIXLoginView(onAuthenticated: {
                    auth.isAuthenticated = true
                })
            } else {
                HomeView()
            }
        }
        .sheet(item: $showAlertDetail) { alertId in
            AlertDetailView(alertId: alertId)
        }
        // Tela de senha para desbloquear app protegido
        .fullScreenCover(isPresented: $showUnlockScreen) {
            UnlockPasswordView(
                isPresented: $showUnlockScreen,
                onUnlocked: { appName in
                    unlockedAppName = appName
                    showUnlockScreen = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        showArrowScreen = true
                    }
                },
                onPPPIXAccess: {
                    // Senha 2 na tela de unlock → acessa PPPIX
                    showUnlockScreen = false
                    auth.isAuthenticated = true
                }
            )
        }
        // Tela de seta após desbloqueio
        .fullScreenCover(isPresented: $showArrowScreen) {
            ArrowUnlockView(appName: unlockedAppName, isPresented: $showArrowScreen)
        }
        .onAppear {
            // Verificar se veio de notificação (cold start)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                checkPasswordFlag()
            }
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
            // Rebloquear PPPIX ao fechar (requer senha 2 na próxima abertura)
            auth.isAuthenticated = false
            #if !targetEnvironment(simulator)
            ScreenTimeManager.shared.reblockOnBackground()
            #endif
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                checkPasswordFlag()
            }
            #if !targetEnvironment(simulator)
            ScreenTimeManager.shared.syncCheckAndReblock()
            #endif
        }
    }

    private func openUnlockScreen() {
        guard !showUnlockScreen, !showArrowScreen else { return }
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

// MARK: - Senha 2 para acessar o PPPIX
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
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            ))
                            .frame(width: 88, height: 88)
                        Image(systemName: "lock.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(LinearGradient(
                                colors: [Color(hex: "#3366FF"), Color(hex: "#6633FF")],
                                startPoint: .top, endPoint: .bottom
                            ))
                    }
                    Text("PPPIX")
                        .font(.title.bold())
                        .foregroundColor(.white)
                    Text("Digite sua senha para continuar")
                        .font(.subheadline)
                        .foregroundColor(Color(white: 0.45))
                }
                .padding(.bottom, 40)

                VStack(spacing: 8) {
                    SecureField("Senha", text: $password)
                        .font(.system(size: 17))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                        .frame(height: 54)
                        .background(Color(white: 0.07))
                        .cornerRadius(14)
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
                    body: VerifyPasswordRequest(password: password, latitude: nil, longitude: nil)
                )
                await MainActor.run {
                    isLoading = false
                    // Aceita open_pppix (quando API implementar), open_bank ou open_bank_alert
                    let validActions = ["open_pppix", "open_bank", "open_bank_alert"]
                    if validActions.contains(response.action) {
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

// MARK: - Tela de senha para desbloquear app protegido
struct UnlockPasswordView: View {
    @Binding var isPresented: Bool
    let onUnlocked: (String) -> Void
    let onPPPIXAccess: () -> Void

    @State private var password = ""
    @State private var errorMsg = ""
    @State private var isLoading = false
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
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            ))
                            .frame(width: 88, height: 88)
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(LinearGradient(
                                colors: [Color(hex: "#3366FF"), Color(hex: "#6633FF")],
                                startPoint: .top, endPoint: .bottom
                            ))
                    }
                    Text("App Protegido")
                        .font(.title2.bold()).foregroundColor(.white)
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
    }

    private func verify() {
        guard !password.isEmpty, !isLoading else { return }
        isLoading = true; errorMsg = ""
        Task {
            do {
                let response = try await APIClient.shared.verifyPassword(
                    body: VerifyPasswordRequest(password: password, latitude: nil, longitude: nil)
                )
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
            // Senha normal → desbloqueia app + tela de seta
            unlock(bundleId: bundleId)
            onUnlocked(appName)

        case "open_bank_alert":
            // Senha emergência → desbloqueia + alerta silencioso + tela de seta
            unlock(bundleId: bundleId)
            NotificationCenter.default.post(name: .sendEmergencyAlert, object: nil)
            onUnlocked(appName)

        default:
            errorMsg = "Senha incorreta"
            password = ""
        }
    }

    private func unlock(bundleId: String) {
        #if !targetEnvironment(simulator)
        ScreenTimeManager.shared.unlockSingleApp(seconds: 60)
        #endif
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

// MARK: - Tela de seta após desbloqueio
struct ArrowUnlockView: View {
    let appName: String
    @Binding var isPresented: Bool

    var body: some View {
        ZStack {
            Color(hex: "#0A0A12").ignoresSafeArea()

            VStack(spacing: 0) {
                // Seta para o canto superior esquerdo
                HStack {
                    Image(systemName: "arrow.up.left")
                        .font(.system(size: 72, weight: .bold))
                        .foregroundStyle(LinearGradient(
                            colors: [Color(hex: "#3366FF"), Color(hex: "#6633FF")],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ))
                        .padding(.top, 60)
                        .padding(.leading, 32)
                    Spacer()
                }

                Spacer()

                VStack(spacing: 20) {
                    // Ícone de sucesso
                    ZStack {
                        Circle()
                            .fill(Color(hex: "#44FF88").opacity(0.12))
                            .frame(width: 80, height: 80)
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 44))
                            .foregroundColor(Color(hex: "#44FF88"))
                    }

                    VStack(spacing: 8) {
                        Text("\(appName) desbloqueado")
                            .font(.title2.bold())
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)

                        Text("Agora você pode usá-lo normalmente.\nToque no ícone no canto superior esquerdo.")
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
                        .foregroundColor(Color(white: 0.4))
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 40)
            }
        }
    }
}

extension Notification.Name {
    static let sendEmergencyAlert = Notification.Name("pppix_send_emergency_alert")
}

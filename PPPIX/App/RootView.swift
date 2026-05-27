import SwiftUI

// Int: Identifiable — necessário para .sheet(item: $Int?)
extension Int: @retroactive Identifiable {
    public var id: Int { self }
}

struct RootView: View {

    @StateObject private var session = SessionManager.shared
    @State private var showAlertDetail: Int? = nil
    @State private var showPasswordScreen = false

    // Timer que monitora UserDefaults para saber quando o ShieldAction pediu senha
    private let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()
    private let sharedDefaults = UserDefaults(suiteName: "group.tech.pppix.app")

    var body: some View {
        Group {
            if session.isLoggedIn {
                HomeView()
            } else {
                LoginView()
            }
        }
        .sheet(item: $showAlertDetail) { alertId in
            AlertDetailView(alertId: alertId)
        }
        .fullScreenCover(isPresented: $showPasswordScreen) {
            ShieldPasswordView(isPresented: $showPasswordScreen)
        }
        .onReceive(NotificationCenter.default.publisher(for: .openAlertDetail)) { notif in
            if let alertId = notif.userInfo?["alert_id"] as? Int {
                showAlertDetail = alertId
            }
        }
        // Monitora quando o ShieldAction sinaliza que o usuário quer digitar senha
        .onReceive(timer) { _ in
            checkForPasswordRequest()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            checkForPasswordRequest()
            // Ao voltar pro app, rebloquear se necessário
            #if !targetEnvironment(simulator)
            Task { @MainActor in
                ScreenTimeManager.shared.reblockAfterUnlock()
            }
            #endif
        }
    }

    private func checkForPasswordRequest() {
        guard let defaults = sharedDefaults,
              defaults.bool(forKey: "pppix_show_password_screen") else { return }

        // Evitar abrir múltiplas vezes
        let requestTime = defaults.double(forKey: "pppix_password_request_time")
        guard requestTime > 0, Date().timeIntervalSince1970 - requestTime < 30 else {
            defaults.removeObject(forKey: "pppix_show_password_screen")
            return
        }

        defaults.removeObject(forKey: "pppix_show_password_screen")
        defaults.removeObject(forKey: "pppix_password_request_time")
        defaults.synchronize()

        if !showPasswordScreen {
            showPasswordScreen = true
        }
    }
}

// MARK: — Tela de senha que aparece quando o usuário toca "Digitar Senha" no shield
struct ShieldPasswordView: View {
    @Binding var isPresented: Bool
    @State private var password = ""
    @State private var errorMsg = ""
    @State private var isLoading = false
    @State private var showSuccess = false
    @FocusState private var isFocused: Bool

    var body: some View {
        ZStack {
            Color(hex: "#0A0A12").ignoresSafeArea()

            VStack(spacing: 28) {

                // Header
                VStack(spacing: 8) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(LinearGradient(
                            colors: [Color(hex: "#3366FF"), Color(hex: "#6633FF")],
                            startPoint: .top, endPoint: .bottom
                        ))

                    Text("Digite sua senha")
                        .font(.title2.bold())
                        .foregroundColor(.white)

                    Text("Para desbloquear o app protegido")
                        .font(.subheadline)
                        .foregroundColor(Color(white: 0.5))
                }
                .padding(.top, 48)

                // Campo de senha
                VStack(spacing: 12) {
                    SecureField("Senha", text: $password)
                        .font(.system(size: 18))
                        .foregroundColor(.white)
                        .accentColor(Color(hex: "#3366FF"))
                        .multilineTextAlignment(.center)
                        .padding(16)
                        .background(Color(white: 0.08))
                        .cornerRadius(13)
                        .overlay(
                            RoundedRectangle(cornerRadius: 13)
                                .stroke(errorMsg.isEmpty ? Color(white: 0.15) : Color(hex: "#FF4444"), lineWidth: 1)
                        )
                        .focused($isFocused)
                        .onSubmit { verify() }

                    if !errorMsg.isEmpty {
                        Text(errorMsg)
                            .font(.caption)
                            .foregroundColor(Color(hex: "#FF4444"))
                    }
                }
                .padding(.horizontal, 32)

                // Botões
                VStack(spacing: 12) {
                    Button { verify() } label: {
                        Group {
                            if isLoading {
                                ProgressView().tint(.white)
                            } else {
                                Text("Confirmar")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.white)
                            }
                        }
                        .frame(maxWidth: .infinity).frame(height: 52)
                        .background(LinearGradient(
                            colors: [Color(hex: "#3366FF"), Color(hex: "#6633FF")],
                            startPoint: .leading, endPoint: .trailing
                        ))
                        .cornerRadius(13)
                    }
                    .disabled(isLoading || password.isEmpty)
                    .padding(.horizontal, 32)

                    Button("Cancelar") {
                        isPresented = false
                    }
                    .font(.subheadline)
                    .foregroundColor(Color(white: 0.4))
                }

                Spacer()
            }
        }
        .onAppear { isFocused = true }
    }

    private func verify() {
        guard !password.isEmpty else { return }
        isLoading = true
        errorMsg = ""

        Task {
            do {
                let response = try await APIClient.shared.verifyPassword(password)
                await MainActor.run {
                    isLoading = false
                    handlePasswordResponse(response)
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    errorMsg = "Senha incorreta"
                    password = ""
                }
            }
        }
    }

    private func handlePasswordResponse(_ response: PasswordResponse) {
        switch response.action {
        case "open_bank":
            // Senha normal — desbloquear e o usuário abre o app normalmente
            unlockApps()

        case "open_bank_alert":
            // Senha de emergência — desbloquear + enviar alerta silencioso
            unlockApps()
            sendEmergencyAlert()

        default:
            errorMsg = "Senha incorreta"
            password = ""
        }
    }

    private func unlockApps() {
        #if !targetEnvironment(simulator)
        ScreenTimeManager.shared.unblockAll()
        #endif
        // Fechar tela de senha — o app bloqueado volta a estar acessível
        isPresented = false
        // Rebloquear após 30 segundos (tempo para o usuário abrir o app)
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
            #if !targetEnvironment(simulator)
            ScreenTimeManager.shared.reblockAfterUnlock()
            #endif
        }
    }

    private func sendEmergencyAlert() {
        NotificationCenter.default.post(name: .sendEmergencyAlert, object: nil)
    }
}

extension Notification.Name {
    static let openAlertDetail = Notification.Name("pppix_open_alert_detail")
    static let sendEmergencyAlert = Notification.Name("pppix_send_emergency_alert")
}

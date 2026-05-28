import SwiftUI

extension Int: @retroactive Identifiable {
    public var id: Int { self }
}

struct RootView: View {

    @StateObject private var session = SessionManager.shared
    @State private var showAlertDetail: Int? = nil
    @State private var showPasswordScreen = false
    private let timer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()
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
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("pppix.openAlertDetail"))) { notif in
            if let alertId = notif.userInfo?["alert_id"] as? Int {
                showAlertDetail = alertId
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("pppix.openUnlockScreen"))) { _ in
            if !showPasswordScreen { showPasswordScreen = true }
        }
        .onReceive(timer) { _ in
            checkForPasswordRequest()
        }
        .onOpenURL { url in
            if url.scheme == "pppix" && url.host == "unlock" {
                if !showPasswordScreen { showPasswordScreen = true }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
            // didEnterBackground — app saiu completamente da tela
            #if !targetEnvironment(simulator)
            ScreenTimeManager.shared.reblockOnBackground()
            #endif
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            // Lição 7 do Habit Doom: verificação síncrona ao voltar pro foreground
            checkForPasswordRequest()
            #if !targetEnvironment(simulator)
            ScreenTimeManager.shared.syncCheckAndReblock()
            #endif
        }
    }

    private func checkForPasswordRequest() {
        guard let defaults = sharedDefaults else { return }
        guard defaults.bool(forKey: "pppix_show_password_screen") else { return }

        let requestTime = defaults.double(forKey: "pppix_password_request_time")
        let age = Date().timeIntervalSince1970 - requestTime

        // Ignorar se muito antigo (> 30s) ou se veio do app principal abrindo normalmente
        guard requestTime > 0, age < 30, age > 0 else {
            defaults.removeObject(forKey: "pppix_show_password_screen")
            defaults.removeObject(forKey: "pppix_password_request_time")
            defaults.synchronize()
            return
        }

        defaults.removeObject(forKey: "pppix_show_password_screen")
        defaults.removeObject(forKey: "pppix_password_request_time")
        defaults.synchronize()

        if !showPasswordScreen { showPasswordScreen = true }
    }
}

// MARK: - Tela de senha
struct ShieldPasswordView: View {
    @Binding var isPresented: Bool
    @State private var password = ""
    @State private var errorMsg = ""
    @State private var isLoading = false
    @FocusState private var isFocused: Bool
    @Environment(\.openURL) private var openURL

    var body: some View {
        ZStack {
            Color(hex: "#0A0A12").ignoresSafeArea()

            VStack(spacing: 0) {

                // Header
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
                        .font(.title2.bold())
                        .foregroundColor(.white)

                    Text("Digite sua senha para continuar")
                        .font(.subheadline)
                        .foregroundColor(Color(white: 0.45))
                }
                .padding(.top, 64)
                .padding(.bottom, 40)

                // Campo de senha
                VStack(spacing: 8) {
                    SecureField("Senha", text: $password)
                        .font(.system(size: 17))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                        .frame(height: 54)
                        .background(Color(white: 0.07))
                        .cornerRadius(14)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(
                                    errorMsg.isEmpty
                                        ? Color(white: 0.12)
                                        : Color(hex: "#FF4444"),
                                    lineWidth: 1
                                )
                        )
                        .focused($isFocused)
                        .onSubmit { verify() }

                    if !errorMsg.isEmpty {
                        Text(errorMsg)
                            .font(.caption)
                            .foregroundColor(Color(hex: "#FF4444"))
                    }
                }
                .padding(.horizontal, 28)

                Spacer().frame(height: 24)

                // Botão confirmar
                Button { verify() } label: {
                    ZStack {
                        if isLoading {
                            ProgressView().tint(.white)
                        } else {
                            Text("Confirmar")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(
                        LinearGradient(
                            colors: [Color(hex: "#3366FF"), Color(hex: "#6633FF")],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                    .cornerRadius(14)
                }
                .disabled(isLoading || password.isEmpty)
                .padding(.horizontal, 28)

                Spacer().frame(height: 12)

                // Botão cancelar
                Button("Cancelar") {
                    isPresented = false
                }
                .font(.subheadline)
                .foregroundColor(Color(white: 0.35))
                .padding(.bottom, 40)

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
                let response = try await APIClient.shared.verifyPassword(
                    body: VerifyPasswordRequest(password: password, latitude: nil, longitude: nil)
                )
                await MainActor.run {
                    isLoading = false
                    handleResponse(response)
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

    private func handleResponse(_ response: VerifyPasswordResponse) {
        switch response.action {
        case "open_bank":
            unlock()

        case "open_bank_alert":
            unlock()
            NotificationCenter.default.post(name: .sendEmergencyAlert, object: nil)

        default:
            errorMsg = "Senha incorreta"
            password = ""
        }
    }

    private func unlock() {
        #if !targetEnvironment(simulator)
        // Libera por 5 minutos — o shield é removido, o app protegido fica acessível
        ScreenTimeManager.shared.unlockTemporarily(seconds: 60)
        #endif
        isPresented = false
        // O app que estava bloqueado já está embaixo, acessível após o shield ser removido
    }
}

extension Notification.Name {
    static let sendEmergencyAlert = Notification.Name("pppix_send_emergency_alert")
}

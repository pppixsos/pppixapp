import SwiftUI

extension Int: @retroactive Identifiable {
    public var id: Int { self }
}

struct RootView: View {

    @StateObject private var session = SessionManager.shared
    @State private var showAlertDetail: Int? = nil
    @State private var showPasswordScreen = false

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
        .onAppear {
            // Verificar ao abrir o app (cold start)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                checkPasswordFlag()
            }
        }
        // Notificação normal do sistema
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("pppix.openUnlockScreen"))) { _ in
            openPasswordScreen()
        }
        // Notificação forçada (da notificação local — sempre abre)
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("pppix.forceOpenUnlockScreen"))) { _ in
            showPasswordScreen = true
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("pppix.openAlertDetail"))) { notif in
            if let alertId = notif.userInfo?["alert_id"] as? Int {
                showAlertDetail = alertId
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
            #if !targetEnvironment(simulator)
            ScreenTimeManager.shared.reblockOnBackground()
            #endif
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                checkPasswordFlag()
            }
            #if !targetEnvironment(simulator)
            ScreenTimeManager.shared.syncCheckAndReblock()
            #endif
        }
    }

    private func openPasswordScreen() {
        guard !showPasswordScreen else { return }
        showPasswordScreen = true
    }

    private func checkPasswordFlag() {
        guard let defaults = sharedDefaults else { return }
        guard defaults.bool(forKey: "pppix_show_password_screen") else { return }
        guard !showPasswordScreen else {
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
        openPasswordScreen()
    }
}

// MARK: - Tela de senha
struct ShieldPasswordView: View {
    @Binding var isPresented: Bool
    @State private var password = ""
    @State private var errorMsg = ""
    @State private var isLoading = false
    @FocusState private var isFocused: Bool

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
                        .font(.title2.bold())
                        .foregroundColor(.white)

                    Text("Digite sua senha para continuar")
                        .font(.subheadline)
                        .foregroundColor(Color(white: 0.45))
                }
                .padding(.top, 64)
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
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(
                                    errorMsg.isEmpty ? Color(white: 0.12) : Color(hex: "#FF4444"),
                                    lineWidth: 1
                                )
                        )
                        .focused($isFocused)

                    if !errorMsg.isEmpty {
                        Text(errorMsg)
                            .font(.caption)
                            .foregroundColor(Color(hex: "#FF4444"))
                    }
                }
                .padding(.horizontal, 28)

                Spacer().frame(height: 24)

                Button {
                    verify()
                } label: {
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
        guard !password.isEmpty, !isLoading else { return }
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
        ScreenTimeManager.shared.unlockSingleApp(seconds: 60)
        #endif

        isPresented = false

        // Abrir o app que estava bloqueado após um pequeno delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let bundleId = UserDefaults(suiteName: "group.tech.pppix.app")?
                .string(forKey: "pppix_target_bundle_id") ?? ""

            let schemeMap: [String: String] = [
                "com.santander.app":             "santander://",
                "com.santander.SantanderBrasil": "santander://",
                "com.nubank.app":                "nubank://",
                "com.itau.iphone":               "itauaplicativo://",
                "com.bradesco.app":              "bradesco://",
                "com.bb.bolsodigital":           "bbdigi://",
                "com.caixa.app":                 "caixatem://",
                "com.inter.Inter":               "interapp://",
                "com.c6bank.ios":                "c6bank://",
                "com.picpay.ios":                "picpay://",
                "com.mercadopago.ios":           "mercadopago://",
                "net.whatsapp.WhatsApp":         "whatsapp://",
                "com.burbn.instagram":           "instagram://",
                "com.facebook.Facebook":         "fb://",
                "com.zhiliaoapp.musically":      "tiktok://",
            ]

            let scheme = schemeMap[bundleId] ?? "santander://"
            if let url = URL(string: scheme) {
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
            }
        }
    }
}

extension Notification.Name {
    static let sendEmergencyAlert = Notification.Name("pppix_send_emergency_alert")
}

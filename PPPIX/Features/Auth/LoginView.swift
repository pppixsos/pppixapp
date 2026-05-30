import SwiftUI
import FirebaseMessaging

struct LoginView: View {

    @State private var email = ""
    @State private var password = ""
    @State private var showPassword = false
    @State private var isLoading = false
    @State private var errorMessage = ""
    @State private var showRegister = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "#0A0A12").ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 32) {

                        // Logo
                        VStack(spacing: 12) {
                            Image(systemName: "shield.fill")
                                .font(.system(size: 64))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [Color(hex: "#3366FF"), Color(hex: "#6633FF")],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                            Text("PPPIX")
                                .font(.system(size: 32, weight: .bold))
                                .foregroundColor(.white)
                            Text("Sua segurança financeira")
                                .font(.subheadline)
                                .foregroundColor(Color(white: 0.6))
                        }
                        .padding(.top, 60)

                        // Form
                        VStack(spacing: 16) {
                            PPPIXTextField(
                                title: "Email",
                                placeholder: "seu@email.com",
                                text: $email,
                                keyboardType: .emailAddress,
                                autocapitalization: .never
                            )

                            PPPIXSecureField(
                                title: "Senha",
                                placeholder: "Digite sua senha",
                                text: $password,
                                showPassword: $showPassword
                            )
                        }

                        // Error
                        if !errorMessage.isEmpty {
                            Text(errorMessage)
                                .font(.footnote)
                                .foregroundColor(Color(hex: "#FF4444"))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }

                        // Login button
                        PPPIXButton(title: "Entrar", isLoading: isLoading) {
                            Task { await login() }
                        }

                        // Register link
                        Button {
                            showRegister = true
                        } label: {
                            HStack(spacing: 4) {
                                Text("Não tem conta?")
                                    .foregroundColor(Color(white: 0.6))
                                Text("Cadastre-se")
                                    .foregroundColor(Color(hex: "#3366FF"))
                                    .fontWeight(.semibold)
                            }
                            .font(.subheadline)
                        }

                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 24)
                }
            }
            .navigationDestination(isPresented: $showRegister) {
                RegisterView()
            }
        }
    }

    // MARK: - Login

    private func login() async {
        let trimmedEmail = email.trimmingCharacters(in: .whitespaces)

        guard !trimmedEmail.isEmpty else { errorMessage = "Informe seu email."; return }
        guard trimmedEmail.contains("@") else { errorMessage = "Email inválido."; return }
        guard !password.isEmpty else { errorMessage = "Informe sua senha."; return }

        isLoading = true
        errorMessage = ""

        do {
            let response = try await APIClient.shared.login(email: trimmedEmail, password: password)
            SessionManager.shared.saveTokens(access: response.access, refresh: response.refresh)

            // Busca dados do usuário
            do {
                let me = try await APIClient.shared.getMe()
                SessionManager.shared.saveUserInfo(id: me.id, email: me.email, name: me.fullName)
                await AlertDiagnosticLog.shared.log("Login OK: \(me.email) id=\(me.id)")
            } catch {
                await AlertDiagnosticLog.shared.log("getMe ERRO: \(error) — usando email do login")
                // Fallback: usar email digitado
                SessionManager.shared.saveUserInfo(id: 0, email: trimmedEmail, name: trimmedEmail)
            }

            // Registra FCM — tenta token salvo ou busca novo do Firebase
            if let fcmToken = SessionManager.shared.fcmToken {
                do {
                    try await APIClient.shared.registerFcmDevice(token: fcmToken, platform: "ios")
                    await AlertDiagnosticLog.shared.log("FCM registrado no login: \(fcmToken.prefix(20))...")
                } catch {
                    await AlertDiagnosticLog.shared.log("FCM registro ERRO no login: \(error)")
                }
            } else {
                // Buscar token diretamente do Firebase
                await AlertDiagnosticLog.shared.log("FCM: buscando token do Firebase...")
                await withCheckedContinuation { continuation in
                    Messaging.messaging().token { token, error in
                        if let token = token {
                            Task { @MainActor in
                                AlertDiagnosticLog.shared.log("FCM token obtido no login: \(token.prefix(20))...")
                                SessionManager.shared.fcmToken = token
                                try? await APIClient.shared.registerFcmDevice(token: token, platform: "ios")
                                AlertDiagnosticLog.shared.log("FCM registrado após busca ✅")
                            }
                        } else {
                            Task { @MainActor in
                                AlertDiagnosticLog.shared.log("FCM: Firebase sem token — \(error?.localizedDescription ?? "desconhecido")")
                            }
                        }
                        continuation.resume()
                    }
                }
            }

        } catch APIError.unauthorized {
            errorMessage = "Email ou senha incorretos."
        } catch APIError.badRequest(let msg) {
            errorMessage = msg
        } catch {
            errorMessage = "Erro de conexão. Verifique sua internet."
        }

        isLoading = false
    }
}

import SwiftUI
import AuthenticationServices
import GoogleSignIn
import FirebaseMessaging

struct LoginView: View {

    @State private var email = ""
    @State private var password = ""
    @State private var showPassword = false
    @State private var isLoading = false
    @State private var isSocialLoading = false
    @State private var errorMessage = ""
    @State private var showForgotPassword = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "#0A0A12").ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 28) {

                        // Logo
                        VStack(spacing: 12) {
                            Image(systemName: "shield.fill")
                                .font(.system(size: 64))
                                .foregroundStyle(LinearGradient(
                                    colors: [Color(hex: "#3366FF"), Color(hex: "#6633FF")],
                                    startPoint: .topLeading, endPoint: .bottomTrailing))
                            Text("PPPIX")
                                .font(.system(size: 32, weight: .bold))
                                .foregroundColor(.white)
                            Text("Sua segurança financeira")
                                .font(.subheadline)
                                .foregroundColor(Color(white: 0.6))
                        }
                        .padding(.top, 56)

                        // Social login
                        VStack(spacing: 10) {
                            SocialButton(
                                icon: "apple.logo",
                                title: "Continuar com Apple",
                                isLoading: isSocialLoading
                            ) { signInWithApple() }

                            SocialButton(
                                icon: "g.circle.fill",
                                title: "Continuar com Google",
                                isLoading: isSocialLoading
                            ) { signInWithGoogle() }
                        }

                        // Divisor
                        HStack {
                            Rectangle().fill(Color(white: 0.15)).frame(height: 1)
                            Text("ou").font(.caption).foregroundColor(Color(white: 0.4)).padding(.horizontal, 8)
                            Rectangle().fill(Color(white: 0.15)).frame(height: 1)
                        }

                        // Email / senha
                        VStack(spacing: 14) {
                            PPPIXTextField(title: "Email", placeholder: "seu@email.com",
                                          text: $email, keyboardType: .emailAddress,
                                          autocapitalization: .never)
                            PPPIXSecureField(title: "Senha", placeholder: "Digite sua senha",
                                            text: $password, showPassword: $showPassword)
                        }

                        if !errorMessage.isEmpty {
                            Text(errorMessage)
                                .font(.footnote).foregroundColor(Color(hex: "#FF4444"))
                                .multilineTextAlignment(.center)
                        }

                        PPPIXButton(title: "Entrar", isLoading: isLoading) {
                            Task { await login() }
                        }

                        Button("Esqueci minha senha") { showForgotPassword = true }
                            .font(.subheadline).foregroundColor(Color(hex: "#3366FF"))

                        Button {
                            PPPIXAuthState.instance.isOnboarding = true
                        } label: {
                            HStack(spacing: 4) {
                                Text("Não tem conta?").foregroundColor(Color(white: 0.6))
                                Text("Cadastre-se").foregroundColor(Color(hex: "#3366FF")).fontWeight(.semibold)
                            }.font(.subheadline)
                        }

                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 24)
                }
            }
            .sheet(isPresented: $showForgotPassword) { ForgotPasswordView() }
        }
    }

    // MARK: - Email login

    private func login() async {
        let e = email.trimmingCharacters(in: .whitespaces)
        guard !e.isEmpty else { errorMessage = "Informe seu email."; return }
        guard e.contains("@") else { errorMessage = "Email inválido."; return }
        guard !password.isEmpty else { errorMessage = "Informe sua senha."; return }

        isLoading = true; errorMessage = ""
        do {
            let r = try await APIClient.shared.login(email: e, password: password)
            await finishLogin(access: r.access, refresh: r.refresh)
        } catch APIError.unauthorized {
            errorMessage = "Email ou senha incorretos."
        } catch APIError.badRequest(let msg) {
            errorMessage = msg
        } catch {
            errorMessage = "Erro de conexão. Verifique sua internet."
        }
        isLoading = false
    }

    // MARK: - Apple Sign In

    private func signInWithApple() {
        let provider = ASAuthorizationAppleIDProvider()
        let req = provider.createRequest()
        req.requestedScopes = [.fullName, .email]
        let controller = ASAuthorizationController(authorizationRequests: [req])
        AppleSignInDelegate.shared.onComplete = { result in
            Task { @MainActor in
                await handleAppleResult(result)
            }
        }
        controller.delegate = AppleSignInDelegate.shared
        controller.presentationContextProvider = AppleSignInDelegate.shared
        controller.performRequests()
    }

    private func handleAppleResult(_ result: Result<ASAuthorizationAppleIDCredential, Error>) async {
        switch result {
        case .failure(let e):
            let code = (e as? ASAuthorizationError)?.code
            if code != .canceled {
                errorMessage = "Apple erro: \(e.localizedDescription)"
            }
        case .success(let cred):
            guard let tokenData = cred.identityToken,
                  let token = String(data: tokenData, encoding: .utf8) else {
                errorMessage = "Token Apple inválido."; return
            }
            isSocialLoading = true; errorMessage = ""
            // Apple só envia nome na primeira vez — salvar localmente
            let firstName = cred.fullName?.givenName
            let lastName  = cred.fullName?.familyName
            // Salvar nome se veio (primeira vez)
            if let fn = firstName, !fn.isEmpty {
                UserDefaults.standard.set(fn, forKey: "apple_first_name")
            }
            if let ln = lastName, !ln.isEmpty {
                UserDefaults.standard.set(ln, forKey: "apple_last_name")
            }
            // Usar nome salvo se não veio agora
            let savedFirst = UserDefaults.standard.string(forKey: "apple_first_name")
            let savedLast  = UserDefaults.standard.string(forKey: "apple_last_name")
            do {
                let r = try await APIClient.shared.socialLogin(
                    provider: "apple", token: token,
                    firstName: firstName ?? savedFirst,
                    lastName: lastName ?? savedLast)
                await finishLogin(access: r.access, refresh: r.refresh)
            } catch APIError.badRequest(let msg) {
                errorMessage = msg
            } catch APIError.unauthorized {
                errorMessage = "Não autorizado pelo servidor Apple."
            } catch {
                errorMessage = "Apple: \(error.localizedDescription)"
            }
            isSocialLoading = false
        }
    }

    // MARK: - Google Sign In

    private func signInWithGoogle() {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = scene.windows.first?.rootViewController else { return }
        // Configurar lazily — garantido independente do AppDelegate
        if GIDSignIn.sharedInstance.configuration == nil {
            let clientID = "11117611081-c4ubusln48ed44n8d1rknc308ddfpqdf.apps.googleusercontent.com"
            GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        }
        isSocialLoading = true; errorMessage = ""
        GIDSignIn.sharedInstance.signIn(withPresenting: root) { result, error in
            // Extrair dados fora do Task para evitar data race
            let signInError = error
            let idToken = result?.user.idToken?.tokenString
            let firstName = result?.user.profile?.givenName
            let lastName = result?.user.profile?.familyName

            Task { @MainActor in
                if let signInError = signInError {
                    if (signInError as NSError).code != GIDSignInError.canceled.rawValue {
                        errorMessage = "Erro ao entrar com Google."
                    }
                    isSocialLoading = false; return
                }
                guard let idToken = idToken else {
                    errorMessage = "Token Google inválido."
                    isSocialLoading = false; return
                }
                do {
                    let r = try await APIClient.shared.socialLogin(
                        provider: "google", token: idToken,
                        firstName: firstName,
                        lastName: lastName)
                    await finishLogin(access: r.access, refresh: r.refresh)
                } catch APIError.badRequest(let msg) {
                    errorMessage = msg
                } catch {
                    errorMessage = "Google: \(error.localizedDescription)"
                }
                isSocialLoading = false
            }
        }
    }

    // MARK: - Finish login

    private func finishLogin(access: String, refresh: String) async {
        SessionManager.shared.saveTokens(access: access, refresh: refresh)
        do {
            let me = try await APIClient.shared.getMe()
            SessionManager.shared.saveUserInfo(id: me.id, email: me.email, name: me.fullName)
        } catch {
            SessionManager.shared.saveUserInfo(id: 0, email: email, name: email)
        }
        await registerPushTokens()
    }

    private func registerPushTokens() async {
        if let apns = SessionManager.shared.pendingApnsToken, !apns.isEmpty {
            try? await APIClient.shared.registerFcmDevice(token: apns, platform: "ios_apns")
        }
        if let fcm = SessionManager.shared.fcmToken {
            try? await APIClient.shared.registerFcmDevice(token: fcm, platform: "ios")
        }
    }
}

// MARK: - Social Button

private struct SocialButton: View {
    let icon: String
    let title: String
    let isLoading: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if isLoading {
                    ProgressView().tint(Color(white: 0.8)).frame(width: 20)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 18))
                        .foregroundColor(.white)
                        .frame(width: 20)
                }
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
            }
            .frame(maxWidth: .infinity).frame(height: 50)
            .background(Color(white: 0.1))
            .cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12)
                .stroke(Color(white: 0.18), lineWidth: 1))
        }
        .disabled(isLoading)
    }
}

// MARK: - Apple Sign In Delegate

final class AppleSignInDelegate: NSObject, ASAuthorizationControllerDelegate,
    ASAuthorizationControllerPresentationContextProviding {

    static let shared = AppleSignInDelegate()
    var onComplete: ((Result<ASAuthorizationAppleIDCredential, Error>) -> Void)?

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow } ?? UIWindow()
    }

    func authorizationController(controller: ASAuthorizationController,
                                 didCompleteWithAuthorization authorization: ASAuthorization) {
        if let cred = authorization.credential as? ASAuthorizationAppleIDCredential {
            onComplete?(.success(cred))
        }
    }

    func authorizationController(controller: ASAuthorizationController,
                                 didCompleteWithError error: Error) {
        onComplete?(.failure(error))
    }
}

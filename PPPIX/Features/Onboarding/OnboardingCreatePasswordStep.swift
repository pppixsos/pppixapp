import SwiftUI

struct OnboardingCreatePasswordStep: View {
    @ObservedObject var data: OnboardingData
    let onBack: () -> Void
    let onAccountCreated: () -> Void

    @State private var showPassword = false
    @State private var showPasswordConfirm = false
    @State private var isLoading = false
    @State private var errorMessage = ""

    var body: some View {
        OnboardingStepShell(
            icon: "lock.fill",
            iconColor: Color(hex: "#6633FF"),
            title: "Crie sua senha de acesso",
            subtitle: "Essa é a senha para entrar no app. Use pelo menos 8 caracteres.",
            stepIndex: 3,
            totalSteps: 13,
            onBack: onBack
        ) {
            VStack(spacing: 14) {
                PPPIXSecureField(
                    title: "Senha",
                    placeholder: "Mínimo 8 caracteres",
                    text: $data.password,
                    showPassword: $showPassword
                )
                PPPIXSecureField(
                    title: "Confirmar Senha",
                    placeholder: "Repita sua senha",
                    text: $data.passwordConfirm,
                    showPassword: $showPasswordConfirm
                )

                if !errorMessage.isEmpty { ErrorBanner(message: errorMessage) }

                PPPIXButton(title: "Criar minha conta", isLoading: isLoading) {
                    Task { await createAccount() }
                }
                .padding(.top, 8)
            }
        }
    }

    private func createAccount() async {
        guard validate() else { return }

        isLoading = true
        errorMessage = ""

        let rawCPF = data.cpf.filter(\.isNumber)
        let rawPhone = data.phone.filter(\.isNumber)
        let rawCEP = data.cep.filter(\.isNumber)
        let email = data.email.trimmingCharacters(in: .whitespaces).lowercased()

        let body = RegisterRequest(
            email: email,
            username: email,
            first_name: data.firstName.trimmingCharacters(in: .whitespaces),
            last_name: data.lastName.trimmingCharacters(in: .whitespaces),
            password: data.password,
            password_confirm: data.passwordConfirm,
            profile: ProfileData(
                cpf: rawCPF,
                phone: rawPhone,
                birth_date: convertDateToISO(data.birthDate),
                cep: rawCEP
            )
        )

        do {
            try await APIClient.shared.register(body: body)

            // Login automático
            let loginResp = try await APIClient.shared.login(email: email, password: data.password)
            SessionManager.shared.saveTokens(access: loginResp.access, refresh: loginResp.refresh)
            let me = try await APIClient.shared.getMe()
            SessionManager.shared.saveUserInfo(id: me.id, email: me.email, name: me.fullName)
            await registerPushTokens()

            isLoading = false
            onAccountCreated()
        } catch APIError.badRequest(let msg) {
            errorMessage = msg
            isLoading = false
        } catch {
            errorMessage = "Erro ao criar conta. Tente novamente."
            isLoading = false
        }
    }

    private func registerPushTokens() async {
        if let apns = SessionManager.shared.pendingApnsToken, !apns.isEmpty {
            try? await APIClient.shared.registerFcmDevice(token: apns, platform: "ios_apns")
        }
        if let fcm = SessionManager.shared.fcmToken {
            try? await APIClient.shared.registerFcmDevice(token: fcm, platform: "ios")
        }
    }

    private func validate() -> Bool {
        if data.password.count < 8 { errorMessage = "Senha deve ter pelo menos 8 caracteres."; return false }
        if data.password != data.passwordConfirm { errorMessage = "As senhas não coincidem."; return false }
        return true
    }

    private func convertDateToISO(_ ddMMyyyy: String) -> String {
        let parts = ddMMyyyy.split(separator: "/")
        guard parts.count == 3 else { return ddMMyyyy }
        return "\(parts[2])-\(parts[1])-\(parts[0])"
    }
}

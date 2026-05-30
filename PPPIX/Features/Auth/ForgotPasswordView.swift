import SwiftUI

struct ForgotPasswordView: View {
    @Environment(\.dismiss) private var dismiss

    // MARK: - Steps
    enum Step { case email, code, newPassword, success }
    @State private var step: Step = .email

    // MARK: - Fields
    @State private var email         = ""
    @State private var code          = ""
    @State private var newPassword   = ""
    @State private var confirmPassword = ""
    // MARK: - State
    @State private var isLoading          = false
    @State private var showNewPassword    = false
    @State private var showConfirmPassword = false
    @State private var errorMessage  = ""

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "#0A0A12").ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 28) {
                        // Header
                        VStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(Color(hex: "#3366FF").opacity(0.12))
                                    .frame(width: 80, height: 80)
                                Image(systemName: stepIcon)
                                    .font(.system(size: 36))
                                    .foregroundColor(Color(hex: "#3366FF"))
                            }
                            Text(stepTitle)
                                .font(.title2.bold())
                                .foregroundColor(.white)
                            Text(stepSubtitle)
                                .font(.subheadline)
                                .foregroundColor(Color(white: 0.45))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 24)
                        }
                        .padding(.top, 20)

                        // Fields
                        VStack(spacing: 16) {
                            if step == .email {
                                PPPIXTextField(
                                    title: "Email",
                                    placeholder: "seu@email.com",
                                    text: $email
                                )
                                .keyboardType(.emailAddress)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                            }

                            if step == .code {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Código de 6 dígitos")
                                        .font(.caption)
                                        .foregroundColor(Color(white: 0.5))
                                    TextField("000000", text: $code)
                                        .keyboardType(.numberPad)
                                        .font(.system(size: 32, weight: .bold, design: .monospaced))
                                        .multilineTextAlignment(.center)
                                        .foregroundColor(.white)
                                        .padding()
                                        .background(Color(white: 0.08))
                                        .cornerRadius(12)
                                        .onChange(of: code) { _ in
                                            code = String(code.filter { $0.isNumber }.prefix(6))
                                        }
                                }
                                .padding(.horizontal, 24)
                            }

                            if step == .newPassword {
                                PPPIXSecureField(
                                    title: "Nova Senha",
                                    placeholder: "Mínimo 8 caracteres",
                                    text: $newPassword,
                                    showPassword: $showNewPassword
                                )
                                PPPIXSecureField(
                                    title: "Confirmar Nova Senha",
                                    placeholder: "Repita a nova senha",
                                    text: $confirmPassword,
                                    showPassword: $showConfirmPassword
                                )

                            }

                            if step == .success {
                                VStack(spacing: 16) {
                                    ZStack {
                                        Circle()
                                            .fill(Color(hex: "#44FF88").opacity(0.12))
                                            .frame(width: 80, height: 80)
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 44))
                                            .foregroundColor(Color(hex: "#44FF88"))
                                    }
                                    Text("Senha alterada com sucesso!")
                                        .font(.headline)
                                        .foregroundColor(.white)
                                    Text("Faça login com sua nova senha.")
                                        .font(.subheadline)
                                        .foregroundColor(Color(white: 0.45))
                                }
                                .padding(.top, 20)
                            }
                        }
                        .padding(.horizontal, 24)

                        // Error
                        if !errorMessage.isEmpty {
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundColor(Color(hex: "#FF4444"))
                                .padding(.horizontal, 24)
                                .multilineTextAlignment(.center)
                        }

                        // Buttons
                        VStack(spacing: 12) {
                            if step != .success {
                                PPPIXButton(
                                    title: stepButtonTitle,
                                    isLoading: isLoading
                                ) {
                                    Task { await handleAction() }
                                }
                                .padding(.horizontal, 24)
                            } else {
                                PPPIXButton(title: "Fazer Login") {
                                    dismiss()
                                }
                                .padding(.horizontal, 24)
                            }

                            if step == .code {
                                Button {
                                    Task { await requestCode() }
                                } label: {
                                    Text("Reenviar código")
                                        .font(.subheadline)
                                        .foregroundColor(Color(hex: "#3366FF"))
                                }
                            }
                        }

                        Spacer(minLength: 40)
                    }
                }
            }
            .navigationTitle("Recuperar Senha")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancelar") { dismiss() }
                        .foregroundColor(Color(white: 0.5))
                }
            }
        }
    }

    // MARK: - Computed
    var stepIcon: String {
        switch step {
        case .email:       return "envelope.fill"
        case .code:        return "number.circle.fill"
        case .newPassword: return "lock.rotation"
        case .success:     return "checkmark.shield.fill"
        }
    }
    var stepTitle: String {
        switch step {
        case .email:       return "Recuperar Senha"
        case .code:        return "Verifique seu Email"
        case .newPassword: return "Nova Senha"
        case .success:     return "Pronto!"
        }
    }
    var stepSubtitle: String {
        switch step {
        case .email:       return "Digite seu email para receber um código de verificação."
        case .code:        return "Enviamos um código de 6 dígitos para \(email). Verifique sua caixa de entrada."
        case .newPassword: return "Escolha uma nova senha forte para sua conta."
        case .success:     return ""
        }
    }
    var stepButtonTitle: String {
        switch step {
        case .email:       return "Enviar Código"
        case .code:        return "Verificar Código"
        case .newPassword: return "Redefinir Senha"
        case .success:     return ""
        }
    }

    // MARK: - Actions
    func handleAction() async {
        errorMessage = ""
        switch step {
        case .email:       await requestCode()
        case .code:        await verifyCode()
        case .newPassword: await confirmReset()
        case .success:     break
        }
    }

    func requestCode() async {
        guard !email.isEmpty else { errorMessage = "Digite seu email."; return }
        isLoading = true
        do {
            try await APIClient.shared.requestPasswordReset(email: email)
            step = .code
        } catch {
            errorMessage = "Email não encontrado ou erro ao enviar código."
        }
        isLoading = false
    }

    func verifyCode() async {
        guard code.count == 6 else { errorMessage = "Digite o código de 6 dígitos."; return }
        isLoading = true
        do {
            try await APIClient.shared.verifyPasswordResetCode(email: email, code: code)
            step = .newPassword
        } catch {
            errorMessage = "Código inválido ou expirado."
        }
        isLoading = false
    }

    func confirmReset() async {
        guard newPassword.count >= 8 else { errorMessage = "A senha precisa ter pelo menos 8 caracteres."; return }
        guard newPassword == confirmPassword else { errorMessage = "As senhas não coincidem."; return }
        isLoading = true
        do {
            try await APIClient.shared.confirmPasswordReset(email: email, code: code, newPassword: newPassword)
            step = .success
        } catch {
            errorMessage = "Erro ao redefinir senha. Tente novamente."
        }
        isLoading = false
    }
}

import SwiftUI

struct PasswordSetupView: View {

    @Environment(\.dismiss) private var dismiss

    @State private var bankPassword = ""
    @State private var ppixPassword = ""
    @State private var emergencyPassword = ""
    @State private var showBank = false
    @State private var showPpix = false
    @State private var showEmergency = false
    @State private var maxAttempts = 3
    @State private var isLoadingPasswords = true
    @State private var isSavingPasswords = false
    @State private var isSavingAttempts = false
    @State private var errorMessage = ""
    @State private var successMessage = ""
    @State private var passwordSettingsId: Int? = nil

    private let attemptOptions = Array(1...10)

    var body: some View {
        ZStack {
            Color(hex: "#0A0A12").ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {

                    // Header
                    VStack(spacing: 8) {
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Color(hex: "#3366FF"), Color(hex: "#6633FF")],
                                    startPoint: .top, endPoint: .bottom
                                )
                            )
                        Text("Configurar Senhas")
                            .font(.title2.bold())
                            .foregroundColor(.white)
                        Text("Defina as 3 senhas de proteção do PPPIX")
                            .font(.subheadline)
                            .foregroundColor(Color(white: 0.5))
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 8)

                    if isLoadingPasswords {
                        ProgressView()
                            .tint(Color(hex: "#3366FF"))
                            .padding()
                    } else {
                        // Senha 1 — Banco
                        PasswordCard(
                            icon: "building.columns.fill",
                            color: Color(hex: "#0099FF"),
                            title: "Senha do Banco",
                            subtitle: "Abre o app normalmente",
                            password: $bankPassword,
                            showPassword: $showBank
                        )

                        // Senha 2 — PPPIX
                        PasswordCard(
                            icon: "shield.fill",
                            color: Color(hex: "#3366FF"),
                            title: "Senha do PPPIX",
                            subtitle: "Abre as configurações do PPPIX",
                            password: $ppixPassword,
                            showPassword: $showPpix
                        )

                        // Senha 3 — Emergência
                        PasswordCard(
                            icon: "exclamationmark.triangle.fill",
                            color: Color(hex: "#FF3333"),
                            title: "Senha de Emergência",
                            subtitle: "Abre o banco + envia alerta silencioso",
                            password: $emergencyPassword,
                            showPassword: $showEmergency
                        )

                        // Mensagens
                        if !errorMessage.isEmpty {
                            ErrorBanner(message: errorMessage)
                        }
                        if !successMessage.isEmpty {
                            Text(successMessage)
                                .font(.footnote)
                                .foregroundColor(Color(hex: "#44FF88"))
                                .multilineTextAlignment(.center)
                        }

                        // Salvar senhas
                        PPPIXButton(title: "Salvar Senhas", isLoading: isSavingPasswords) {
                            Task { await savePasswords() }
                        }

                        Divider().overlay(Color(white: 0.15))

                        // Limite de tentativas
                        AttemptsCard(
                            maxAttempts: $maxAttempts,
                            isSaving: isSavingAttempts,
                            options: attemptOptions
                        ) {
                            Task { await saveAttempts() }
                        }
                    }

                    Spacer(minLength: 32)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Senhas")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadPasswords() }
    }

    // MARK: - Load

    private func loadPasswords() async {
        isLoadingPasswords = true
        defer { isLoadingPasswords = false }
        do {
            let list = try await APIClient.shared.getPasswords()
            if let settings = list.first {
                passwordSettingsId = settings.id
                bankPassword      = settings.bank_password_plain ?? ""
                ppixPassword      = settings.ppix_password_plain ?? ""
                emergencyPassword = settings.emergency_password_plain ?? ""
                maxAttempts       = settings.max_wrong_attempts ?? 3
            }
        } catch { /* silencioso — campos ficam vazios */ }
    }

    // MARK: - Save passwords

    private func savePasswords() async {
        errorMessage = ""
        successMessage = ""

        let bank = bankPassword.trimmingCharacters(in: .whitespaces)
        let ppix = ppixPassword.trimmingCharacters(in: .whitespaces)
        let emg  = emergencyPassword.trimmingCharacters(in: .whitespaces)

        if bank.isEmpty      { errorMessage = "Informe a senha do banco."; return }
        if bank.count < 4    { errorMessage = "Senha do banco: mínimo 4 caracteres."; return }
        if ppix.isEmpty      { errorMessage = "Informe a senha do PPPIX."; return }
        if ppix.count < 4    { errorMessage = "Senha do PPPIX: mínimo 4 caracteres."; return }
        if emg.isEmpty       { errorMessage = "Informe a senha de emergência."; return }
        if emg.count < 4     { errorMessage = "Senha emergência: mínimo 4 caracteres."; return }
        if bank == ppix      { errorMessage = "Senha do PPPIX deve ser diferente da do banco."; return }
        if bank == emg       { errorMessage = "Senha de emergência deve ser diferente da do banco."; return }
        if ppix == emg       { errorMessage = "Senha de emergência deve ser diferente da do PPPIX."; return }

        isSavingPasswords = true
        do {
            try await APIClient.shared.setPasswords(body: SetPasswordsRequest(
                bank_password: bank,
                ppix_password: ppix,
                emergency_password: emg
            ))
            SessionManager.shared.arePasswordsConfigured = true
            successMessage = "✓ Senhas salvas com sucesso!"
            // Recarrega ID
            await loadPasswords()
        } catch APIError.badRequest(let msg) {
            errorMessage = msg
        } catch {
            errorMessage = "Erro de conexão. Tente novamente."
        }
        isSavingPasswords = false
    }

    // MARK: - Save attempts

    private func saveAttempts() async {
        guard let id = passwordSettingsId else {
            // Tenta buscar ID
            await loadPasswords()
            guard let id2 = passwordSettingsId else {
                errorMessage = "Salve as senhas primeiro."
                return
            }
            await doSaveAttempts(id: id2)
            return
        }
        await doSaveAttempts(id: id)
    }

    private func doSaveAttempts(id: Int) async {
        isSavingAttempts = true
        do {
            try await APIClient.shared.updatePasswordSettings(id: id, body: PasswordAttemptsRequest(
                max_wrong_attempts: maxAttempts,
                reset_attempts_after_minutes: 60
            ))
            successMessage = "✓ Limite salvo: \(maxAttempts) tentativa\(maxAttempts > 1 ? "s" : "")"
        } catch {
            errorMessage = "Erro ao salvar limite."
        }
        isSavingAttempts = false
    }
}

// MARK: - PasswordCard

private struct PasswordCard: View {
    let icon: String
    let color: Color
    let title: String
    let subtitle: String
    @Binding var password: String
    @Binding var showPassword: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.system(size: 18))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(Color(white: 0.5))
                }
            }

            PPPIXSecureField(
                title: "",
                placeholder: "Mínimo 4 caracteres",
                text: $password,
                showPassword: $showPassword
            )
        }
        .padding(16)
        .background(Color(hex: "#141422"))
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(color.opacity(0.25), lineWidth: 1)
        )
    }
}

// MARK: - AttemptsCard

private struct AttemptsCard: View {
    @Binding var maxAttempts: Int
    let isSaving: Bool
    let options: [Int]
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.shield.fill")
                    .foregroundColor(Color(hex: "#FF6600"))
                    .font(.system(size: 18))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Limite de Tentativas Erradas")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                    Text("Alerta automático ao exceder o limite")
                        .font(.caption)
                        .foregroundColor(Color(white: 0.5))
                }
            }

            Picker("Tentativas", selection: $maxAttempts) {
                ForEach(options, id: \.self) { n in
                    Text("\(n) tentativa\(n > 1 ? "s" : "")").tag(n)
                }
            }
            .pickerStyle(.wheel)
            .frame(height: 100)
            .clipped()

            PPPIXButton(title: "Salvar Limite", isLoading: isSaving, style: .secondary, action: onSave)
        }
        .padding(16)
        .background(Color(hex: "#141422"))
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color(hex: "#FF6600").opacity(0.25), lineWidth: 1)
        )
    }
}

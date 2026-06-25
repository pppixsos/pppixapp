import SwiftUI

struct RegisterView: View {

    @Environment(\.dismiss) private var dismiss

    @State private var firstName = ""
    @State private var lastName = ""
    @State private var email = ""
    @State private var cpf = ""
    @State private var phone = ""
    @State private var birthDate = ""
    @State private var cep = ""
    @State private var password = ""
    @State private var passwordConfirm = ""
    @State private var showPassword = false
    @State private var showPasswordConfirm = false
    @State private var isLoading = false
    @State private var errorMessage = ""
    @State private var successMessage = ""

    var body: some View {
        ZStack {
            Color(hex: "#0A0A12").ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 8) {
                        Image(systemName: "person.badge.plus")
                            .font(.system(size: 48))
                            .foregroundColor(Color(hex: "#3366FF"))
                        Text("Criar Conta")
                            .font(.title2.bold())
                            .foregroundColor(.white)
                    }
                    .padding(.top, 20)

                    // Personal data
                    VStack(alignment: .leading, spacing: 16) {
                        SectionHeader(title: "Dados Pessoais")

                        HStack(spacing: 12) {
                            PPPIXTextField(title: "Nome", placeholder: "João", text: $firstName)
                            PPPIXTextField(title: "Sobrenome", placeholder: "Silva", text: $lastName)
                        }

                        PPPIXTextField(
                            title: "CPF",
                            placeholder: "000.000.000-00",
                            text: $cpf,
                            keyboardType: .numberPad,
                            onChange: { cpf = formatCPF($0) }
                        )

                        PPPIXTextField(
                            title: "Telefone",
                            placeholder: "(11) 99999-9999",
                            text: $phone,
                            keyboardType: .phonePad,
                            onChange: { phone = formatPhone($0) }
                        )

                        PPPIXTextField(
                            title: "Data de Nascimento",
                            placeholder: "DD/MM/AAAA",
                            text: $birthDate,
                            keyboardType: .numberPad,
                            onChange: { birthDate = formatDate($0) }
                        )

                        PPPIXTextField(
                            title: "CEP",
                            placeholder: "00000-000",
                            text: $cep,
                            keyboardType: .numberPad,
                            onChange: { cep = formatCEP($0) }
                        )
                    }

                    // Account data
                    VStack(alignment: .leading, spacing: 16) {
                        SectionHeader(title: "Dados de Acesso")

                        PPPIXTextField(
                            title: "Email",
                            placeholder: "seu@email.com",
                            text: $email,
                            keyboardType: .emailAddress,
                            autocapitalization: .never
                        )

                        PPPIXSecureField(
                            title: "Senha",
                            placeholder: "Mínimo 8 caracteres",
                            text: $password,
                            showPassword: $showPassword
                        )

                        PPPIXSecureField(
                            title: "Confirmar Senha",
                            placeholder: "Repita sua senha",
                            text: $passwordConfirm,
                            showPassword: $showPasswordConfirm
                        )
                    }

                    // Messages
                    if !errorMessage.isEmpty {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundColor(Color(hex: "#FF4444"))
                            .multilineTextAlignment(.center)
                    }

                    if !successMessage.isEmpty {
                        Text(successMessage)
                            .font(.footnote)
                            .foregroundColor(Color(hex: "#44FF88"))
                            .multilineTextAlignment(.center)
                    }

                    // Submit
                    PPPIXButton(title: "Criar Conta", isLoading: isLoading) {
                        Task { await register() }
                    }

                    Button("Já tenho conta") { dismiss() }
                        .font(.subheadline)
                        .foregroundColor(Color(hex: "#3366FF"))

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 24)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationBarBackButtonHidden(false)
        .navigationTitle("")
    }

    // MARK: - Register

    private func register() async {
        guard validateFields() else { return }

        isLoading = true
        errorMessage = ""

        let rawCPF   = cpf.filter(\.isNumber)
        let rawPhone  = phone.filter(\.isNumber)
        let rawBirth  = birthDate // ex: "23/05/1990" → converter para "1990-05-23"
        let rawCEP    = cep.filter(\.isNumber)

        let body = RegisterRequest(
            email: email.trimmingCharacters(in: .whitespaces).lowercased(),
            username: email.trimmingCharacters(in: .whitespaces).lowercased(),
            first_name: firstName.trimmingCharacters(in: .whitespaces),
            last_name: lastName.trimmingCharacters(in: .whitespaces),
            password: password,
            password_confirm: passwordConfirm,
            profile: ProfileData(
                cpf: rawCPF,
                phone: rawPhone,
                birth_date: convertDateToISO(rawBirth),
                cep: rawCEP
            )
        )

        do {
            try await APIClient.shared.register(body: body)
            successMessage = "Conta criada! Fazendo login..."

            // Auto login
            let loginResp = try await APIClient.shared.login(
                email: body.email, password: password
            )
            SessionManager.shared.saveTokens(access: loginResp.access, refresh: loginResp.refresh)
            let me = try await APIClient.shared.getMe()
            SessionManager.shared.saveUserInfo(id: me.id, email: me.email, name: me.fullName)

        } catch APIError.badRequest(let msg) {
            errorMessage = msg
        } catch {
            errorMessage = "Erro ao criar conta. Tente novamente."
        }

        isLoading = false
    }

    private func validateFields() -> Bool {
        if firstName.trimmingCharacters(in: .whitespaces).isEmpty {
            errorMessage = "Informe seu nome."; return false
        }
        if email.trimmingCharacters(in: .whitespaces).isEmpty || !email.contains("@") {
            errorMessage = "Email inválido."; return false
        }
        if cpf.filter(\.isNumber).count != 11 {
            errorMessage = "CPF deve ter 11 dígitos."; return false
        }
        if password.count < 8 {
            errorMessage = "Senha deve ter pelo menos 8 caracteres."; return false
        }
        if password != passwordConfirm {
            errorMessage = "As senhas não coincidem."; return false
        }
        return true
    }

    // MARK: - Masks

    private func formatCPF(_ raw: String) -> String {
        let digits = raw.filter(\.isNumber).prefix(11)
        var result = ""
        for (i, c) in digits.enumerated() {
            if i == 3 || i == 6 { result += "." }
            if i == 9 { result += "-" }
            result.append(c)
        }
        return result
    }

    private func formatPhone(_ raw: String) -> String {
        let digits = raw.filter(\.isNumber).prefix(11)
        var result = ""
        for (i, c) in digits.enumerated() {
            if i == 0 { result += "(" }
            if i == 2 { result += ") " }
            if digits.count == 11 && i == 7 { result += "-" }
            if digits.count < 11  && i == 6 { result += "-" }
            result.append(c)
        }
        return result
    }

    private func formatDate(_ raw: String) -> String {
        let digits = raw.filter(\.isNumber).prefix(8)
        var result = ""
        for (i, c) in digits.enumerated() {
            if i == 2 || i == 4 { result += "/" }
            result.append(c)
        }
        return result
    }

    private func formatCEP(_ raw: String) -> String {
        let digits = raw.filter(\.isNumber).prefix(8)
        var result = ""
        for (i, c) in digits.enumerated() {
            if i == 5 { result += "-" }
            result.append(c)
        }
        return result
    }

    private func convertDateToISO(_ ddMMyyyy: String) -> String {
        // "23/05/1990" → "1990-05-23"
        let parts = ddMMyyyy.split(separator: "/")
        guard parts.count == 3 else { return ddMMyyyy }
        return "\(parts[2])-\(parts[1])-\(parts[0])"
    }
}

private struct SectionHeader: View {
    let title: String
    var body: some View {
        Text(title)
            .font(.footnote.bold())
            .foregroundColor(Color(white: 0.5))
            .textCase(.uppercase)
    }
}

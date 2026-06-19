import SwiftUI

struct OnboardingContactsStep: View {
    let onBack: () -> Void
    let onNext: () -> Void

    @State private var contactsAdded: [String] = []
    @State private var method: ContactMethodChoice? = nil
    @State private var email = ""
    @State private var contactName = ""
    @State private var phone = ""
    @State private var isSaving = false
    @State private var errorMessage = ""

    enum ContactMethodChoice { case email, phone }

    var body: some View {
        OnboardingStepShell(
            icon: "person.2.fill",
            iconColor: Color(hex: "#44FF88"),
            title: "Contatos de emergência",
            subtitle: "Quem deve ser avisado se você precisar de ajuda? Adicione pelo menos 1 contato.",
            stepIndex: 10,
            totalSteps: 12,
            onBack: onBack
        ) {
            VStack(spacing: 18) {
                if !contactsAdded.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(contactsAdded, id: \.self) { name in
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(Color(hex: "#44FF88"))
                                Text(name).foregroundColor(.white).font(.subheadline)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(Color(hex: "#141422"))
                    .cornerRadius(12)
                }

                if method == nil {
                    VStack(spacing: 10) {
                        Button { method = .email } label: {
                            optionRow(icon: "envelope.badge.fill",
                                      title: "Tem o PPPIX instalado",
                                      subtitle: "Adicionar pelo email")
                        }
                        Button { method = .phone } label: {
                            optionRow(icon: "phone.badge.plus",
                                      title: "Não tem o app",
                                      subtitle: "Adicionar pelo nome e telefone (WhatsApp)")
                        }
                    }
                } else if method == .email {
                    VStack(spacing: 14) {
                        PPPIXTextField(title: "Email do contato", placeholder: "email@exemplo.com",
                                        text: $email, keyboardType: .emailAddress, autocapitalization: .never)
                        PPPIXButton(title: "Adicionar", isLoading: isSaving) {
                            Task { await addEmailContact() }
                        }
                        Button("Cancelar") { method = nil; errorMessage = "" }
                            .font(.subheadline).foregroundColor(Color(white: 0.5))
                    }
                } else {
                    VStack(spacing: 14) {
                        PPPIXTextField(title: "Nome do contato", placeholder: "Ex: Maria Silva",
                                        text: $contactName, autocapitalization: .words)
                        PPPIXTextField(title: "Telefone", placeholder: "+5527999998888",
                                        text: $phone, keyboardType: .phonePad)
                        PPPIXButton(title: "Adicionar", isLoading: isSaving) {
                            Task { await addPhoneContact() }
                        }
                        Button("Cancelar") { method = nil; errorMessage = "" }
                            .font(.subheadline).foregroundColor(Color(white: 0.5))
                    }
                }

                if !errorMessage.isEmpty { ErrorBanner(message: errorMessage) }

                if !contactsAdded.isEmpty {
                    PPPIXButton(title: "Continuar") { onNext() }
                        .padding(.top, 4)
                } else {
                    Button("Pular por agora") { onNext() }
                        .font(.subheadline)
                        .foregroundColor(Color(white: 0.5))
                        .padding(.top, 4)
                }
            }
        }
    }

    private func optionRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.system(size: 22))
                .foregroundColor(Color(hex: "#3366FF")).frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundColor(.white)
                Text(subtitle).font(.caption).foregroundColor(Color(white: 0.5))
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundColor(Color(white: 0.4))
        }
        .padding(14)
        .background(Color(hex: "#141422"))
        .cornerRadius(12)
    }

    private func addEmailContact() async {
        let trimmed = email.trimmingCharacters(in: .whitespaces).lowercased()
        if trimmed.isEmpty || !trimmed.contains("@") { errorMessage = "Email inválido."; return }

        isSaving = true; errorMessage = ""
        do {
            try await APIClient.shared.sendConnectionRequest(email: trimmed)
            contactsAdded.append(trimmed)
            email = ""
            method = nil
        } catch {
            errorMessage = "Erro ao enviar convite. Verifique o email."
        }
        isSaving = false
    }

    private func addPhoneContact() async {
        let trimmedName = contactName.trimmingCharacters(in: .whitespaces)
        var trimmedPhone = phone.trimmingCharacters(in: .whitespaces)
        trimmedPhone = trimmedPhone.filter { $0.isNumber || $0 == "+" }

        if trimmedName.isEmpty { errorMessage = "Digite o nome do contato."; return }
        if trimmedPhone.count < 8 { errorMessage = "Telefone inválido."; return }

        isSaving = true; errorMessage = ""
        do {
            try await APIClient.shared.addExternalContact(name: trimmedName, phone: trimmedPhone)
            contactsAdded.append(trimmedName)
            contactName = ""; phone = ""
            method = nil
        } catch {
            errorMessage = "Erro ao adicionar contato."
        }
        isSaving = false
    }
}

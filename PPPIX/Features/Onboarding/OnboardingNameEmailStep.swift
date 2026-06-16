import SwiftUI

struct OnboardingNameEmailStep: View {
    @ObservedObject var data: OnboardingData
    let onNext: () -> Void

    @State private var errorMessage = ""
    @FocusState private var focusedField: Field?
    enum Field { case first, last, email }

    var body: some View {
        OnboardingStepShell(
            icon: "person.text.rectangle.fill",
            iconColor: Color(hex: "#3366FF"),
            title: "Como você se chama?",
            subtitle: "Vamos te conhecer primeiro. Use seu nome completo, como no documento.",
            stepIndex: 0,
            totalSteps: 13
        ) {
            VStack(spacing: 14) {
                PPPIXTextField(title: "Nome", placeholder: "João", text: $data.firstName)
                    .focused($focusedField, equals: .first)
                PPPIXTextField(title: "Sobrenome", placeholder: "Silva", text: $data.lastName)
                    .focused($focusedField, equals: .last)
                PPPIXTextField(title: "Email", placeholder: "seu@email.com",
                                text: $data.email, keyboardType: .emailAddress,
                                autocapitalization: .never)
                    .focused($focusedField, equals: .email)

                if !errorMessage.isEmpty { ErrorBanner(message: errorMessage) }

                PPPIXButton(title: "Continuar") { validateAndNext() }
                    .padding(.top, 8)
            }
        }
        .onAppear { focusedField = .first }
    }

    private func validateAndNext() {
        let first = data.firstName.trimmingCharacters(in: .whitespaces)
        let last = data.lastName.trimmingCharacters(in: .whitespaces)
        let email = data.email.trimmingCharacters(in: .whitespaces)

        if first.isEmpty { errorMessage = "Informe seu nome."; return }
        if last.isEmpty { errorMessage = "Informe seu sobrenome."; return }
        if email.isEmpty || !email.contains("@") { errorMessage = "Informe um email válido."; return }

        errorMessage = ""
        onNext()
    }
}

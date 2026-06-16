import SwiftUI

struct OnboardingPhoneCpfBirthStep: View {
    @ObservedObject var data: OnboardingData
    let onBack: () -> Void
    let onNext: () -> Void

    @State private var errorMessage = ""

    var body: some View {
        OnboardingStepShell(
            icon: "phone.badge.checkmark",
            iconColor: Color(hex: "#0099FF"),
            title: "Seus dados de contato",
            subtitle: "Usamos isso para identificar você e, em caso de emergência, te localizar com precisão.",
            stepIndex: 1,
            totalSteps: 13,
            onBack: onBack
        ) {
            VStack(spacing: 14) {
                PPPIXTextField(
                    title: "Telefone (com DDD)",
                    placeholder: "(11) 99999-9999",
                    text: $data.phone,
                    keyboardType: .phonePad,
                    onChange: { data.phone = formatPhone($0) }
                )
                PPPIXTextField(
                    title: "CPF",
                    placeholder: "000.000.000-00",
                    text: $data.cpf,
                    keyboardType: .numberPad,
                    onChange: { data.cpf = formatCPF($0) }
                )
                PPPIXTextField(
                    title: "Data de Nascimento",
                    placeholder: "DD/MM/AAAA",
                    text: $data.birthDate,
                    keyboardType: .numberPad,
                    onChange: { data.birthDate = formatDate($0) }
                )

                if !errorMessage.isEmpty { ErrorBanner(message: errorMessage) }

                PPPIXButton(title: "Continuar") { validateAndNext() }
                    .padding(.top, 8)
            }
        }
    }

    private func validateAndNext() {
        if data.phone.filter(\.isNumber).count < 10 { errorMessage = "Telefone inválido."; return }
        if data.cpf.filter(\.isNumber).count != 11 { errorMessage = "CPF deve ter 11 dígitos."; return }
        if data.birthDate.filter(\.isNumber).count != 8 { errorMessage = "Informe a data completa."; return }

        errorMessage = ""
        onNext()
    }

    private func formatPhone(_ raw: String) -> String {
        let digits = raw.filter(\.isNumber).prefix(11)
        var result = ""
        for (i, c) in digits.enumerated() {
            if i == 0 { result += "(" }
            if i == 2 { result += ") " }
            if digits.count == 11 && i == 7 { result += "-" }
            if digits.count < 11 && i == 6 { result += "-" }
            result.append(c)
        }
        return result
    }

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

    private func formatDate(_ raw: String) -> String {
        let digits = raw.filter(\.isNumber).prefix(8)
        var result = ""
        for (i, c) in digits.enumerated() {
            if i == 2 || i == 4 { result += "/" }
            result.append(c)
        }
        return result
    }
}

import SwiftUI

struct OnboardingCepStep: View {
    @ObservedObject var data: OnboardingData
    let onBack: () -> Void
    let onNext: () -> Void

    @State private var errorMessage = ""

    var body: some View {
        OnboardingStepShell(
            icon: "map.fill",
            iconColor: Color(hex: "#00CC66"),
            title: "Onde você mora?",
            subtitle: "Seu CEP ajuda a calibrar o alerta de emergência para a sua região.",
            stepIndex: 2,
            totalSteps: 13,
            onBack: onBack
        ) {
            VStack(spacing: 14) {
                PPPIXTextField(
                    title: "CEP",
                    placeholder: "00000-000",
                    text: $data.cep,
                    keyboardType: .numberPad,
                    onChange: { data.cep = formatCEP($0) }
                )

                if !errorMessage.isEmpty { ErrorBanner(message: errorMessage) }

                PPPIXButton(title: "Continuar") { validateAndNext() }
                    .padding(.top, 8)
            }
        }
    }

    private func validateAndNext() {
        if data.cep.filter(\.isNumber).count != 8 { errorMessage = "CEP deve ter 8 dígitos."; return }
        errorMessage = ""
        onNext()
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
}

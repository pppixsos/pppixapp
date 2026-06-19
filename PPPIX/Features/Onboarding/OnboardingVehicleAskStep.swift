import SwiftUI

struct OnboardingVehicleAskStep: View {
    let onBack: () -> Void
    let onAnswer: (Bool) -> Void

    var body: some View {
        OnboardingStepShell(
            icon: "car.fill",
            iconColor: Color(hex: "#3366FF"),
            title: "Você tem um veículo?",
            subtitle: "Se você for acionar um alerta de emergência, os dados do seu veículo ajudam quem for te socorrer a te encontrar.",
            stepIndex: 9,
            totalSteps: 12,
            onBack: onBack
        ) {
            VStack(spacing: 12) {
                PPPIXButton(title: "Sim, quero adicionar") { onAnswer(true) }
                Button("Não, pular esta etapa") { onAnswer(false) }
                    .font(.subheadline)
                    .foregroundColor(Color(white: 0.5))
                    .padding(.top, 4)
            }
        }
    }
}

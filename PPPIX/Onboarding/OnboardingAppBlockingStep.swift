import SwiftUI

/// Última etapa do onboarding: reaproveita a tela AppListView já existente
/// no app (sem modificá-la) para selecionar quais apps serão protegidos,
/// com um botão "Concluir" sobreposto para finalizar o fluxo.
struct OnboardingAppBlockingStep: View {
    let onFinish: () -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            NavigationStack {
                AppListView()
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            // Sem botão de voltar aqui — esta é a última etapa
                            // antes da home; "Concluir" assume esse papel.
                            EmptyView()
                        }
                    }
            }

            VStack(spacing: 0) {
                LinearGradient(
                    colors: [Color(hex: "#0A0A12").opacity(0), Color(hex: "#0A0A12")],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: 40)

                PPPIXButton(title: "Concluir cadastro") { onFinish() }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                    .padding(.top, 4)
                    .background(Color(hex: "#0A0A12"))
            }
        }
    }
}

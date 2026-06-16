import SwiftUI

/// Primeira tela que o usuário vê ao abrir o app sem estar logado.
/// Decide entre o login normal (LoginView, inalterado) e o novo fluxo
/// de cadastro passo-a-passo (OnboardingFlowView).
struct WelcomeGateView: View {

    @State private var goToLogin = false
    @ObservedObject private var auth = PPPIXAuthState.instance

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "#0A0A12").ignoresSafeArea()

                VStack(spacing: 28) {
                    Spacer()

                    VStack(spacing: 12) {
                        Image(systemName: "shield.fill")
                            .font(.system(size: 64))
                            .foregroundStyle(LinearGradient(
                                colors: [Color(hex: "#3366FF"), Color(hex: "#6633FF")],
                                startPoint: .topLeading, endPoint: .bottomTrailing))
                        Text("PPPIX")
                            .font(.system(size: 32, weight: .bold))
                            .foregroundColor(.white)
                        Text("Sua segurança pessoal e financeira")
                            .font(.subheadline)
                            .foregroundColor(Color(white: 0.6))
                            .multilineTextAlignment(.center)
                    }

                    Spacer()

                    VStack(spacing: 12) {
                        PPPIXButton(title: "Criar minha conta") {
                            auth.isOnboarding = true
                        }

                        Button {
                            goToLogin = true
                        } label: {
                            HStack(spacing: 4) {
                                Text("Já tenho conta").foregroundColor(Color(white: 0.6))
                                Text("Entrar").foregroundColor(Color(hex: "#3366FF")).fontWeight(.semibold)
                            }.font(.subheadline)
                        }
                    }
                    .padding(.bottom, 40)
                }
                .padding(.horizontal, 24)
            }
            .navigationDestination(isPresented: $goToLogin) { LoginView() }
        }
    }
}

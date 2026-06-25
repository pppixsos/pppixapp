import SwiftUI

/// Container visual padrão para cada etapa do onboarding: ícone, título,
/// subtítulo explicativo, botão de voltar opcional e barra de progresso.
struct OnboardingStepShell<Content: View>: View {

    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    var stepIndex: Int? = nil
    var totalSteps: Int? = nil
    var onBack: (() -> Void)? = nil
    @ViewBuilder var content: () -> Content

    // Largura máxima do conteúdo — limita em iPad para não ficar esticado
    private let maxContentWidth: CGFloat = 560

    var body: some View {
        VStack(spacing: 0) {
            // Barra superior: voltar + progresso
            HStack {
                if let onBack {
                    Button(action: onBack) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 36, height: 36)
                            .background(Color(white: 0.12))
                            .clipShape(Circle())
                    }
                } else {
                    Spacer().frame(width: 36, height: 36)
                }

                Spacer()

                if let stepIndex, let totalSteps {
                    HStack(spacing: 5) {
                        ForEach(0..<totalSteps, id: \.self) { i in
                            Capsule()
                                .fill(i <= stepIndex ? Color(hex: "#3366FF") : Color(white: 0.15))
                                .frame(width: i == stepIndex ? 18 : 8, height: 6)
                        }
                    }
                }

                Spacer()
                Spacer().frame(width: 36, height: 36)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)

            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 10) {
                        Image(systemName: icon)
                            .font(.system(size: 46))
                            .foregroundColor(iconColor)
                        Text(title)
                            .font(.title2.bold())
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundColor(Color(white: 0.55))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 12)
                    }
                    .padding(.top, 24)

                    content()

                    Spacer(minLength: 24)
                }
                .padding(.horizontal, 24)
                .frame(maxWidth: maxContentWidth)
                .frame(maxWidth: .infinity) // centraliza no iPad
            }
        }
    }
}

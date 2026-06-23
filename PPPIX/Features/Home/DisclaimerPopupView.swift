import SwiftUI

/// Aviso de responsabilidade exibido uma única vez na Home logo após
/// a configuração inicial. Controlado por UserDefaults.
enum DisclaimerPopup {
    private static let key = "pppix_has_seen_responsibility_disclaimer"
    static var shouldShow: Bool { !UserDefaults.standard.bool(forKey: key) }
    static func markAsSeen() { UserDefaults.standard.set(true, forKey: key) }
}

struct DisclaimerPopupView: View {
    let onAccept: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.72).ignoresSafeArea()

            VStack(spacing: 0) {
                VStack(spacing: 14) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 38))
                        .foregroundColor(Color(hex: "#FFAA00"))
                        .padding(.top, 28)

                    Text("Aviso Importante")
                        .font(.title3.bold())
                        .foregroundColor(.white)

                    VStack(alignment: .leading, spacing: 12) {
                        DisclaimerLine(
                            text: "O PPPIX garante o funcionamento técnico do app — que ele opere sem falhas quando configurado corretamente."
                        )
                        DisclaimerLine(
                            text: "O PPPIX não se responsabiliza pela sua segurança pessoal, nem pelo resultado de situações de emergência."
                        )
                        DisclaimerLine(
                            text: "Falhas por configuração incorreta — permissões não concedidas, senhas mal configuradas, contatos desatualizados — são responsabilidade do usuário."
                        )
                        DisclaimerLine(
                            text: "Mantenha o app configurado e testado. Siga o Tutorial de Instalação disponível na tela inicial."
                        )
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
                }
                .padding(.bottom, 22)

                Divider().overlay(Color(white: 0.1))

                Button {
                    DisclaimerPopup.markAsSeen()
                    onAccept()
                } label: {
                    Text("Li e estou ciente")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(
                            LinearGradient(
                                colors: [Color(hex: "#3366FF"), Color(hex: "#6633FF")],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                }
                .padding(16)
            }
            .background(Color(hex: "#141422"))
            .cornerRadius(20)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color(hex: "#FFAA00").opacity(0.3), lineWidth: 1.5)
            )
            .padding(.horizontal, 24)
        }
    }
}

private struct DisclaimerLine: View {
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(Color(hex: "#FFAA00"))
                .frame(width: 5, height: 5)
                .padding(.top, 7)
            Text(text)
                .font(.footnote)
                .foregroundColor(Color(white: 0.72))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

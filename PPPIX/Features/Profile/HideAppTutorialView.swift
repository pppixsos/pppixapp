import SwiftUI

/// Tutorial didático, passo a passo, ensinando o usuário a usar o app
/// Atalhos (Shortcuts) da Apple para criar um ícone com nome customizado
/// que abre o PPPIX, e depois remover o ícone original da Tela de Início.
/// Isso não é feito por código — é o usuário seguindo os passos no
/// próprio iPhone, já que o iOS não permite que um app se oculte ou se
/// renomeie via programação.
struct HideAppTutorialView: View {

    private let shortcutsURL = URL(string: "shortcuts://create-shortcut")
    private let shortcutsAppURL = URL(string: "shortcuts://")

    var body: some View {
        ZStack {
            Color(hex: "#0A0A12").ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 8) {
                        Image(systemName: "eye.slash.fill")
                            .font(.system(size: 44))
                            .foregroundColor(Color(hex: "#666688"))
                        Text("Ocultar o PPPIX")
                            .font(.title2.bold())
                            .foregroundColor(.white)
                        Text("O iOS não permite que nenhum app se esconda ou se renomeie por conta própria. Mas você mesmo pode fazer isso em poucos passos, usando o app Atalhos da Apple.")
                            .font(.subheadline)
                            .foregroundColor(Color(white: 0.55))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 12)
                    }
                    .padding(.top, 16)

                    VStack(spacing: 14) {
                        TutorialStep(
                            number: 1,
                            title: "Abra o app Atalhos",
                            description: "É um app da Apple, já vem instalado no seu iPhone (ícone colorido com quadrados).",
                            actionLabel: "Abrir Atalhos",
                            systemImage: "square.stack.3d.up.fill"
                        ) {
                            openURL(shortcutsAppURL)
                        }

                        TutorialStep(
                            number: 2,
                            title: "Crie um novo atalho",
                            description: "Toque no botão \"+\" no canto superior direito da tela do Atalhos.",
                            actionLabel: nil,
                            systemImage: "plus.circle.fill",
                            action: nil
                        )

                        TutorialStep(
                            number: 3,
                            title: "Adicione a ação \"Abrir App\"",
                            description: "Toque em \"Adicionar Ação\", busque por \"Abrir App\" (ou \"Open App\") e selecione essa ação.",
                            actionLabel: nil,
                            systemImage: "magnifyingglass",
                            action: nil
                        )

                        TutorialStep(
                            number: 4,
                            title: "Escolha o PPPIX",
                            description: "Na ação que você adicionou, toque em \"Escolha\" e selecione o app PPPIX na lista.",
                            actionLabel: nil,
                            systemImage: "shield.fill",
                            action: nil
                        )

                        TutorialStep(
                            number: 5,
                            title: "Adicione à Tela de Início",
                            description: "Toque nos \"•••\" no canto superior direito, depois em \"Adicionar à Tela de Início\".",
                            actionLabel: nil,
                            systemImage: "ellipsis.circle.fill",
                            action: nil
                        )

                        TutorialStep(
                            number: 6,
                            title: "Escolha nome e ícone",
                            description: "Apague o nome \"Abrir PPPIX\" e digite o nome que quiser (ex: \"Notas Rápidas\"). Toque no ícone para trocar a imagem por algo neutro.",
                            actionLabel: nil,
                            systemImage: "textformat",
                            action: nil
                        )

                        TutorialStep(
                            number: 7,
                            title: "Toque em \"Adicionar\"",
                            description: "Esse novo ícone aparece na sua Tela de Início, com o nome e imagem que você escolheu. Ele abre o PPPIX normalmente.",
                            actionLabel: nil,
                            systemImage: "checkmark.circle.fill",
                            action: nil
                        )

                        TutorialStep(
                            number: 8,
                            title: "Remova o ícone original do PPPIX",
                            description: "Pressione e mantenha o ícone original do PPPIX na Tela de Início até ele tremer, toque em \"Remover App\" e escolha \"Remover da Tela de Início\" (nunca \"Apagar App\").",
                            actionLabel: nil,
                            systemImage: "trash.fill",
                            action: nil,
                            isWarning: true
                        )
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "info.circle.fill")
                                .foregroundColor(Color(hex: "#0099FF"))
                            Text("Importante")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.white)
                        }
                        Text("O PPPIX continua instalado e funcionando normalmente — só o ícone na Tela de Início muda de lugar e aparência. Notificações e alertas continuam chegando sem nenhuma alteração.")
                            .font(.caption)
                            .foregroundColor(Color(white: 0.6))
                    }
                    .padding(14)
                    .background(Color(hex: "#141422"))
                    .cornerRadius(12)

                    Spacer(minLength: 24)
                }
                .padding(.horizontal, 20)
            }
        }
        .navigationTitle("Ocultar o App")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func openURL(_ url: URL?) {
        guard let url else { return }
        UIApplication.shared.open(url)
    }
}

private struct TutorialStep: View {
    let number: Int
    let title: String
    let description: String
    let actionLabel: String?
    let systemImage: String
    var action: (() -> Void)? = nil
    var isWarning: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(isWarning ? Color(hex: "#FF6600").opacity(0.15) : Color(hex: "#3366FF").opacity(0.15))
                    .frame(width: 36, height: 36)
                Text("\(number)")
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(isWarning ? Color(hex: "#FF9933") : Color(hex: "#6699FF"))
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: systemImage)
                        .font(.caption)
                        .foregroundColor(Color(white: 0.5))
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                }
                Text(description)
                    .font(.caption)
                    .foregroundColor(Color(white: 0.55))
                    .fixedSize(horizontal: false, vertical: true)

                if let actionLabel, let action {
                    Button(action: action) {
                        Text(actionLabel)
                            .font(.caption.weight(.semibold))
                            .foregroundColor(Color(hex: "#3366FF"))
                            .padding(.vertical, 8)
                            .padding(.horizontal, 14)
                            .background(Color(hex: "#3366FF").opacity(0.12))
                            .cornerRadius(8)
                    }
                    .padding(.top, 2)
                }
            }

            Spacer()
        }
        .padding(14)
        .background(Color(hex: "#141422"))
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(isWarning ? Color(hex: "#FF6600").opacity(0.3) : Color.clear, lineWidth: 1)
        )
    }
}

import SwiftUI

/// Tela onde o usuário escolhe disfarçar o PPPIX como outro app (ícone +
/// nome de exibição mudam juntos na Tela de Início) ou reverter ao
/// ícone original.
struct AppDisguiseView: View {
    @StateObject private var manager = AppDisguiseManager.shared
    @State private var isApplying = false
    @State private var errorMessage = ""
    @State private var showSuccessFor: String?

    var body: some View {
        ZStack {
            Color(hex: "#0A0A12").ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    VStack(spacing: 8) {
                        Image(systemName: "theatermasks.fill")
                            .font(.system(size: 44))
                            .foregroundColor(Color(hex: "#3366FF"))
                        Text("Disfarçar o App")
                            .font(.title2.bold())
                            .foregroundColor(.white)
                        Text("Troque apenas o ícone do PPPIX na Tela de Início por outro app comum. O nome continua aparecendo como \"PPPIX\" embaixo do ícone — essa é uma limitação do próprio iOS, sem solução possível. Você pode voltar ao ícone original quando quiser.")
                            .font(.subheadline)
                            .foregroundColor(Color(white: 0.55))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 12)
                    }
                    .padding(.top, 16)

                    // Opção: ícone original
                    DisguiseOptionRow(
                        title: "PPPIX (Original)",
                        subtitle: "Ícone e nome padrão do app",
                        symbol: "shield.fill",
                        symbolColor: Color(hex: "#3366FF"),
                        isSelected: manager.currentDisguise == nil,
                        isLoading: isApplying && showSuccessFor == "original"
                    ) {
                        apply(nil, key: "original")
                    }

                    Divider().overlay(Color(white: 0.1)).padding(.vertical, 4)

                    ForEach(AppDisguise.allCases) { disguise in
                        DisguiseOptionRow(
                            title: disguise.displayName,
                            subtitle: "O app aparecerá como \"\(disguise.displayName)\" na Tela de Início",
                            symbol: disguise.sfSymbol,
                            symbolColor: Color(hex: "#44CC88"),
                            isSelected: manager.currentDisguise == disguise,
                            isLoading: isApplying && showSuccessFor == disguise.rawValue
                        ) {
                            apply(disguise, key: disguise.rawValue)
                        }
                    }

                    if !errorMessage.isEmpty {
                        ErrorBanner(message: errorMessage)
                            .padding(.top, 8)
                    }

                    Text("O iOS mostra um aviso ao trocar o ícone — isso é um comportamento padrão do sistema e não pode ser desativado.")
                        .font(.caption)
                        .foregroundColor(Color(white: 0.4))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .padding(.top, 8)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
        }
        .navigationTitle("Disfarce do App")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func apply(_ disguise: AppDisguise?, key: String) {
        guard !isApplying else { return }
        isApplying = true
        showSuccessFor = key
        errorMessage = ""

        manager.apply(disguise) { success in
            isApplying = false
            showSuccessFor = nil
            if !success {
                errorMessage = "Não foi possível alterar o ícone agora. Tente novamente."
            }
        }
    }
}

private struct DisguiseOptionRow: View {
    let title: String
    let subtitle: String
    let symbol: String
    let symbolColor: Color
    let isSelected: Bool
    let isLoading: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(white: 0.1))
                        .frame(width: 48, height: 48)
                    Image(systemName: symbol)
                        .font(.system(size: 22))
                        .foregroundColor(symbolColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(Color(white: 0.5))
                        .multilineTextAlignment(.leading)
                }

                Spacer()

                if isLoading {
                    ProgressView().tint(.white)
                } else if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(Color(hex: "#44CC88"))
                        .font(.system(size: 20))
                }
            }
            .padding(14)
            .background(Color(hex: "#141422"))
            .cornerRadius(14)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isSelected ? Color(hex: "#44CC88").opacity(0.4) : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }
}

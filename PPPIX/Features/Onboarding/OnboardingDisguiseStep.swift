import SwiftUI

/// Última etapa do tutorial (cadastro ou novo dispositivo): o usuário
/// escolhe se quer disfarçar o ícone/nome do PPPIX na Tela de Início,
/// ou manter o original. Pode ser alterado depois em Perfil > Disfarçar o App.
struct OnboardingDisguiseStep: View {
    let onFinish: () -> Void

    @StateObject private var manager = AppDisguiseManager.shared
    @State private var isApplying = false
    @State private var applyingKey: String?
    @State private var errorMessage = ""

    var body: some View {
        OnboardingStepShell(
            icon: "theatermasks.fill",
            iconColor: Color(hex: "#3366FF"),
            title: "Quer disfarçar o app?",
            subtitle: "Você pode trocar o ícone e o nome do PPPIX na Tela de Início por outro app comum, para mais discrição. Pode mudar isso quando quiser no seu Perfil.",
            stepIndex: 12,
            totalSteps: 13
        ) {
            VStack(spacing: 12) {
                DisguiseQuickOption(
                    title: "Manter PPPIX (Original)",
                    symbol: "shield.fill",
                    isSelected: manager.currentDisguise == nil,
                    isLoading: isApplying && applyingKey == "original"
                ) {
                    apply(nil, key: "original")
                }

                ForEach(AppDisguise.allCases) { disguise in
                    DisguiseQuickOption(
                        title: disguise.displayName,
                        symbol: disguise.sfSymbol,
                        isSelected: manager.currentDisguise == disguise,
                        isLoading: isApplying && applyingKey == disguise.rawValue
                    ) {
                        apply(disguise, key: disguise.rawValue)
                    }
                }

                if !errorMessage.isEmpty { ErrorBanner(message: errorMessage) }

                PPPIXButton(title: "Concluir") { onFinish() }
                    .padding(.top, 8)
            }
        }
    }

    private func apply(_ disguise: AppDisguise?, key: String) {
        guard !isApplying else { return }
        isApplying = true
        applyingKey = key
        errorMessage = ""

        manager.apply(disguise) { success in
            isApplying = false
            applyingKey = nil
            if !success {
                errorMessage = "Não foi possível alterar o ícone agora. Você pode tentar novamente depois, em Perfil."
            }
        }
    }
}

private struct DisguiseQuickOption: View {
    let title: String
    let symbol: String
    let isSelected: Bool
    let isLoading: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 18))
                    .foregroundColor(Color(hex: "#44CC88"))
                    .frame(width: 28)
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.white)
                Spacer()
                if isLoading {
                    ProgressView().tint(.white)
                } else if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(Color(hex: "#44CC88"))
                }
            }
            .padding(14)
            .background(Color(hex: "#141422"))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color(hex: "#44CC88").opacity(0.4) : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }
}

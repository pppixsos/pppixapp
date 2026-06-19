import SwiftUI

enum OnboardingPasswordKind {
    case bank, ppix, emergency

    var icon: String {
        switch self {
        case .bank: return "building.columns.fill"
        case .ppix: return "shield.fill"
        case .emergency: return "exclamationmark.triangle.fill"
        }
    }

    var color: Color {
        switch self {
        case .bank: return Color(hex: "#0099FF")
        case .ppix: return Color(hex: "#3366FF")
        case .emergency: return Color(hex: "#FF3333")
        }
    }

    var title: String {
        switch self {
        case .bank: return "Senha do Banco"
        case .ppix: return "Senha do PPPIX"
        case .emergency: return "Senha de Emergência"
        }
    }

    var explanation: String {
        switch self {
        case .bank:
            return "Use essa senha para abrir normalmente os apps que você bloquear (banco, redes sociais, etc). É a sua senha do dia a dia."
        case .ppix:
            return "Use essa senha para abrir as configurações do PPPIX quando o app estiver bloqueado por Screen Time."
        case .emergency:
            return "Em uma situação de perigo, digite essa senha em vez da senha normal. O app abre normalmente, mas dispara um alerta silencioso para seus contatos de emergência — sem que ninguém perceba."
        }
    }
}

struct OnboardingSinglePasswordStep: View {
    @ObservedObject var data: OnboardingData
    let kind: OnboardingPasswordKind
    let onBack: () -> Void
    let onNext: () -> Void

    @State private var showPassword = false
    @State private var errorMessage = ""

    private var stepIndex: Int {
        switch kind {
        case .bank: return 5
        case .ppix: return 6
        case .emergency: return 7
        }
    }

    private var binding: Binding<String> {
        switch kind {
        case .bank: return $data.bankPassword
        case .ppix: return $data.ppixPassword
        case .emergency: return $data.emergencyPassword
        }
    }

    var body: some View {
        OnboardingStepShell(
            icon: kind.icon,
            iconColor: kind.color,
            title: kind.title,
            subtitle: kind.explanation,
            stepIndex: stepIndex,
            totalSteps: 12,
            onBack: onBack
        ) {
            VStack(spacing: 14) {
                PPPIXSecureField(
                    title: "",
                    placeholder: "Mínimo 4 caracteres",
                    text: binding,
                    showPassword: $showPassword
                )

                if !errorMessage.isEmpty { ErrorBanner(message: errorMessage) }

                PPPIXButton(title: "Continuar") { validateAndNext() }
                    .padding(.top, 8)
            }
        }
    }

    private func validateAndNext() {
        let value = binding.wrappedValue.trimmingCharacters(in: .whitespaces)
        if value.isEmpty { errorMessage = "Digite a senha."; return }
        if value.count < 4 { errorMessage = "Mínimo 4 caracteres."; return }

        switch kind {
        case .ppix:
            if value == data.bankPassword {
                errorMessage = "Deve ser diferente da senha do banco."; return
            }
        case .emergency:
            if value == data.bankPassword {
                errorMessage = "Deve ser diferente da senha do banco."; return
            }
            if value == data.ppixPassword {
                errorMessage = "Deve ser diferente da senha do PPPIX."; return
            }
        case .bank:
            break
        }

        errorMessage = ""
        onNext()
    }
}

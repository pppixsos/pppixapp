import SwiftUI

/// Disparado após um LOGIN (não cadastro) quando detectamos que este é
/// um dispositivo novo que ainda não passou pelo fluxo de configuração
/// local (permissões do iOS, que são sempre por-aparelho). Se a conta já
/// tiver as 3 senhas configuradas no servidor, pulamos essa etapa —
/// só pedimos o que realmente falta neste dispositivo.
struct DeviceSetupFlowView: View {
    let onFinished: () -> Void

    private enum Step {
        case checking
        case permissions
        case bankPassword
        case ppixPassword
        case emergencyPassword
        case attemptsLimit
        case appBlocking
        case done
    }

    @State private var step: Step = .checking
    @StateObject private var data = OnboardingData()
    @State private var passwordsAlreadyExist = false

    var body: some View {
        ZStack {
            Color(hex: "#0A0A12").ignoresSafeArea()

            switch step {
            case .checking:
                ProgressView().tint(.white)
                    .onAppear { Task { await checkExistingPasswords() } }

            case .permissions:
                OnboardingPermissionsStep(onNext: {
                    step = passwordsAlreadyExist ? .appBlocking : .bankPassword
                })

            case .bankPassword:
                OnboardingSinglePasswordStep(
                    data: data, kind: .bank,
                    onBack: { step = .permissions },
                    onNext: { step = .ppixPassword }
                )

            case .ppixPassword:
                OnboardingSinglePasswordStep(
                    data: data, kind: .ppix,
                    onBack: { step = .bankPassword },
                    onNext: { step = .emergencyPassword }
                )

            case .emergencyPassword:
                OnboardingSinglePasswordStep(
                    data: data, kind: .emergency,
                    onBack: { step = .ppixPassword },
                    onNext: { step = .attemptsLimit }
                )

            case .attemptsLimit:
                OnboardingAttemptsLimitStep(
                    data: data,
                    onBack: { step = .emergencyPassword },
                    onNext: { step = .appBlocking }
                )

            case .appBlocking:
                OnboardingAppBlockingStep(onFinish: { step = .done })

            case .done:
                Color.clear.onAppear {
                    onFinished()
                }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: step)
    }

    private func checkExistingPasswords() async {
        if let list = try? await APIClient.shared.getPasswords(), !list.isEmpty {
            passwordsAlreadyExist = true
        }
        step = .permissions
    }
}

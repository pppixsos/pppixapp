import SwiftUI

/// Disparado após um LOGIN (não cadastro) quando detectamos que este é
/// um dispositivo novo que ainda não passou pelo fluxo de configuração
/// local. Pede tudo que é configurado por-aparelho — permissões, as 3
/// senhas, veículo, e seleção de apps protegidos — exatamente como no
/// cadastro, mas SEM pedir novamente os dados pessoais (nome, email,
/// telefone, CPF, CEP), que já existem na conta.
struct DeviceSetupFlowView: View {
    let onFinished: () -> Void

    private enum Step {
        case permissions
        case bankPassword
        case ppixPassword
        case emergencyPassword
        case attemptsLimit
        case vehicleAsk
        case vehicleDetails
        case appBlocking
        case done
    }

    @State private var step: Step = .permissions
    @StateObject private var data = OnboardingData()

    var body: some View {
        ZStack {
            Color(hex: "#0A0A12").ignoresSafeArea()

            switch step {
            case .permissions:
                OnboardingPermissionsStep(onNext: { step = .bankPassword })

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
                    onNext: { step = .vehicleAsk }
                )

            case .vehicleAsk:
                OnboardingVehicleAskStep(
                    onBack: { step = .attemptsLimit },
                    onAnswer: { hasVehicle in
                        data.wantsVehicle = hasVehicle
                        step = hasVehicle ? .vehicleDetails : .appBlocking
                    }
                )

            case .vehicleDetails:
                OnboardingVehicleDetailsStep(
                    data: data,
                    onBack: { step = .vehicleAsk },
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
}

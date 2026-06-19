import SwiftUI

/// Dados coletados ao longo de todo o fluxo de cadastro passo-a-passo.
/// Compartilhado entre todas as telas do onboarding via @StateObject único.
@MainActor
final class OnboardingData: ObservableObject {
    // Dados pessoais — etapa 1
    @Published var firstName = ""
    @Published var lastName = ""
    @Published var email = ""

    // Dados pessoais — etapa 2
    @Published var phone = ""
    @Published var cpf = ""
    @Published var birthDate = ""

    // Endereço — etapa 3
    @Published var cep = ""

    // Senha de acesso — etapa 4
    @Published var password = ""
    @Published var passwordConfirm = ""

    // Senhas de proteção (banco / ppix / emergência)
    @Published var bankPassword = ""
    @Published var ppixPassword = ""
    @Published var emergencyPassword = ""

    // Veículo (opcional)
    @Published var wantsVehicle: Bool? = nil
    @Published var vehicleModel = ""
    @Published var vehiclePlate = ""
    @Published var vehicleColor = ""
    @Published var vehicleYear = ""
}

/// Etapas do fluxo, em ordem. Permite navegação sequencial com "voltar".
enum OnboardingStep: Int, CaseIterable {
    case nameEmail
    case phoneCpfBirth
    case cep
    case createPassword
    case permissions
    case bankPassword
    case ppixPassword
    case emergencyPassword
    case attemptsLimit
    case vehicleAsk
    case vehicleDetails
    case contacts
    case appBlocking
    case done
}

/// Orquestra todo o fluxo de cadastro passo-a-passo: dados pessoais →
/// criação de conta → login automático → permissões → 3 senhas →
/// veículo (opcional) → contatos de emergência → bloqueio de apps → home.
struct OnboardingFlowView: View {

    let onFinished: () -> Void

    @StateObject private var data = OnboardingData()
    @State private var step: OnboardingStep = .nameEmail
    @State private var accountCreated = false

    var body: some View {
        ZStack {
            Color(hex: "#0A0A12").ignoresSafeArea()

            Group {
                switch step {
                case .nameEmail:
                    OnboardingNameEmailStep(data: data, onNext: { advance(to: .phoneCpfBirth) })

                case .phoneCpfBirth:
                    OnboardingPhoneCpfBirthStep(
                        data: data,
                        onBack: { back(to: .nameEmail) },
                        onNext: { advance(to: .cep) }
                    )

                case .cep:
                    OnboardingCepStep(
                        data: data,
                        onBack: { back(to: .phoneCpfBirth) },
                        onNext: { advance(to: .createPassword) }
                    )

                case .createPassword:
                    OnboardingCreatePasswordStep(
                        data: data,
                        onBack: { back(to: .cep) },
                        onAccountCreated: {
                            accountCreated = true
                            advance(to: .permissions)
                        }
                    )

                case .permissions:
                    OnboardingPermissionsStep(onNext: { advance(to: .bankPassword) })

                case .bankPassword:
                    OnboardingSinglePasswordStep(
                        data: data,
                        kind: .bank,
                        onBack: { back(to: .permissions) },
                        onNext: { advance(to: .ppixPassword) }
                    )

                case .ppixPassword:
                    OnboardingSinglePasswordStep(
                        data: data,
                        kind: .ppix,
                        onBack: { back(to: .bankPassword) },
                        onNext: { advance(to: .emergencyPassword) }
                    )

                case .emergencyPassword:
                    OnboardingSinglePasswordStep(
                        data: data,
                        kind: .emergency,
                        onBack: { back(to: .ppixPassword) },
                        onNext: { advance(to: .attemptsLimit) }
                    )

                case .attemptsLimit:
                    OnboardingAttemptsLimitStep(
                        data: data,
                        onBack: { back(to: .emergencyPassword) },
                        onNext: { advance(to: .vehicleAsk) }
                    )

                case .vehicleAsk:
                    OnboardingVehicleAskStep(
                        onBack: { back(to: .attemptsLimit) },
                        onAnswer: { hasVehicle in
                            data.wantsVehicle = hasVehicle
                            advance(to: hasVehicle ? .vehicleDetails : .contacts)
                        }
                    )

                case .vehicleDetails:
                    OnboardingVehicleDetailsStep(
                        data: data,
                        onBack: { back(to: .vehicleAsk) },
                        onNext: { advance(to: .contacts) }
                    )

                case .contacts:
                    OnboardingContactsStep(
                        onBack: {
                            back(to: data.wantsVehicle == true ? .vehicleDetails : .vehicleAsk)
                        },
                        onNext: { advance(to: .appBlocking) }
                    )

                case .appBlocking:
                    OnboardingAppBlockingStep(onFinish: { advance(to: .done) })

                case .done:
                    Color.clear.onAppear { finishOnboarding() }
                }
            }
            .transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            ))
        }
        .animation(.easeInOut(duration: 0.25), value: step)
    }

    private func advance(to next: OnboardingStep) {
        withAnimation { step = next }
    }

    private func back(to previous: OnboardingStep) {
        withAnimation { step = previous }
    }

    private func finishOnboarding() {
        // Login já foi finalizado em OnboardingCreatePasswordStep, e o
        // cadastro já passou por permissões/senhas/etc — portanto este
        // dispositivo já está com a configuração local completa.
        PPPIXAuthState.instance.hasCompletedDeviceSetupThisSession = true
        onFinished()
    }
}

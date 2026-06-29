import SwiftUI

/// Disparado após um LOGIN quando este aparelho ainda não passou pelo
/// setup local (primeiro login, ou após logout).
///
/// Busca os dados já existentes na conta (senhas, veículo, limite de
/// tentativas) e pré-preenche o OnboardingData — o usuário só confirma
/// e avança, em vez de redigitar tudo do zero.
struct DeviceSetupFlowView: View {
    let onFinished: () -> Void

    private enum Step {
        case loading
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

    @State private var step: Step = .loading
    @StateObject private var data = OnboardingData()

    @State private var existingPasswordId: Int? = nil
    @State private var existingVehicle: Vehicle? = nil
    @State private var existingMaxAttempts: Int = 3

    var body: some View {
        ZStack {
            Color(hex: "#0A0A12").ignoresSafeArea()

            switch step {
            case .loading:
                loadingView

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
                    preloadedMaxAttempts: existingMaxAttempts,
                    existingPasswordId: existingPasswordId,
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
                    existingVehicle: existingVehicle,
                    onBack: { step = .vehicleAsk },
                    onNext: { step = .appBlocking }
                )

            case .appBlocking:
                OnboardingAppBlockingStep(onFinish: { step = .done })

            case .done:
                Color.clear.onAppear { onFinished() }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: step)
        .task { await loadExistingData() }
    }

    // MARK: - Loading view (nunca mostra erro — sempre avança)

    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                .scaleEffect(1.4)
            Text("Carregando...")
                .font(.subheadline)
                .foregroundColor(Color(white: 0.5))
        }
    }

    // MARK: - Carrega dados existentes da conta

    private func loadExistingData() async {
        // Timeout de 8 segundos — se a API não responder, avança sem dados.
        // NUNCA mostrar erro de rede para o usuário nesta tela.
        await withTimeout(seconds: 8) {
            do {
                let passwords = try await APIClient.shared.getPasswords()
                let vehicles  = try await APIClient.shared.getVehicles()

                if let pw = passwords.first {
                    existingPasswordId     = pw.id
                    data.bankPassword      = pw.bank_password_plain      ?? ""
                    data.ppixPassword      = pw.ppix_password_plain      ?? ""
                    data.emergencyPassword = pw.emergency_password_plain ?? ""
                    existingMaxAttempts    = pw.max_wrong_attempts        ?? 3
                }

                if let active = vehicles.first(where: { $0.is_active }) ?? vehicles.first {
                    existingVehicle     = active
                    data.vehicleModel   = active.model
                    data.vehiclePlate   = active.license_plate
                    data.vehicleColor   = active.color
                    data.vehicleYear    = String(active.year)
                    data.wantsVehicle   = true
                }
            } catch {
                // Erro de rede — ignora e continua sem dados pré-carregados
                print("[DeviceSetup] API indisponível, continuando sem dados: \(error)")
            }
        }
        // Garante que sempre avança, independente do resultado
        step = .permissions
    }

    /// Executa uma task com timeout — se exceder, cancela e retorna
    private func withTimeout(seconds: Double, operation: @escaping () async -> Void) async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await operation() }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            }
            // Espera o primeiro a terminar (operação ou timeout)
            await group.next()
            group.cancelAll()
        }
    }
}

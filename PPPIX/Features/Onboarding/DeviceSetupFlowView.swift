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
        case loading       // buscando dados do servidor
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

    // Dados existentes na conta, buscados no .loading
    @State private var existingPasswordId: Int? = nil
    @State private var existingVehicle: Vehicle? = nil
    @State private var existingMaxAttempts: Int = 3
    @State private var loadError = ""

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

    // MARK: - Loading view

    private var loadingView: some View {
        VStack(spacing: 20) {
            if loadError.isEmpty {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(1.4)
                Text("Carregando seus dados...")
                    .font(.subheadline)
                    .foregroundColor(Color(white: 0.5))
            } else {
                Image(systemName: "wifi.slash")
                    .font(.system(size: 36))
                    .foregroundColor(Color(hex: "#FF4444"))
                Text("Erro ao carregar dados")
                    .font(.headline)
                    .foregroundColor(.white)
                Text(loadError)
                    .font(.caption)
                    .foregroundColor(Color(white: 0.5))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                PPPIXButton(title: "Tentar novamente") {
                    loadError = ""
                    Task { await loadExistingData() }
                }
                .padding(.horizontal, 40)
            }
        }
    }

    // MARK: - Carrega dados existentes da conta

    private func loadExistingData() async {
        do {
            // Busca senhas e veículo sequencialmente (APIClient é @MainActor,
            // não compatível com async let nonisolated no Swift 6)
            let passwords = try await APIClient.shared.getPasswords()
            let vehicles  = try await APIClient.shared.getVehicles()

            // Pré-preenche senhas
            if let pw = passwords.first {
                existingPasswordId = pw.id
                data.bankPassword      = pw.bank_password_plain      ?? ""
                data.ppixPassword      = pw.ppix_password_plain      ?? ""
                data.emergencyPassword = pw.emergency_password_plain ?? ""
                existingMaxAttempts    = pw.max_wrong_attempts        ?? 3
            }

            // Pré-preenche veículo ativo
            if let active = vehicles.first(where: { $0.is_active }) ?? vehicles.first {
                existingVehicle     = active
                data.vehicleModel   = active.model
                data.vehiclePlate   = active.license_plate
                data.vehicleColor   = active.color
                data.vehicleYear    = String(active.year)
                data.wantsVehicle   = true
            }

            step = .permissions

        } catch {
            loadError = "Verifique sua conexão e tente novamente."
        }
    }
}

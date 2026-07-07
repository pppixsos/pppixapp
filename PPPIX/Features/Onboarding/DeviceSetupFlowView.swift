import SwiftUI

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
                Color.clear.onAppear { onFinished() }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: step)
        .task { await loadExistingData() }
    }

    // MARK: - Loading view

    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                .scaleEffect(1.4)
            Text("Carregando seus dados...")
                .font(.subheadline)
                .foregroundColor(Color(white: 0.5))
        }
    }

    // MARK: - Carrega dados existentes com timeout

    private func loadExistingData() async {
        // Task de carregamento com timeout de 8s
        // Se a API não responder, avança sem dados — nunca trava
        let loadTask = Task { () -> Bool in
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
                return true
            } catch {
                print("[DeviceSetup] API indisponível, continuando sem dados: \(error)")
                return false
            }
        }

        // Timeout de 8 segundos
        let timeoutTask = Task {
            try? await Task.sleep(nanoseconds: 8_000_000_000)
        }

        await withTaskGroup(of: Void.self) { group in
            group.addTask { _ = await loadTask.value }
            group.addTask { await timeoutTask.value }
            await group.next()
            group.cancelAll()
            loadTask.cancel()
            timeoutTask.cancel()
        }

        // Sempre avança para o próximo passo
        step = .permissions
    }
}

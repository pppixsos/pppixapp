import SwiftUI

struct OnboardingVehicleDetailsStep: View {
    @ObservedObject var data: OnboardingData
    let onBack: () -> Void
    let onNext: () -> Void

    @State private var isSaving = false
    @State private var errorMessage = ""

    var body: some View {
        OnboardingStepShell(
            icon: "car.fill",
            iconColor: Color(hex: "#3366FF"),
            title: "Dados do seu veículo",
            subtitle: "Essas informações só são compartilhadas durante um alerta de emergência.",
            stepIndex: 9,
            totalSteps: 13,
            onBack: onBack
        ) {
            VStack(spacing: 14) {
                PPPIXTextField(title: "Modelo", placeholder: "Ex: Civic", text: $data.vehicleModel)
                PPPIXTextField(title: "Placa", placeholder: "ABC1D23", text: $data.vehiclePlate,
                                autocapitalization: .characters,
                                onChange: { data.vehiclePlate = $0.uppercased() })
                PPPIXTextField(title: "Cor", placeholder: "Ex: Prata", text: $data.vehicleColor)
                PPPIXTextField(title: "Ano", placeholder: "Ex: 2022", text: $data.vehicleYear,
                                keyboardType: .numberPad)

                if !errorMessage.isEmpty { ErrorBanner(message: errorMessage) }

                PPPIXButton(title: "Salvar veículo", isLoading: isSaving) {
                    Task { await saveAndNext() }
                }
            }
        }
    }

    private func saveAndNext() async {
        let model = data.vehicleModel.trimmingCharacters(in: .whitespaces)
        let plate = data.vehiclePlate.trimmingCharacters(in: .whitespaces)
        let color = data.vehicleColor.trimmingCharacters(in: .whitespaces)

        if model.isEmpty { errorMessage = "Informe o modelo."; return }
        if plate.isEmpty { errorMessage = "Informe a placa."; return }
        if color.isEmpty { errorMessage = "Informe a cor."; return }
        guard let year = Int(data.vehicleYear.filter(\.isNumber)) else {
            errorMessage = "Informe um ano válido."; return
        }

        isSaving = true
        errorMessage = ""

        do {
            _ = try await APIClient.shared.createVehicle(body: VehicleRequest(
                model: model, license_plate: plate, color: color, year: year, is_active: true
            ))
            isSaving = false
            onNext()
        } catch {
            errorMessage = "Erro ao salvar veículo. Tente novamente."
            isSaving = false
        }
    }
}

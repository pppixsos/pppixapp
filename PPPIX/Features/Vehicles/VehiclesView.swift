import SwiftUI

struct VehiclesView: View {

    @State private var vehicles: [Vehicle] = []
    @State private var isLoading = true
    @State private var showAddSheet = false
    @State private var vehicleToEdit: Vehicle? = nil
    @State private var successMessage = ""
    @State private var errorMessage = ""

    var body: some View {
        ZStack {
            Color(hex: "#0A0A12").ignoresSafeArea()

            if isLoading {
                ProgressView().tint(Color(hex: "#3366FF"))
            } else if vehicles.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "car.fill")
                        .font(.system(size: 48))
                        .foregroundColor(Color(white: 0.3))
                    Text("Nenhum veículo cadastrado")
                        .foregroundColor(Color(white: 0.4))
                    Text("Seu veículo aparece no alerta de emergência")
                        .font(.caption)
                        .foregroundColor(Color(white: 0.3))
                        .multilineTextAlignment(.center)
                }
                .padding()
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(vehicles) { vehicle in
                            VehicleRow(
                                vehicle: vehicle,
                                onSetActive: { Task { await setActive(vehicle) } },
                                onDelete: { Task { await deleteVehicle(vehicle) } }
                            )
                        }

                        if !successMessage.isEmpty {
                            Text(successMessage)
                                .font(.footnote)
                                .foregroundColor(Color(hex: "#44FF88"))
                                .padding()
                        }
                        if !errorMessage.isEmpty {
                            ErrorBanner(message: errorMessage)
                        }

                        Spacer(minLength: 80)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                }
            }

            // FAB
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Button {
                        vehicleToEdit = nil
                        showAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 56, height: 56)
                            .background(
                                LinearGradient(
                                    colors: [Color(hex: "#3366FF"), Color(hex: "#6633FF")],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .clipShape(Circle())
                            .shadow(color: Color(hex: "#3366FF").opacity(0.5), radius: 8)
                    }
                    .padding(.trailing, 24)
                    .padding(.bottom, 24)
                }
            }
        }
        .navigationTitle("Meus Veículos")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showAddSheet) {
            AddVehicleSheet(vehicleToEdit: vehicleToEdit) { _ in
                Task { await loadVehicles() }
            }
        }
        .task { await loadVehicles() }
        .refreshable { await loadVehicles() }
    }

    // MARK: - Actions

    private func loadVehicles() async {
        isLoading = true
        defer { isLoading = false }
        vehicles = (try? await APIClient.shared.getVehicles()) ?? []
    }

    private func setActive(_ vehicle: Vehicle) async {
        guard let id = vehicle.id, !vehicle.is_active else { return }
        _ = try? await APIClient.shared.setActiveVehicle(id: id)
        await loadVehicles()
        successMessage = "✓ Veículo definido como principal!"
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { successMessage = "" }
    }

    private func deleteVehicle(_ vehicle: Vehicle) async {
        guard let id = vehicle.id else { return }
        try? await APIClient.shared.deleteVehicle(id: id)
        await loadVehicles()
    }
}

// MARK: - VehicleRow

private struct VehicleRow: View {
    let vehicle: Vehicle
    let onSetActive: () -> Void
    let onDelete: () -> Void

    @State private var showDeleteConfirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(vehicle.displayText)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                        if vehicle.is_active {
                            Text("Principal")
                                .font(.caption2.bold())
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color(hex: "#3366FF"))
                                .cornerRadius(6)
                        }
                    }
                }
                Spacer()
                Image(systemName: "car.fill")
                    .font(.system(size: 24))
                    .foregroundColor(vehicle.is_active ? Color(hex: "#3366FF") : Color(white: 0.3))
            }

            HStack(spacing: 10) {
                if !vehicle.is_active {
                    Button(action: onSetActive) {
                        Label("Definir como Principal", systemImage: "star.fill")
                            .font(.caption.bold())
                            .foregroundColor(Color(hex: "#3366FF"))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Color(hex: "#3366FF").opacity(0.15))
                            .cornerRadius(8)
                    }
                }

                Spacer()

                Button {
                    showDeleteConfirm = true
                } label: {
                    Image(systemName: "trash.fill")
                        .font(.caption)
                        .foregroundColor(Color(hex: "#FF4444"))
                        .padding(8)
                        .background(Color(hex: "#FF4444").opacity(0.1))
                        .cornerRadius(8)
                }
            }
        }
        .padding(16)
        .background(Color(hex: "#141422"))
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(vehicle.is_active ? Color(hex: "#3366FF").opacity(0.4) : Color(white: 0.1), lineWidth: 1)
        )
        .confirmationDialog("Remover veículo?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Remover \(vehicle.model)", role: .destructive, action: onDelete)
            Button("Cancelar", role: .cancel) {}
        }
    }
}

// MARK: - AddVehicleSheet

struct AddVehicleSheet: View {

    let vehicleToEdit: Vehicle?
    let onSaved: (Vehicle) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var model = ""
    @State private var plate = ""
    @State private var color = ""
    @State private var year = ""
    @State private var isActive = false
    @State private var isSaving = false
    @State private var errorMessage = ""

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "#0A0A12").ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        PPPIXTextField(title: "Modelo", placeholder: "Ex: Honda Civic", text: $model)
                        PPPIXTextField(
                            title: "Placa",
                            placeholder: "Ex: ABC1234",
                            text: $plate,
                            autocapitalization: .characters,
                            onChange: { plate = $0.uppercased() }
                        )
                        PPPIXTextField(title: "Cor", placeholder: "Ex: Preto", text: $color)
                        PPPIXTextField(
                            title: "Ano",
                            placeholder: "Ex: 2022",
                            text: $year,
                            keyboardType: .numberPad
                        )

                        Toggle(isOn: $isActive) {
                            Text("Definir como veículo principal")
                                .font(.subheadline)
                                .foregroundColor(.white)
                        }
                        .tint(Color(hex: "#3366FF"))

                        if !errorMessage.isEmpty {
                            ErrorBanner(message: errorMessage)
                        }

                        PPPIXButton(title: vehicleToEdit == nil ? "Adicionar Veículo" : "Salvar", isLoading: isSaving) {
                            Task { await save() }
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle(vehicleToEdit == nil ? "Novo Veículo" : "Editar Veículo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancelar") { dismiss() }
                        .foregroundColor(Color(white: 0.6))
                }
            }
            .onAppear {
                if let v = vehicleToEdit {
                    model    = v.model
                    plate    = v.license_plate
                    color    = v.color
                    year     = String(v.year)
                    isActive = v.is_active
                }
            }
        }
    }

    private func save() async {
        let m = model.trimmingCharacters(in: .whitespaces)
        let p = plate.trimmingCharacters(in: .whitespaces).uppercased()
        let c = color.trimmingCharacters(in: .whitespaces)
        let y = year.trimmingCharacters(in: .whitespaces)

        if m.isEmpty  { errorMessage = "Informe o modelo do veículo (ex: Honda Civic)"; return }
        if p.isEmpty  { errorMessage = "Informe a placa (ex: ABC1234)"; return }
        if p.count < 7 { errorMessage = "Placa inválida. Use o formato ABC1234 ou ABC1D23"; return }
        if c.isEmpty  { errorMessage = "Informe a cor do veículo (ex: Preto)"; return }
        guard let yearInt = Int(y), yearInt >= 1950, yearInt <= 2030 else {
            errorMessage = "Ano inválido. Deve ser entre 1950 e 2030"; return
        }

        isSaving = true
        do {
            let body = VehicleRequest(model: m, license_plate: p, color: c, year: yearInt, is_active: isActive)
            let saved: Vehicle
            if let v = vehicleToEdit, let id = v.id {
                saved = try await APIClient.shared.updateVehicle(id: id, body: body)
            } else {
                saved = try await APIClient.shared.createVehicle(body: body)
            }
            onSaved(saved)
            dismiss()
        } catch APIError.badRequest(let msg) {
            errorMessage = msg
        } catch {
            errorMessage = "Erro de conexão. Tente novamente."
        }
        isSaving = false
    }
}

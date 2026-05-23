import SwiftUI

struct AlertDetailView: View {

    let alertId: Int

    @Environment(\.dismiss) private var dismiss
    @State private var alert: Alert? = nil
    @State private var isLoading = true
    @State private var isCancelling = false
    @State private var showCancelConfirm = false
    @State private var cancelDone = false

    private var myEmail: String { SessionManager.shared.userEmail }
    private var isSender: Bool { alert?.sender_email.lowercased() == myEmail.lowercased() }
    private var isCancelled: Bool { alert?.status == "cancelled" || cancelDone }

    var body: some View {
        NavigationStack {
            mainContent()
        }
        .task {
            EmergencyAudioService.shared.stopSiren()
            await loadAlert()
        }
        .confirmationDialog("Voce esta bem?", isPresented: $showCancelConfirm, titleVisibility: .visible) {
            Button("Sim, Estou Bem") { Task { await cancelAlert() } }
            Button("Voltar", role: .cancel) {}
        } message: {
            Text("Seus contatos serao avisados.")
        }
    }

    @ViewBuilder
    private func mainContent() -> some View {
        ZStack {
            Color(hex: "#0A0A12").ignoresSafeArea()
            ScrollView {
                VStack(spacing: 20) {
                    headerSection()
                    if isLoading {
                        ProgressView().tint(Color(hex: "#3366FF")).padding()
                    } else if let a = alert {
                        detailSection(a)
                    }
                    Spacer(minLength: 32)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
            }
        }
        .navigationTitle("Detalhe do Alerta")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(Color(white: 0.5))
                }
            }
        }
    }

    @ViewBuilder
    private func headerSection() -> some View {
        VStack(spacing: 12) {
            Text(isCancelled ? "CANCELADO" : "ATIVO")
                .font(.caption.bold())
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(isCancelled ? Color(white: 0.3) : Color(hex: "#CC0000"))
                .cornerRadius(20)
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 52))
                .foregroundColor(isCancelled ? Color(white: 0.5) : Color(hex: "#FF3333"))
            Text(isSender ? "VOCE DISPAROU O ALERTA" : "ALERTA DE EMERGENCIA")
                .font(.title3.bold())
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(Color(hex: "#330000"))
        .cornerRadius(16)
    }

    @ViewBuilder
    private func detailSection(_ a: Alert) -> some View {
        VStack(spacing: 12) {
            DetailRow(icon: "clock.fill", color: Color(hex: "#3366FF"), label: "Data", value: a.formattedDate)
            DetailRow(icon: "location.fill", color: Color(hex: "#FF6600"), label: "GPS", value: a.has_location ? "Disponivel" : "Indisponivel")
            if a.has_location, let url = a.googleMapsURL {
                Link(destination: url) {
                    HStack {
                        Image(systemName: "map.fill")
                        Text("Ver no Maps").fontWeight(.semibold)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color(hex: "#0099FF"))
                    .cornerRadius(10)
                }
            }
            DetailRow(icon: "car.fill", color: Color(hex: "#FF6600"), label: "Veiculo", value: a.vehicleText.isEmpty ? "Nao informado" : a.vehicleText)
            if isSender && !isCancelled {
                PPPIXButton(title: "Estou Bem - Cancelar Alerta", isLoading: isCancelling) {
                    showCancelConfirm = true
                }
            }
            Button {
                if let url = URL(string: "tel://190") { UIApplication.shared.open(url) }
            } label: {
                HStack {
                    Image(systemName: "phone.fill")
                    Text("Ligar 190").fontWeight(.semibold)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color(hex: "#CC0000"))
                .cornerRadius(12)
            }
        }
    }

    private func loadAlert() async {
        isLoading = true
        defer { isLoading = false }
        alert = try? await APIClient.shared.getAlert(id: alertId)
    }

    private func cancelAlert() async {
        isCancelling = true
        defer { isCancelling = false }
        do {
            try await APIClient.shared.patchAlertStatus(id: alertId, status: "cancelled")
            cancelDone = true
            await loadAlert()
        } catch {
            try? await APIClient.shared.markAlertRead(id: alertId)
            cancelDone = true
        }
    }
}

private struct DetailRow: View {
    let icon: String
    let color: Color
    let label: String
    let value: String
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.system(size: 18)).foregroundColor(color).frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.caption).foregroundColor(Color(white: 0.5))
                Text(value).font(.system(size: 14, weight: .medium)).foregroundColor(.white)
            }
            Spacer()
        }
        .padding(14)
        .background(Color(hex: "#141422"))
        .cornerRadius(14)
    }
}

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
            ZStack {
                Color(hex: "#0A0A12").ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {

                        // Header vermelho
                        VStack(spacing: 12) {
                            // Badge status
                            Text(isCancelled ? "CANCELADO" : "⚠️ ATIVO")
                                .font(.caption.bold())
                                .foregroundColor(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 6)
                                .background(isCancelled ? Color(white: 0.3) : Color(hex: "#CC0000"))
                                .cornerRadius(20)

                            Image(systemName: isSender ? "bell.fill" : "exclamationmark.triangle.fill")
                                .font(.system(size: 52))
                                .foregroundColor(isCancelled ? Color(white: 0.5) : Color(hex: "#FF3333"))

                            Text(isSender ? "VOCÊ DISPAROU O ALERTA" : "🚨 ALERTA DE EMERGÊNCIA")
                                .font(.title3.bold())
                                .foregroundColor(.white)
                                .multilineTextAlignment(.center)

                            if let a = alert {
                                Text(isSender ? "Seu alerta foi enviado aos contatos" : a.sender_name)
                                    .font(.subheadline)
                                    .foregroundColor(Color(white: 0.7))
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                        .padding(.horizontal, 20)
                        .background(
                            LinearGradient(
                                colors: isCancelled
                                    ? [Color(hex: "#1A1A1A"), Color(hex: "#0A0A12")]
                                    : [Color(hex: "#330000"), Color(hex: "#0A0A12")],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .cornerRadius(16)

                        if isLoading {
                            ProgressView().tint(Color(hex: "#3366FF")).padding()
                        } else if let a = alert {
                            // Hora
                            DetailRow(icon: "clock.fill", color: Color(hex: "#3366FF"),
                                     label: "Data e Hora", value: "⏱ \(a.formattedDate)")

                            // Localização
                            VStack(spacing: 0) {
                                DetailRow(
                                    icon: "location.fill",
                                    color: Color(hex: "#FF6600"),
                                    label: "Localização",
                                    value: a.has_location ? "📍 GPS disponível" : "📍 Localização não disponível"
                                )
                                if a.has_location, let mapsURL = a.googleMapsURL ?? a.locationUrl.flatMap(URL.init) {
                                    Link(destination: mapsURL) {
                                        HStack {
                                            Image(systemName: "map.fill")
                                            Text("Ver no Maps")
                                                .fontWeight(.semibold)
                                        }
                                        .foregroundColor(.white)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                        .background(Color(hex: "#0099FF"))
                                        .cornerRadius(10)
                                        .padding([.horizontal, .bottom], 14)
                                    }
                                }
                            }
                            .background(Color(hex: "#141422"))
                            .cornerRadius(14)

                            // Veículo
                            DetailRow(
                                icon: "car.fill",
                                color: Color(hex: "#FF6600"),
                                label: "Veículo",
                                value: a.vehicleText.isEmpty ? "🚗 Veículo não informado" : "🚗 \(a.vehicleText)"
                            )

                            // Botão Cancelar (só quem enviou)
                            if isSender {
                                if isCancelled {
                                    HStack {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(Color(hex: "#44FF88"))
                                        Text("Alerta Cancelado — Contatos notificados")
                                            .font(.subheadline)
                                            .foregroundColor(Color(hex: "#44FF88"))
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color(hex: "#44FF88").opacity(0.1))
                                    .cornerRadius(12)
                                } else {
                                    PPPIXButton(
                                        title: isCancelling ? "Cancelando..." : "✅  Estou Bem — Cancelar Alerta",
                                        isLoading: isCancelling,
                                        style: .primary
                                    ) {
                                        showCancelConfirm = true
                                    }
                                }
                            }

                            // Ligar 190
                            Button {
                                if let url = URL(string: "tel://190") {
                                    UIApplication.shared.open(url)
                                }
                            } label: {
                                HStack {
                                    Image(systemName: "phone.fill")
                                    Text("Ligar 190 — Polícia Militar")
                                        .fontWeight(.semibold)
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color(hex: "#CC0000"))
                                .cornerRadius(12)
                            }
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
                            .font(.system(size: 22))
                    }
                }
            }
        }
        .task {
            // Para sirene ao abrir detalhe
            EmergencyAudioService.shared.stopSiren()
            await loadAlert()
        }
        .confirmationDialog("Você está bem?", isPresented: $showCancelConfirm, titleVisibility: .visible) {
            Button("✅ Sim, Estou Bem") { Task { await cancelAlert() } }
            Button("Voltar", role: .cancel) {}
        } message: {
            Text("Seus contatos serão avisados que o alerta foi encerrado.")
        }
    }

    // MARK: - Load

    private func loadAlert() async {
        isLoading = true
        defer { isLoading = false }
        alert = try? await APIClient.shared.getAlert(id: alertId)
    }

    // MARK: - Cancel

    private func cancelAlert() async {
        isCancelling = true
        defer { isCancelling = false }
        do {
            try await APIClient.shared.patchAlertStatus(id: alertId, status: "cancelled")
            cancelDone = true
            await loadAlert()
        } catch {
            // Fallback: mark_read
            try? await APIClient.shared.markAlertRead(id: alertId)
            cancelDone = true
        }
    }
}

// MARK: - DetailRow

private struct DetailRow: View {
    let icon: String
    let color: Color
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(color)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption)
                    .foregroundColor(Color(white: 0.5))
                Text(value)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
            }
            Spacer()
        }
        .padding(14)
        .background(Color(hex: "#141422"))
        .cornerRadius(14)
    }
}

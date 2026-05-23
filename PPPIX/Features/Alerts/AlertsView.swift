import SwiftUI

struct AlertsView: View {

    @State private var sentAlerts: [Alert] = []
    @State private var receivedAlerts: [Alert] = []
    @State private var isLoading = true
    @State private var showAllSent = false
    @State private var showAllReceived = false
    @State private var errorMessage = ""
    @State private var selectedAlertId: Int? = nil
    @State private var showCancelConfirm = false
    @State private var alertToCancel: Alert? = nil

    private var myEmail: String { SessionManager.shared.userEmail }

    private var activeAlert: Alert? {
        (sentAlerts + receivedAlerts)
            .filter { $0.status != "cancelled" && $0.status != "read" }
            .max { $0.created_at < $1.created_at }
    }

    var body: some View {
        ZStack {
            Color(hex: "#0A0A12").ignoresSafeArea()

            if isLoading {
                ProgressView().tint(Color(hex: "#3366FF"))
            } else {
                ScrollView {
                    VStack(spacing: 16) {

                        // Banner alerta ativo
                        if let active = activeAlert {
                            ActiveAlertBanner(alert: active) {
                                selectedAlertId = active.id
                            }
                        }

                        // Botão 190
                        Button {
                            if let url = URL(string: "tel://190") {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            HStack {
                                Image(systemName: "phone.fill")
                                Text("Ligar para Emergências (190)")
                                    .fontWeight(.semibold)
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color(hex: "#CC0000"))
                            .cornerRadius(12)
                        }

                        // Enviados
                        AlertSection(
                            title: "📤 Alertas Enviados",
                            alerts: showAllSent ? sentAlerts : Array(sentAlerts.prefix(1)),
                            total: sentAlerts.count,
                            showAll: showAllSent,
                            emptyText: "Nenhum alerta enviado",
                            isSender: true,
                            myEmail: myEmail,
                            onTap: { selectedAlertId = $0.id },
                            onCancel: { alertToCancel = $0; showCancelConfirm = true },
                            onToggle: { showAllSent.toggle() }
                        )

                        // Recebidos
                        AlertSection(
                            title: "📥 Alertas Recebidos",
                            alerts: showAllReceived ? receivedAlerts : Array(receivedAlerts.prefix(1)),
                            total: receivedAlerts.count,
                            showAll: showAllReceived,
                            emptyText: "Nenhum alerta recebido",
                            isSender: false,
                            myEmail: myEmail,
                            onTap: { selectedAlertId = $0.id },
                            onCancel: nil,
                            onToggle: { showAllReceived.toggle() }
                        )

                        Spacer(minLength: 32)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                }
            }
        }
        .navigationTitle("Histórico de Alertas")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedAlertId) { alertId in
            AlertDetailView(alertId: alertId)
        }
        .confirmationDialog("Você está bem?", isPresented: $showCancelConfirm, titleVisibility: .visible) {
            Button("✅ Sim, Estou Bem — Cancelar Alerta") {
                if let a = alertToCancel { Task { await cancelAlert(a) } }
            }
            Button("Voltar", role: .cancel) {}
        } message: {
            Text("Seus contatos serão notificados que o alerta foi cancelado e você está bem.")
        }
        .task { await loadAlerts() }
        .refreshable { await loadAlerts() }
    }

    // MARK: - Load

    private func loadAlerts() async {
        isLoading = true
        defer { isLoading = false }
        do {
            async let sent = APIClient.shared.getSentAlerts()
            async let received = APIClient.shared.getReceivedAlerts()
            sentAlerts = try await sent
            receivedAlerts = try await received
        } catch {
            errorMessage = "Erro ao carregar alertas."
        }
    }

    // MARK: - Cancel

    private func cancelAlert(_ alert: Alert) async {
        do {
            try await APIClient.shared.patchAlertStatus(id: alert.id, status: "cancelled")
            await loadAlerts()
        } catch {
            // tenta mark_read como fallback
            try? await APIClient.shared.markAlertRead(id: alert.id)
            await loadAlerts()
        }
    }
}

// MARK: - ActiveAlertBanner

private struct ActiveAlertBanner: View {
    let alert: Alert
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.white)
                    .font(.system(size: 18))
                VStack(alignment: .leading, spacing: 2) {
                    Text("⚠️ ALERTA ATIVO")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                    Text(alert.sender_name.isEmpty ? "Seu alerta" : alert.sender_name)
                        .font(.caption)
                        .foregroundColor(Color(white: 0.8))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundColor(Color(white: 0.7))
                    .font(.caption)
            }
            .padding(14)
            .background(Color(hex: "#CC0000"))
            .cornerRadius(12)
        }
    }
}

// MARK: - AlertSection

private struct AlertSection: View {
    let title: String
    let alerts: [Alert]
    let total: Int
    let showAll: Bool
    let emptyText: String
    let isSender: Bool
    let myEmail: String
    let onTap: (Alert) -> Void
    let onCancel: ((Alert) -> Void)?
    let onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)

            if alerts.isEmpty && total == 0 {
                Text(emptyText)
                    .font(.subheadline)
                    .foregroundColor(Color(white: 0.4))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            } else {
                ForEach(alerts) { alert in
                    AlertRow(
                        alert: alert,
                        isSender: isSender,
                        myEmail: myEmail,
                        onTap: { onTap(alert) },
                        onCancel: onCancel.map { fn in { fn(alert) } }
                    )
                }

                if total > 1 {
                    Button {
                        onToggle()
                    } label: {
                        HStack {
                            Text(showAll
                                 ? "▲ Ver menos"
                                 : "▼ Ver mais (\(total - 1) alerta\(total - 1 > 1 ? "s" : ""))")
                                .font(.footnote)
                                .foregroundColor(Color(hex: "#3366FF"))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }
                }
            }
        }
    }
}

// MARK: - AlertRow

private struct AlertRow: View {
    let alert: Alert
    let isSender: Bool
    let myEmail: String
    let onTap: () -> Void
    let onCancel: (() -> Void)?

    private var isCancelled: Bool { alert.status == "cancelled" }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(alert.alertIcon)
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(isSender ? "Para seus contatos" : alert.sender_name)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                        Text(alert.formattedDate)
                            .font(.caption)
                            .foregroundColor(Color(white: 0.5))
                    }
                    Spacer()
                    // Badge status
                    Text(isCancelled ? "Cancelado" : "Ativo")
                        .font(.caption2.bold())
                        .foregroundColor(isCancelled ? Color(white: 0.5) : .white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(isCancelled ? Color(white: 0.2) : Color(hex: "#CC0000"))
                        .cornerRadius(6)
                }

                if !alert.vehicleText.isEmpty {
                    Text("🚗 \(alert.vehicleText)")
                        .font(.caption)
                        .foregroundColor(Color(white: 0.6))
                }

                if alert.has_location {
                    Text("📍 GPS disponível")
                        .font(.caption)
                        .foregroundColor(Color(white: 0.6))
                }

                // Botão cancelar (só para quem enviou)
                if isSender, let cancel = onCancel, !isCancelled {
                    Button(action: cancel) {
                        Text("✅  Estou Bem — Cancelar Alerta")
                            .font(.caption.bold())
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(Color(hex: "#228B22"))
                            .cornerRadius(8)
                    }
                }
            }
            .padding(14)
            .background(Color(hex: "#141422"))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isCancelled ? Color(white: 0.1) : Color(hex: "#CC0000").opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

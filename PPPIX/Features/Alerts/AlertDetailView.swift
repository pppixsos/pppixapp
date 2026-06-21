import SwiftUI
import MapKit
import CoreLocation

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
            await pollLocationLoop()
        }
        .confirmationDialog("Voce esta bem?", isPresented: $showCancelConfirm, titleVisibility: .visible) {
            Button("Sim, Estou Bem") { Task { await cancelAlert() } }
            Button("Voltar", role: .cancel) {}
        } message: {
            Text("Seus contatos serao avisados.")
        }
    }

    /// Carrega o alerta e, enquanto ele estiver ativo (não cancelado), continua
    /// recarregando a cada 2 segundos para refletir a localização em tempo real
    /// enviada por quem disparou o alerta. O loop para sozinho quando a view
    /// desaparece (cancelamento automático de `.task`) ou quando o status muda
    /// para "cancelled".
    private func pollLocationLoop() async {
        await loadAlert()
        while !Task.isCancelled && !isCancelled {
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2s
            guard !Task.isCancelled else { return }
            await loadAlert(showLoadingSpinner: false)
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
            DetailRow(icon: "person.fill", color: Color(hex: "#9966FF"), label: isSender ? "Para" : "De",
                      value: a.sender_name.isEmpty ? a.sender_email : a.sender_name)

            // Mapa com prévia
            if a.has_location, let latStr = a.latitude, let lngStr = a.longitude,
               let lat = Double(latStr), let lng = Double(lngStr) {
                VStack(spacing: 0) {
                    // Prévia do mapa nativo
                    ZStack(alignment: .topTrailing) {
                        MapPreviewView(latitude: lat, longitude: lng)
                            .frame(height: 200)
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color(hex: "#FF6600").opacity(0.4), lineWidth: 1)
                            )

                        if !isCancelled {
                            HStack(spacing: 5) {
                                Circle()
                                    .fill(Color(hex: "#FF3333"))
                                    .frame(width: 6, height: 6)
                                Text("AO VIVO")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.white)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(Color.black.opacity(0.55))
                            .cornerRadius(20)
                            .padding(8)
                        }
                    }

                    // Coordenadas + botão Maps
                    HStack {
                        Image(systemName: "location.fill")
                            .foregroundColor(Color(hex: "#FF6600"))
                            .font(.system(size: 12))
                        Text("\(latStr), \(lngStr)")
                            .font(.caption)
                            .foregroundColor(Color(white: 0.5))
                        Spacer()
                        if let url = a.googleMapsURL {
                            Link(destination: url) {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.up.right.square.fill")
                                        .font(.system(size: 12))
                                    Text("Abrir Maps")
                                        .font(.caption.bold())
                                }
                                .foregroundColor(Color(hex: "#44AAFF"))
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(hex: "#141422"))
                    .cornerRadius(0)
                }
                .cornerRadius(12)
                .background(Color(hex: "#141422"))
                .cornerRadius(12)
            } else {
                DetailRow(icon: "location.slash.fill", color: Color(hex: "#FF6600"), label: "GPS", value: "Localização não disponível")
            }

            if !a.vehicleText.isEmpty {
                DetailRow(icon: "car.fill", color: Color(hex: "#FF6600"), label: "Veículo", value: a.vehicleText)
            }

            // Ligar 190
            Button {
                if let url = URL(string: "tel://190") { UIApplication.shared.open(url) }
            } label: {
                HStack {
                    Image(systemName: "phone.fill")
                    Text("Ligar 190 — Polícia").fontWeight(.semibold)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color(hex: "#CC0000"))
                .cornerRadius(12)
            }

            if isSender && !isCancelled {
                PPPIXButton(title: "Estou Bem — Cancelar Alerta", isLoading: isCancelling) {
                    showCancelConfirm = true
                }
            }
        }
    }

    private func loadAlert(showLoadingSpinner: Bool = true) async {
        if showLoadingSpinner { isLoading = true }
        defer { if showLoadingSpinner { isLoading = false } }
        if let updated = try? await APIClient.shared.getAlert(id: alertId) {
            alert = updated
        }
    }

    private func cancelAlert() async {
        isCancelling = true
        defer { isCancelling = false }
        do {
            try await APIClient.shared.patchAlertStatus(id: alertId, status: "cancelled")
            cancelDone = true
            if LiveLocationTracker.shared.activeAlertId == alertId {
                LiveLocationTracker.shared.stop()
            }
            await loadAlert()
        } catch {
            try? await APIClient.shared.markAlertRead(id: alertId)
            cancelDone = true
            if LiveLocationTracker.shared.activeAlertId == alertId {
                LiveLocationTracker.shared.stop()
            }
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


// MARK: - Mapa Nativo (prévia)
struct MapPreviewView: UIViewRepresentable {
    let latitude: Double
    let longitude: Double

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.isScrollEnabled = false
        map.isZoomEnabled = false
        map.isUserInteractionEnabled = false

        // Cria o pino uma única vez; updateUIView só move sua coordenada,
        // em vez de remover/recriar a cada atualização (isso é o que causava
        // o "piscar" — o ícone sumir e reaparecer a cada 2 segundos).
        let pin = MKPointAnnotation()
        pin.title = "Localização"
        map.addAnnotation(pin)

        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        let coord = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)

        // Move o pino já existente — anima suavemente em vez de piscar.
        if let pin = map.annotations.first as? MKPointAnnotation {
            UIView.animate(withDuration: 0.5) {
                pin.coordinate = coord
            }
        }

        // Só recentraliza a câmera se a posição mudou o suficiente para
        // valer a pena (evita "tremedeira" quando o GPS manda a mesma
        // leitura, ou uma leitura quase idêntica, repetidamente).
        let lastCenter = context.coordinator.lastCenter
        let moved = lastCenter.map { CLLocation(latitude: $0.latitude, longitude: $0.longitude)
            .distance(from: CLLocation(latitude: coord.latitude, longitude: coord.longitude)) } ?? .greatestFiniteMagnitude

        if moved > 5 { // só recentraliza se moveu mais de 5 metros
            let region = MKCoordinateRegion(center: coord,
                                            latitudinalMeters: 800,
                                            longitudinalMeters: 800)
            map.setRegion(region, animated: true)
            context.coordinator.lastCenter = coord
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var lastCenter: CLLocationCoordinate2D?
    }
}

import Foundation
import CoreLocation

/// Orquestra o envio de localização em tempo real para um alerta ativo.
///
/// Dois mecanismos trabalham juntos para garantir envio a cada 2s:
///
/// 1. Callbacks do CLLocationManager (LocationService) — disparam sempre
///    que o GPS reporta nova posição. Acorda o processo em background
///    quando a permissão "Sempre" está concedida.
///
/// 2. Timer de segurança em foreground — reenvia a última posição conhecida
///    a cada 2s mesmo sem callback novo (ex: aparelho parado, GPS impreciso).
///    Garante que o caso mais testado na prática — app aberto durante o alerta
///    — sempre atualize, mesmo que o mecanismo 1 falhe.
@MainActor
final class LiveLocationTracker {

    static let shared = LiveLocationTracker()
    private init() {}

    private static let activeAlertIdKey = "pppix_live_tracking_alert_id"

    private var currentAlertId: Int?
    private var isSending = false
    private var lastSentAt: Date = .distantPast
    private var lastSentCoord: CLLocationCoordinate2D? = nil
    private var foregroundTimer: Timer?
    private var consecutiveFailures = 0
    private let maxConsecutiveFailures = 5

    /// Intervalo de envio ao backend: a cada 2 segundos.
    private let sendInterval: TimeInterval = 2.0

    var isActive: Bool { currentAlertId != nil }
    var activeAlertId: Int? { currentAlertId }

    // MARK: - Start / Stop

    func start(alertId: Int) {
        guard currentAlertId != alertId else {
            log("start ignorado — já rastreando alert_id=\(alertId)")
            return
        }
        stop()

        currentAlertId = alertId
        lastSentAt = .distantPast
        lastSentCoord = nil
        consecutiveFailures = 0
        UserDefaults.standard.set(alertId, forKey: Self.activeAlertIdKey)
        log("INICIANDO rastreamento para alert_id=\(alertId)")

        // Mecanismo 1: callbacks do GPS
        LocationService.shared.startContinuousTracking { [weak self] coord in
            Task { @MainActor in self?.attemptSend(coord, source: "GPS") }
        }

        // Mecanismo 2: timer de segurança (foreground)
        // Usa .common para rodar mesmo durante scrolls/animações
        let t = Timer(timeInterval: sendInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                guard let coord = LocationService.shared.lastKnownLocation else {
                    self.log("timer: sem lastKnownLocation ainda")
                    return
                }
                self.attemptSend(coord, source: "timer")
            }
        }
        RunLoop.main.add(t, forMode: .common)
        foregroundTimer = t

        // Envia imediatamente se já há posição em cache
        if let cached = LocationService.shared.lastKnownLocation {
            attemptSend(cached, source: "cache-inicial")
        } else {
            log("sem cache inicial — aguardando GPS")
        }
    }

    func stop() {
        if let id = currentAlertId {
            log("ENCERRANDO rastreamento (alert_id=\(id))")
        }
        foregroundTimer?.invalidate()
        foregroundTimer = nil
        currentAlertId = nil
        lastSentCoord = nil
        consecutiveFailures = 0
        UserDefaults.standard.removeObject(forKey: Self.activeAlertIdKey)
        LocationService.shared.stopContinuousTracking()
    }

    func resumeIfNeeded() {
        guard currentAlertId == nil else { return }
        let saved = UserDefaults.standard.integer(forKey: Self.activeAlertIdKey)
        guard saved > 0 else { return }
        log("retomando alert_id=\(saved) após relançamento")
        start(alertId: saved)
    }

    // MARK: - Envio com throttle

    private func attemptSend(_ coord: CLLocationCoordinate2D, source: String) {
        guard let alertId = currentAlertId else { return }

        // Throttle de 2s entre envios
        guard Date().timeIntervalSince(lastSentAt) >= sendInterval else { return }

        // Não enviar se há um envio em andamento (evita sobreposição)
        // MAS: se isSending ficou travado por falhas consecutivas, reseta
        if isSending {
            consecutiveFailures += 1
            if consecutiveFailures >= maxConsecutiveFailures {
                log("⚠️ isSending travado — forçando reset após \(consecutiveFailures) falhas")
                isSending = false
                consecutiveFailures = 0
            } else {
                return
            }
        }

        lastSentAt = Date()
        lastSentCoord = coord
        isSending = true
        consecutiveFailures = 0

        log("ENVIANDO (\(source)) alert=\(alertId) lat=\(String(format:"%.5f",coord.latitude)) lng=\(String(format:"%.5f",coord.longitude))")

        Task { @MainActor [weak self] in
            // IMPORTANTE: defer garante que isSending seja sempre liberado,
            // mesmo em caso de erro inesperado não capturado pelo catch.
            defer {
                self?.isSending = false
            }
            guard let self, let id = self.currentAlertId else { return }
            do {
                try await APIClient.shared.updateAlertLocation(
                    id: id,
                    latitude: coord.latitude,
                    longitude: coord.longitude
                )
                self.consecutiveFailures = 0
                self.log("✅ lat=\(String(format:"%.5f",coord.latitude)) lng=\(String(format:"%.5f",coord.longitude))")
            } catch {
                self.consecutiveFailures += 1
                self.log("❌ Falha #\(self.consecutiveFailures): \(error.localizedDescription)")
                // Reseta lastSentAt para tentar novamente no próximo tick
                // em vez de esperar mais 2s após uma falha de rede
                self.lastSentAt = .distantPast
            }
        }
    }

    private func log(_ msg: String) {
        let full = "[LiveTracker] \(msg)"
        print(full)
        AlertDiagnosticLog.shared.log(full)
    }
}

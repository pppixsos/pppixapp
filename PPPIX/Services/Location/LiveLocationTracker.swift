import Foundation
import CoreLocation

/// Orquestra o envio de localização em tempo real para um alerta ativo.
///
/// Fluxo: ao enviar um alerta de emergência, chame `start(alertId:)`. A partir
/// daí, a localização é capturada continuamente pelo GPS e enviada ao backend
/// a cada ~2 segundos (PATCH em /alerts/{id}/), até que `stop()` seja chamado
/// — o que acontece quando o usuário cancela o alerta ("Sim, Estou Bem").
///
/// Dois mecanismos trabalham juntos para garantir o envio a cada 2s:
///
/// 1. Callbacks do CLLocationManager (via LocationService) — disparam sempre
///    que o GPS reporta uma nova posição. É o caminho que também acorda o
///    processo em background, quando a permissão "Sempre" está concedida.
///
/// 2. Um Timer de segurança em foreground — reenvia a última posição
///    conhecida a cada 2s mesmo que nenhum callback novo tenha chegado nesse
///    intervalo (ex: GPS muito impreciso, dispositivo praticamente parado,
///    ou qualquer falha pontual no stream do CLLocationManager). Esse timer
///    só roda com o app em primeiro plano (é a natureza de um Timer comum),
///    mas garante que o caso mais testado na prática — app aberto enquanto
///    o alerta está ativo — sempre atualize, mesmo se o mecanismo 1 falhar
///    por algum motivo específico do aparelho/iOS.
///
/// O estado (qual alerta está sendo rastreado) é persistido em UserDefaults
/// para que, se o app for finalizado e relançado pelo sistema em background,
/// o rastreamento seja retomado automaticamente em vez de se perder.
@MainActor
final class LiveLocationTracker {

    static let shared = LiveLocationTracker()
    private init() {}

    private static let activeAlertIdKey = "pppix_live_tracking_alert_id"

    private var currentAlertId: Int?
    private var isSending = false
    private var lastSentAt: Date = .distantPast
    private var foregroundTimer: Timer?

    /// Intervalo de envio ao backend, conforme solicitado: a cada 2 segundos.
    private let sendInterval: TimeInterval = 2.0

    /// true se há um alerta sendo rastreado em tempo real no momento.
    var isActive: Bool { currentAlertId != nil }

    /// ID do alerta atualmente sendo rastreado, se houver.
    var activeAlertId: Int? { currentAlertId }

    // MARK: - Start / Stop

    /// Inicia o rastreamento em tempo real para o alerta recém-criado.
    /// Chamar logo após o backend confirmar a criação do alerta (precisa do `id`).
    func start(alertId: Int) {
        guard currentAlertId != alertId else {
            log("start ignorado — já rastreando alert_id=\(alertId)")
            return
        }
        stop() // encerra qualquer rastreamento anterior, por segurança

        currentAlertId = alertId
        lastSentAt = .distantPast
        UserDefaults.standard.set(alertId, forKey: Self.activeAlertIdKey)

        log("INICIANDO rastreamento para alert_id=\(alertId)")

        // Mecanismo 1: callbacks do GPS (cobre background com permissão Always)
        LocationService.shared.startContinuousTracking { [weak self] coord in
            Task { @MainActor in self?.attemptSend(coord, source: "callback-GPS") }
        }

        // Mecanismo 2: timer de segurança em foreground, garante envio a cada
        // 2s mesmo sem callback novo do GPS nesse intervalo.
        let t = Timer(timeInterval: sendInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let coord = LocationService.shared.lastKnownLocation else {
                    self?.log("timer disparou mas ainda não há lastKnownLocation")
                    return
                }
                self.attemptSend(coord, source: "timer-foreground")
            }
        }
        RunLoop.main.add(t, forMode: .common)
        foregroundTimer = t

        // Envia imediatamente se já houver alguma posição em cache, sem
        // esperar o primeiro tick do timer ou callback.
        if let cached = LocationService.shared.lastKnownLocation {
            attemptSend(cached, source: "cache-inicial")
        } else {
            log("sem lastKnownLocation no momento do start — aguardando GPS")
        }
    }

    /// Encerra o rastreamento em tempo real (alerta cancelado/pausado pelo usuário).
    func stop() {
        if let id = currentAlertId {
            log("ENCERRANDO rastreamento (alert_id=\(id))")
        }
        foregroundTimer?.invalidate()
        foregroundTimer = nil
        currentAlertId = nil
        UserDefaults.standard.removeObject(forKey: Self.activeAlertIdKey)
        LocationService.shared.stopContinuousTracking()
    }

    /// Chamar na inicialização do app (ex: PPPIXApp.didFinishLaunching) para
    /// retomar o rastreamento caso o app tenha sido finalizado pelo sistema
    /// enquanto um alerta ainda estava ativo.
    func resumeIfNeeded() {
        guard currentAlertId == nil else { return }
        let saved = UserDefaults.standard.integer(forKey: Self.activeAlertIdKey)
        guard saved > 0 else { return }
        log("retomando alert_id=\(saved) após relançamento do app")
        start(alertId: saved)
    }

    // MARK: - Envio com throttle de 2s

    private func attemptSend(_ coord: CLLocationCoordinate2D, source: String) {
        guard let alertId = currentAlertId else { return }
        guard !isSending else {
            log("envio pulado (\(source)) — já há um envio em andamento")
            return
        }
        guard Date().timeIntervalSince(lastSentAt) >= sendInterval else {
            return // throttle silencioso — comportamento normal, não logar para não poluir
        }

        lastSentAt = Date()
        isSending = true
        log("ENVIANDO (\(source)) alert_id=\(alertId) lat=\(coord.latitude) lng=\(coord.longitude)")

        Task { @MainActor in
            defer { isSending = false }
            do {
                try await APIClient.shared.updateAlertLocation(
                    id: alertId,
                    latitude: coord.latitude,
                    longitude: coord.longitude
                )
                log("✅ SUCESSO alert_id=\(alertId) lat=\(coord.latitude) lng=\(coord.longitude)")
            } catch {
                log("❌ FALHA alert_id=\(alertId): \(error)")
            }
        }
    }

    private func log(_ msg: String) {
        let full = "[PPPIX][LiveLocationTracker] \(msg)"
        print(full)
        AlertDiagnosticLog.shared.log(full)
    }
}

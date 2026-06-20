import Foundation
import CoreLocation

/// Orquestra o envio de localização em tempo real para um alerta ativo.
///
/// Fluxo: ao enviar um alerta de emergência, chame `start(alertId:)`. A partir
/// daí, a localização é capturada continuamente pelo GPS e enviada ao backend
/// a cada ~2 segundos (PATCH em /alerts/{id}/), até que `stop()` seja chamado
/// — o que acontece quando o usuário cancela o alerta ("Sim, Estou Bem").
///
/// IMPORTANTE: o envio é disparado diretamente pelos callbacks de localização
/// do CLLocationManager (via `LocationService`), e não por um `Timer` comum —
/// um `Timer` preso ao RunLoop principal para de disparar quando o app é
/// suspenso em background. Os callbacks de CLLocationManager, em contrapartida,
/// acordam o processo mesmo com o app minimizado ou removido da tela de apps
/// recentes, desde que a permissão "Sempre" tenha sido concedida — por isso
/// esse é o mecanismo correto para manter o envio funcionando com o app fechado.
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

    /// Intervalo mínimo entre envios ao backend, conforme solicitado: 2 segundos.
    private let sendInterval: TimeInterval = 2.0

    /// true se há um alerta sendo rastreado em tempo real no momento.
    var isActive: Bool { currentAlertId != nil }

    /// ID do alerta atualmente sendo rastreado, se houver.
    var activeAlertId: Int? { currentAlertId }

    // MARK: - Start / Stop

    /// Inicia o rastreamento em tempo real para o alerta recém-criado.
    /// Chamar logo após o backend confirmar a criação do alerta (precisa do `id`).
    func start(alertId: Int) {
        guard currentAlertId != alertId else { return } // já rastreando este alerta
        stop() // encerra qualquer rastreamento anterior, por segurança

        currentAlertId = alertId
        lastSentAt = .distantPast
        UserDefaults.standard.set(alertId, forKey: Self.activeAlertIdKey)

        print("[PPPIX] LiveLocationTracker: iniciando para alert_id=\(alertId)")
        AlertDiagnosticLog.shared.log("[PPPIX] LiveLocationTracker: iniciando para alert_id=\(alertId)")

        // Liga o GPS contínuo. Cada nova leitura chama handleNewLocation,
        // que envia ao backend respeitando o intervalo mínimo de 2s.
        LocationService.shared.startContinuousTracking { [weak self] coord in
            Task { @MainActor in self?.handleNewLocation(coord) }
        }

        // Se já houver uma leitura em cache (warmUp anterior), envia de imediato
        // em vez de esperar a próxima atualização do GPS.
        if let cached = LocationService.shared.lastKnownLocation {
            handleNewLocation(cached)
        }
    }

    /// Encerra o rastreamento em tempo real (alerta cancelado/pausado pelo usuário).
    func stop() {
        if currentAlertId != nil {
            print("[PPPIX] LiveLocationTracker: encerrado (alert_id=\(currentAlertId!))")
            AlertDiagnosticLog.shared.log("[PPPIX] LiveLocationTracker: encerrado (alert_id=\(currentAlertId!))")
        }

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
        print("[PPPIX] LiveLocationTracker: retomando alert_id=\(saved) após relançamento")
        AlertDiagnosticLog.shared.log("[PPPIX] LiveLocationTracker: retomando alert_id=\(saved) após relançamento")
        start(alertId: saved)
    }

    // MARK: - Envio com throttle de 2s

    private func handleNewLocation(_ coord: CLLocationCoordinate2D) {
        guard let alertId = currentAlertId else { return }
        guard !isSending else { return } // evita sobrepor envios se uma request demorar
        guard Date().timeIntervalSince(lastSentAt) >= sendInterval else { return } // throttle de 2s

        lastSentAt = Date()
        isSending = true
        Task { @MainActor in
            defer { isSending = false }
            do {
                try await APIClient.shared.updateAlertLocation(
                    id: alertId,
                    latitude: coord.latitude,
                    longitude: coord.longitude
                )
                print("[PPPIX] LiveLocationTracker: localização atualizada (alert_id=\(alertId)) \(coord.latitude),\(coord.longitude)")
            } catch {
                print("[PPPIX] LiveLocationTracker: falha ao atualizar localização: \(error)")
                AlertDiagnosticLog.shared.log("[PPPIX] LiveLocationTracker: falha ao atualizar localização: \(error)")
            }
        }
    }
}

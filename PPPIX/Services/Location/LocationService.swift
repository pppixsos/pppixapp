import CoreLocation

/// Serviço de GPS — mantém CLLocationManager ativo para cache quente.
final class LocationService: NSObject, @unchecked Sendable {

    nonisolated(unsafe) static let shared = LocationService()

    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 20
    }

    private let manager = CLLocationManager()
    private var pendingContinuation: CheckedContinuation<CLLocationCoordinate2D?, Never>?
    private var timeoutWork: DispatchWorkItem?

    /// Callback chamado a cada nova leitura de GPS enquanto o modo de
    /// rastreamento contínuo (usado durante alertas ativos) está ligado.
    private var trackingHandler: (@Sendable (CLLocationCoordinate2D) -> Void)?
    private var isTracking = false

    var authorizationStatus: CLAuthorizationStatus { manager.authorizationStatus }

    func requestPermission() {
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse: manager.requestAlwaysAuthorization()
        default: break
        }
    }

    /// Pede uma leitura para popular o cache assim que o app abre.
    func warmUp() {
        guard manager.authorizationStatus == .authorizedWhenInUse
           || manager.authorizationStatus == .authorizedAlways else { return }
        manager.requestLocation()
    }

    // MARK: - Rastreamento contínuo (durante alerta ativo)
    //
    // Usa `startUpdatingLocation()` contínuo (não `requestLocation()` em loop,
    // que é projetado pela Apple para UMA leitura pontual e para de entregar
    // updates logo em seguida — usá-lo repetidamente NÃO atualiza em tempo real).

    /// Liga o GPS em modo contínuo. As leituras chegam via `handler` sempre
    /// que o sistema reportar uma nova posição; o disparo do envio a cada 2s
    /// é feito pelo `LiveLocationTracker`, que aplica o throttle.
    func startContinuousTracking(handler: @escaping @Sendable (CLLocationCoordinate2D) -> Void) {
        // Cancela qualquer leitura pontual pendente (getCurrentLocation) para
        // não deixar o manager num estado intermediário inconsistente — uma
        // continuation pendente de requestLocation() competindo com o modo
        // contínuo era uma das causas da localização "travar".
        timeoutWork?.cancel()
        timeoutWork = nil
        if let cont = pendingContinuation {
            pendingContinuation = nil
            cont.resume(returning: manager.location?.coordinate)
        }

        trackingHandler = handler
        isTracking = true

        // CRÍTICO: só liga o modo background se a permissão "Sempre" foi de
        // fato concedida. Setar allowsBackgroundLocationUpdates=true sem
        // permissão Always (ou sem o background mode "location" no
        // Info.plist) faz o CLLocationManager parar de entregar atualizações
        // silenciosamente, sem nenhum erro — essa era a causa raiz do bug de
        // "localização não atualiza nunca". Em foreground o GPS funciona
        // normalmente mesmo sem essa flag.
        let canUseBackground = manager.authorizationStatus == .authorizedAlways
        manager.allowsBackgroundLocationUpdates = canUseBackground
        manager.pausesLocationUpdatesAutomatically = false
        manager.showsBackgroundLocationIndicator = canUseBackground

        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = kCLDistanceFilterNone

        // NÃO fazemos stopUpdatingLocation() + startUpdatingLocation() aqui.
        // Parar e reiniciar o GPS cria um gap de 1-3s onde nenhuma posição
        // chega (o hardware precisa reconectar os satélites). Apenas mudar
        // desiredAccuracy/distanceFilter enquanto o manager já está ativo
        // é suficiente e não interrompe o stream.
        // Se o manager não estava ativo, startUpdatingLocation() o inicia.
        manager.startUpdatingLocation()

        let msg = "[GPS] tracking iniciado (background=\(canUseBackground), auth=\(manager.authorizationStatus.rawValue))"
        print(msg)
        Task { @MainActor in AlertDiagnosticLog.shared.log(msg) }
    }

    /// Desliga o rastreamento contínuo (alerta cancelado/pausado).
    func stopContinuousTracking() {
        guard isTracking else { return }
        isTracking = false
        trackingHandler = nil
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        manager.showsBackgroundLocationIndicator = false
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 20
        print("[PPPIX] GPS: rastreamento contínuo encerrado")
        Task { @MainActor in AlertDiagnosticLog.shared.log("[PPPIX] GPS: rastreamento contínuo encerrado") }
    }

    /// Última posição conhecida (cache quente do CLLocationManager).
    var lastKnownLocation: CLLocationCoordinate2D? {
        manager.location?.coordinate
    }

    // MARK: - Obter localização para EMERGÊNCIA (sempre solicita nova leitura)

    func getCurrentLocation() async -> CLLocationCoordinate2D? {
        guard CLLocationManager.locationServicesEnabled() else {
            print("[PPPIX] GPS: serviços desativados")
            Task { @MainActor in AlertDiagnosticLog.shared.log("[PPPIX] GPS: serviços desativados") }
            return nil
        }
        let status = manager.authorizationStatus
        guard status == .authorizedWhenInUse || status == .authorizedAlways else {
            print("[PPPIX] GPS: sem permissão (\(status.rawValue))")
            Task { @MainActor in AlertDiagnosticLog.shared.log("[PPPIX] GPS: sem permissão (\(status.rawValue))") }
            return nil
        }

        // Se o tracking contínuo já estiver ativo, usa a posição mais recente
        // do cache em vez de competir com o modo contínuo por uma leitura
        // pontual via requestLocation() (que pararia o streaming).
        if isTracking, let current = manager.location?.coordinate {
            return current
        }

        // Cache muito recente (< 15s) com boa precisão — usar direto
        if let cached = manager.location,
           cached.timestamp.timeIntervalSinceNow > -15,
           cached.horizontalAccuracy > 0,
           cached.horizontalAccuracy < 200 {
            print("[PPPIX] GPS cache recente (\(Int(-cached.timestamp.timeIntervalSinceNow))s): \(cached.coordinate.latitude),\(cached.coordinate.longitude) acc=\(Int(cached.horizontalAccuracy))m")
            Task { @MainActor in AlertDiagnosticLog.shared.log("[PPPIX] GPS cache recente (\(Int(-cached.timestamp.timeIntervalSinceNow))s): \(cached.coordinate.latitude),\(cached.coordinate.longitude) acc=\(Int(cached.horizontalAccuracy))m") }
            return cached.coordinate
        }

        // Solicitar com melhor precisão (leitura pontual)
        manager.desiredAccuracy = kCLLocationAccuracyBest
        print("[PPPIX] GPS: solicitando localização de alta precisão...")
        Task { @MainActor in AlertDiagnosticLog.shared.log("[PPPIX] GPS: solicitando localização de alta precisão...") }

        return await withCheckedContinuation { continuation in
            self.pendingContinuation = continuation
            let fallback = self.manager.location?.coordinate

            // Timeout de 10s — usa última posição como fallback
            let work = DispatchWorkItem { [weak self] in
                if let fb = fallback {
                    print("[PPPIX] GPS timeout — usando fallback: \(fb.latitude),\(fb.longitude)")
                    Task { @MainActor in AlertDiagnosticLog.shared.log("[PPPIX] GPS timeout — usando fallback: \(fb.latitude),\(fb.longitude)") }
                } else {
                    print("[PPPIX] GPS timeout — sem localização disponível")
                    Task { @MainActor in AlertDiagnosticLog.shared.log("[PPPIX] GPS timeout — sem localização disponível") }
                }
                self?.resolve(fallback)
            }
            self.timeoutWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: work)
            self.manager.requestLocation()
        }
    }

    private func resolve(_ coord: CLLocationCoordinate2D?) {
        timeoutWork?.cancel()
        timeoutWork = nil
        // Restaurar precisão normal após emergência, exceto se o rastreamento
        // contínuo estiver ativo (ele controla a precisão nesse caso)
        if !isTracking {
            manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        }
        if let cont = pendingContinuation {
            pendingContinuation = nil
            cont.resume(returning: coord)
        }
    }
}

extension LocationService: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last, loc.horizontalAccuracy >= 0 else { return }
        let msg = "[PPPIX] GPS obtido: \(loc.coordinate.latitude),\(loc.coordinate.longitude) acc=\(Int(loc.horizontalAccuracy))m tracking=\(isTracking)"
        print(msg)
        Task { @MainActor in AlertDiagnosticLog.shared.log(msg) }
        resolve(loc.coordinate)
        if isTracking {
            trackingHandler?(loc.coordinate)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let msg = "[PPPIX] GPS erro: \(error.localizedDescription) tracking=\(isTracking)"
        print(msg)
        Task { @MainActor in AlertDiagnosticLog.shared.log(msg) }
        resolve(manager.location?.coordinate)
        // Se o erro ocorreu durante o tracking contínuo, tenta reiniciar —
        // alguns erros (kCLErrorLocationUnknown) são temporários e a Apple
        // recomenda simplesmente continuar tentando.
        if isTracking {
            manager.stopUpdatingLocation()
            manager.startUpdatingLocation()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let s = manager.authorizationStatus
        print("[PPPIX] GPS auth mudou: \(s.rawValue)")
        Task { @MainActor in AlertDiagnosticLog.shared.log("[PPPIX] GPS auth mudou: \(s.rawValue)") }
        if s == .authorizedWhenInUse || s == .authorizedAlways {
            if isTracking {
                // Permissão mudou durante tracking ativo (ex: usuário foi em
                // Ajustes e trocou para "Sempre") — reaplica a config.
                manager.allowsBackgroundLocationUpdates = (s == .authorizedAlways)
                manager.showsBackgroundLocationIndicator = (s == .authorizedAlways)
                manager.startUpdatingLocation()
            } else {
                manager.requestLocation()
            }
        }
    }
}

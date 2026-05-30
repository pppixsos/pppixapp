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

        // Cache muito recente (< 15s) com boa precisão — usar direto
        if let cached = manager.location,
           cached.timestamp.timeIntervalSinceNow > -15,
           cached.horizontalAccuracy > 0,
           cached.horizontalAccuracy < 200 {
            print("[PPPIX] GPS cache recente (\(Int(-cached.timestamp.timeIntervalSinceNow))s): \(cached.coordinate.latitude),\(cached.coordinate.longitude) acc=\(Int(cached.horizontalAccuracy))m")
            Task { @MainActor in AlertDiagnosticLog.shared.log("[PPPIX] GPS cache recente (\(Int(-cached.timestamp.timeIntervalSinceNow))s): \(cached.coordinate.latitude),\(cached.coordinate.longitude) acc=\(Int(cached.horizontalAccuracy))m") }
            return cached.coordinate
        }

        // Solicitar com melhor precisão para emergência
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
        // Restaurar precisão normal após emergência
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        if let cont = pendingContinuation {
            pendingContinuation = nil
            cont.resume(returning: coord)
        }
    }
}

extension LocationService: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last, loc.horizontalAccuracy >= 0 else { return }
        print("[PPPIX] GPS obtido: \(loc.coordinate.latitude),\(loc.coordinate.longitude) acc=\(Int(loc.horizontalAccuracy))m")
        Task { @MainActor in AlertDiagnosticLog.shared.log("[PPPIX] GPS obtido: \(loc.coordinate.latitude),\(loc.coordinate.longitude) acc=\(Int(loc.horizontalAccuracy))m") }
        resolve(loc.coordinate)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("[PPPIX] GPS erro: \(error.localizedDescription)")
        Task { @MainActor in AlertDiagnosticLog.shared.log("[PPPIX] GPS erro: \(error.localizedDescription)") }
        resolve(manager.location?.coordinate)
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let s = manager.authorizationStatus
        print("[PPPIX] GPS auth mudou: \(s.rawValue)")
        Task { @MainActor in AlertDiagnosticLog.shared.log("[PPPIX] GPS auth mudou: \(s.rawValue)") }
        if s == .authorizedWhenInUse || s == .authorizedAlways {
            manager.requestLocation()
        }
    }
}

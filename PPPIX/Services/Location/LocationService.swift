import CoreLocation

/// Serviço de GPS — equivalent ao FusedLocationProviderClient do Android.
/// Mantém um CLLocationManager ativo para ter localização "quente" disponível.
final class LocationService: NSObject, @unchecked Sendable {

    nonisolated(unsafe) static let shared = LocationService()

    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 50
    }

    private let manager = CLLocationManager()
    private var pendingContinuation: CheckedContinuation<CLLocationCoordinate2D?, Never>?
    private var timeoutWork: DispatchWorkItem?

    var authorizationStatus: CLAuthorizationStatus { manager.authorizationStatus }

    // MARK: - Permissões

    func requestPermission() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            manager.requestAlwaysAuthorization()
        default: break
        }
    }

    /// Inicia monitoramento de localização em background para ter cache quente.
    /// Chamar quando o app abre (equivale ao FusedLocationClient do Android que já está ativo).
    func warmUp() {
        guard manager.authorizationStatus == .authorizedWhenInUse
           || manager.authorizationStatus == .authorizedAlways else { return }
        // Pede localização para popular o cache
        manager.requestLocation()
    }

    // MARK: - Obter localização

    func getCurrentLocation() async -> CLLocationCoordinate2D? {
        guard CLLocationManager.locationServicesEnabled() else {
            print("[PPPIX] GPS: serviços desativados")
            return nil
        }
        let status = manager.authorizationStatus
        guard status == .authorizedWhenInUse || status == .authorizedAlways else {
            print("[PPPIX] GPS: sem permissão (\(status.rawValue))")
            return nil
        }

        // Cache recente (< 120s) com boa precisão — retorna imediatamente
        if let cached = manager.location,
           cached.timestamp.timeIntervalSinceNow > -120,
           cached.horizontalAccuracy > 0,
           cached.horizontalAccuracy < 1000 {
            print("[PPPIX] GPS cache: \(cached.coordinate.latitude),\(cached.coordinate.longitude) acc=\(Int(cached.horizontalAccuracy))m")
            return cached.coordinate
        }

        print("[PPPIX] GPS: solicitando nova leitura...")
        return await withCheckedContinuation { continuation in
            self.pendingContinuation = continuation
            let fallback = self.manager.location?.coordinate
            let work = DispatchWorkItem { [weak self] in
                print("[PPPIX] GPS timeout — fallback: \(String(describing: fallback))")
                self?.resolve(fallback)
            }
            self.timeoutWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: work)
            self.manager.requestLocation()
        }
    }

    private func resolve(_ coord: CLLocationCoordinate2D?) {
        timeoutWork?.cancel()
        timeoutWork = nil
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
        resolve(loc.coordinate)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("[PPPIX] GPS erro: \(error.localizedDescription)")
        resolve(manager.location?.coordinate)
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let s = manager.authorizationStatus
        print("[PPPIX] GPS auth: \(s.rawValue)")
        if s == .authorizedWhenInUse || s == .authorizedAlways {
            manager.requestLocation()
        }
    }
}

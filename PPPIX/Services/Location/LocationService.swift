import CoreLocation

final class LocationService: NSObject {

    static let shared = LocationService()
    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters // mais rápido que Best
        manager.distanceFilter = 50
    }

    private let manager = CLLocationManager()

    var authorizationStatus: CLAuthorizationStatus { manager.authorizationStatus }

    func requestPermission() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            // Pode tentar upgradar para Always (iOS mostra prompt de forma lazy)
            manager.requestAlwaysAuthorization()
        default:
            break
        }
    }

    // NOVA ABORDAGEM: usa manager.location (cache do sistema) IMEDIATAMENTE
    // É preenchido pelo iOS automaticamente se o usuário tem localização ativa
    // Não tem delay — retorna o que o sistema já tem
    func getCurrentLocation() async -> CLLocationCoordinate2D? {
        guard CLLocationManager.locationServicesEnabled() else { return nil }
        let status = manager.authorizationStatus
        guard status == .authorizedWhenInUse || status == .authorizedAlways else { return nil }

        // Tenta a localização em cache do sistema primeiro (sem delay)
        if let cached = manager.location, cached.timestamp.timeIntervalSinceNow > -60 {
            return cached.coordinate
        }

        // Se não tem cache recente, pede uma leitura com timeout de 4s
        return await withCheckedContinuation { cont in
            var resumed = false

            let delegate = OneShotLocationDelegate {  coord in
                guard !resumed else { return }
                resumed = true
                cont.resume(returning: coord)
            }
            delegate.start()

            // Timeout — retorna o que o sistema tem (mesmo que antigo)
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                guard !resumed else { return }
                resumed = true
                cont.resume(returning: self.manager.location?.coordinate)
            }
        }
    }
}

// Delegate temporário para uma única leitura
private class OneShotLocationDelegate: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private let callback: (CLLocationCoordinate2D?) -> Void

    init(callback: @escaping (CLLocationCoordinate2D?) -> Void) {
        self.callback = callback
    }

    func start() {
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.requestLocation()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        callback(locations.last?.coordinate)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        callback(nil)
    }
}

extension LocationService: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {}
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let s = manager.authorizationStatus
        if s == .authorizedWhenInUse || s == .authorizedAlways {
            manager.requestLocation() // popula o cache imediatamente
        }
    }
}

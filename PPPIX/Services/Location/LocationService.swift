import CoreLocation

final class LocationService: NSObject {

    static let shared = LocationService()
    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocationCoordinate2D?, Never>?
    private var lastKnownLocation: CLLocationCoordinate2D?

    var authorizationStatus: CLAuthorizationStatus { manager.authorizationStatus }

    func requestPermission() {
        manager.requestAlwaysAuthorization()
    }

    // Retorna localização com timeout de 5s — usa última conhecida como fallback
    func getCurrentLocation() async -> CLLocationCoordinate2D? {
        guard CLLocationManager.locationServicesEnabled() else { return lastKnownLocation }
        let status = manager.authorizationStatus
        guard status == .authorizedWhenInUse || status == .authorizedAlways else {
            return lastKnownLocation
        }

        // Se já temos uma localização recente (< 30s), retorna imediatamente
        if let last = lastKnownLocation { return last }

        return await withCheckedContinuation { cont in
            self.continuation = cont
            manager.requestLocation()

            // Timeout de 5 segundos — não bloqueia o unlock
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                guard let self = self, self.continuation != nil else { return }
                self.continuation?.resume(returning: self.lastKnownLocation)
                self.continuation = nil
            }
        }
    }
}

extension LocationService: CLLocationManagerDelegate {

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let coord = locations.last?.coordinate {
            lastKnownLocation = coord
        }
        continuation?.resume(returning: locations.last?.coordinate ?? lastKnownLocation)
        continuation = nil
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        continuation?.resume(returning: lastKnownLocation)
        continuation = nil
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        if status == .authorizedAlways || status == .authorizedWhenInUse {
            // Começa a monitorar localização em segundo plano quando autorizado
            manager.startUpdatingLocation()
        }
    }
}
